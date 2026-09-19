# Walkthrough 05: LLM proxies: from access logs to content

> ⛔ **INSTRUCTOR ONLY.** Contains every answer. Student handout:
> [`labs/05-llm-proxy/README.md`](../../labs/05-llm-proxy/README.md).

**Modules:** M8 (Lab E, 60 min) + M9 (Lab F, 105 min) = **165 min**
**Checkpoint:** `stage-llm-proxy` (one for the whole lab)
**Flex:** M8 is ⏱ and is the **first thing to cut** (−60); M9 is 🔒
**Deck:** [`slides/05-opencode-proxy.md`](../../slides/05-opencode-proxy.md)

This is the payoff module for the whole course. The network and endpoint labs ended on "we can see *that* AI happened, never
*what*." This is where that changes. Everything before it is setup; everything after it (MCP,
detections) analyzes what this module captures.

---

## The three paths, at a glance

| Path | What lands |
|---|---|
| litellm → `tag=syslog` | access lines, on the raw-text listener `<ID>09` |
| LLM ingester → `tag=llm` | 7 event types incl. `response.reasoning`, `request.tool_result` |
| Python proxy → `tag=proxy` | 7 event types incl. `request.tools_offered` |
| Key-injection gateway | wrong token 401 / right token 200; the two-tier chain |

## Five gotchas that will cost you class time

1. **`docker logs <ID>llm` is empty.** The ingester logs to a file *inside* the container. Use
   `docker exec <ID>llm tail -20 /opt/gravwell/log/llm_ingester.log`.
2. **opencode's `baseURL` needs a `/v1` suffix.** The SDK appends `/messages`, so
   `http://localhost:<ID>81` 404s on every request. It must be `http://localhost:<ID>81/v1`.
3. **opencode ignores `ANTHROPIC_API_KEY` if a stored credential exists.** If anyone has ever run
   `opencode auth login`, the stored credential wins and you get *"API key is invalid"* through the
   proxy. Put the token in `options.apiKey` in the config instead, which is what the key
   architecture wants anyway.
4. **litellm ships to its own raw-text listener on `<ID>09`**, not to the image's built-in syslog
   listeners. Those are `Reader-Type=rfc5424` and **silently drop** docker's default RFC3164. Rather
   than negotiate formats for logs we only intend to squint at, `config/simple_relay-litellm.conf`
   declares a listener with **no `Reader-Type`**: raw line-delimited text, whatever the driver
   sends.
5. **Never bind 514 or 601 in `simple_relay.conf.d`.** The stock image already defines
   `syslogudp`/`syslogtcp` there. A duplicate bind fails config validation, simple_relay exits 0
   three times, and the manager sleeps 10 minutes: killing *every* ingest listener, not just
   syslog. Our listener uses its own port precisely to avoid this. Debug with
   `docker exec <ID>gravwell /opt/gravwell/bin/gravwell_simple_relay -validate`.

## Timing

| Min | Segment | |
|---:|---|---|
| **M8** | | |
| 0–15 | Slides: why the choke point is the proxy | |
| 15–30 | litellm up, one request through it | |
| 30–45 | `testai.sh`, look at `tag=syslog` | |
| 45–60 | **The discussion.** What do you actually know? | |
| **M9** | | |
| 60–70 | Slides: plan B, it's all HTTP anyway | |
| 70–93 | Ingester: confirm hot, point opencode, prompt it | |
| 93–107 | `tag=llm`: find your own prompt, the tool calls, the tokens | |
| 107–117 | Install the LLM Observability kit, same data through someone else's dashboards | ⏱ |
| 117–135 | Python proxy: run it, re-point, compare | |
| 135–140 | Slides: the prompt you didn't write | |
| 140–160 | **Part 2c:** read the system prompt, measure it, write into it with `AGENTS.md`, then "user is a role, not a person" | |
| 160–165 | Debrief: the event model is the portable part | |

**Running late?** Skip M8 entirely and open M9 with one slide: "generic gateways log like load
balancers." You lose the students' own discovery of that fact, which is a real loss, but M9 is the
module that matters. Do not compress M9 to save M8, and in particular do not drop Part 2c: reading
the system prompt is the part of this module people quote back to you months later.

## Prerequisites

- Lab 00 stack up, including the `<ID>llm` sidecar. **litellm's syslog logging driver connects at
  container start**: if Gravwell isn't listening on `<ID>514/udp`, the litellm container fails to
  start. Bring Gravwell up first, always.
- `stage-opencode` (Lab 04): opencode installed and working against a provider.
- A **live** `ANTHROPIC_API_KEY` in `~/.workshop_env`. This is the first module that actually
  spends tokens. Twenty seats × a handful of short prompts is small money, but confirm the key
  works and has quota **before** the room finds out for you.

## Rehearsing without spending tokens

You can dry-run the entire M9 half against the mock provider, do this the night before:

