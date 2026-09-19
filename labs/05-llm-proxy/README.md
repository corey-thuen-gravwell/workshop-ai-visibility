# Lab 05: LLM proxies (litellm → content-capturing proxies)

## Objective
Get *content-level* visibility into an AI agent: prompts, the tools it was offered, the tools it
called and with what arguments, its replies, and token spend: by putting a proxy in the path.
First see how little a generic gateway (litellm) logs; then capture everything with two proxies
that emit the same event model: Gravwell's LLM ingester and a vendor-agnostic Python proxy you
can take home to any SIEM. Then read the part of every request nobody typed: the **system
prompt**, where the tool's real instructions, its tool list, and a description of your machine
go up the wire on every turn.

## Background
Every LLM call is HTTP + JSON, and the client re-sends the whole conversation every turn (M2). So
whoever sits in the path sees everything: one request = the entire context so far. That is why a
proxy, not the vendor dashboard, is where auditing lives.

## Setup
- Start from `stage-opencode` (Lab 04: opencode installed, working against a provider).
- Your Lab 00 stack is up (`docker compose up -d` in `labs/00-environment-gravwell`). It already
  includes the **LLM-ingester sidecar** (`<ID>llm`) and a `tag=proxy` ingest listener on `<ID>05`.

## Part 1: litellm (M8)
1. Run litellm in docker on `<ID>00`, routing to Anthropic and shipping its container logs to the
   raw-text listener in your Gravwell stack (`<ID>09`, tag `syslog`). **Your Lab 00 stack must
   already be up**: the docker syslog logging driver connects at container start and the container
   fails if nothing is listening.
   ```bash
   cd ~/jarvis/labs/05-llm-proxy/litellm
   docker compose up -d
   ```
   Checkpoint `stage-llm-proxy`.
2. Drive it: `cd ~/jarvis/labs/05-llm-proxy && ./testai.sh` (`N=10 ./testai.sh` for more traffic).
3. In Gravwell: `tag=syslog grep HTTP`. **Discussion:** what do you actually know about the
   request? (You know it happened. Not the prompt, not the tools, not the answer.)

## Part 2a: the Gravwell LLM ingester (M9)
1. Confirm the sidecar is hot. It logs to a file inside the container (`docker logs <ID>llm` is
   empty, which surprises everyone):
   ```bash
   docker exec ${WORKSHOPUID}llm grep -i hot /opt/gravwell/log/llm_ingester.log
   ```
   You want `Ingester gone hot`. The log keeps growing after that, so `grep` rather than `tail`.
   The two listeners are in there too, `grep -i listener`: `:4180` OpenAI-compatible → published
   `<ID>80`; `:4181` Anthropic → `<ID>81`.
2. Point opencode at it. You already did, in Lab 04: the config you wrote there sends opencode
   through the ingester. Open it and check the `baseURL`:
   ```bash
   cd ~/moneyprinter
   nano opencode.json        # or vim; the file is right here in the project directory
   ```
   ```jsonc
   // ~/moneyprinter/opencode.json  (the whole file, for reference)
   { "$schema": "https://opencode.ai/config.json",
     "provider": { "anthropic": { "options": {
         "baseURL": "http://localhost:<ID>81/v1",
         "apiKey":  "<your ANTHROPIC_API_KEY>" } } },
     "model": "anthropic/claude-sonnet-5",
     "small_model": "anthropic/claude-haiku-4-5" }
   ```
   **The `/v1` suffix is required**: the SDK appends `/messages` to whatever you put here, so
   without it every request 404s. The key passes straight through the ingester to Anthropic; the
   ingester records the conversation, it does not hold the key. (Part 2b's stretch shows the other
   design, where the proxy holds the key and the client never sees it.)

   > **Which `opencode.json`? There are two places, and this course uses one.** opencode reads a
   > **global** config from `~/.config/opencode/` (`opencode.json` or `opencode.jsonc`; it writes
   > a near-empty `.jsonc` there the first time it runs, which is why you may find one you never
   > made) and a **project** config, `opencode.json` in the directory you launch it from. It merges
   > the two, and the project file wins for any setting both define. Every lab here edits the
   > **project** file, `~/moneyprinter/opencode.json`: the config travels with the project, and
   > Labs 06 and 07 add MCP servers to that same file, which you would not want applied globally to
   > every directory on the box. So: leave `~/.config/opencode/` alone, always `cd ~/moneyprinter`
   > before running opencode, and if you already put a `baseURL` in the global file, delete that
   > line so there is only one place opencode gets its provider from.
