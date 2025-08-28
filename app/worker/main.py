import json
import logging
import os
import signal
import sys
import time
import concurrent.futures
import threading
from datetime import datetime
from typing import Optional, List
from queue import Queue

import pytesseract
from PIL import Image
from azure.servicebus import ServiceBusClient, ServiceBusReceiver, ServiceBusReceivedMessage
from azure.storage.blob import BlobServiceClient
from azure.data.tables import TableServiceClient, TableEntity
from prometheus_client import Counter, Histogram, start_http_server, generate_latest
import io

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

JOBS_PROCESSED = Counter("ocr_worker_jobs_processed_total", "Total OCR jobs processed")
JOBS_FAILED = Counter("ocr_worker_jobs_failed_total", "Total OCR jobs failed", ["error_type"])
PROCESSING_TIME = Histogram("ocr_worker_processing_seconds", "OCR processing time")
POISON_MESSAGES = Counter("ocr_worker_poison_messages_total", "Total messages sent to poison queue")

CONNECTION_STRING = os.getenv("SERVICEBUS_CONNECTION_STRING")
QUEUE_NAME = os.getenv("SERVICEBUS_QUEUE_NAME", "ocr-jobs")
POISON_QUEUE_NAME = os.getenv("SERVICEBUS_POISON_QUEUE_NAME", "ocr-jobs-poison")
STORAGE_CONNECTION_STRING = os.getenv("STORAGE_CONNECTION_STRING")
UPLOAD_CONTAINER = os.getenv("STORAGE_UPLOAD_CONTAINER", "uploads")
RESULT_CONTAINER = os.getenv("STORAGE_RESULT_CONTAINER", "results")
TABLE_NAME = os.getenv("TABLE_NAME", "ocrjobs")
MAX_RETRIES = int(os.getenv("MAX_RETRIES", "3"))
METRICS_PORT = int(os.getenv("METRICS_PORT", "8001"))
CONCURRENT_WORKERS = int(os.getenv("CONCURRENT_WORKERS", "3"))  # Process 3 messages concurrently
TESSERACT_POOL_SIZE = int(os.getenv("TESSERACT_POOL_SIZE", "3"))  # Pre-initialized Tesseract engines

sb_client: Optional[ServiceBusClient] = None
blob_service_client: Optional[BlobServiceClient] = None
table_service_client: Optional[TableServiceClient] = None
receiver: Optional[ServiceBusReceiver] = None
running = True

# Tesseract engine pool for performance
tesseract_pool = Queue()
tesseract_pool_lock = threading.Lock()

def signal_handler(signum, frame):
    """Handle shutdown signals gracefully."""
    global running
    logger.info(f"Received signal {signum}, shutting down...")
    running = False

signal.signal(signal.SIGTERM, signal_handler)
signal.signal(signal.SIGINT, signal_handler)

def initialize_tesseract_pool():
    """Initialize pool of Tesseract engines for performance."""
    logger.info(f"Initializing {TESSERACT_POOL_SIZE} Tesseract engines...")
    for i in range(TESSERACT_POOL_SIZE):
        try:
            # Pre-configure Tesseract for optimal performance
            config = '--psm 3 --oem 3 -c tessedit_do_invert=0'
            tesseract_pool.put(config)
            logger.info(f"Initialized Tesseract engine {i+1}/{TESSERACT_POOL_SIZE}")
        except Exception as e:
            logger.error(f"Failed to initialize Tesseract engine {i+1}: {e}")
    logger.info("Tesseract pool initialization complete")

def initialize_clients():
    """Initialize Azure service clients."""
    global sb_client, blob_service_client, table_service_client, receiver
    
    try:
        if CONNECTION_STRING:
            sb_client = ServiceBusClient.from_connection_string(CONNECTION_STRING)
            receiver = sb_client.get_queue_receiver(
                queue_name=QUEUE_NAME,
                max_wait_time=5,
                receive_mode="peeklock"
            )
            logger.info("Service Bus client initialized")
        else:
            logger.error("SERVICEBUS_CONNECTION_STRING not set")
            sys.exit(1)
            
        if STORAGE_CONNECTION_STRING:
            blob_service_client = BlobServiceClient.from_connection_string(STORAGE_CONNECTION_STRING)
            table_service_client = TableServiceClient.from_connection_string(STORAGE_CONNECTION_STRING)
            
            # Ensure containers exist
            try:
                blob_service_client.create_container(UPLOAD_CONTAINER)
            except:
                pass  # Container already exists
            try:
                blob_service_client.create_container(RESULT_CONTAINER)
            except:
                pass  # Container already exists
            
            # Ensure table exists
            try:
                table_client = table_service_client.get_table_client(TABLE_NAME)
                table_client.create_table()
            except:
                pass  # Table already exists
            
            logger.info("Storage clients initialized")
        else:
            logger.error("STORAGE_CONNECTION_STRING not set")
            sys.exit(1)
        
        # Initialize Tesseract pool
        initialize_tesseract_pool()
        
    except Exception as e:
        logger.error(f"Failed to initialize clients: {e}")
        sys.exit(1)

