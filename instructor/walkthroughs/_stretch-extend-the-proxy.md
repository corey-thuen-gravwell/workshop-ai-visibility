# Walkthrough: P2: Vibe-code your own proxy

> ⛔ **INSTRUCTOR ONLY.** Contains the reference solutions. Student handout:
> [`labs/_stretch/extend-the-proxy/README.md`](../../labs/_stretch/extend-the-proxy/README.md).

**Padding module P2** · **~45 min hands-on** · insert after M9 · **Flex:** optional
**The reference solutions run against `mock_llm_upstream.py`, so you can rehearse without spending tokens.**

## Why this module earns its slot

M9 ends with "it's all HTTP anyway, take the proxy home." P2 is where that claim gets tested. The
edits are small, but each one teaches something the deck can only assert:

| Task | What it actually teaches |
|---|---|
| 1 · add a field | The envelope **cherry-picks**: you must follow the data, not change one line |
| 2 · add a sink | Every event funnels through one method; find it and you get all events free |
| 3 · add a detection | A security tool that copies secrets into your SIEM made things worse |
| 4 · read the log | You just used an AI to modify your audit tooling, and you have the transcript |

## Timing

| Min | Segment |
|---:|---|
| 0–8 | Setup: own copy, running, `tail -f` in a second terminal, opencode pointed at it |
| 8–20 | Task 1: the field, and the cherry-pick trap |
| 20–32 | Task 2: the webhook sink |
| 32–42 | Task 3: the detection, and the "shape not secret" rule |
| 42–45 | Task 4: read the transcript, discussion |

Running short? Cut Task 2: it is the least surprising of the three. **Keep Task 3**; the
"never copy the secret" rule is the one they will actually reuse at work.

## Setup notes

- **Their own copy** (`~/myproxy.py`). Do not let them edit the repo file, `git checkout` later
  wipes their work and the repo copy is what other labs use.
- **`tail -f` in a second terminal is not optional.** Without it the loop is edit → guess. With it,
  every change is visible in a second.
- They are editing the proxy they are talking *through*. Restarting drops opencode's connection
  mid-conversation. **Say this before they start**, or the first restart reads as a bug.
- No API spend needed for testing shapes, `instructor/runbook/scripts/mock_llm_upstream.py` on a
  spare port works for everything except Task 4's transcript.

---

## Task 1: the field · reference solution

**Two edits, and that is the lesson.** In `parse_request`:

```python
    meta = {"model": body.get("model"), "stream": bool(body.get("stream")),
            "session_id": session_id_for(system_text, msgs), "max_tokens": body.get("max_tokens"),
            "temperature": body.get("temperature"),          # <-- added
```

That alone changes **nothing**, because `_handle` builds the envelope by naming fields explicitly:

```python
        env = {**base, "model": meta.get("model"), "session_id": meta.get("session_id"),
               "stream": meta.get("stream", False),
               "temperature": meta.get("temperature")}       # <-- and here
```

*Beat:* almost everyone does the first edit, restarts, sees nothing, and assumes they broke it.
**Let them.** Then ask: "you added it to `meta`, is `meta` what gets emitted?" That question is the
whole exercise. Grepping for where `meta` is consumed is a five-second answer and a lasting habit.

**Measured after both edits:** every event carries `temperature=0.7`.

## Task 2: the sink · reference solution

`Sinks.emit` is the single funnel. Three small additions:

```python
# in Sinks.__init__
        self.webhook = urlsplit(a.webhook) if getattr(a, "webhook", None) else None

# in Sinks.emit, alongside the other sinks
            if self.webhook: self._webhook(line)

# a new method
    def _webhook(self, line):
        try:
            u = self.webhook
            C = http.client.HTTPSConnection if u.scheme == "https" else http.client.HTTPConnection
            c = C(u.netloc, timeout=3)
            c.request("POST", u.path or "/", body=line.encode(),
                      headers={"content-type": "application/json"})
            c.getresponse().read(); c.close()
        except OSError as e:
            sys.stderr.write(f"[proxy] webhook sink failed: {e}\n")
```