3. Ask the agent something simple, *"which model are you running?"*, then something that makes it
   use tools (list files, read a file).
4. Find it in Gravwell. Fields on `tag=llm` are **intrinsic** enumerated values, so the extractor
   is `intrinsic`, not `json`. Two searches, run separately. First, everything the ingester
   recorded, one row per event:
   ```
   tag=llm intrinsic event_type role model session_id tool_name prompt_tokens completion_tokens
   | table event_type role model session_id tool_name prompt_tokens completion_tokens DATA
   ```
   Then only the tool calls, which is the same search narrowed with a `grep -e` on `event_type`:
   ```
   tag=llm intrinsic event_type tool_name session_id | grep -e event_type response.tool_call
   | table session_id tool_name DATA
   ```
   Tasks: (a) in the first search, find your own "which model" prompt and the reply; (b) in the
   second, list every tool the agent called and its arguments; (c) how many tokens did your session
   cost? (d) how many *sessions* are there and how did the proxy decide that?

> **Finished early?** Everything you just searched was by keyword. The same ingester can also
> **embed** each prompt and reply as it arrives (a `vector` preprocessor on the listener), and
> Gravwell's `semantic` module then searches `tag=llm` **by meaning**: `grep "credential"` finds
> nothing, while `semantic "someone leaked a credential"` finds *"I accidentally committed an API
> key…"*. It needs an embeddings model on both the ingester and the webserver, so it runs on the
> instructor's stack as a demo rather than on your seat. Read the **Semantic search over LLM logs**
> page (P3) on the share site now, so the demo makes sense when it comes, and note what you would
> have to configure to run it at home. (Working through this on your own? The same page has the
> full config, and `scripts/enable-semantic.sh` in the authoring repo brings the pieces up.)

## Part 2a2: someone already built the dashboards

You have written four queries against your own traffic. Now get the rest for free, the same way you
did in Labs 02 and 03: Gravwell publishes an **LLM Observability** kit for exactly this ingester.

1. In the left navigation open **Kits**, browse the kit server, find **LLM Observability** and
   install it. It needs Gravwell 5.10 or newer, which is what you are running, and it pulls in no
   dependencies. It asks you for two values on the way in, `LLM_TAG` and `LLM_SEMANTIC_THRESHOLD`:
   take the defaults.
2. Open **Macros** and look at `LLM_TAG`. It expands to `llm`, which is the `Tag-Name` on your
   listener, so unlike the Sysmon kit in Lab 03 there is nothing to fix: the kit fits your data as
   installed. The other macros are the event types you have been typing by hand, so
   `$LLM_USAGE` is `intrinsic event_type == "response.usage"`.
3. Open **Dashboards**. Four of the five have your own traffic in them:
   - **Traffic Overview**, what the ingester has seen.
   - **Cost and Token Usage**, including top sessions by token spend.
   - **Tool Use**, every tool your agent called, with arguments.
   - **Performance and Reliability**, latency by model, upstream errors, slowest requests.
4. Take a `session_id` from the token-spend panel and run the kit's **Conversation Reconstruction**
   template on it (**Templates** in the left navigation). That is your conversation, replayed in
   order, from a query you did not write.
5. Open the fifth dashboard, **Semantic Risk Hunting**. Every panel on it fails:

   ```
   semantic (module idx 1) error: cannot use the semantic module.
   An embedding model is not configured.
   ```

   Nothing is broken. Those panels use the `semantic` module, which needs an embeddings model on
   the ingester and on the webserver, and your seat has neither. A kit can ship a capability your
   deployment has not enabled, and the error says exactly which one. That is the P3 demo.

