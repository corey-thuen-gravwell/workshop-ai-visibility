#!/usr/bin/env python3
"""Mock LLM provider for testing proxies without spending tokens.
Serves OpenAI /v1/chat/completions and Anthropic /v1/messages, streaming and buffered.
If the last user message contains 'tool', the reply is a tool call (get_weather) instead of text."""
import json, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 9999
REPLY = "I am mock-model-1, running in the test harness."

class H(BaseHTTPRequestHandler):
    def log_message(self, f, *a): sys.stderr.write("[mock] " + f % a + "\n")
    def _read(self):
        n = int(self.headers.get("content-length", 0)); return json.loads(self.rfile.read(n) or b"{}")
    def _send(self, code, obj, ctype="application/json"):
        body = json.dumps(obj).encode(); self.send_response(code)
        self.send_header("content-type", ctype); self.send_header("content-length", str(len(body)))
        self.send_header("x-request-id", "req_mock123"); self.end_headers(); self.wfile.write(body)
    def _sse_start(self):
        self.send_response(200); self.send_header("content-type", "text/event-stream")
        self.send_header("cache-control", "no-cache"); self.send_header("x-request-id", "req_mock123"); self.end_headers()
    def _sse(self, data, event=None):
        if event: self.wfile.write(f"event: {event}\n".encode())
        self.wfile.write(f"data: {json.dumps(data) if not isinstance(data, str) else data}\n\n".encode()); self.wfile.flush(); time.sleep(0.02)
    def _wants_tool(self, body):
        msgs = body.get("messages", [])
        last = next((m for m in reversed(msgs) if m.get("role") == "user"), {})
        c = last.get("content", ""); c = c if isinstance(c, str) else json.dumps(c)
        return "tool" in c.lower()
    def do_GET(self):
        if self.path.startswith("/v1/models"):
            return self._send(200, {"object": "list", "data": [{"id": "mock-model-1", "object": "model"}]})
        self._send(404, {"error": "nope"})
    def do_POST(self):
        body = self._read(); auth = self.headers.get("authorization") or self.headers.get("x-api-key")
        sys.stderr.write(f"[mock] auth seen: {str(auth)[:14]}... stream={body.get('stream')}\n")
        if self.path.startswith("/v1/chat/completions"): return self.openai(body)
        if self.path.startswith("/v1/messages"): return self.anthropic(body)
        self._send(404, {"error": {"message": "unknown path " + self.path}})
    # --- OpenAI ---
    def openai(self, body):
        model = body.get("model", "mock-model-1"); tool = self._wants_tool(body)
        usage = {"prompt_tokens": 42, "completion_tokens": 11, "total_tokens": 53}
        if not body.get("stream"):
            msg = {"role": "assistant", "content": None, "tool_calls": [{"id": "call_1", "type": "function", "function": {"name": "get_weather", "arguments": json.dumps({"city": "Boise"})}}]} if tool \
                else {"role": "assistant", "content": REPLY}
            return self._send(200, {"id": "chatcmpl-mock1", "object": "chat.completion", "created": int(time.time()), "model": model,
                                    "choices": [{"index": 0, "message": msg, "finish_reason": "tool_calls" if tool else "stop"}], "usage": usage})
        self._sse_start()
        base = {"id": "chatcmpl-mock1", "object": "chat.completion.chunk", "created": int(time.time()), "model": model}
        if tool:
            self._sse({**base, "choices": [{"index": 0, "delta": {"role": "assistant", "tool_calls": [{"index": 0, "id": "call_1", "type": "function", "function": {"name": "get_weather", "arguments": ""}}]}}]})
            for piece in ['{"city":', ' "Boise"}']:
                self._sse({**base, "choices": [{"index": 0, "delta": {"tool_calls": [{"index": 0, "function": {"arguments": piece}}]}}]})
            self._sse({**base, "choices": [{"index": 0, "delta": {}, "finish_reason": "tool_calls"}]})
        else:
            self._sse({**base, "choices": [{"index": 0, "delta": {"role": "assistant", "content": ""}}]})
            for w in REPLY.split(" "):
                self._sse({**base, "choices": [{"index": 0, "delta": {"content": w + " "}}]})
            self._sse({**base, "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]})
        self._sse({**base, "choices": [], "usage": usage}); self._sse("[DONE]")
    # --- Anthropic ---
    def anthropic(self, body):
        model = body.get("model", "mock-model-1"); tool = self._wants_tool(body)
        usage = {"input_tokens": 42, "output_tokens": 11}
        if not body.get("stream"):
            content = [{"type": "tool_use", "id": "toolu_1", "name": "get_weather", "input": {"city": "Boise"}}] if tool else [{"type": "text", "text": REPLY}]
            return self._send(200, {"id": "msg_mock1", "type": "message", "role": "assistant", "model": model, "content": content,
                                    "stop_reason": "tool_use" if tool else "end_turn", "usage": usage})
        self._sse_start()
        self._sse({"type": "message_start", "message": {"id": "msg_mock1", "type": "message", "role": "assistant", "model": model, "content": [], "usage": {"input_tokens": 42, "output_tokens": 0}}}, "message_start")
        if tool:
            self._sse({"type": "content_block_start", "index": 0, "content_block": {"type": "tool_use", "id": "toolu_1", "name": "get_weather", "input": {}}}, "content_block_start")
            for piece in ['{"city":', ' "Boise"}']:
                self._sse({"type": "content_block_delta", "index": 0, "delta": {"type": "input_json_delta", "partial_json": piece}}, "content_block_delta")
        else:
            self._sse({"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}}, "content_block_start")
            for w in REPLY.split(" "):
                self._sse({"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": w + " "}}, "content_block_delta")
        self._sse({"type": "content_block_stop", "index": 0}, "content_block_stop")
        self._sse({"type": "message_delta", "delta": {"stop_reason": "tool_use" if tool else "end_turn"}, "usage": {"output_tokens": 11}}, "message_delta")
        self._sse({"type": "message_stop"}, "message_stop")

if __name__ == "__main__":
    print(f"mock upstream on :{PORT}", file=sys.stderr); ThreadingHTTPServer(("0.0.0.0", PORT), H).serve_forever()
