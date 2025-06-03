from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler

class CORSRequestHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
        super().end_headers()

# Use ThreadingHTTPServer instead of HTTPServer
server = ThreadingHTTPServer(('localhost', 8000), CORSRequestHandler)
server.serve_forever()