```bash
python3 instructor/runbook/scripts/mock_llm_upstream.py 9999 &
python3 src/logging-proxy/llm_audit_proxy.py --upstream http://127.0.0.1:9999 --stdout
# in another shell, send it anything; put "tool" in the prompt to get a tool call back
```

The mock serves both OpenAI `/v1/chat/completions` and Anthropic `/v1/messages`, streaming and
buffered. To rehearse the ingester instead, point a listener's `Upstream-URL` at the mock in
`labs/00-environment-gravwell/config/llm_ingester.conf`.

---

# Part 1: litellm (M8)

## Step 1: Bring it up

```bash
cd ~/jarvis/labs/05-llm-proxy/litellm
docker compose up -d
docker compose logs --tail 20
```

**Expected:** litellm listening on `<ID>00`, no auth errors.

| Symptom | Cause | Fix |
|---|---|---|
| Container exits immediately, `failed to initialize logging driver` | Gravwell isn't up: nothing on `<ID>514/udp` | Start the Lab 00 stack first, then `docker compose up -d` here |
| `ANTHROPIC_API_KEY: unbound variable` | Non-interactive shell | `. ~/.workshop_env` |
| 401 from the gateway | Client didn't present the master key | It's `sk-workshop` unless `LITELLM_MASTER_KEY` was overridden |
| `port is already allocated` | Two seats on one ID, or a stale container | `docker ps -a` |

## Step 2: Drive it

```bash
cd ~/jarvis/labs/05-llm-proxy
./testai.sh
```

Sends four short prompts and first prints the gateway's routing table. Checkpoint
`N=10 ./testai.sh` if you want more rows to look at.

**Expected:** real answers coming back, proving traffic flowed through the gateway to Anthropic.

## Step 3: The discussion (this *is* the module)

```
tag=syslog grep HTTP
```

**Expected:** one access-log line per request, timestamp, method, path, status, latency. Genuine
proof that requests happened.

Now run the exercise properly. Ask the room to find, in those logs:

| Question | Answer |
|---|---|
| The text of any prompt | **Not there.** |
| The model's reply | **Not there.** |
| Which tools the agent was offered | **Not there.** |
| Which tools it called, with what arguments | **Not there.** |
| Whether any of it touched sensitive data | **Not there.** |
| That a request occurred, to which model, and how long it took | ✅ There. |

*Beat:* "This is what most 'AI governance' deployments actually have. A gateway, an access log, and
a slide that says we have visibility into AI usage." Let it land before you rescue them.

### The marker demo: do this one live

The most convincing 60 seconds in the course. Send **the same nonsense word** through both proxies,
then grep for it. Run it on the projector once M9 is up (or record it beforehand):

```bash
MARKER="pineapple-quesadilla-7731"
# 1) through litellm, the generic gateway
curl -sS http://localhost:${WORKSHOPUID}00/v1/chat/completions \
  -H "Authorization: Bearer sk-workshop" -H 'content-type: application/json' \
  -d "{\"model\":\"claude-fast\",\"max_tokens\":24,
       \"messages\":[{\"role\":\"user\",\"content\":\"Repeat this word back: $MARKER\"}]}"
# 2) through the Gravwell LLM ingester, the content-capturing proxy
curl -sS http://localhost:${WORKSHOPUID}81/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" -H "anthropic-version: 2023-06-01" \
  -H 'content-type: application/json' \
  -d "{\"model\":\"claude-haiku-4-5\",\"max_tokens\":24,
       \"messages\":[{\"role\":\"user\",\"content\":\"Repeat this word back: $MARKER\"}]}"
```

Then, in Gravwell:

```
tag=syslog grep "pineapple-quesadilla-7731"     ->  no results
tag=llm    grep "pineapple-quesadilla-7731"     ->  the prompt AND the reply
```

**Same request. Same provider. Same second. One proxy remembers what was said and the other
doesn't.** That is the entire M8→M9 arc, and it fits on one screen.

> **Why not just turn on litellm's content logging?** Fair question, and someone will ask. litellm
> has a `success_callback` path; the original workshop tried it and **it never worked cleanly**.
> More importantly, the architectural point stands: a routing gateway's job is routing, and its
> logging is shaped like a load balancer's. You want a proxy built to *audit*, which is Part 2.
> Don't spend more than a minute here.

---

# Part 2a: The Gravwell LLM ingester (M9)

## Step 4: Confirm the sidecar is hot

```bash
docker exec ${WORKSHOPUID}llm grep -i hot /opt/gravwell/log/llm_ingester.log
```

> **`docker logs ${WORKSHOPUID}llm` returns nothing**: this container logs to a file inside
> itself, not stdout. Don't let an empty `docker logs` convince you the sidecar is broken.

**Expected:** `Ingester gone hot`, plus two `starting listener` lines, `:4180` (published
`<ID>80`, OpenAI-compatible) and `:4181` (published `<ID>81`, Anthropic Messages).

