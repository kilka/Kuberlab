#!/usr/bin/env python3
"""
Simple proxy server for OCR web app testing.
Serves static files and proxies API requests to avoid CORS issues.
"""

import json
import os
import sys
from http.server import HTTPServer, SimpleHTTPRequestHandler
from urllib.parse import urlparse
import requests
from pathlib import Path

# Read API configuration
config_file = Path(__file__).parent / "api-config.json"
if not config_file.exists():
    print("ERROR: api-config.json not found. Run 'make deploy' first.")
    sys.exit(1)

with open(config_file) as f:
    config = json.load(f)
    API_URL = config["apiUrl"]

print(f"🔗 Proxying to: {API_URL}")

class ProxyHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(Path(__file__).parent), **kwargs)
    
    def do_GET(self):
        if self.path.startswith('/api/'):
            self.proxy_request()
        elif self.path == '/' or self.path == '/index.html':
            # Serve the main HTML file
            self.path = '/index.html'
            return super().do_GET()
        else:
            # Ignore other requests (like Chrome DevTools, favicon, etc.)
            self.send_error(404)
    
    def do_POST(self):
        if self.path.startswith('/api/'):
            self.proxy_request()
        else:
            self.send_error(404)
    
    def do_PUT(self):
        if self.path.startswith('/blob-proxy/'):
            self.proxy_blob_upload()
        else:
            self.send_error(404)
    
    def proxy_request(self):
        """Proxy requests to the actual API."""
        # Remove /api prefix and construct target URL
        api_path = self.path[4:]  # Remove '/api'
        target_url = API_URL + api_path
        
        try:
            # Prepare headers (remove hop-by-hop headers)
            headers = {}
            for key, value in self.headers.items():
                if key.lower() not in ['host', 'connection']:
                    headers[key] = value
            
            # Read body for POST requests
            body = None
            if self.command == 'POST':
                content_length = int(self.headers.get('Content-Length', 0))
                if content_length > 0:
                    body = self.rfile.read(content_length)
            
            # Make the request to the actual API
            if self.command == 'GET':
                response = requests.get(target_url, headers=headers, timeout=30)
            else:  # POST
                # Special handling for multipart/form-data
                if 'multipart/form-data' in self.headers.get('Content-Type', ''):
                    # Parse the multipart data properly
                    from io import BytesIO
                    import cgi
                    
                    # Create environment for cgi.FieldStorage
                    environ = {
                        'REQUEST_METHOD': 'POST',
                        'CONTENT_TYPE': self.headers['Content-Type'],
                        'CONTENT_LENGTH': self.headers['Content-Length']
                    }
                    
                    # Parse form data
                    form = cgi.FieldStorage(
                        fp=BytesIO(body),
                        environ=environ,
                        keep_blank_values=True
                    )
                    
                    # Reconstruct files dict for requests
                    files = {}
                    for key in form.keys():
                        field = form[key]
                        if field.filename:
                            files[key] = (field.filename, field.file.read(), field.type)
                    
                    response = requests.post(target_url, files=files, timeout=30)
                else:
                    response = requests.post(target_url, data=body, headers=headers, timeout=30)
            
            # Send response back to client
            self.send_response(response.status_code)
            
            # Send headers (skip hop-by-hop headers)
            for key, value in response.headers.items():
                if key.lower() not in ['connection', 'transfer-encoding', 'content-encoding', 'content-length']:
                    self.send_header(key, value)
            
            # Send content-length
            content = response.content
            self.send_header('Content-Length', str(len(content)))
            self.end_headers()
            
            # Send body
            if content:
                self.wfile.write(content)
                
        except requests.exceptions.RequestException as e:
            # API is not reachable
            error_response = json.dumps({
                "error": "API not reachable",
                "detail": str(e),
                "url": target_url
            })
            self.send_response(503)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(error_response)))
            self.end_headers()
            self.wfile.write(error_response.encode())
        except Exception as e:
            # Other errors
            error_response = json.dumps({
                "error": "Proxy error",
                "detail": str(e)
            })
            self.send_response(500)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(error_response)))
            self.end_headers()
            self.wfile.write(error_response.encode())
    
    def proxy_blob_upload(self):
        """Proxy blob uploads to Azure Storage to avoid CORS issues."""
        # Extract blob URL from path: /blob-proxy/{encoded_url}
        import urllib.parse
        
        encoded_url = self.path[12:]  # Remove '/blob-proxy/'
        try:
            blob_url = urllib.parse.unquote(encoded_url)
        except Exception as e:
            error_response = json.dumps({
                "error": "Invalid blob URL",
                "detail": str(e)
            })
            self.send_response(400)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(error_response)))
            self.end_headers()
            self.wfile.write(error_response.encode())
            return
        
        try:
            # Read the file data
            content_length = int(self.headers.get('Content-Length', 0))
            if content_length == 0:
                raise Exception("No file data provided")
            
            file_data = self.rfile.read(content_length)
            
            # Prepare headers for Azure Blob Storage
            headers = {
                'x-ms-blob-type': self.headers.get('x-ms-blob-type', 'BlockBlob'),
                'Content-Type': self.headers.get('Content-Type', 'application/octet-stream')
            }
            
            # Upload to Azure Blob Storage
            response = requests.put(blob_url, data=file_data, headers=headers, timeout=60)
            
            # Send response back to client
            self.send_response(response.status_code)
            
            # Send headers
            for key, value in response.headers.items():
                if key.lower() not in ['connection', 'transfer-encoding', 'content-encoding']:
                    self.send_header(key, value)
            
            self.end_headers()
            
            # Send body if any
            if response.content:
                self.wfile.write(response.content)
            
            print(f"🔄 Blob Proxy: Uploaded to {blob_url[:50]}... -> HTTP {response.status_code}")
                
        except Exception as e:
            error_response = json.dumps({
                "error": "Blob upload failed",
                "detail": str(e)
            })
            self.send_response(500)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(error_response)))
            self.end_headers()
            self.wfile.write(error_response.encode())
    
    def log_message(self, format, *args):
        """Override to provide cleaner logging."""
        # Only log actual requests, not errors
        if len(args) > 0 and isinstance(args[0], str):
            if '/api/' in args[0]:
                print(f"🔄 Proxy: {args[0]}")
            elif 'index.html' in args[0] or args[0] == '"GET / HTTP/1.1"':
                print(f"📁 Static: {args[0]}")
            # Silently ignore other requests like favicon, Chrome DevTools, etc.

if __name__ == '__main__':
    port = 8080
    server = HTTPServer(('', port), ProxyHandler)
    print(f"🌐 OCR Testing Web App")
    print(f"📍 Server running at http://localhost:{port}")
    print(f"🎯 API endpoint: {API_URL}")
    print(f"\n✨ Open http://localhost:{port} in your browser")
    print("Press Ctrl+C to stop\n")
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n👋 Shutting down...")
        server.shutdown()
        server.server_close()
        print("Server stopped")
        sys.exit(0)