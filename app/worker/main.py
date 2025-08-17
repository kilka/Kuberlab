import json
import logging
import os
import signal
import sys
import time
from datetime import datetime
from typing import Optional

import pytesseract
from PIL import Image
from azure.servicebus import ServiceBusClient, ServiceBusReceiver, ServiceBusReceivedMessage
from azure.storage.blob import BlobServiceClient
from azure.storage.table import TableServiceClient, TableEntity
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

sb_client: Optional[ServiceBusClient] = None
blob_service_client: Optional[BlobServiceClient] = None
table_service_client: Optional[TableServiceClient] = None
receiver: Optional[ServiceBusReceiver] = None
running = True

def signal_handler(signum, frame):
    """Handle shutdown signals gracefully."""
    global running
    logger.info(f"Received signal {signum}, shutting down...")
    running = False

signal.signal(signal.SIGTERM, signal_handler)
signal.signal(signal.SIGINT, signal_handler)

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
                table_service_client.create_table(TABLE_NAME)
            except:
                pass  # Table already exists
            
            logger.info("Storage clients initialized")
        else:
            logger.error("STORAGE_CONNECTION_STRING not set")
            sys.exit(1)
    except Exception as e:
        logger.error(f"Failed to initialize clients: {e}")
        sys.exit(1)

def update_job_status(job_id: str, status: str, error: Optional[str] = None, result_blob: Optional[str] = None):
    """Update job status in table storage."""
    if not table_service_client:
        return
    
    try:
        entity = table_service_client.get_entity(TABLE_NAME, partition_key="jobs", row_key=job_id)
        entity["status"] = status
        entity["updated_at"] = datetime.utcnow().isoformat()
        
        if status == "completed":
            entity["completed_at"] = datetime.utcnow().isoformat()
        
        if error:
            entity["error"] = error
        
        if result_blob:
            entity["result_blob"] = result_blob
        
        table_service_client.update_entity(TABLE_NAME, entity, mode="merge")
        logger.info(f"Updated job {job_id} status to {status}")
    except Exception as e:
        logger.error(f"Failed to update job status: {e}")

def process_ocr(job_id: str, blob_name: str) -> str:
    """Process OCR on the image blob and return extracted text."""
    if not blob_service_client:
        raise Exception("Blob service client not initialized")
    
    try:
        # Download image from blob storage
        container_client = blob_service_client.get_container_client(UPLOAD_CONTAINER)
        blob_client = container_client.get_blob_client(blob_name)
        image_data = blob_client.download_blob().readall()
        
        # Open image with PIL
        image = Image.open(io.BytesIO(image_data))
        
        # Convert to RGB if necessary (for PNG with alpha channel)
        if image.mode != 'RGB':
            image = image.convert('RGB')
        
        # Perform OCR with Tesseract (English only)
        text = pytesseract.image_to_string(image, lang='eng')
        
        if not text or text.strip() == "":
            text = "No text detected in image"
        
        logger.info(f"OCR completed for job {job_id}, extracted {len(text)} characters")
        return text
        
    except Exception as e:
        logger.error(f"OCR processing failed for job {job_id}: {e}")
        raise

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
    """Main worker loop."""
    global running
    
    logger.info("Starting OCR worker...")
    
    # Start Prometheus metrics server
    start_http_server(METRICS_PORT)
    logger.info(f"Metrics server started on port {METRICS_PORT}")
    
    # Initialize clients
    initialize_clients()
    
    logger.info("Worker ready, waiting for messages...")
    
    while running:
        try:
            # Receive messages
            messages = receiver.receive_messages(max_message_count=1, max_wait_time=5)
            
            for message in messages:
                if not running:
                    break
                    
                logger.info(f"Received message: {message.message_id}")
                process_message(message)
            
        except KeyboardInterrupt:
            logger.info("Received keyboard interrupt")
            break
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