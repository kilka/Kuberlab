import hashlib
import json
import logging
import os
from datetime import datetime, timedelta
from typing import Optional

from azure.servicebus import ServiceBusClient, ServiceBusMessage
from azure.storage.blob import BlobServiceClient, generate_blob_sas, BlobSasPermissions
from azure.data.tables import TableServiceClient, TableEntity
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import JSONResponse
from prometheus_client import Counter, Histogram, generate_latest
from starlette.responses import Response

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="OCR API", version="1.0.0")

REQUEST_COUNT = Counter("ocr_api_requests_total", "Total OCR API requests", ["method", "endpoint", "status"])
REQUEST_DURATION = Histogram("ocr_api_request_duration_seconds", "OCR API request duration")
JOB_CREATED = Counter("ocr_jobs_created_total", "Total OCR jobs created")
JOB_ERRORS = Counter("ocr_job_errors_total", "Total OCR job errors", ["error_type"])

CONNECTION_STRING = os.getenv("SERVICEBUS_CONNECTION_STRING")
QUEUE_NAME = os.getenv("SERVICEBUS_QUEUE_NAME", "ocr-jobs")
STORAGE_CONNECTION_STRING = os.getenv("STORAGE_CONNECTION_STRING")
STORAGE_CONTAINER = os.getenv("STORAGE_CONTAINER", "uploads")
TABLE_NAME = os.getenv("TABLE_NAME", "ocrjobs")

ALLOWED_EXTENSIONS = {".jpg", ".jpeg", ".png"}
MAX_FILE_SIZE = 10 * 1024 * 1024  # 10MB

sb_client = None
blob_service_client = None
table_service_client = None

@app.on_event("startup")
async def startup_event():
    """Initialize Azure service clients on startup."""
    global sb_client, blob_service_client, table_service_client
    
    try:
        if CONNECTION_STRING:
            sb_client = ServiceBusClient.from_connection_string(CONNECTION_STRING)
            logger.info("Service Bus client initialized")
        else:
            logger.warning("SERVICEBUS_CONNECTION_STRING not set")
            
        if STORAGE_CONNECTION_STRING:
            blob_service_client = BlobServiceClient.from_connection_string(STORAGE_CONNECTION_STRING)
            table_service_client = TableServiceClient.from_connection_string(STORAGE_CONNECTION_STRING)
            
            # Ensure table exists
            try:
                table_client = table_service_client.get_table_client(TABLE_NAME)
                table_client.create_table()
            except:
                pass  # Table already exists
            
            logger.info("Storage clients initialized")
        else:
            logger.warning("STORAGE_CONNECTION_STRING not set")
    except Exception as e:
        logger.error(f"Failed to initialize clients: {e}")

@app.on_event("shutdown")
async def shutdown_event():
    """Clean up resources on shutdown."""
    global sb_client
    if sb_client:
        sb_client.close()
        logger.info("Service Bus client closed")

@app.get("/health")
async def health():
    """Health check endpoint for Kubernetes probes."""
    return {"status": "healthy"}

@app.get("/ready")
async def ready():
    """Readiness check endpoint."""
    if not sb_client or not blob_service_client:
        return JSONResponse(status_code=503, content={"status": "not ready"})
    return {"status": "ready"}

@app.get("/metrics")
async def metrics():
    """Prometheus metrics endpoint."""
    return Response(generate_latest(), media_type="text/plain")