| Symptom | Cause | Fix |
|---|---|---|
| Restart loop, `device or resource busy` on rename | The ingester rewrites its config on boot to stamp an `Ingester-UUID`; a `:ro` bind mount blocks it | The compose already mounts to `/config/` and `cp`s it in. If someone changed that, revert. **The manager backs off 10 min after 3 failures**: fix, then `docker compose up -d --force-recreate llm-ingester` |
| `Failed authentication, bad secret` | `GRAVWELL_INGEST_SECRET` mismatch between sidecar and indexer | All three (indexer AUTH, simple_relay SECRET, sidecar SECRET) must be the same value |
| Hot, but nothing lands in `tag=llm` | Nothing has been sent through it yet | That's Step 5 |

## Step 5: Point opencode at it

```jsonc
// ~/moneyprinter/opencode.json  (the Lab 04 project file; it already says this)
{ "$schema": "https://opencode.ai/config.json",
  "provider": { "anthropic": { "options": {
      "baseURL": "http://localhost:<ID>81/v1",
      "apiKey":  "<their ANTHROPIC_API_KEY>" } } },
  "model": "anthropic/claude-sonnet-5" }
```

**One config file, the project one.** Do not point students at `~/.config/opencode/opencode.json`:
that puts them on two configs at once. opencode merges the global file with the
project's `opencode.json` and the project wins, so a `baseURL` change in the global file did
nothing while they sat in `~/moneyprinter`. It also writes an almost-empty
`~/.config/opencode/opencode.jsonc` on first run, so students find a file they never made and edit
that. The handout edits `~/moneyprinter/opencode.json` for every part, with an aside explaining
the two locations. If a seat is behaving oddly, `cat ~/.config/opencode/opencode.json*` and remove
any `provider` block there.

⚠️ **The `/v1` is not optional** and **the key must be in `options.apiKey`**, not the environment.
Each mistake produces a different confusing failure (`404 page not
found` and `API key is invalid` respectively).

The Anthropic-native listener (`<ID>81`) is the simpler path, use it. The OpenAI-compatible one
(`<ID>80`) is the one that goes through Anthropic's compat layer and is the **less-proven** of the
two; keep it as the "other provider style" demo, not the default.

**The key they paste is the real provider key**, from their own `~/.workshop_env`. It passes
straight through the ingester to Anthropic; the ingester records the conversation and does not hold
a credential. There is no key-injecting gateway in front of the seats, deliberately: that reveal
belongs to Step 9, where they build the boundary themselves and watch the key leave their
workstation. See [`../runbook/api-key-architecture.md`](../runbook/api-key-architecture.md) for the
decision and why an earlier gateway design was dropped.

Then have them run two prompts:

1. *"which model are you running?"*, a plain text exchange.
2. Something that forces tool use: *"list the files in this directory and tell me what this project
   does."*

> **The answer to #1 is frequently wrong, and that is a gift.** In testing, a request explicitly
> routed to `claude-haiku-4-5` came back *"I'm Claude 3.5 Sonnet, made by Anthropic"*, while the
> proxy log recorded `model: claude-haiku-4-5-20251001`. Show both side by side.
>
> *Beat:* the model is an unreliable narrator about itself. Your proxy is not. **If your AI
> inventory is built on asking the assistant what it is, your inventory is fiction**, this is the
> shadow-AI lesson from Lab 02 arriving from the opposite direction.

## Step 6: Find it in Gravwell

Fields arrive as **intrinsic enumerated values**, so searches use `intrinsic`, not `json`:

```
tag=llm intrinsic event_type role model session_id tool_name prompt_tokens completion_tokens
| table event_type role model session_id tool_name prompt_tokens completion_tokens DATA
```

```
tag=llm intrinsic event_type tool_name session_id | grep -e event_type response.tool_call
| table session_id tool_name DATA
```

```
tag=llm intrinsic event_type | count by event_type | table event_type count
```

Checkpoint `stage-llm-proxy` covers this and everything else in the lab.

### Answers to the four tasks

**(a) Find your own "which model" prompt and the reply.**
`event_type=request.user_message` carries the prompt; `response.assistant_message` carries the
reply. Both in `DATA`. *Beat:* thirty minutes ago the best you could say was "a request happened."

**(b) List every tool the agent called and its arguments.**
`event_type=response.tool_call`, with `tool_name` and the arguments in `DATA`. Streaming responses
deliver tool arguments in fragments and the ingester **reassembles** them, worth pointing out,
because a naive proxy that logs raw chunks gives you unusable confetti.

**(c) How many tokens did your session cost?**
`event_type=response.usage`, with `prompt_tokens` / `completion_tokens`.
```
tag=llm intrinsic event_type session_id prompt_tokens completion_tokens
| grep -e event_type response.usage
| stats sum(prompt_tokens) as in sum(completion_tokens) as out by session_id
| table session_id in out
```
**Real numbers from a measured session:** one small opencode task, list a directory,
read a 3-line file, answer in two sentences: cost **22,393 input tokens and 350 output tokens**.
Sixty-four input tokens for every output token.

