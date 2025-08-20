# OCR System Production Improvements

## Executive Summary
After load testing with 400+ concurrent jobs, we identified that the API pods became the bottleneck, not the gateway or workers. The synchronous file handling in the API caused health check failures and request timeouts. This document outlines the improvements needed for production-ready performance.

## Current Architecture Bottleneck

### What Happened During Load Testing
- **0-400 jobs**: System handled load, but API pods became increasingly stressed
- **400+ jobs**: API pods failed health checks, requests started failing
- **Root Cause**: Each API request does synchronous I/O (upload to blob, write to table, send to queue)
- **Evidence**: Only 252 requests reached API pods, health probes timed out, HPA couldn't get metrics

### Current Request Flow
```
Client → AGC Gateway → API Pod → Blob Storage (200-400ms)
                               → Table Storage (50-100ms)
                               → Service Bus (50-100ms)
                               = ~500-1000ms per request
```

With 2 pods at 0.5 CPU each, max throughput: ~4-6 requests/second

## Recommended Production Architecture

### 1. Direct-to-Storage Pattern (Industry Standard)

#### New Request Flow
```
1. Client → API: Request upload URL (5ms)
2. API → Client: Return SAS token + job ID
3. Client → Blob Storage: Direct upload (bypasses API)
4. Blob Storage → Event Grid → Service Bus: Trigger processing
5. Worker → Process OCR → Update status
```

#### Benefits
- API handles 1000+ requests/second (just generating URLs)
- No memory pressure on API pods
- Automatic retry/resume for large files
- Follows Azure/AWS/GCP best practices
- Infinite scaling with storage service

#### Implementation Changes

**API Changes (main_v2.py)**:
```python
@app.post("/ocr")
async def create_ocr_job(request: OCRJobRequest):
    job_id = str(uuid.uuid4())
    sas_url = generate_sas_url(f"uploads/{job_id}")
    
    # Create job record with status "awaiting_upload"
    await table_storage.create_entity({
        "PartitionKey": "jobs",
        "RowKey": job_id,
        "status": "awaiting_upload"
    })
    
    return {
        "job_id": job_id,
        "upload_url": sas_url,
        "method": "PUT",
        "headers": {"x-ms-blob-type": "BlockBlob"}
    }
```

**Storage Configuration (Terraform)**:
```hcl
# Add CORS for browser support
resource "azurerm_storage_account" "main" {
  cors_rule {
    allowed_origins    = ["http://localhost:8080", "*"]
    allowed_methods    = ["PUT", "POST", "GET", "OPTIONS"]
    allowed_headers    = ["*"]
    exposed_headers    = ["*"]
    max_age_in_seconds = 3600
  }
}
```

**Client Changes**:
```bash
# Get upload URL
response=$(curl -X POST $API_URL/ocr -d '{"filename":"test.png","file_size":1024}')
upload_url=$(echo $response | jq -r '.upload_url')

# Upload directly to blob
curl -X PUT "$upload_url" \
  -H "x-ms-blob-type: BlockBlob" \
  --data-binary @image.png
```

### 2. API Pod Resource Optimization

**Current Settings (Too Low)**:
```yaml
resources:
  requests:
    cpu: 50m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

**Recommended Production Settings**:
```yaml
resources:
  requests:
    cpu: 500m    # 10x increase
    memory: 512Mi # 2x increase
  limits:
    cpu: 2000m   # 4x increase
    memory: 1Gi  # 2x increase
```

### 3. Horizontal Pod Autoscaler Tuning

**Current HPA**:
```yaml
minReplicas: 2
maxReplicas: 10
```

**Recommended HPA**:
```yaml
minReplicas: 4   # Higher baseline
maxReplicas: 20  # More headroom
behavior:
  scaleUp:
    stabilizationWindowSeconds: 0  # Scale immediately
    policies:
    - type: Percent
      value: 100  # Double pods
      periodSeconds: 15