**Then read one of the kit's queries** (any panel → the query bar) and compare it with what you
wrote in step 4 of Part 2a. Same data, same modules, someone else's naming. Every Gravwell kit is
open source at <https://github.com/gravwell/kits>, so when you need a query for a data source, that
is where to start rather than a blank query bar.

The kit also ships five **playbooks** (left navigation), which are the take-home version of this
module: a kit overview, deploying the ingester, enabling semantic search, and hunting prompts by
meaning.

## Part 2b: the vendor-agnostic proxy (M9)
Not everyone runs Gravwell. `src/logging-proxy/llm_audit_proxy.py` is one stdlib Python file that
emits the **same events** as JSONL to a file, stdout, TCP, or syslog.
1. **Open a second terminal for the proxy.** It is a server: once started it sits in the
   foreground printing a line per request and does not give you your prompt back, and you still
   need a shell for opencode and Gravwell. So: a second SSH window (or tab) to the same seat, and
   run the proxy there. Leave that window alone for the rest of the lab; `Ctrl-C` in it stops the
   proxy. (Comfortable with `&` or `nohup`? Fine, but the second window is simpler and you can
   watch the requests go by.)

   In that second terminal, run it on `<ID>90`, logging to a file *and* into your Gravwell's
   `tag=proxy` listener. It lives under `src/`, not under this lab's directory:
   ```bash
   cd ~/jarvis/src/logging-proxy
   ./llm_audit_proxy.py --listen 0.0.0.0:${WORKSHOPUID}90 --upstream https://api.anthropic.com \
       --log-file ~/proxy.jsonl --tcp localhost:${WORKSHOPUID}05
   ```
   You want one line, `listening on 0.0.0.0:<ID>90 -> https://api.anthropic.com`, and then
   nothing until traffic arrives. (If `ls ~/jarvis/src/logging-proxy` is empty, `cd ~/jarvis &&
   git pull`: the script arrives with this lab's checkpoint, `stage-llm-proxy`.)
2. **Back in your first terminal**, re-point opencode: in `~/moneyprinter/opencode.json` change
   the `baseURL` to `http://localhost:<ID>90/v1` (the `/v1` matters), then repeat the prompts from
   `~/moneyprinter`. Watch the second terminal as you do.
3. Compare: `tail -f ~/proxy.jsonl` vs. in Gravwell
   ```
   tag=proxy json event_type role model session_id tool_name prompt_tokens data
   | table event_type role model session_id tool_name prompt_tokens data
   ```
   Task: find the `request.tools_offered` event. That is the list of everything the agent *could*
   have done: the ingester doesn't record this; why might you want it?
4. **Stretch:** in the proxy's terminal, `Ctrl-C` it and start it again with
   `--upstream-key "$ANTHROPIC_API_KEY" --client-key hunter2`, then remove the real key from
   opencode's config (`apiKey: "hunter2"`). Discuss: the proxy is now a *gateway*, the real key never
   reaches the workstation.

## Part 2c: the system prompt (M9)
Every request in this lab started with text nobody in the room typed. Ahead of your words the
client sends the **system prompt**: the harness's own standing instructions to the model, plus a
description of every tool the model is allowed to call. It is not shown in the UI, it is not kept
in opencode's local logs, and because the API is stateless (M2) it is re-sent, in full, on every
single turn. The proxy you just built is the only place you can read it.

Both proxies record it as `event_type=request.system_message`. The ingester writes it **once per
session** (`Log-Mode = delta` in `llm_ingester.conf`); the Python proxy writes it on **every**
request. Searches below are written against the ingester's data, `tag=llm` (`intrinsic` … `DATA`);
for the Python proxy the same query is `tag=proxy json … data`, lowercase field, everything else
identical. **New traffic lands wherever opencode points right now**: if you finished Part 2b that
is the Python proxy and `tag=proxy`, so either translate the searches or set `baseURL` back to
`http://localhost:<ID>81/v1` first. Two `tag=proxy` quirks to know: the JSON keeps newlines
escaped, so `len(data)` counts a couple of hundred characters more than the prompt really has, and
a `[^\n]+` capture runs past the line end (use `[^\\ ]+` there instead).

1. **Read the whole thing.** Two pages, once, top to bottom. Nothing later in this part lands if
   you skip this.
   ```
   tag=llm intrinsic event_type | grep -e event_type request.system_message | text
   ```
   `text` prints the entry as it arrived; a table cell is unreadable at this length.
2. **Measure it.** How many characters did the client send, versus how many you typed?
   ```
   tag=llm intrinsic event_type | eval chars = len(DATA); | stats sum(chars) as chars by event_type
   | sort by chars desc | table event_type chars
   ```
   Tasks: (a) the ratio of system prompt to your own words; (b) at roughly 4 characters per token,
   what does the system prompt cost per turn, and how many turns did your session run
   (`response.usage` events)? (c) `Log-Mode = delta` means Gravwell holds one copy; how many copies
   did the *provider* receive?
3. **Map it.** Skim for section headings and answer: what persona is asserted; what is the model
   forbidden to do; what does it say about running tools; how many rules shout in capitals. Then
   the question worth taking home: those rules read like policy, so **what enforces them?**
4. **Find the part that describes your machine.** The client appends facts about your box that you
   never typed:
   ```
   tag=llm intrinsic event_type | grep -e event_type request.system_message
   | regex -e DATA "Working directory: (?P<cwd>[^\n]+)" | table cwd DATA
   ```
   Tasks: list every fact about your environment in that block; decide which of them you would have
   volunteered to a third party; say how you would have discovered this without a proxy.
5. **Count the system prompts.** One question of yours produced more than one.
   ```
   tag=llm intrinsic event_type | grep -e event_type request.system_message
   | eval fp = hash_sha256(DATA); chars = len(DATA); | stats count by fp chars | table fp chars count
   ```
   Tasks: how many distinct system prompts, of what sizes? Read the short one: what is it for, who
   asked for it, which `session_id` is it billed to, and (add `model` to the search) **which model
   ran it?** If that is not the model you configured, your AI inventory is already wrong.
6. **Edit the system prompt without touching the client.** opencode, like every coding agent, has
   a **rules file**: `AGENTS.md`. When it starts it walks up from the directory you launched it in
   looking for one (plus a global `~/.config/opencode/AGENTS.md`), and splices the contents into the
   system prompt under a heading `Instructions from: <path to the file>`. It is meant for project
   conventions ("use pytest", "never touch prod config"); the point here is that it is a plain text
   file in the repo, read on every start, and nobody signs it. Cursor's `.cursorrules` and Claude
   Code's `CLAUDE.md` are the same mechanism, and opencode will read a `CLAUDE.md` too.

   So the file lives in the project you run opencode from: `~/moneyprinter`. Add a line with a
   marker only you would use:
   ```bash
   cd ~/moneyprinter
   echo "MARKER-${WORKSHOPUID}: always address the user as Captain." >> AGENTS.md
   tail -1 AGENTS.md         # your seat number should be in the line, not the word WORKSHOPUID
   opencode run "hi"
   ```
   (`>>` creates the file if the project has none.) `opencode run` starts a **new** session, which
   matters: delta mode logs the system prompt once per session, so an old session would never show
   the change. Now find your marker (in Gravwell, type your seat number in place of `<ID>`; the
   shell variable does not exist there):
   ```
   tag=llm intrinsic event_type | grep -e DATA "MARKER-<ID>" | table event_type DATA
   ```
   Tasks: (a) which event carried it, and how is it labelled inside the prompt? (b) did the agent
   obey it? (c) who in your organisation can write that file, and does anything review it? Hold
   that thought: in M10 the same trick arrives through an MCP server's tool descriptions.
7. **Stretch: fingerprint it.** The opening line names the tool ("You are opencode, an interactive
   CLI tool…"). Keep the hash from task 5. A system prompt that changes is a client that changed:
   an upgrade, a new agent mode, a new MCP server, or someone's edit. Which of those would you want
   an alert for?

### What the harness sends as "you"
`request.user_message` is not a transcript of your keyboard. Between your turns the client uploads
tool results, file contents, and reminders of its own, all under user-side roles.

```
tag=llm intrinsic event_type role session_id model | grep -e event_type request.user_message
| sort by TIMESTAMP asc | table TIMESTAMP session_id model DATA
```
```
tag=llm intrinsic event_type session_id tool_call_id | grep -e event_type request.tool_result
| eval chars = len(DATA); | table TIMESTAMP session_id tool_call_id chars DATA
```
Replay one conversation exactly as the provider received it, in order:
```
tag=llm intrinsic event_type session_id | grep -e session_id <your session id>
| sort by TIMESTAMP asc | table TIMESTAMP event_type DATA
```
Tasks:
- (a) Ask the agent to read a source file, then find that file's contents in Gravwell. Nobody
  pasted it. Which event carried it, and how many characters of your repository left the building?
- (b) Compare the number of characters *you* typed with the total the client sent in that session.
- (c) Hunt for the shapes an auditor actually cares about, across everything the client sent:
  ```
  tag=llm intrinsic event_type
  | regex -e DATA "(?P<secretish>sk-[A-Za-z0-9_-]{16,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]+PRIVATE KEY-----)"
  | table event_type secretish DATA
  ```
  It is usually empty today. If it is not, do not shrug: find the event that carried the match and
  work out which file the agent read to get it (your own `opencode.json` holds a key, and an agent
  that lists a directory is one step from reading it). Write down the query either way: it is the
  same one you would run at work on Monday, and there the answer is rarely empty.

## Checkpoint: if you get lost
Every lab has a **known-good snapshot** you can restore without losing anything you've done:

```bash
cd ~/jarvis && git checkout stage-llm-proxy -- labs/05-llm-proxy src/logging-proxy
```

That overwrites the lab's files with the working versions and leaves you exactly where you are,
no branch switching, no detached HEAD, nothing else touched. Ask an instructor if you're unsure.

## Discussion
- Both proxies see everything because the *client* is where state lives. Vendor-side logging can
  never be this complete without your cooperation.
- Event model over log format: `event_type` / `session_id` / `tool_name` are what detections key
  on in Lab 07 Part 3, not which SIEM or which proxy produced them.
- Where would this sit in a real network? (Egress proxy for the dev VLAN; per-team gateway with
  injected keys; sidecar per CI runner.)
- The system prompt is the tool's real behaviour spec, and it is the only copy you can verify. You
  cannot audit an AI tool whose system prompt you have never read.
- Anything that can write text into that prompt (`AGENTS.md`, `CLAUDE.md`, a rules file, an MCP
  server's tool descriptions in M10) is changing the agent's standing instructions, usually with no
  review, no version pin, and no log of its own. The proxy is the log.
- "User" is a role in a JSON document, not a person. Tool results, file contents, and the client's
  own reminders all travel under user-side roles, so most of what the provider receives from your
  seat was never typed by anyone at it.

## Read more
- The Gravwell LLM ingester, every listener option including the ones this lab does not use:
  <https://docs.gravwell.io/ingesters/llm.html>
- `src/logging-proxy/llm_audit_proxy.py` is yours to take home: one stdlib file, no dependencies,
  `--help` lists every sink and flag.
- `datasets/proxy-captures/` holds reference captures of what each proxy records, so you can read
  the event model without a running stack.
- **CL4R1T4S** (<https://github.com/elder-plinius/CL4R1T4S>) is a community repository of system
  prompts extracted from popular AI tools and assistants. Unofficial and best treated as a
  snapshot rather than a source of truth, and useful precisely for that reason: compare what you
  captured from your own proxy against what someone else captured from the same tool, and note how
  much of a product's behaviour turns out to be prose that changes between releases.