*Beat:* this is per-session cost attribution the vendor dashboard will not give you, on data you
own. And look at the ratio: `prompt_tokens` climbs every turn because the client resends the whole
conversation each time (M2). **The stateless-API lesson from this morning is now a line on a bill.**

**(d) How many sessions are there, and how did the proxy decide?**
`count by session_id`. The ingester assigns a session either from the
`Session-ID-Header` (`x-claude-code-session-id`, when the client sends one) or by **prefix
matching**: same system prompt + same conversation opening within `Session-Match-Window`
(10) and `Session-TTL` (30m), both set in `llm_ingester.conf`.
*Beat:* ask what breaks that heuristic. Answers you're steering toward: two users with identical
system prompts, or a long gap mid-conversation. Sessionization is inference unless the client
cooperates: which is an argument for making your clients send a session header.

---

## Part 2a2: the LLM Observability kit

Gravwell publishes **LLM Observability** (`io.gravwell.llm_observability`, min 5.10.0, on the kit
server) for exactly the ingester the students just pointed opencode at. Installing it here is the
third time the room meets a kit, and the first time one fits without an argument.

**What they get**, counted off a real install (5.10.1): five dashboards (Traffic Overview
· Cost and Token Usage · Tool Use · Performance and Reliability · Semantic Risk Hunting), 25
searches, two templates (Conversation Reconstruction by `session_id`, Semantic Hunt), eight macros,
five playbooks, two resources, two files. **No dependencies**, so there is no "this needs another
kit" prompt the way Corelight has one in Lab 02, and it installs in about six seconds. It asks for
two config macros on the way in, `LLM_TAG` (default `llm`) and `LLM_SEMANTIC_THRESHOLD` (default
70); both defaults are right here.

**The teaching beats, in order:**

1. **It fits with no edit.** `LLM_TAG` expands to `llm`, which is the `Tag-Name` on both listeners
   in `llm_ingester.conf`. Put that next to Lab 03, where the Sysmon kit's `PROVIDER` macro said
   `Microsoft-Windows-Sysmon` and our data said `Linux-Sysmon`, so nothing populated until they
   edited it. Same mechanism, opposite outcome: a kit is a set of assumptions, and you check them.
2. **The macros are the queries they just typed.** `$LLM_USAGE` is
   `intrinsic event_type == "response.usage"`, `$LLM_TOOL_CALLS` is the `response.tool_call` filter.
   The kit's own searches read `tag=$LLM_TAG $LLM_USAGE session_id model total_tokens | stats …`,
   which is their step-4 query with the filter hidden behind a name.
3. **Four dashboards populate; the fifth throws an error on every panel.** Semantic Risk Hunting
   needs the `vector` preprocessor on the ingester and the `[AI]` block on the webserver, and a seat
   has neither, so each panel returns

   > `semantic (module idx 1) error: cannot use the semantic module. An embedding model is not configured.`

   Say out loud that it is an error and not a bug, because it looks like breakage: a kit can ship a
   capability your deployment has not enabled, and the message names it. That capability is the P3
   demo, so this is the moment to point at it.

   **Measured tile by tile** against a seat with real ingester traffic: Tool Use 3/3 panels with
   data, Cost and Token Usage 4/4, Traffic Overview 6/7, Performance and Reliability 3/6. Every one
   of the four empty panels is an **upstream-errors** panel, which needs a request that actually
   failed. That is worth knowing in advance for two reasons: an empty error panel is the correct
   state for a healthy seat, and the student who typos their API key is the one whose panel lights
   up. If somebody's does, put it on the projector.
4. **Conversation Reconstruction** on a `session_id` from the token-spend panel replays their own
   conversation in order, from a query they did not write: system prompt, user message, reply, usage,
   oldest first, `tool_name` and `duration_ms` blank on the turns that do not carry them. It is the
   same thing they will build by hand in Lab 07 Part 3.
5. **What it looks like with a real agent** (three opencode tasks
   through the `<ID>81` listener). Four of the kit's panels do a better job of making the course's
   own points than the slides do, so read them out:

   | Panel | What it showed | The point |
   |---|---|---|
   | Tool Call Frequency | `bash` 8 · `read` 5 · `edit` 1 | Lower case, because tool names are the *client's* label. Claude Code writes `Read`. That is the P4 finding, in a panel |
   | Top Sessions by Token Spend | 127,543 · 32,656 · 10,587 on sonnet, then three haiku sessions of 613 to 1,176 | The little ones are opencode's `small_model` writing session titles. **Sessions are not tasks**, and nobody asked for those three |
   | Prompt vs Completion Ratio | sonnet **168,631 prompt against 2,155 completion** | Seventy-eight to one. M2's "the client resends the whole conversation" is now a line on a bill |
   | Token Totals by Model | `claude-sonnet-5`, `claude-haiku-4-5-20251001`, `claude-haiku-4-5` | The same model under two names, one pinned and one aliased. Ask the room what that does to a detection keyed on model |

