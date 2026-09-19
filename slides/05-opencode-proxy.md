---
marp: true
theme: jarvis
paginate: true
header: 'Exploring AI Visibility · Proxies'
---

<!-- _class: lead -->
# From watching to intercepting
## Get that AI traffic

<!--
Everything so far was passive: spotting AI in logs you already had. Now we get active: sit in the path and read the prompts, tools, and responses directly.
-->

---

## Meet the AI user

You install **opencode**, make a project (`moneyprinter` it's 2026, we don't build software to solve problems anymore), point it at a model, and let it run tools.

Now, as the auditor: where are the logs?

- opencode keeps local logs in `~/.local/share/opencode/log/`
- …and they're about as useful as the vendor's. Billing-shaped, not security-shaped.

<!-- Same visibility hole as the network labs, now on your own box. The client logs won't tell you what the model was asked or what it did. -->

---

## The quest for visibility: proxies

If the client won't tell us, we sit **in the middle**.

- **litellm**: popular OpenAI-compatible gateway
- **Gravwell LLM ingester** / **your own**, content-capturing proxies (next)
- **SOCKS**: ol' reliable

Deploy one, route the AI through it, ship its logs to Gravwell or your log analysis tool of choice.

<!-- The proxy is the choke point. Everything the client sends passes through it, which is exactly where visibility should live. -->

---

## litellm: it runs, but…

Stand up litellm in docker (per-attendee `WORKSHOPUID` ports), send a request, ship syslog to Gravwell:

```
tag=syslog grep HTTP
```

**Discussion:** how useful are these logs, really?

> Spoiler: you get that a request happened. Not the prompt. Not the tools. Not the response.

<!-- litellm logs prove traffic flowed. They don't capture the content we actually need. The success-callback path never worked cleanly either. So: plan B. -->

---

## Plan B: it's all HTTP anyway

We need a proxy that **actually logs**: prompts, tool lists, tool calls, responses.

Two of them, same event model:

- **Gravwell LLM ingester**: official sidecar, prepped for this workshop. OpenAI + Anthropic listeners, streaming, tool calls, sessions, token usage: `tag=llm`
- **`llm_audit_proxy.py`**: python, no dependencies. Same events as JSONL / TCP / syslog to *any* SIEM (`tag=proxy` in Gravwell). Take it home and run it.

> **Bonus exercise:** extend the Python proxy, time permitting.

<!-- The ingester is the production-grade path if you run Gravwell. The Python proxy proves the point that none of this is magic, it's HTTP, JSON, and a few hundred lines, and gives non-Gravwell shops something to leave with. Both emit the same event_type vocabulary, so the detections in Lab 07 Part 3 do not care which one produced the data. -->

---

## opencode → your proxy

```jsonc
// ~/.config/opencode/opencode.json: Anthropic-native, via the ingester's :4181 listener
{ "provider": { "anthropic": { "options": { "baseURL": "http://localhost:<ID>81" } } } }
```
```jsonc
// …or OpenAI-compatible, via :4180 (or the Python proxy on <ID>90)
"provider": { "myprovider": {
  "npm": "@ai-sdk/openai-compatible",
  "options": { "baseURL": "http://localhost:<ID>80/v1" },
  "models": { "jarvis": { "name": "Jarvis the best AI" } } } }
```

Now interact with the agent and watch entries appear:

```
tag=llm intrinsic event_type tool_name session_id | table event_type tool_name session_id DATA
```

<!-- One config change repoints the agent through your logging proxy. From here, everything the model sees and says is yours. Point out the session_id: the proxy stitched turns into a conversation without any help from the client. -->

---

## What you'll see

| event_type | who | what |
|---|---|---|
| `request.system_message` | client | the system prompt |
| `request.user_message` | user | the newest turn |
| `request.tools_offered` | client | every tool the agent *could* call *(Python proxy)* |
| `response.tool_call` | model | the tool it *did* call, with arguments |
| `request.tool_result` | client | what came back |
| `response.assistant_message` | model | what it said |
| `response.usage` | - | tokens in / out |