@app.post("/generate-upload-url")
async def generate_upload_url(filename: str):
    """
    Generate direct upload URL to blob storage with SAS token.
    
    This enables clients to upload directly to blob storage, eliminating
    the API server bottleneck and reducing bandwidth costs.
    """
    REQUEST_COUNT.labels(method="POST", endpoint="/generate-upload-url", status="started").inc()
    
    if not blob_service_client:
        REQUEST_COUNT.labels(method="POST", endpoint="/generate-upload-url", status="503").inc()
        raise HTTPException(status_code=503, detail="Storage service unavailable")
    
    try:
        # Validate file extension
        file_extension = os.path.splitext(filename)[1].lower()
        if file_extension not in ALLOWED_EXTENSIONS:
            REQUEST_COUNT.labels(method="POST", endpoint="/generate-upload-url", status="400").inc()
            raise HTTPException(status_code=400, detail=f"Invalid file format. Allowed: {ALLOWED_EXTENSIONS}")
        
        # Pre-generate job ID for idempotency (based on filename + timestamp)
        temp_content = f"{filename}_{datetime.utcnow().isoformat()}"
        job_id = hashlib.sha256(temp_content.encode()).hexdigest()
        
        blob_name = f"{job_id}{file_extension}"
        
        # Generate SAS token for direct upload
        sas_token = generate_blob_sas(
            account_name=blob_service_client.account_name,
            account_key=blob_service_client.credential.account_key,
            container_name=STORAGE_CONTAINER,
            blob_name=blob_name,
            permission=BlobSasPermissions(write=True),
            expiry=datetime.utcnow() + timedelta(minutes=10)
        )
        
        upload_url = f"https://{blob_service_client.account_name}.blob.core.windows.net/{STORAGE_CONTAINER}/{blob_name}?{sas_token}"
        
        REQUEST_COUNT.labels(method="POST", endpoint="/generate-upload-url", status="200").inc()
        
        return {
            "job_id": job_id,
            "upload_url": upload_url,
            "blob_name": blob_name,
            "expires_in": 600,  # 10 minutes
            "max_file_size": MAX_FILE_SIZE,
            "message": "Upload file directly to this URL, then call /ocr/confirm-upload"
        }
        
    except Exception as e:
        logger.error(f"Failed to generate upload URL: {e}")
        REQUEST_COUNT.labels(method="POST", endpoint="/generate-upload-url", status="500").inc()
        raise HTTPException(status_code=500, detail="Failed to generate upload URL")