Plus the flag: `ap.add_argument("--webhook", help="URL, POST each event as JSON")`.

*Beat:* they added one destination and got **every** event type, including ones they never
considered. That is what a funnel buys you, and it is why the tool is 350 lines instead of 3,000.

Watch for a **blocking** webhook: a slow endpoint stalls the proxy and therefore the agent. Good
discussion: should an audit sink be allowed to slow down the thing it audits? (The shipped sinks are
best-effort and swallow errors for exactly this reason.)

## Task 3: the detection · reference solution

```python
SECRET_RE = re.compile(r"(sk-[A-Za-z0-9_-]{16,}|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20,}"
                       r"|-----BEGIN [A-Z ]*PRIVATE KEY-----)")

def secret_hits(text):
    """Return de-duplicated *shapes*: never the secret itself."""
    return sorted({m.split("-")[0][:4] + "…" if m.startswith("-----") else m[:6] + "…"
                   for m in SECRET_RE.findall(text or "")})
```

Wired into the funnel, so it covers every event with no per-call-site changes:

```python
    def emit(self, ev):
        hits = secret_hits(ev.get("data"))
        if hits:
            ev = {**ev, "secret_shapes": hits, "secret_count": len(hits)}
        line = json.dumps(ev, ensure_ascii=False, separators=(",", ":"))
```

**Measured:**

```
request.user_message   temperature=0.7  secret_shapes=['AKIAIO…', 'sk-ant…']
response.assistant…    temperature=0.7  secret_shapes=None
```

### The trap, and it is a good one

The obvious pattern is `sk-[A-Za-z0-9]{16,}`. Real Anthropic keys look like
`sk-ant-api03-…`: **the hyphens stop the match dead**, so that pattern catches AWS keys and
silently misses the one that matters. My first version did exactly this.

*Beat:* "Your detection ran clean against a live key and reported nothing. How long would it have
taken to notice?" That is a better lesson about detection engineering than anything on a slide.

### The rule to enforce out loud

**Log the shape, never the secret.** If someone emits the full match, stop the room. A tool that
copies credentials into a SIEM that the whole company can search has *increased* exposure, and the
students who did it will recognise the mistake instantly, which is why it is worth catching live.

## Task 4: read the transcript

```bash
jq -r 'select(.event_type=="request.user_message") | .data' ~/myproxy.jsonl | tail -20
jq -r 'select(.event_type=="response.tool_call") | .tool_name' ~/myproxy.jsonl | sort | uniq -c
```

*Closing beat:* "You just used an AI agent to modify your security tooling. It read and wrote files
on this box. And the only reason you can say precisely what it did is that you were running the
thing that records it, which you also just modified." That is the whole course in one paragraph,
and it is the right note to end a padding module on.

## Answer key

| Q | Answer |
|---|---|
| Why doesn't adding to `meta` work? | `_handle` builds `env` by naming fields explicitly; `meta` is not spread |
| Where does one sink cover all events? | `Sinks.emit`: the single funnel |
| Why does `sk-[A-Za-z0-9]{16,}` fail? | Real keys contain hyphens; the class must include `-` |
| What must never be logged? | The matched secret. Emit a shape/class/truncation |
| Tools the agent used | `read`, `edit`, `bash`, visible in `response.tool_call` |

## Where students get stuck

1. **Editing the repo copy** instead of `~/myproxy.py`. Their work vanishes at the next
   `git checkout … -- .`
2. **Forgetting to restart.** Python does not hot-reload. Symptom: "my change did nothing."
3. **Editing the proxy they are talking through.** The restart kills the in-flight opencode session.
   Expected; warn first.
4. **Adding the field to `meta` only**, Task 1's designed trap.
5. **A regex that never fires**, because of the hyphen. Give them the test string, not the answer.