def update_job_status(job_id: str, status: str, error: Optional[str] = None, result_blob: Optional[str] = None):
    """Update job status in table storage."""
    if not table_service_client:
        return
    
    try:
        table_client = table_service_client.get_table_client(TABLE_NAME)
        entity = table_client.get_entity(partition_key="jobs", row_key=job_id)
        entity["status"] = status
        entity["updated_at"] = datetime.utcnow().isoformat()
        
        if status == "completed":
            entity["completed_at"] = datetime.utcnow().isoformat()
        
        if error:
            entity["error"] = error
        
        if result_blob:
            entity["result_blob"] = result_blob
        
        table_client.update_entity(entity, mode="merge")
        logger.info(f"Updated job {job_id} status to {status}")
    except Exception as e:
        logger.error(f"Failed to update job status: {e}")

def process_ocr(job_id: str, blob_name: str) -> str:
    """Process OCR on the image blob and return extracted text with optimized streaming."""
    if not blob_service_client:
        raise Exception("Blob service client not initialized")
    
    tesseract_config = None
    try:
        # Get Tesseract engine from pool
        tesseract_config = tesseract_pool.get(timeout=30)
        
        # Stream image data instead of loading entire file
        container_client = blob_service_client.get_container_client(UPLOAD_CONTAINER)
        blob_client = container_client.get_blob_client(blob_name)
        
        # Stream processing - read in chunks to reduce memory usage
        with io.BytesIO() as image_buffer:
            # Download in 64KB chunks
            blob_stream = blob_client.download_blob()
            for chunk in blob_stream.chunks():
                image_buffer.write(chunk)
                if image_buffer.tell() > 50 * 1024 * 1024:  # 50MB limit
                    raise Exception("Image too large for processing")
            
            image_buffer.seek(0)
            
            # Open image with PIL from buffer
            image = Image.open(image_buffer)
            
            # Convert to RGB if necessary (for PNG with alpha channel)
            if image.mode != 'RGB':
                image = image.convert('RGB')
            
            # Optimize image for OCR (resize if too large)
            width, height = image.size
            if width > 3000 or height > 3000:
                # Resize large images to reduce processing time
                ratio = min(3000/width, 3000/height)
                new_size = (int(width * ratio), int(height * ratio))
                image = image.resize(new_size, Image.Resampling.LANCZOS)
                logger.info(f"Resized image for job {job_id} from {width}x{height} to {new_size[0]}x{new_size[1]}")
            
            # Perform OCR with pooled Tesseract engine
            text = pytesseract.image_to_string(image, lang='eng', config=tesseract_config)
            
            if not text or text.strip() == "":
                text = "No text detected in image"
            
            logger.info(f"OCR completed for job {job_id}, extracted {len(text)} characters")
            return text
        
    except Exception as e:
        logger.error(f"OCR processing failed for job {job_id}: {e}")
        raise
    finally:
        # Return Tesseract engine to pool
        if tesseract_config:
            tesseract_pool.put(tesseract_config)

def save_result(job_id: str, text: str) -> str:
    """Save OCR result to blob storage and return blob name."""
    if not blob_service_client:
        raise Exception("Blob service client not initialized")
    
    try:
        result_blob_name = f"{job_id}.txt"
        container_client = blob_service_client.get_container_client(RESULT_CONTAINER)
        blob_client = container_client.get_blob_client(result_blob_name)
        blob_client.upload_blob(text.encode('utf-8'), overwrite=True)
        
        logger.info(f"Saved result for job {job_id} to blob {result_blob_name}")
        return result_blob_name
        
    except Exception as e:
        logger.error(f"Failed to save result for job {job_id}: {e}")
        raise

