# Vibe-code your own proxy
**Padding module P2.** Insert after M9. ~45 min, hands-on.

## Objective
Change the audit tool you have been using all day: add a field it doesn't capture, a destination it
doesn't ship to, and a detection it doesn't make. Do it **with the AI agent**, routed through the
proxy, so the proxy records the conversation in which you modify it.

## Why this is the point, not a bonus
The whole Day-2 argument is *"it's all HTTP anyway"*. If that's true, the proxy isn't a product you
buy, it's 350 lines of Python you own. This is where you find out whether you believe it.

## Setup

```bash
cd ~/jarvis/src/logging-proxy
cp llm_audit_proxy.py ~/myproxy.py          # work on your own copy
```

Run **your** copy, and watch it in a second terminal:

```bash
python3 ~/myproxy.py --listen 0.0.0.0:${WORKSHOPUID}90 \
    --upstream https://api.anthropic.com --log-file ~/myproxy.jsonl
```
```bash
tail -f ~/myproxy.jsonl | jq -c '{event_type, model, data: (.data // "" | .[0:40])}'
```

Point opencode at it (`baseURL: http://localhost:<ID>90/v1`) and ask it to make the changes below.
Hand-editing is fine too, the edits are small, but using the agent is the joke and the point.

> **Restart after every edit.** Python does not reload a running file, and the proxy you are talking
> *through* is the one you are editing. Expect to break your own connection at least once. That is
> the lab.

## Task 1: Capture a field it currently drops

The proxy never records `temperature`, so you cannot answer *"was anyone running our models at
temperature 0?"*

Add it, so every event carries it. **Then check your `tail -f`: the first attempt usually shows
`temperature` missing, or absent entirely.**

*Hint: find where the request body is parsed into `meta`. Then follow `meta` and see how much of it
actually reaches the event. Not all of it does.*

## Task 2: Add a destination

JSONL, stdout, TCP and syslog are supported. Add a **webhook**: POST each event as JSON to a URL,
behind a `--webhook` flag.

Give yourself something to receive it:

```bash
python3 -c "
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
class H(BaseHTTPRequestHandler):
    def log_message(self,*a): pass
    def do_POST(self):
        d = json.loads(self.rfile.read(int(self.headers['content-length'])))
        print('got', d.get('event_type'), flush=True)
        self.send_response(200); self.send_header('content-length','0'); self.end_headers()
ThreadingHTTPServer(('127.0.0.1',9500),H).serve_forever()"
```

*Hint: every event already funnels through one method. Add your destination there and you get all of
them for free: including ones you haven't thought about.*

## Task 3: Make it detect something

Flag events whose text contains a **secret-shaped string**: an `sk-…` API key, an `AKIA…` AWS id,
a `ghp_…` GitHub token, a PEM header. Add a field naming what was found.

**One hard rule: record the *shape*, never the secret.** A security tool that copies credentials
into your SIEM has made the problem worse. Truncate, or emit a class name.

Test it by sending yourself a fake one:

```bash
curl -sS http://localhost:${WORKSHOPUID}90/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" -H 'anthropic-version: 2023-06-01' \
  -H 'content-type: application/json' \
  -d '{"model":"claude-haiku-4-5","max_tokens":16,"messages":[{"role":"user",
       "content":"is sk-ant-api03-AAAABBBBCCCCDDDD still valid?"}]}'
```

*Hint: real Anthropic keys contain hyphens. A character class of `[A-Za-z0-9]` will quietly match
almost none of them: check your pattern against the string above rather than assuming.*

## Task 4: Read what you just did

Your proxy logged the entire conversation in which you modified your proxy.

```bash
jq -r 'select(.event_type=="request.user_message") | .data' ~/myproxy.jsonl | tail -20
jq -r 'select(.event_type=="response.tool_call") | .tool_name' ~/myproxy.jsonl | sort | uniq -c
```

1. Which files did the agent read and write?
2. If this had been a colleague changing your detection tooling, is this the record you'd want?
3. Anything in there you would not want shipped to a SIEM your whole company can read?

## Discussion
- You changed what gets collected in about twenty minutes. What does that say about the argument
  that you have to wait for a vendor to add a field?
- Your webhook sink now sends prompts to a third destination. Who approved that, and how would
  anyone know?
- The detection you wrote runs **in the path**. What happens to the request when it fires, and what
  *should* happen?

## Take-home
`~/myproxy.py` is yours. It is one stdlib file with no dependencies, it speaks two vendor APIs, and
you have now proved you can change it.
