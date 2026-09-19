#!/usr/bin/env python3
"""
llm_audit_proxy.py: a vendor-agnostic, SIEM-agnostic LLM logging proxy. Python 3.9+, stdlib only.

Sits between an LLM client (opencode, Claude Code, curl, an SDK) and the provider. Forwards every
request unmodified, streams the response back, and emits ONE JSON EVENT PER LOGICAL THING that
happened: the same event model Gravwell's LLM ingester uses, so the searches taught in class work
against either source:

    request.system_message    the system prompt
    request.user_message      the newest user turn (delta mode) or every message (full mode)
    request.tool_result       a tool result the client sent back to the model
    request.tools_offered     the tool list the client advertised (name + description), the
                              "what could this agent do?" record the vendor never gives you
    response.assistant_message  what the model said
    response.reasoning        exposed reasoning/thinking, when present
    response.tool_call        a tool the model asked to run, with arguments
    response.usage            token accounting
    proxy.error               upstream failure / parse failure (never silently dropped)

Protocols: OpenAI Chat Completions (/v1/chat/completions) and Anthropic Messages (/v1/messages),
streaming (SSE) and buffered. Anything else on the allowed-path list is forwarded and logged as
`proxy.passthrough`. Sinks (any combination): JSONL file, stdout, TCP line (Gravwell simple_relay,
Splunk TCP, anything that eats newline-delimited JSON), UDP syslog (RFC 5424 with the JSON as msg).

    ./llm_audit_proxy.py --listen 0.0.0.0:1290 --upstream https://api.anthropic.com \
        --log-file proxy.jsonl --tcp localhost:1205
    export OPENAI_BASE_URL=http://localhost:1290/v1   ANTHROPIC_BASE_URL=http://localhost:1290

The client's own credentials pass through untouched unless --upstream-key is set, in which case
the real key stays in the proxy and clients present whatever (or --client-key gates them).
"""
import argparse, base64, datetime as dt, hashlib, http.client, json, os, socket, ssl, sys, threading, time, uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

VERSION = "1.0.0"
HOP_HEADERS = {"connection", "keep-alive", "proxy-authenticate", "proxy-authorization", "te", "trailers",
               "transfer-encoding", "upgrade", "host", "content-length", "accept-encoding"}
DEFAULT_ALLOWED = ["/v1/chat/completions", "/v1/messages", "/v1/messages/count_tokens", "/v1/models",
                   "/v1/embeddings", "/v1/responses"]

# ----------------------------------------------------------------------------- sinks
class Sinks:
    """Fan a JSON event out to every configured destination. Thread-safe, best-effort per sink."""
    def __init__(self, a):
        self.lock = threading.Lock(); self.stdout = a.stdout
        self.fh = open(a.log_file, "a", buffering=1) if a.log_file else None
        self.tcp = self._hostport(a.tcp); self.tcp_sock = None
        self.syslog = self._hostport(a.syslog); self.udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM) if self.syslog else None
        self.hostname = socket.gethostname()
    @staticmethod
    def _hostport(s):
        if not s: return None
        h, _, p = s.rpartition(":"); return (h or "127.0.0.1", int(p))
    def emit(self, ev):
        line = json.dumps(ev, ensure_ascii=False, separators=(",", ":"))
        with self.lock:
            if self.stdout: sys.stdout.write(line + "\n"); sys.stdout.flush()
            if self.fh: self.fh.write(line + "\n")
            if self.tcp: self._tcp(line)
            if self.syslog: self._syslog(line, ev)
    def _tcp(self, line):
        for attempt in (1, 2):
            try:
                if self.tcp_sock is None:
                    self.tcp_sock = socket.create_connection(self.tcp, timeout=3)
                self.tcp_sock.sendall((line + "\n").encode()); return
            except OSError as e:
                try: self.tcp_sock and self.tcp_sock.close()
                except OSError: pass
                self.tcp_sock = None
                if attempt == 2: sys.stderr.write(f"[proxy] tcp sink {self.tcp} failed: {e}\n")
    def _syslog(self, line, ev):
        ts = ev.get("ts", dt.datetime.now(dt.timezone.utc).isoformat())
        msg = f"<134>1 {ts} {self.hostname} llm_audit_proxy - {ev.get('event_type','-')} - {line}"
        try: self.udp.sendto(msg.encode(), self.syslog)
        except OSError as e: sys.stderr.write(f"[proxy] syslog sink failed: {e}\n")