6. **Traffic by Listener** is quietly useful later: both listeners are named in the seat config
   (`openai` and `anthropic`), so a room that runs P4 sees Claude Code arrive on one and opencode on
   the other, in a panel nobody wrote.

**Timing:** ten minutes, and it is ⏱ if you are behind: the lab works without it. Install it from
the front of the room if the venue's kit-server fetch is slow.

**If the kit server is unreachable** (an air-gapped instance, or a seat with no egress), the kit is
open source at <https://github.com/gravwell/kits/tree/main/llm_observability> and installs from a
file. Same for anyone working through this alone.

---

# Part 2b: The vendor-agnostic proxy (M9)

The pitch: *not everyone runs Gravwell, and you should be able to take this home.* One stdlib
Python file, no dependencies, same event vocabulary, any SIEM.

## Step 7: Run it

```bash
cd ~/jarvis/src/logging-proxy
./llm_audit_proxy.py --listen 0.0.0.0:${WORKSHOPUID}90 --upstream https://api.anthropic.com \
    --log-file ~/proxy.jsonl --tcp localhost:${WORKSHOPUID}05
```

Both protocols on one port, routed by path. Two sinks at once: a local file they can `tail`, and
TCP into Gravwell's `<ID>05` listener → `tag=proxy`.

Re-point opencode at `http://localhost:<ID>90` and repeat the prompts. Checkpoint
`stage-llm-proxy`.

| Symptom | Cause | Fix |
|---|---|---|
| Events in `~/proxy.jsonl` but nothing in `tag=proxy` | `<ID>05` listener not up, or Gravwell down | `ss -ltn \| grep ${WORKSHOPUID}05` |
| Connection refused from opencode | Proxy bound to `127.0.0.1` | Use `--listen 0.0.0.0:<ID>90` as written |
| 404s on unusual paths | Path allow-list | `--allow-path <prefix>` (repeatable), or `--allow-unknown-paths` (never with `--upstream-key`) |
| Want to see it live | | `tail -f ~/proxy.jsonl \| jq -r '.event_type + " " + (.tool_name // "")'` |

## Step 8: Compare the two

```
tag=proxy json event_type role model session_id tool_name protocol prompt_tokens data
| table event_type role model session_id tool_name prompt_tokens data
```

Note `json` here vs `intrinsic` for `tag=llm`: different extraction, **same field names**, which
is the deliberate design. One set of concepts, two implementations.

### The task: find `request.tools_offered`

```
tag=proxy json event_type tool_names | grep -e event_type request.tools_offered | table tool_names
```

This is the **only event the ingester does not produce**, and the most interesting one in the
module.

**Measured in a real opencode session:** the agent **called `read`**, and was
**offered 10 tools**: `bash`, `edit`, `glob`, `grep`, `read`, `skill`, `task`, `todowrite`,
`webfetch`, `write`. One used; ten available; `bash` and `write` among them, on every single turn.
Put those two numbers on a slide.

*Beat: ask the room why you'd want it:* `response.tool_call` tells you what the agent **did**.
`request.tools_offered` tells you what it **could have done**. That's the agent's blast radius on
every single turn. If an agent is offered a `delete_file` tool a thousand times and calls it once,
the tool call is the incident and the offer list is the risk you were carrying all along. It's also
the thing that changes silently when someone adds an MCP server, which is exactly where Labs 06 and
07 go next.

Full event vocabulary, both sources:

`request.system_message` · `request.user_message` · `request.assistant_message` ·
`request.tool_result` · `request.tools_offered`\* · `response.assistant_message` ·
`response.reasoning` · `response.tool_call` · `response.usage` · `proxy.passthrough`\* ·
`proxy.error`\*: (\* = Python proxy only)

## Step 9: the proxy as a key boundary (not a stretch: do this one)

> **This is the only place in the course where students see a key boundary**, now that seats hold the
> real key and there is no gateway in front of them (see
> [`../runbook/api-key-architecture.md`](../runbook/api-key-architecture.md)). It is not
> optional: it's the payoff for the whole key discussion, and it takes four minutes.

```bash
./llm_audit_proxy.py --listen 0.0.0.0:${WORKSHOPUID}90 --upstream https://api.anthropic.com \
    --upstream-key "$ANTHROPIC_API_KEY" --client-key hunter2 --log-file ~/proxy.jsonl
```

Then remove `ANTHROPIC_API_KEY` from opencode's environment and give it `hunter2` instead.

*Beat:* the workstation no longer holds a provider key. Revoking one developer's access is now a
line in your proxy config, not a key rotation across the fleet. Ask where this would sit in their
network: egress proxy for the dev VLAN, per-team gateway, sidecar per CI runner. This is the
architecture slide they'll actually take back to work.