@app.post("/ocr/confirm-upload")
async def confirm_upload(job_id: str, filename: str):
    """
    Confirm that a file has been uploaded directly to blob storage
    and queue it for OCR processing.
    """
    REQUEST_COUNT.labels(method="POST", endpoint="/ocr/confirm-upload", status="started").inc()
    
    try:
        file_extension = os.path.splitext(filename)[1].lower()
        blob_name = f"{job_id}{file_extension}"
        
        # Verify the blob exists and get its size
        if blob_service_client:
            try:
                container_client = blob_service_client.get_container_client(STORAGE_CONTAINER)
                blob_client = container_client.get_blob_client(blob_name)
                blob_properties = blob_client.get_blob_properties()
                file_size = blob_properties.size
                
                if file_size == 0:
                    REQUEST_COUNT.labels(method="POST", endpoint="/ocr/confirm-upload", status="400").inc()
                    raise HTTPException(status_code=400, detail="Uploaded file is empty")
                
                if file_size > MAX_FILE_SIZE:
                    REQUEST_COUNT.labels(method="POST", endpoint="/ocr/confirm-upload", status="400").inc()
                    raise HTTPException(status_code=400, detail="Uploaded file exceeds size limit")
                
            except Exception as e:
                if "BlobNotFound" in str(e):
                    REQUEST_COUNT.labels(method="POST", endpoint="/ocr/confirm-upload", status="404").inc()
                    raise HTTPException(status_code=404, detail="File not found. Please upload first.")
                raise HTTPException(status_code=500, detail="Failed to verify uploaded file")
        
        # Check if job already exists
        if table_service_client:
            try:
                table_client = table_service_client.get_table_client(TABLE_NAME)
                entity = table_client.get_entity(partition_key="jobs", row_key=job_id)
                if entity:
                    logger.info(f"Job {job_id} already exists, returning existing job")
                    REQUEST_COUNT.labels(method="POST", endpoint="/ocr/confirm-upload", status="200").inc()
                    return {
                        "job_id": job_id,
                        "status": entity.get("status", "processing"),
                        "message": "Job already exists"
                    }
            except Exception:
                pass  # Job doesn't exist, continue with creation
        
        # Send message to queue
        message_body = {
            "job_id": job_id,
            "blob_name": blob_name,
            "filename": filename,
            "created_at": datetime.utcnow().isoformat(),
            "file_size": file_size
        }
        
        if sb_client:
            try:
                with sb_client:
                    sender = sb_client.get_queue_sender(queue_name=QUEUE_NAME)
                    with sender:
                        message = ServiceBusMessage(
                            body=json.dumps(message_body),
                            content_type="application/json",
                            message_id=job_id
                        )
                        sender.send_messages(message)
                        logger.info(f"Sent message to queue for job: {job_id}")
            except Exception as e:
                logger.error(f"Failed to send message to Service Bus: {e}")
                JOB_ERRORS.labels(error_type="queue_send_failed").inc()
                raise HTTPException(status_code=500, detail="Failed to queue job")
        
        # Create table entry
        if table_service_client:
            try:
                table_client = table_service_client.get_table_client(TABLE_NAME)
                entity = TableEntity()
                entity["PartitionKey"] = "jobs"
                entity["RowKey"] = job_id
                entity["status"] = "queued"
                entity["filename"] = filename
                entity["blob_name"] = blob_name
                entity["created_at"] = datetime.utcnow().isoformat()
                entity["file_size"] = file_size
                
                table_client.create_entity(entity)
                logger.info(f"Created table entity for job: {job_id}")
            except Exception as e:
                logger.error(f"Failed to create table entity: {e}")
                # Don't fail the request if table storage fails
        
        JOB_CREATED.inc()
        REQUEST_COUNT.labels(method="POST", endpoint="/ocr/confirm-upload", status="202").inc()
        
        return JSONResponse(
            status_code=202,
            content={
                "job_id": job_id,
                "status": "queued",
                "message": "Job created successfully"
            }
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        REQUEST_COUNT.labels(method="POST", endpoint="/ocr/confirm-upload", status="500").inc()
        JOB_ERRORS.labels(error_type="unexpected").inc()
        raise HTTPException(status_code=500, detail="Internal server error")

@app.post("/ocr")
async def create_ocr_job(file: UploadFile = File(...)):
    """
    Create an OCR job for the uploaded image.
    
    - Accepts JPEG/PNG images only
    - Generates SHA256 hash as job ID for idempotency
    - Uploads image to blob storage
    - Sends job message to Service Bus queue
    - Returns job ID for tracking
    """
    REQUEST_COUNT.labels(method="POST", endpoint="/ocr", status="started").inc()
    
    try:
        file_extension = os.path.splitext(file.filename)[1].lower()
        if file_extension not in ALLOWED_EXTENSIONS:
            REQUEST_COUNT.labels(method="POST", endpoint="/ocr", status="400").inc()
            JOB_ERRORS.labels(error_type="invalid_format").inc()
            raise HTTPException(status_code=400, detail=f"Invalid file format. Allowed: {ALLOWED_EXTENSIONS}")
        
        content = await file.read()
        
        if len(content) > MAX_FILE_SIZE:
            REQUEST_COUNT.labels(method="POST", endpoint="/ocr", status="400").inc()
            JOB_ERRORS.labels(error_type="file_too_large").inc()
            raise HTTPException(status_code=400, detail=f"File too large. Max size: {MAX_FILE_SIZE} bytes")
        
        if len(content) == 0:
            REQUEST_COUNT.labels(method="POST", endpoint="/ocr", status="400").inc()
            JOB_ERRORS.labels(error_type="empty_file").inc()
            raise HTTPException(status_code=400, detail="Empty file")
        
        job_id = hashlib.sha256(content).hexdigest()
        
        if table_service_client:
            try:
                table_client = table_service_client.get_table_client(TABLE_NAME)
                entity = table_client.get_entity(partition_key="jobs", row_key=job_id)
                if entity:
                    logger.info(f"Job {job_id} already exists, returning existing job")
                    REQUEST_COUNT.labels(method="POST", endpoint="/ocr", status="200").inc()
                    return {
                        "job_id": job_id,
                        "status": entity.get("status", "processing"),
                        "message": "Job already exists"
                    }
            except Exception:
                pass  # Job doesn't exist, continue with creation
        
        blob_name = f"{job_id}{file_extension}"
        if blob_service_client:
            try:
                container_client = blob_service_client.get_container_client(STORAGE_CONTAINER)
                blob_client = container_client.get_blob_client(blob_name)
                blob_client.upload_blob(content, overwrite=True)
                logger.info(f"Uploaded blob: {blob_name}")
            except Exception as e:
                logger.error(f"Failed to upload blob: {e}")
                JOB_ERRORS.labels(error_type="blob_upload_failed").inc()
                raise HTTPException(status_code=500, detail="Failed to upload file")
        
        message_body = {
            "job_id": job_id,
            "blob_name": blob_name,
            "filename": file.filename,
            "created_at": datetime.utcnow().isoformat(),
            "file_size": len(content)
        }
        
        if sb_client:
            try:
                with sb_client:
                    sender = sb_client.get_queue_sender(queue_name=QUEUE_NAME)
                    with sender:
                        message = ServiceBusMessage(
                            body=json.dumps(message_body),
                            content_type="application/json",
                            message_id=job_id
                        )
                        sender.send_messages(message)
                        logger.info(f"Sent message to queue for job: {job_id}")
            except Exception as e:
                logger.error(f"Failed to send message to Service Bus: {e}")
                JOB_ERRORS.labels(error_type="queue_send_failed").inc()
                raise HTTPException(status_code=500, detail="Failed to queue job")
        
        if table_service_client:
            try:
                table_client = table_service_client.get_table_client(TABLE_NAME)
                entity = TableEntity()
                entity["PartitionKey"] = "jobs"
                entity["RowKey"] = job_id
                entity["status"] = "queued"
                entity["filename"] = file.filename
                entity["blob_name"] = blob_name
                entity["created_at"] = datetime.utcnow().isoformat()
                entity["file_size"] = len(content)
                
                table_client.create_entity(entity)
                logger.info(f"Created table entity for job: {job_id}")
            except Exception as e:
                logger.error(f"Failed to create table entity: {e}")
                # Don't fail the request if table storage fails
        
        JOB_CREATED.inc()
        REQUEST_COUNT.labels(method="POST", endpoint="/ocr", status="202").inc()
        
        return JSONResponse(
            status_code=202,
            content={
                "job_id": job_id,
                "status": "queued",
                "message": "Job created successfully"
            }
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        REQUEST_COUNT.labels(method="POST", endpoint="/ocr", status="500").inc()
        JOB_ERRORS.labels(error_type="unexpected").inc()
        raise HTTPException(status_code=500, detail="Internal server error")

@app.get("/ocr/{job_id}")
async def get_job_status(job_id: str):
    """Get the status of an OCR job."""
    REQUEST_COUNT.labels(method="GET", endpoint="/ocr/{job_id}", status="started").inc()
    
    if not table_service_client:
        REQUEST_COUNT.labels(method="GET", endpoint="/ocr/{job_id}", status="503").inc()
        raise HTTPException(status_code=503, detail="Storage service unavailable")
    
    try:
        table_client = table_service_client.get_table_client(TABLE_NAME)
        entity = table_client.get_entity(partition_key="jobs", row_key=job_id)
        REQUEST_COUNT.labels(method="GET", endpoint="/ocr/{job_id}", status="200").inc()
        
        response = {
            "job_id": job_id,
            "status": entity.get("status", "unknown"),
            "filename": entity.get("filename"),
            "created_at": entity.get("created_at"),
            "completed_at": entity.get("completed_at")
        }
        
        if entity.get("status") == "completed" and entity.get("result_blob"):
            response["result_url"] = f"/ocr/{job_id}/result"
        
        if entity.get("error"):
            response["error"] = entity.get("error")
        
        return response
        
    except Exception as e:
        logger.error(f"Failed to get job status: {e}")
        REQUEST_COUNT.labels(method="GET", endpoint="/ocr/{job_id}", status="404").inc()
        raise HTTPException(status_code=404, detail="Job not found")

@app.get("/ocr/{job_id}/result")
async def get_job_result(job_id: str):
    """Get the OCR result for a completed job."""
    REQUEST_COUNT.labels(method="GET", endpoint="/ocr/{job_id}/result", status="started").inc()
    
    if not table_service_client or not blob_service_client:
        REQUEST_COUNT.labels(method="GET", endpoint="/ocr/{job_id}/result", status="503").inc()
        raise HTTPException(status_code=503, detail="Storage service unavailable")
    
    try:
        table_client = table_service_client.get_table_client(TABLE_NAME)
        entity = table_client.get_entity(partition_key="jobs", row_key=job_id)
        
        if entity.get("status") != "completed":
            REQUEST_COUNT.labels(method="GET", endpoint="/ocr/{job_id}/result", status="400").inc()
            raise HTTPException(status_code=400, detail=f"Job not completed. Status: {entity.get('status')}")
        
        result_blob = entity.get("result_blob")
        if not result_blob:
            REQUEST_COUNT.labels(method="GET", endpoint="/ocr/{job_id}/result", status="404").inc()
            raise HTTPException(status_code=404, detail="Result not found")
        
        container_client = blob_service_client.get_container_client("results")
        blob_client = container_client.get_blob_client(result_blob)
        result_data = blob_client.download_blob().readall()
        
        REQUEST_COUNT.labels(method="GET", endpoint="/ocr/{job_id}/result", status="200").inc()
        
        return JSONResponse(
            content={
                "job_id": job_id,
                "text": result_data.decode("utf-8"),
                "completed_at": entity.get("completed_at")
            }
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to get job result: {e}")
        REQUEST_COUNT.labels(method="GET", endpoint="/ocr/{job_id}/result", status="500").inc()
        raise HTTPException(status_code=500, detail="Failed to retrieve result")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)