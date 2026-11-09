# A tiny web app for the Docker intro. Standard library only: the image needs no pip install.
import signal
import socket
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = 8000
count = 0


class Hello(BaseHTTPRequestHandler):
    def do_GET(self):
        global count
        if self.path != "/":
            self.send_error(404)  # browsers also ask for /favicon.ico; do not count it
            return
        count += 1
        body = f"hello from {socket.gethostname()}, request #{count}\n".encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


# As PID 1 in a container, Python ignores SIGTERM by default; without this, docker stop has to kill it.
signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
print(f"listening on port {PORT}", flush=True)
# 0.0.0.0, not localhost: published ports arrive on the container's network interface.
HTTPServer(("0.0.0.0", PORT), Hello).serve_forever()