---

# Part 2c: The system prompt (M9)

The pitch: *you have spent an hour building the only place this text can be read, so read it.*
Students have `tag=llm` (Part 2a) and `tag=proxy` (Part 2b) full of `request.system_message` events
they have walked straight past.

**Which tag holds live traffic now?** Whatever opencode points at. After Part 2b that is the Python
proxy, so anything they run in this part lands in `tag=proxy` (`json … data`) while the ingester's
copy from Part 2a still sits in `tag=llm` (`intrinsic … DATA`). Either is fine; say it out loud
once, because the "my search returns nothing" hands all come from this.

Two `tag=proxy` gotchas: `len(data)` counts JSON escaping (9,851 where the prompt is
really 9,720 characters), and a `[^\n]+` capture does not stop at a line end because the newlines
are escaped in the JSON. Use `[^\\ ]+` on `tag=proxy`, `[^\n]+` on `tag=llm`.

## Reference numbers from a seat run (real API)

`opencode 1.18.29`, seat `workshop29`, Anthropic Sonnet 5 through the ingester's `<ID>81` listener.
Three invocations: *"which model are you running?"*, *"read pricing.py and tell me in one sentence
what it does"*, and *"hi"* after `AGENTS.md` was added. Numbers move with every opencode release
and with the model you route to; the *shape* is what matters. Re-measure before class.

| What the client sent | Measured |
|---|---|
| Main agent system prompt | **9,259 chars**, roughly 2,300 tokens |
| The same prompt after adding `AGENTS.md` | **9,416 chars**: the file, verbatim, plus its header line |
| Second, hidden request per question: the **title generator** | **2,096 chars**, its own `session_id`, ~600 input tokens, and it runs on **`claude-haiku-4-5`**, not the model they chose |
| One 28-character question, end to end | **10,595 input tokens / 42 output**. The system prompt is ~2,300 of those; most of the rest is tool schemas, which `tag=llm` does not log and `request.tools_offered` on the Python proxy does |
| Three-turn session with one file read | **32,146 in / 193 out** |
| Events for three questions | 6 `request.system_message`, 6 `request.user_message`, 2 `response.tool_call`, 2 `request.tool_result`, 3 `response.reasoning`, 8 `response.usage` |

Section headings in the main prompt: *Tone and style · Professional objectivity · Task Management ·
Doing tasks · Tool usage policy · Code References*, then the machine-written tail:

```
<env>
  Working directory: /home/workshop29/moneyprinter
  Workspace root folder: /
  Is directory a git repo: no
  Platform: linux
  Today's date: Fri Sep 11 2026
</env>
Instructions from: /home/workshop29/moneyprinter/AGENTS.md
# Project rules
MARKER-8842: always address the user as Captain.
```

Rule-shouting in that prompt: IMPORTANT x 3, NEVER x 3, MUST x 1. Count it live, do not quote these.

> **Do not put the opening line on a slide as a fixed quote.** Routed at Anthropic natively the
> prompt opens *"You are OpenCode, the best coding agent on the planet."*; the same binary through
> an OpenAI-compatible route opened *"You are opencode, an interactive CLI tool that helps users
> with software engineering tasks."* One client, two system prompts, chosen by where you point it.
> That is a finding, not an inconsistency: hand it to the room as one.

*Two models for one question.* The title generator is billed to `claude-haiku-4-5` while the work
runs on Sonnet. Anyone whose AI inventory says "we use Sonnet" is already wrong, and only the proxy
knows.

Reference capture without a stack: `gravwell-evidence/lab05-llm-proxy/`
(`part2c-seat29-system-prompts.csv` is the three prompts as `| text` returned them,
`part2c-opencode-system-prompt.jsonl` is the same client through the Python proxy against the mock).

## Step 10: read it (5 min)

```
tag=llm intrinsic event_type | grep -e event_type request.system_message | text
```

Give them three quiet minutes with it on their own screen. This is the only part of the course
where the exercise is *reading*, and it is the part people quote back to you afterwards.

If nobody has a `request.system_message` in `tag=llm`, they never completed Part 2a; point them at
`tag=proxy json event_type data | grep -e event_type request.system_message | text` instead.

## Step 11: the four measurements (10 min)

```
tag=llm intrinsic event_type | eval chars = len(DATA); | stats sum(chars) as chars by event_type
| sort by chars desc | table event_type chars
```
```
tag=llm intrinsic event_type | grep -e event_type request.system_message
| eval fp = hash_sha256(DATA); chars = len(DATA); | stats count by fp chars | table fp chars count
```
```
tag=llm intrinsic event_type | grep -e event_type request.system_message
| regex -e DATA "Working directory: (?P<cwd>[^\n]+)" | table cwd DATA
```

**Note the eval syntax**: statements are semicolon-terminated, *including the last one*.
`eval chars = len(DATA)` without the trailing `;` is a parse error ("unexpected EOF"), and the
error text does not say so. It costs five minutes if you let them find it alone.