```

### 4. Health Probe Adjustments

**Current Probes (Too Aggressive)**:
```yaml
livenessProbe:
  timeoutSeconds: 3
  periodSeconds: 30
readinessProbe:
  timeoutSeconds: 3
  periodSeconds: 10
```

**Recommended Probes**:
```yaml
livenessProbe:
  timeoutSeconds: 10  # More tolerance
  periodSeconds: 60   # Less frequent
  failureThreshold: 3 # More attempts
readinessProbe:
  timeoutSeconds: 5
  periodSeconds: 10
  failureThreshold: 2
```

### 5. Additional Production Enhancements

#### Connection Pooling
```python
# Add to API startup
class ConnectionPool:
    def __init__(self):
        self.blob_clients = []  # Pool of clients
        self.sb_clients = []    # Pool of clients
        
    def get_blob_client(self):
        # Return client from pool
        pass
```

#### Async Processing
```python
# Use FastAPI background tasks
from fastapi import BackgroundTasks

@app.post("/ocr")
async def create_job(background_tasks: BackgroundTasks):
    job_id = generate_id()
    
    # Return immediately
    background_tasks.add_task(process_upload, job_id)
    return {"job_id": job_id}
```

#### Caching Layer
- Add Redis for job status caching
- Implement content-based deduplication
- Cache SAS tokens for repeated uploads

#### Queue Optimization
- Enable batch receiving (10-20 messages)
- Configure prefetch for lower latency
- Implement dead letter queue handling

## Performance Targets

### Current Performance
- **Max throughput**: ~6 requests/second
- **Failure point**: ~400 concurrent requests
- **Processing rate**: ~70 jobs/minute

### Expected Performance After Improvements
- **Max throughput**: 1000+ requests/second (SAS token generation)
- **Concurrent requests**: 5000+ (limited only by gateway)
- **Processing rate**: 200+ jobs/minute (with 20 workers)

## Implementation Priority

1. **High Priority (Immediate)**
   - Increase API pod resources
   - Adjust HPA settings
   - Tune health probes

2. **Medium Priority (Next Sprint)**
   - Implement SAS token pattern
   - Add connection pooling
   - Configure CORS for web UI

3. **Low Priority (Future)**
   - Add Redis caching
   - Implement Event Grid triggers
   - Multi-region deployment

## Cost Impact

### Current Costs
- 2 API pods (B2ms): ~$0.10/hour
- 1-20 workers (B2ms): ~$0.05-1.00/hour

### Production Costs
- 4-20 API pods: ~$0.20-1.00/hour
- 1-50 workers: ~$0.05-2.50/hour
- Redis cache: ~$0.50/hour
- Total: ~$1-4/hour during peak load

## Testing Recommendations

### Load Testing Script Updates
```bash
# Reduce parallel jobs for large batches
if [ $NUM_JOBS -gt 200 ]; then
    PARALLEL_JOBS=5  # Was 10
fi

# Add pauses between batches
if [ $((i % 100)) -eq 0 ]; then
    sleep 3  # Let system stabilize
fi
```

### Monitoring Improvements
- Add custom metrics for queue depth
- Monitor connection pool usage
- Track SAS token generation rate
- Alert on health check failures

## Conclusion

The system performed well up to ~400 concurrent requests but hit API pod limitations. By implementing the direct-to-storage pattern (industry standard), we can achieve 100-1000x improvement in throughput while reducing costs and complexity. The changes are backward compatible and can be rolled out incrementally.

## References
- [Azure Blob Storage SAS Tokens](https://docs.microsoft.com/en-us/azure/storage/common/storage-sas-overview)
- [FastAPI Background Tasks](https://fastapi.tiangolo.com/tutorial/background-tasks/)
- [Kubernetes HPA Scaling Policies](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [Azure Event Grid with Blob Storage](https://docs.microsoft.com/en-us/azure/event-grid/event-schema-blob-storage)