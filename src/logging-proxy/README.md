# LLM logging proxies (M9 / Lab F)

Two ways to capture **what an AI agent was asked, what tools it was offered, what it chose to call,
and what it answered**: the content the vendor dashboards never give you.

| | Gravwell LLM ingester (primary in class) | `llm_audit_proxy.py` (take-home, vendor-agnostic) |
|---|---|---|
| What | Official `gravwell/llm_ingester` image, runs as a sidecar in the Lab 00 compose | One stdlib-only Python file, no deps, runs anywhere |
| Protocols | OpenAI Chat Completions, Anthropic Messages (streaming + buffered) | Same two, plus passthrough of `/v1/models`, `/v1/embeddings`, `/v1/responses`, `count_tokens` |
| Output | Direct to the student's Gravwell indexer, `tag=llm`, fields as **intrinsic enumerated values** | JSONL to file / stdout / **TCP line** / **UDP syslog** → any SIEM. In class: `--tcp localhost:<ID>05` → `tag=proxy` |
| Sessions | Prefix matching or a client header (`x-claude-code-session-id`) | Same idea (hash of system + first user turn), same header |
| Extras | Token usage, `delta`/`user`/`full` modes, key gating/injection, embeddings preprocessor → semantic search | **`request.tools_offered`** (the advertised tool list), key gating/injection, path allow-list |
| Ports | `<ID>80` OpenAI-compatible · `<ID>81` Anthropic | `<ID>90` (both protocols on one port, routed by path) |

**Same event vocabulary on both**, so one set of searches teaches the concept regardless of SIEM:
`request.system_message`, `request.user_message`, `request.tool_result`, `response.assistant_message`,
`response.reasoning`, `response.tool_call`, `response.usage` (+ proxy-only `request.tools_offered`,
`proxy.passthrough`, `proxy.error`). Common fields: `model`, `session_id`, `tool_name`,
`tool_call_id`, `prompt_tokens`, `completion_tokens`, `upstream_status`, `duration_ms`, `stream`.

## The Gravwell LLM ingester

Config: `labs/00-environment-gravwell/config/llm_ingester.conf` (both listeners forward to
Anthropic: the OpenAI listener uses Anthropic's OpenAI-compatibility layer). Ingest secret and
indexer target are env-driven in the compose (`GRAVWELL_INGEST_SECRET`, `GRAVWELL_CLEARTEXT_TARGETS`).
Docs: https://docs.gravwell.io/ingesters/llm.html

Gotcha (fixed in the compose): the ingester **rewrites its config on boot** to stamp an
`Ingester-UUID`, which fails on a read-only bind mount (`rename … device or resource busy`). The
compose mounts the template at `/config/` and copies it into place before starting the manager.

```
# what did every conversation say / do?
tag=llm intrinsic event_type role model session_id tool_name protocol prompt_tokens completion_tokens
| table event_type role model session_id tool_name prompt_tokens completion_tokens DATA

# every tool the agent invoked, with arguments
tag=llm intrinsic event_type tool_name session_id | grep -e event_type response.tool_call
| table session_id tool_name DATA

# volume by event type
tag=llm intrinsic event_type | count by event_type | table event_type count
```

**Optional (padding module P3):** attach embeddings at ingest with the `vector` preprocessor and
search prompts by meaning with `semantic`, needs an OpenAI-compatible embeddings endpoint:
https://docs.gravwell.io/ingesters/preprocessors/vector.html ·
https://docs.gravwell.io/search/semantic/semantic.html

## `llm_audit_proxy.py`

```bash
# in class (seat <ID>): listen on <ID>90, forward to Anthropic, log to file AND to Gravwell tag=proxy
./llm_audit_proxy.py --listen 0.0.0.0:${WORKSHOPUID}90 --upstream https://api.anthropic.com \
    --log-file ~/proxy.jsonl --tcp localhost:${WORKSHOPUID}05

# point clients at it
export OPENAI_BASE_URL=http://localhost:${WORKSHOPUID}90/v1     # OpenAI-style clients
export ANTHROPIC_BASE_URL=http://localhost:${WORKSHOPUID}90      # Anthropic SDK / Claude Code

# other sinks: --stdout · --syslog siem.example.com:514 (RFC 5424 UDP, JSON as the message)
# hide the real key behind the proxy: --upstream-key "$ANTHROPIC_API_KEY" --client-key some-shared-token
# full transcript every request instead of just the new turn: --log-mode full
```

```
# Gravwell searches on the JSON events
tag=proxy json event_type role model session_id tool_name protocol prompt_tokens data
| table event_type role model session_id tool_name prompt_tokens data

tag=proxy json event_type tool_name data | grep -e event_type response.tool_call | table tool_name data
tag=proxy json event_type tool_names | grep -e event_type request.tools_offered | table tool_names
```

Design notes for students who want to read/extend it: the hands-on version is **padding module
P2**, `labs/_stretch/extend-the-proxy/`:
- `parse_request()`: request side. Add a field here (e.g. log `temperature`).
- `ResponseAccumulator`: rebuilds one logical response from a buffered body **or** from SSE deltas
  (OpenAI `choices[].delta`, Anthropic `content_block_*` events). Tool-call arguments arrive in
  fragments and are concatenated.
- `Sinks`: add a destination (HTTP POST to a webhook, Kafka, …) by adding one method.
- It never buffers the stream before relaying: chunks go to the client as they arrive, and the
  copy is parsed on the side, so the agent doesn't feel the proxy.

## Testing without spending tokens

`instructor/runbook/scripts/mock_llm_upstream.py` fakes both provider APIs (streaming + buffered;
say "tool" in the prompt to get a tool call). Point either proxy's upstream at it:
```bash
python3 mock_llm_upstream.py 9999 &
./llm_audit_proxy.py --upstream http://127.0.0.1:9999 --stdout
```