| Task | Answer |
|---|---|
| (2a) Ratio of prompt to typed words | 9,259 : 28 on the measured seat, call it 300:1, and that is before the tool schemas |
| (2b) Cost per turn | ~2,400 tokens of system prompt on **every** request, re-sent because the API is stateless. Multiply by the `response.usage` count for the session |
| (2c) Copies Gravwell holds vs the provider received | Gravwell: one (delta mode). The provider: one per turn |
| (3) What enforces those IMPORTANT/NEVER rules | **Nothing.** They are prose asking a text predictor to behave. The enforcement points are elsewhere: the harness's permission prompts, the proxy, the credentials the agent holds. This is the sentence to slow down on |
| (4) Facts about the box, volunteered | working directory (so: username and project name), workspace root, whether it is a git repo, platform, date, the model id. Nobody typed any of it and nothing on the seat records that it was sent |
| (5) How many system prompts | Two per invocation, different sizes, different `session_id`s, and on the seat run **different models**: the 2,096-char title generator went to `claude-haiku-4-5` while the work went to Sonnet. A whole extra request, prompt and bill for a string that only opencode's own UI displays |

*Beat for (5):* they asked one question and paid for two conversations, on two different models.
Expect ~600 input tokens for the title, matching P4's ~606. Ask what else their clients do that they have never seen. The honest answer
is that nobody in the room knew about the title generator until the proxy showed them.

## Step 12: write into the system prompt (10 min)

This is the one they will retell at work.

```bash
cd ~/moneyprinter
echo 'MARKER-8842: always address the user as Captain.' >> AGENTS.md
opencode run "hi"          # a NEW session: delta mode logs the system prompt once per session
```
```
tag=proxy json event_type data | grep -e data "MARKER-8842" | table event_type data
```
(`tag=llm intrinsic event_type | grep -e DATA "MARKER-8842" | table event_type DATA` if they
re-pointed at the ingester.)

**Expected:** the marker inside `request.system_message`, introduced by
`Instructions from: /home/workshopNN/moneyprinter/AGENTS.md`, sitting between the vendor's own
sections. Expect the prompt to grow from 9,259 to 9,416 chars, the student's
own heading (`# Project rules`) joined opencode's list right after `# Code References`, and the
agent's next reply opened **"Hello, Captain."** Run the marker line as an instruction, not a
comment, so the room sees the model obey a file nobody reviewed.

| Task | Answer |
|---|---|
| (a) Which event, how labelled | `request.system_message`, under `Instructions from: <path>` |
| (b) Does it obey | It did on the first seat run, first reply, unprompted: *"Hello, Captain."* On a later run (a one-sentence factual question) it answered plainly and never said Captain, with the marker verifiably in the prompt. Expect "usually", and "usually" is the finding, not "yes" |
| (c) Who can write that file | Anyone with commit rights, plus anything that can write to the repo: a dependency's postinstall, a generated file, a PR from outside. There is no signature, no review requirement, and no log of the change on the seat |

*Beat:* an unreviewed text file in a repo is now part of the instruction set of a process that has
`bash` and `write`. That is the whole of Labs 06 and 07 in one line, and they just did it to
themselves in thirty seconds. Do not let anyone leave this step thinking it is an opencode quirk:
`CLAUDE.md`, `.cursorrules`, `.github/copilot-instructions.md`, every one of them.

## Step 13: "user" is a role, not a person (10 min)

```
tag=llm intrinsic event_type role session_id model | grep -e event_type request.user_message
| sort by TIMESTAMP asc | table TIMESTAMP session_id model DATA

tag=llm intrinsic event_type session_id tool_call_id | grep -e event_type request.tool_result
| eval chars = len(DATA); | table TIMESTAMP session_id tool_call_id chars DATA

tag=llm intrinsic event_type session_id | grep -e session_id <one session>
| sort by TIMESTAMP asc | table TIMESTAMP event_type DATA
```

Have them ask the agent to read a source file, then find that file's contents in Gravwell.

| Task | Answer |
|---|---|
| (a) Which event carried the file | `request.tool_result`. Nobody pasted it; the agent read it and the client uploaded it. On the wire it is a user-role message: to the provider, the "user" sent the source file |
| (b) Chars typed vs chars sent | Two to three orders of magnitude apart on any real task |
| (c) Secret-shaped strings | Often empty, and the point is that the query exists. `regex -e DATA "(?P<secretish>sk-[A-Za-z0-9_-]{16,}\|AKIA[0-9A-Z]{16}\|-----BEGIN [A-Z ]+PRIVATE KEY-----)"`. At work, an agent that reads `.env` to "understand the config" puts the contents in this table |

