#!/usr/bin/env python3
"""Serve the bundled game locally and open it in the browser (Python 3 only)."""
from functools import partial
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
import threading
import webbrowser

root = Path(__file__).resolve().parent
web = root / 'web'
if not web.exists():
    web = root / 'build' / 'web'
if not (web / 'index.html').exists():
    raise SystemExit('Web build not found. Extract the entire download before running play.py.')

class Handler(SimpleHTTPRequestHandler):
    extensions_map = {**SimpleHTTPRequestHandler.extensions_map, '.wasm': 'application/wasm', '.pck': 'application/octet-stream'}
    def log_message(self, fmt, *args):
        pass

# Stable origin preserves browser saves across launches. No access from other machines.
try:
    server = ThreadingHTTPServer(('127.0.0.1', 8766), partial(Handler, directory=str(web)))
except OSError as error:
    raise SystemExit('Could not open local port 8766. Close any previous Kyoto launcher, then try again.\n' + str(error))
url = 'http://127.0.0.1:8766/'
print('Kyoto & the Midnight Signal\n' + url + '\nKeep this window open. Press Ctrl+C to stop.')
threading.Timer(0.5, lambda: webbrowser.open(url)).start()
try:
    server.serve_forever()
except KeyboardInterrupt:
    pass
finally:
    server.server_close()