<!-- This table is the contract for the rest of the class. Lab 07 Part 3 builds detections on exactly these fields: tool_name, session_id, event_type. -->

---

## The prompt you didn't write

Before your words, the client sends a **system prompt**: the harness's own standing instructions to
the model, plus a schema for every tool the model may call.

- It is **not a setting on your box**. It is text in the HTTP body, rebuilt by the client on every request.
- The API is stateless (M2), so it is **re-sent in full, every turn**, and billed every turn.
- The UI never shows it. The client's local logs don't keep it. **The proxy is where you read it.**

`request.system_message`, and it is the first thing in every conversation you just captured.

<!-- Say it plainly: the model has no memory and no config file. Everything that makes opencode behave like opencode is prose, shipped up the wire with each request. That prose is now sitting in their Gravwell. -->

---

## What opencode actually sends

One question, **28 characters** typed: *"which model are you running?"*. Measured on a lab seat:

| What went up | Size |
|---|---|
| System prompt: persona, tone, task rules, tool policy | **9,259 chars** (~2,300 tokens) |
| Tool definitions: 10 tools, `bash` and `write` among them | on every request |
| An `<env>` block: working directory, git repo or not, platform, date | the client volunteered it |
| Your `AGENTS.md`, pasted in verbatim under "Instructions from: …" | 9,259 → **9,416 chars** |
| A **second, hidden request** to name the conversation, on a **different model** | **2,096 chars**, ~600 tokens |

### The bill for those 28 characters: **10,595 input tokens.**

<!-- 28 characters in, 10,595 input tokens billed, and the system prompt is only ~2,300 of them: most of the rest is tool schemas. Nobody in the room typed the env block. And the title generator ran on Haiku while the work ran on Sonnet, so an inventory that says "we use Sonnet" was already wrong. -->

---

## Why an auditor reads it

- It is the tool's **real behaviour spec**. Release notes are marketing; the system prompt is what the model was actually told.
- Those IMPORTANT/NEVER rules are **requests, not controls**. Nothing enforces them. Your proxy is the only place their failure is visible.
- It is an **inventory signal**: the opening line names the tool, so a hash of the prompt fingerprints the client. Shadow AI from the network labs, now at content level.
- It is **writable by your coworkers**. `AGENTS.md`, `CLAUDE.md`, a rules file, an MCP server's tool descriptions (M10): all of it lands inside the prompt, unreviewed.

> **CL4R1T4S**: <https://github.com/elder-plinius/CL4R1T4S>, a community repo of system prompts extracted from popular AI tools. Unofficial, and useful for exactly that reason.

<!-- CL4R1T4S is worth 30 seconds on the projector: scroll it, note how many familiar products are in there, and note that the community had to extract these because vendors don't publish them. Then the point that matters: you don't need the repo, you have a proxy, and yours is current and yours. -->

---

## "User" is a role, not a person

```
tag=llm intrinsic event_type session_id | grep -e session_id <one session>
| sort by TIMESTAMP asc | table TIMESTAMP event_type DATA
```

Between your turns the client uploads, under user-side roles:

- **tool results**: the file it just read, in full. Your source code, at the provider, because the agent opened it.
- **its own reminders** and environment updates
- the newest thing you typed, somewhere in the middle of all that

<!-- Run this live if you have a session handy. The moment that lands is finding a file's contents in the transcript that nobody pasted. That is the data-loss conversation, and it is the same event model Lab 07 Part 3 writes detections against. -->

---

<!-- _class: lead -->
# Labs 04–05
## Configure opencode to use various proxies for data collection

<span class="muted">`stage-opencode` → `stage-llm-proxy`</span>

<!-- Hands-on chain: opencode configured, litellm up, then the real logging proxy, each with a checkpoint so nobody's stuck. -->