> **It does land sometimes, in this room, on this lab.** Seen: one hit in
> `request.tool_result`, the context around it `"options": { "baseURL": …, "apiKey": "sk-ant-ap…`.
> The agent had read its own `~/moneyprinter/opencode.json` while answering a question about
> `pricing.py`, so the workshop's provider key went to the provider inside a tool result and into
> the seat's Gravwell. Nobody typed it and nobody asked for it. If it happens in front of you,
> **stop and use it**: it is the whole module in one row, and the follow-up question is the one that
> matters at work, which is not "who pasted a secret" but "which files did the agent decide to
> read". The key is the class key, which is revoked at the end of the day, so there is nothing to
> clean up beyond saying that out loud.

*Beat:* the DLP question at work is not "did someone paste a secret into a chat box." It is "which
files did the agent decide to read." The second is much bigger and nobody has a control for it.

## Slides for this part

`slides/05-opencode-proxy.md`: *The prompt you didn't write* · *What opencode actually sends* ·
*Why an auditor reads it* (with the CL4R1T4S link) · *"User" is a role, not a person*. Put
<https://github.com/elder-plinius/CL4R1T4S> on the projector for thirty seconds: community-extracted
system prompts for tools the room uses. Unofficial, sometimes stale, and the honest framing is the
point: the community had to extract these because vendors do not publish them, and the students now
have a way to extract their own, current, for whatever the company actually runs.

## Cutting this part

Do not. Cut M8 (litellm) instead, which the flex table already says is the first thing to go. If
you are down to five minutes, run Step 10 and Step 12 from the front of the room on your own seat
and skip the measurements: reading the prompt and writing into it are what people remember.

---

## Debrief (5 min)

Three things, in this order:

1. **The client is where state lives, so the path is where visibility lives.** Every request
   carries the entire conversation (M2). Whoever sits in the middle sees all of it. No vendor
   cooperation required.
2. **The event model is the portable part.** `event_type` / `session_id` / `tool_name` are what
   the detections in Lab 07 Part 3 key on, not which SIEM, not which proxy. Two very different
   implementations produced the same searchable vocabulary today.
3. **You now have the data the log-analysis labs couldn't give you.** Same rogue-agent question, but this time you
   can answer what it *said*. That's the setup for MCP and detections.
4. **Most of what your seat sent, nobody at your seat typed.** The system prompt, the tool schemas,
   the environment block, the files the agent chose to read. The proxy is the only inventory of it,
   and the file that edits it is sitting unreviewed in a repo.

## Answer key (short form)

| Q | Answer |
|---|---|
| What does litellm's log tell you? | That a request happened, to which model, status, latency. No prompt, no reply, no tools |
| Where is the prompt under `tag=llm`? | `event_type=request.user_message`, content in `DATA` |
| Where are tool calls? | `event_type=response.tool_call`: `tool_name` + reassembled arguments |
| Session token cost | `event_type=response.usage`, sum `prompt_tokens`/`completion_tokens` by `session_id` |
| How are sessions decided? | `x-claude-code-session-id` header if sent; otherwise prefix matching within `Session-Match-Window`/`Session-TTL` |
| The event only the Python proxy emits | `request.tools_offered`: the agent's blast radius per turn |
| `tag=llm` vs `tag=proxy` extraction | `intrinsic` vs `json`; same field names by design |
| Where is the system prompt? | `event_type=request.system_message`. Once per session in delta mode, every request from the Python proxy |
| How big is it, versus what they typed | ~9,700 chars against 23, plus 10 tool schemas, re-sent every turn |
| What is the second, smaller system prompt | opencode's title generator: its own request, own `session_id`, own bill |
| How does `AGENTS.md` reach the model | Pasted verbatim into the system prompt under `Instructions from: <path>` |
| Which event holds a file the agent read | `request.tool_result`, a user-side role: the "user" sent your source code |
| What enforces the prompt's IMPORTANT/NEVER rules | Nothing. Prose, not a control |

## Where students get stuck

1. **`intrinsic` vs `json`.** Using the wrong one returns nothing and looks like "my data didn't
   land." Put both search shapes on a slide side by side.
2. **Editing `opencode.json` in a terminal editor.** This room is weak on the terminal and this is
   the module with the most config editing. Have the exact JSON on a slide, and consider shipping a
   pre-written file they copy over.
3. **Forgetting to restart opencode** after re-pointing `baseURL`.
4. **Expecting `tag=llm` and `tag=proxy` to both be populated at once.** They point opencode at one
   proxy at a time; the earlier tag keeps its old data, which is what makes the comparison work.
5. **Time range.** Always.
6. **`eval` without a trailing semicolon.** `| eval chars = len(DATA)` is a parse error; it needs
   `| eval chars = len(DATA);`. The error text says "unexpected EOF" and names none of that.
7. **Looking for the marker in the wrong tag.** After Part 2b, new opencode traffic goes to the
   Python proxy (`tag=proxy`), not to the ingester. Say which tag is live before they start Part 2c.
8. **Editing `AGENTS.md` but reusing the session.** Delta mode logs the system prompt once per
   session; the marker only appears on a new one.
