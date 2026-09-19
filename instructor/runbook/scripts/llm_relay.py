#!/usr/bin/env python3
"""Loopback relay for Lab 01b: adds the Gravwell LLM credential so seats never hold it.

Listens on 127.0.0.1 only. Forwards an allowlisted set of paths to the upstream endpoint with
``Authorization: Bearer <token>`` injected; anything the client sent in Authorization is dropped.
Runs as root under systemd (see start-llm-relay.sh); the token is read from the environment
(LLM_UPSTREAM_URL / LLM_UPSTREAM_TOKEN) and never written to a log or an error body.

Stdlib only: nothing to install.

    python3 llm_relay.py --listen 127.0.0.1:9010
"""
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DEFAULT_ALLOW = "/api/generate,/api/embed,/api/tags"


def log(msg):
    sys.stderr.write(msg + "\n")
    sys.stderr.flush()


class Relay(BaseHTTPRequestHandler):
    server_version = "workshop-llm-relay/1"
    upstream = ""
    token = ""
    allow = set()
    timeout = 180

    def log_message(self, *_):  # silence the default per-request access line
        pass

    def _send(self, code, body, ctype="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _relay(self):
        t0 = time.time()
        path = self.path.split("?", 1)[0]
        if path not in self.allow:
            self._send(403, json.dumps({"error": f"path not allowed by the workshop relay: {path}"}).encode())
            log(f"{self.command} {path} -> 403 (not allowed)")
            return
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else None
        req = urllib.request.Request(self.upstream + path, data=body, method=self.command)
        req.add_header("Authorization", "Bearer " + self.token)
        req.add_header("Content-Type", self.headers.get("Content-Type") or "application/json")
        req.add_header("Accept", self.headers.get("Accept") or "*/*")
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as r:
                code, ctype, out = r.status, r.headers.get("Content-Type", "application/json"), r.read()
        except urllib.error.HTTPError as e:
            code, ctype, out = e.code, e.headers.get("Content-Type", "application/json"), e.read()
        except Exception as e:  # upstream down / DNS / TLS, never echo anything sensitive
            code, ctype = 502, "application/json"
            out = json.dumps({"error": f"upstream unreachable: {type(e).__name__}"}).encode()
        self._send(code, out, ctype)
        log(f"{self.command} {path} -> {code} {len(body or b'')}B in / {len(out)}B out / {int((time.time()-t0)*1000)}ms")

    do_GET = _relay
    do_POST = _relay


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--listen", default="127.0.0.1:9010", help="host:port (loopback only)")
    ap.add_argument("--upstream", default=os.environ.get("LLM_UPSTREAM_URL", ""), help="or env LLM_UPSTREAM_URL")
    ap.add_argument("--allow", default=DEFAULT_ALLOW, help="comma-separated paths to forward")
    ap.add_argument("--timeout", type=int, default=180)
    args = ap.parse_args()

    token = os.environ.get("LLM_UPSTREAM_TOKEN", "")
    if not args.upstream or not token:
        sys.exit("set LLM_UPSTREAM_URL and LLM_UPSTREAM_TOKEN in the environment (see start-llm-relay.sh)")
    host, port = args.listen.rsplit(":", 1)
    if host not in ("127.0.0.1", "localhost", "::1"):
        sys.exit(f"refusing to listen on {host}: this relay holds a credential and must stay on loopback")

    Relay.upstream = args.upstream.rstrip("/")
    Relay.token = token
    Relay.allow = {p.strip() for p in args.allow.split(",") if p.strip()}
    Relay.timeout = args.timeout
    srv = ThreadingHTTPServer((host, int(port)), Relay)
    srv.daemon_threads = True
    log(f"workshop-llm-relay listening on http://{host}:{port} -> {Relay.upstream} (paths: {', '.join(sorted(Relay.allow))})")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