def send_to_poison_queue(message: ServiceBusReceivedMessage, error: str):
    """Send failed message to poison queue."""
    if not sb_client:
        return
    
    try:
        with sb_client:
            sender = sb_client.get_queue_sender(queue_name=POISON_QUEUE_NAME)
            with sender:
                # Create new message with error details
                poison_message = ServiceBusMessage(
                    body=str(message),
                    content_type="application/json",
                    application_properties={
                        "original_message_id": message.message_id,
                        "error": error,
                        "failed_at": datetime.utcnow().isoformat()
                    }
                )
                sender.send_messages(poison_message)
                POISON_MESSAGES.inc()
                logger.info(f"Sent message {message.message_id} to poison queue")
    except Exception as e:
        logger.error(f"Failed to send message to poison queue: {e}")

def process_message(message: ServiceBusReceivedMessage):
    """Process a single message from the queue."""
    start_time = time.time()
    
    try:
        # Parse message body
        message_body = json.loads(str(message))
        job_id = message_body.get("job_id")
        blob_name = message_body.get("blob_name")
        
        if not job_id or not blob_name:
            raise ValueError("Missing job_id or blob_name in message")
        
        logger.info(f"Processing job {job_id} from blob {blob_name}")
        
        # Update status to processing
        update_job_status(job_id, "processing")
        
        # Perform OCR
        text = process_ocr(job_id, blob_name)
        
        # Save result
        result_blob = save_result(job_id, text)
        
        # Update status to completed
        update_job_status(job_id, "completed", result_blob=result_blob)
        
        # Complete the message
        receiver.complete_message(message)
        
        JOBS_PROCESSED.inc()
        PROCESSING_TIME.observe(time.time() - start_time)
        logger.info(f"Successfully processed job {job_id}")
        
    except Exception as e:
        error_msg = str(e)
        logger.error(f"Failed to process message: {error_msg}")
        
        # Try to extract job_id for status update
        try:
            message_body = json.loads(str(message))
            job_id = message_body.get("job_id")
            if job_id:
                update_job_status(job_id, "failed", error=error_msg)
        except:
            pass
        
        # Check if message should be retried or sent to poison queue
        if message.delivery_count >= MAX_RETRIES:
            logger.warning(f"Message exceeded max retries ({MAX_RETRIES}), sending to poison queue")
            send_to_poison_queue(message, error_msg)
            try:
                receiver.complete_message(message)
            except:
                pass
            JOBS_FAILED.labels(error_type="max_retries_exceeded").inc()
        else:
            # Abandon message for retry
            try:
                receiver.abandon_message(message)
                logger.info(f"Abandoned message for retry (attempt {message.delivery_count + 1}/{MAX_RETRIES})")
            except:
                pass
            JOBS_FAILED.labels(error_type="retryable").inc()

def main():
    """Main worker loop with concurrent message processing."""
    global running
    
    logger.info(f"Starting OCR worker with {CONCURRENT_WORKERS} concurrent workers...")
    
    # Start Prometheus metrics server
    start_http_server(METRICS_PORT)
    logger.info(f"Metrics server started on port {METRICS_PORT}")
    
    # Initialize clients
    initialize_clients()
    
    logger.info("Worker ready, waiting for messages...")
    
    # Use ThreadPoolExecutor for concurrent message processing
    with concurrent.futures.ThreadPoolExecutor(max_workers=CONCURRENT_WORKERS) as executor:
        while running:
            try:
                # Receive multiple messages for concurrent processing
                messages = receiver.receive_messages(
                    max_message_count=CONCURRENT_WORKERS,
                    max_wait_time=5
                )
                
                if messages:
                    # Submit messages for concurrent processing
                    futures = []
                    for message in messages:
                        if not running:
                            break
                        logger.info(f"Received message: {message.message_id}")
                        future = executor.submit(process_message, message)
                        futures.append(future)
                    
                    # Wait for all concurrent tasks to complete (with timeout)
                    for future in concurrent.futures.as_completed(futures, timeout=300):  # 5 minute timeout
                        try:
                            future.result()  # This will raise any exceptions from the worker
                        except Exception as e:
                            logger.error(f"Concurrent worker failed: {e}")
                
            except KeyboardInterrupt:
                logger.info("Received keyboard interrupt")
                break
            except concurrent.futures.TimeoutError:
                logger.warning("Some worker tasks timed out, continuing...")
            except Exception as e:
                logger.error(f"Error in main loop: {e}")
                time.sleep(5)  # Wait before retrying
    
    # Cleanup
    logger.info("Shutting down worker...")
    if receiver:
        receiver.close()
    if sb_client:
        sb_client.close()
    logger.info("Worker shutdown complete")

if __name__ == "__main__":
    main()