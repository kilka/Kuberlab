FROM python:3.11-slim AS base

# Install system dependencies including Tesseract
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    tesseract-ocr \
    tesseract-ocr-eng \
    ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN groupadd -r appuser && useradd -r -g appuser -u 1000 appuser

# Set working directory
WORKDIR /app

# Copy requirements first for better caching
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY main.py .

# Create writable directories for Tesseract and prometheus
RUN mkdir -p /tmp/tesseract /tmp/prometheus && \
    chown -R appuser:appuser /tmp/tesseract /tmp/prometheus

# Set Tesseract temp directory
ENV TESSDATA_PREFIX=/usr/share/tesseract-ocr/5/tessdata
ENV TMPDIR=/tmp/tesseract

# Switch to non-root user
USER appuser

# Expose metrics port
EXPOSE 8001

# Health check (check if process is running)
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8001/')" || exit 1

# Run the worker
CMD ["python", "-u", "main.py"]