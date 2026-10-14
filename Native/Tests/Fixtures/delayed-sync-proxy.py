import http.server
import json
import pathlib
import sys
import threading
import time
import urllib.error
import urllib.request

backend, directory, method = sys.argv[1:]
control = pathlib.Path(directory)
mutex = threading.Lock()

def publish(name, value):
    temporary = control / (name + '.tmp')
    temporary.write_text(value)
    temporary.replace(control / name)

class Proxy(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        self.forward()

    def do_POST(self):
        self.forward()

    def forward(self):
        if method == 'FAIL' and not (control / 'online').exists():
            self.send_error(503, 'Isolated server temporarily unavailable')
            return
        body = self.rfile.read(int(self.headers.get('Content-Length', 0)))
        headers = {key: value for key, value in self.headers.items()
                   if key.lower() not in {'host', 'connection', 'content-length'}}
        request = urllib.request.Request(backend.rstrip('/') + self.path, data=body if body else None,
                                         headers=headers, method=self.command)
        try:
            response = urllib.request.urlopen(request, timeout=10)
        except urllib.error.HTTPError as error:
            response = error
        data = response.read()
        status = response.status
        outgoing = dict(response.headers)
        if self.command == method and status == 200 and not (control / 'released').exists():
            with mutex:
                if not (control / 'blocked.json').exists():
                    publish('blocked.json', json.dumps({'method': self.command, 'status': status, 'path': self.path}))
            while not (control / 'released').exists():
                time.sleep(0.01)
        try:
            self.send_response(status)
            for key, value in outgoing.items():
                if key.lower() not in {'connection', 'transfer-encoding', 'content-length'}:
                    self.send_header(key, value)
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Proxy)
publish('url', 'http://127.0.0.1:' + str(server.server_port))
server.serve_forever()