# ----------------------------------------------------------------------------- helpers
def now_iso(): return dt.datetime.now(dt.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")
def text_of(content):
    """Flatten OpenAI/Anthropic content (str or list of parts) into plain text."""
    if content is None: return ""
    if isinstance(content, str): return content
    out = []
    for part in content:
        if isinstance(part, str): out.append(part)
        elif isinstance(part, dict):
            t = part.get("type")
            if t in ("text", "input_text", "output_text"): out.append(part.get("text", ""))
            elif t == "tool_result": out.append(text_of(part.get("content")))
            elif t in ("image", "image_url", "input_image"): out.append("[image]")
            elif t == "document": out.append("[document]")
    return "".join(out)
def session_id_for(system_text, messages):
    """Derive a stable conversation id from the first user turn + system prompt (what the Gravwell
    ingester calls prefix matching, simplified). Clients that stamp their own header win."""
    first = next((text_of(m.get("content")) for m in messages if m.get("role") == "user"), "")
    return hashlib.sha1((system_text[:2000] + "\x00" + first[:2000]).encode("utf-8", "replace")).hexdigest()[:16]

# ----------------------------------------------------------------------------- protocol: request side
def parse_request(protocol, body, log_mode):
    """Return (events, meta). events lack the common envelope; meta carries model/session/stream."""
    ev = []; msgs = body.get("messages") or []
    if protocol == "anthropic-messages":
        system_text = text_of(body.get("system"))
    else:
        system_text = "\n".join(text_of(m.get("content")) for m in msgs if m.get("role") in ("system", "developer"))
    if system_text: ev.append({"event_type": "request.system_message", "role": "system", "data": system_text})
    # user / tool-result messages
    chosen = msgs if log_mode == "full" else msgs[-1:]  # delta: only the newest message is new information
    for m in chosen:
        role = m.get("role"); content = m.get("content")
        if role in ("system", "developer"): continue
        if protocol == "openai-chat" and role == "tool":
            ev.append({"event_type": "request.tool_result", "role": "tool", "tool_call_id": m.get("tool_call_id"), "data": text_of(content)})
        elif role == "user":
            parts = content if isinstance(content, list) else [content]
            for p in parts:
                if isinstance(p, dict) and p.get("type") == "tool_result":
                    ev.append({"event_type": "request.tool_result", "role": "tool", "tool_call_id": p.get("tool_use_id"), "data": text_of(p.get("content"))})
            txt = text_of([p for p in parts if not (isinstance(p, dict) and p.get("type") == "tool_result")])
            if txt: ev.append({"event_type": "request.user_message", "role": "user", "data": txt})
        elif role == "assistant" and log_mode == "full":
            ev.append({"event_type": "request.assistant_message", "role": "assistant", "data": text_of(content)})
    tools = body.get("tools") or []
    if tools:
        names = []
        for t in tools:
            f = t.get("function", t)
            names.append({"name": f.get("name"), "description": (f.get("description") or "")[:300]})
        ev.append({"event_type": "request.tools_offered", "role": "client", "tool_count": len(names),
                   "tool_names": [n["name"] for n in names], "data": json.dumps(names, ensure_ascii=False)})
    meta = {"model": body.get("model"), "stream": bool(body.get("stream")),
            "session_id": session_id_for(system_text, msgs), "max_tokens": body.get("max_tokens"),
            "tool_choice": body.get("tool_choice") if isinstance(body.get("tool_choice"), str) else None}
    return ev, meta

# ----------------------------------------------------------------------------- protocol: response side
class ResponseAccumulator:
    """Rebuilds the logical response from a buffered JSON body or a stream of SSE events."""
    def __init__(self, protocol):
        self.p = protocol; self.text = []; self.reasoning = []; self.tools = {}; self.usage = None
        self.request_id = None; self.model = None; self.stop = None; self._anth_blocks = {}
    # buffered
    def from_json(self, obj):
        self.request_id = obj.get("id"); self.model = obj.get("model")
        if self.p == "openai-chat":
            for ch in obj.get("choices") or []:
                m = ch.get("message") or {}; self.stop = ch.get("finish_reason")
                if m.get("content"): self.text.append(text_of(m["content"]))
                if m.get("reasoning_content"): self.reasoning.append(m["reasoning_content"])
                for tc in m.get("tool_calls") or []:
                    f = tc.get("function") or {}
                    self.tools[tc.get("id") or str(len(self.tools))] = {"name": f.get("name"), "arguments": f.get("arguments") or ""}
            self.usage = obj.get("usage")
        else:
            for b in obj.get("content") or []:
                if b.get("type") == "text": self.text.append(b.get("text", ""))
                elif b.get("type") == "thinking": self.reasoning.append(b.get("thinking", ""))
                elif b.get("type") == "tool_use": self.tools[b.get("id")] = {"name": b.get("name"), "arguments": json.dumps(b.get("input", {}))}
            self.stop = obj.get("stop_reason"); self.usage = obj.get("usage")
    # streaming
    def from_sse_data(self, data):
        if data.strip() == "[DONE]": return
        try: obj = json.loads(data)
        except ValueError: return
        if self.p == "openai-chat":
            self.request_id = self.request_id or obj.get("id"); self.model = self.model or obj.get("model")
            if obj.get("usage"): self.usage = obj["usage"]
            for ch in obj.get("choices") or []:
                d = ch.get("delta") or {}
                if ch.get("finish_reason"): self.stop = ch["finish_reason"]
                if d.get("content"): self.text.append(d["content"])
                if d.get("reasoning_content"): self.reasoning.append(d["reasoning_content"])
                for tc in d.get("tool_calls") or []:
                    key = tc.get("index", 0); slot = self.tools.setdefault(key, {"id": None, "name": None, "arguments": ""})
                    if tc.get("id"): slot["id"] = tc["id"]
                    f = tc.get("function") or {}
                    if f.get("name"): slot["name"] = f["name"]
                    if f.get("arguments"): slot["arguments"] += f["arguments"]
        else:
            t = obj.get("type")
            if t == "message_start":
                m = obj.get("message", {}); self.request_id = m.get("id"); self.model = m.get("model"); self.usage = dict(m.get("usage") or {})
            elif t == "content_block_start":
                self._anth_blocks[obj.get("index")] = obj.get("content_block", {})
                cb = obj["content_block"]
                if cb.get("type") == "tool_use": self.tools[obj.get("index")] = {"id": cb.get("id"), "name": cb.get("name"), "arguments": ""}
            elif t == "content_block_delta":
                d = obj.get("delta", {}); dtp = d.get("type")
                if dtp == "text_delta": self.text.append(d.get("text", ""))
                elif dtp == "thinking_delta": self.reasoning.append(d.get("thinking", ""))
                elif dtp == "input_json_delta" and obj.get("index") in self.tools: self.tools[obj["index"]]["arguments"] += d.get("partial_json", "")
            elif t == "message_delta":
                self.stop = (obj.get("delta") or {}).get("stop_reason")
                if obj.get("usage"): (self.usage or {}).update(obj["usage"]) if self.usage is not None else None; self.usage = self.usage or obj["usage"]
    def events(self):
        ev = []
        if self.reasoning: ev.append({"event_type": "response.reasoning", "role": "assistant", "data": "".join(self.reasoning)})
        if self.text: ev.append({"event_type": "response.assistant_message", "role": "assistant", "data": "".join(self.text)})
        for k, t in self.tools.items():
            ev.append({"event_type": "response.tool_call", "role": "assistant", "tool_name": t.get("name"),
                       "tool_call_id": t.get("id") or (k if isinstance(k, str) else None), "data": t.get("arguments", "")})
        if self.usage:
            u = self.usage
            pt = u.get("prompt_tokens", u.get("input_tokens")); ct = u.get("completion_tokens", u.get("output_tokens"))
            ev.append({"event_type": "response.usage", "role": "assistant", "prompt_tokens": pt, "completion_tokens": ct,
                       "total_tokens": u.get("total_tokens", (pt or 0) + (ct or 0)), "data": ""})
        return ev

# ----------------------------------------------------------------------------- the proxy
class Proxy(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"; server_version = f"llm_audit_proxy/{VERSION}"
    def log_message(self, fmt, *args):
        if self.server.args.verbose: sys.stderr.write("[proxy] " + fmt % args + "\n")

    def _protocol(self):
        if self.path.startswith("/v1/chat/completions"): return "openai-chat"
        if self.path.startswith("/v1/messages") and not self.path.startswith("/v1/messages/count_tokens"): return "anthropic-messages"
        return None
    def _allowed(self):
        a = self.server.args
        return a.allow_unknown_paths or any(self.path.split("?")[0].startswith(p) for p in a.allowed_paths)
    def _client_ip(self): return self.headers.get("x-forwarded-for", self.client_address[0]).split(",")[0].strip()

    def do_GET(self): self._handle(b"")
    def do_POST(self):
        n = int(self.headers.get("content-length") or 0)
        if n > self.server.args.max_body: return self._reply(413, {"error": "request body too large"})
        self._handle(self.rfile.read(n) if n else b"")

    def _reply(self, code, obj):
        body = json.dumps(obj).encode(); self.send_response(code); self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body))); self.end_headers(); self.wfile.write(body)

    def _handle(self, body):
        a = self.server.args; t0 = time.monotonic(); proto = self._protocol()
        req_uuid = str(uuid.uuid4()); client_ip = self._client_ip()
        if not self._allowed():
            return self._reply(404, {"error": f"path not proxied: {self.path} (see --allow-path)"})
        if a.client_key:
            presented = (self.headers.get("authorization") or "").removeprefix("Bearer ").strip() or self.headers.get("x-api-key", "")
            if presented != a.client_key: return self._reply(401, {"error": "bad client key"})
        # --- request-side events
        base = {"ts": now_iso(), "proxy_request_id": req_uuid, "client_ip": client_ip, "listener": a.listen,
                "protocol": proto or "passthrough", "path": self.path, "method": self.command,
                "user_agent": self.headers.get("user-agent", "")}
        meta = {}; req_events = []
        if proto and body:
            try:
                parsed = json.loads(body); req_events, meta = parse_request(proto, parsed, a.log_mode)
            except ValueError as e:
                req_events = [{"event_type": "proxy.error", "data": f"request body not JSON: {e}"}]
        sid = self.headers.get(a.session_header) if a.session_header else None
        if sid: meta["session_id"] = sid
        env = {**base, "model": meta.get("model"), "session_id": meta.get("session_id"), "stream": meta.get("stream", False)}
        for e in req_events: self.server.sinks.emit({**env, **e})
        # --- forward upstream
        up = self.server.upstream
        headers = {k: v for k, v in self.headers.items() if k.lower() not in HOP_HEADERS}
        headers["host"] = up.netloc
        if a.upstream_key:
            if proto == "anthropic-messages" or "x-api-key" in {k.lower() for k in headers}:
                headers.pop("authorization", None); headers["x-api-key"] = a.upstream_key
            else:
                headers.pop("x-api-key", None); headers["authorization"] = f"Bearer {a.upstream_key}"
        if proto == "anthropic-messages" and "anthropic-version" not in {k.lower() for k in headers}:
            headers["anthropic-version"] = "2023-06-01"
        headers["content-length"] = str(len(body))
        conn_cls = http.client.HTTPSConnection if up.scheme == "https" else http.client.HTTPConnection
        kw = {"timeout": a.timeout}
        if up.scheme == "https" and a.insecure_upstream: kw["context"] = ssl._create_unverified_context()
        try:
            conn = conn_cls(up.hostname, up.port, **kw)
            conn.request(self.command, up.path.rstrip("/") + self.path, body=body, headers=headers)
            resp = conn.getresponse()
        except (OSError, http.client.HTTPException) as e:
            self.server.sinks.emit({**env, "event_type": "proxy.error", "upstream_status": 502, "data": f"upstream {up.geturl()} unreachable: {e}"})
            return self._reply(502, {"error": {"message": f"upstream unreachable: {e}"}})
        # --- relay response, accumulating for the log
        acc = ResponseAccumulator(proto) if proto else None
        ctype = resp.getheader("content-type", ""); streaming = "text/event-stream" in ctype
        self.send_response(resp.status)
        for k, v in resp.getheaders():
            if k.lower() not in HOP_HEADERS and k.lower() != "content-encoding": self.send_header(k, v)
        raw = b""
        if streaming:
            self.send_header("transfer-encoding", "chunked"); self.end_headers(); buf = b""
            while True:
                chunk = resp.read1(8192) if hasattr(resp, "read1") else resp.read(8192)
                if not chunk: break
                self.wfile.write(b"%x\r\n%s\r\n" % (len(chunk), chunk)); self.wfile.flush()
                if acc:
                    buf += chunk
                    while b"\n\n" in buf:
                        frame, buf = buf.split(b"\n\n", 1)
                        for line in frame.decode("utf-8", "replace").splitlines():
                            if line.startswith("data:"): acc.from_sse_data(line[5:].strip())
            self.wfile.write(b"0\r\n\r\n"); self.wfile.flush()
        else:
            raw = resp.read(); self.send_header("content-length", str(len(raw))); self.end_headers(); self.wfile.write(raw)
            if acc and resp.status < 400:
                try: acc.from_json(json.loads(raw))
                except ValueError as e: self.server.sinks.emit({**env, "event_type": "proxy.error", "data": f"response not JSON: {e}"})
        conn.close()
        dur = int((time.monotonic() - t0) * 1000)
        tail = {**env, "upstream_status": resp.status, "duration_ms": dur, "request_id": (acc.request_id if acc else None) or resp.getheader("x-request-id"),
                "model": (acc.model if acc and acc.model else env["model"]), "stop_reason": acc.stop if acc else None}
        if not proto:
            self.server.sinks.emit({**tail, "event_type": "proxy.passthrough", "data": ""}); return
        if resp.status >= 400:
            self.server.sinks.emit({**tail, "event_type": "proxy.error", "data": raw[:2000].decode("utf-8", "replace") if raw else f"upstream HTTP {resp.status}"}); return
        for e in acc.events(): self.server.sinks.emit({**tail, **e})

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--listen", default=os.environ.get("PROXY_LISTEN", "127.0.0.1:1290"), help="host:port to listen on")
    ap.add_argument("--upstream", default=os.environ.get("PROXY_UPSTREAM", "https://api.anthropic.com"), help="provider base URL")
    ap.add_argument("--upstream-key", default=os.environ.get("PROXY_UPSTREAM_KEY"), help="inject this API key upstream (else pass client's through)")
    ap.add_argument("--client-key", default=os.environ.get("PROXY_CLIENT_KEY"), help="require clients to present this key")
    ap.add_argument("--log-mode", choices=["delta", "full"], default="delta", help="delta: newest message only; full: every message every request")
    ap.add_argument("--session-header", default="x-claude-code-session-id", help="client header carrying a conversation id")
    ap.add_argument("--log-file", help="append JSONL events here")
    ap.add_argument("--stdout", action="store_true", help="print JSONL events to stdout")
    ap.add_argument("--tcp", help="host:port, newline-delimited JSON over TCP (e.g. Gravwell simple_relay)")
    ap.add_argument("--syslog", help="host:port, RFC5424 UDP syslog, JSON as the message")
    ap.add_argument("--allow-path", dest="allowed_paths", action="append", default=None, help="add a forwarded path prefix (repeatable)")
    ap.add_argument("--allow-unknown-paths", action="store_true", help="forward every path (INSECURE with --upstream-key)")
    ap.add_argument("--insecure-upstream", action="store_true", help="skip upstream TLS verification (lab only)")
    ap.add_argument("--timeout", type=float, default=600.0); ap.add_argument("--max-body", type=int, default=16 * 1024 * 1024)
    ap.add_argument("-v", "--verbose", action="store_true"); ap.add_argument("--version", action="version", version=VERSION)
    a = ap.parse_args()
    a.allowed_paths = DEFAULT_ALLOWED + (a.allowed_paths or [])
    if not (a.log_file or a.stdout or a.tcp or a.syslog): a.stdout = True
    host, _, port = a.listen.rpartition(":")
    srv = ThreadingHTTPServer((host or "0.0.0.0", int(port)), Proxy); srv.daemon_threads = True
    srv.args = a; srv.upstream = urlsplit(a.upstream); srv.sinks = Sinks(a)
    sys.stderr.write(f"[proxy] llm_audit_proxy {VERSION} listening on {a.listen} -> {a.upstream} "
                     f"(mode={a.log_mode}, key={'injected' if a.upstream_key else 'pass-through'})\n")
    try: srv.serve_forever()
    except KeyboardInterrupt: pass

if __name__ == "__main__": main()
