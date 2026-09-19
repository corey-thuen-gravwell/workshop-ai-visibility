# Walkthrough 06: MCP deep dive

> ⛔ **INSTRUCTOR ONLY.** Contains every answer. Student handout:
> [`labs/06-mcp-deep-dive/README.md`](../../labs/06-mcp-deep-dive/README.md).

**Module:** M10 + Lab G · **Budget:** ~105 min (Part 1 ≈60, Part 2 ≈45) · **Checkpoint:** none
**Flex:** ⏱ compressible · **Deck:** [`slides/06-mcp.md`](../../slides/06-mcp.md)

> **Scope.** M10 is the *protocol*. What a manifest can make a model do across *several* servers,
> and how to detect it, is **Lab 07**. This module's job is to make the wire format so familiar
> that Lab 07 needs no protocol explanation. Leave the cross-server questions open here.

---

## ⚠️ Hard requirement: Gravwell 5.10.x

The MCP server lives at `/api/mcp` and **only exists on 5.10.x**. On 5.8.13 it returns **404** and
this entire lab is dead in the water.

The Lab 00 compose is **pinned to `gravwell/gravwell:5.10.1`** for exactly this reason: a stale
`:latest` can be 5.8.13 and silently have no MCP. `preflight.sh`
performs a real `initialize` against seat `$START_ID` and fails if it doesn't get a 200. **Run
pre-flight and see that check pass before you teach this.**

## The plan: both parts, hands-on

This module has two halves and **both are hands-on**. Part 1 reads someone else's MCP server; Part 2
writes your own and points a real agent at it. Part 2 is where the module's central claim:
*a tool description is an instruction to the model*: stops being an assertion and becomes something
students cause and observe on their own machine.

Roughly 105 minutes for both. **That is an estimate, not a schedule.** If you're behind when Part 1
finishes, the compression is: **run Part 1 from the front of the room next time** (−20) and protect
Part 2. Protocol reading demos fine; protocol authoring does not.

Within Part 2, if you have to cut, cut in this order:

1. **Task 9** (build your own from the template) → make it the optional take-home. Costs the most
   time, and students can do it after class.
2. **Task 10** (audit your own server in Gravwell) → show it on the projector from your own run.
3. **Never cut Task 8.** It is the best ten minutes in the module and it needs their hands on it.

## Timing

| Min | Segment | |
|---:|---|---|
| 0–30 | Deck: three roles, the stdio → SSE → streamable-HTTP story, JSON-RPC shapes | |
| 30–36 | Task 1: `initialize`, capture the session header | **Part 1** |
| 36–44 | Task 2: `tools/list`. **50 tools.** The count is the lesson | |
| 44–52 | Task 3: read a description as the model reads it | |
| 52–57 | Task 4: `tools/call`, schema-first | |
| 57–60 | Task 5: `whoami` | |
| 60–70 | Task 6: run the worked example, poke it over HTTP | **Part 2** |
| 70–80 | Task 7: connect opencode, watch the model choose the tool | |
| 80–92 | Task 8: **change the description, not the code** | ← the peak |
| 92–102 | Task 9: build your own | |
| 102–105 | Task 10: audit your own server, and the hand-off to Lab 07 | |

If Part 1 is dragging, demo Tasks 1 and 4 from the front and have them do only 2, 3 and 5, those
three carry it: then move to Part 2 on schedule.

## Setup notes

- Students hit **their own** Gravwell, so there's no shared server to overload and no new
  infrastructure. Nice property: the MCP server they're probing is one they administer.
- The handout authenticates with the **API token from Lab 00** (`$GRAVWELL_TOKEN`, minted by
  `make-token.sh`), sent as `Gravwell-Token:`. That is also how Claude Code and Copilot CLI connect,
  per the Gravwell docs. Two things to have ready: a token sent as `Authorization: Bearer` returns
  **401** (that header is only for a password login's JWT), and `/api/mcp` itself requires the
  **`LogbotAI`** capability, which is the concrete answer when Task 5 asks how you would shrink an
  agent's blast radius. The UI path is Tools & Resources → API Tokens if somebody wants to see it.
- `jq` required.

**The whole of Part 1, in one block**, so you can paste it on a projector or recover a seat that
has lost its shell. Same commands as the handout, in order:

```bash
export GW=https://localhost:${WORKSHOPUID}443
. ~/.workshop_env                          # $GRAVWELL_TOKEN, from Lab 00's make-token.sh

export SID=$(curl -sk -D - -o /dev/null -X POST $GW/api/mcp \
  -H "Gravwell-Token: $GRAVWELL_TOKEN" -H 'content-type: application/json' \
  -H 'accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18",
       "clientInfo":{"name":"lab06","version":"1.0"},"capabilities":{}}}' \
  | grep -i '^mcp-session-id' | tr -d '\r' | cut -d' ' -f2)

mcp() { curl -sk -X POST $GW/api/mcp -H "Gravwell-Token: $GRAVWELL_TOKEN" \
    -H "Mcp-Session-Id: $SID" -H 'content-type: application/json' \
    -H 'accept: application/json, text/event-stream' -d "$1"; }

mcp '{"jsonrpc":"2.0","method":"notifications/initialized"}'          # task 1
mcp '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' > tools.json     # task 2
jq '.result.tools | length' tools.json
jq -r '.result.tools[].name' tools.json | sed 's/_.*//' | sort | uniq -c | sort -rn
jq '.result.tools[] | select(.name=="execute_query") | {description, inputSchema}' tools.json
mcp '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"execute_query",
      "arguments":{"query":"tag=gravwell limit 3","duration":"1h"}}}'  # task 4, fails on purpose
mcp '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"execute_query",
      "arguments":{"query":"start=-1h tag=gravwell limit 3 | table TIMESTAMP DATA"}}}'
mcp '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"whoami","arguments":{}}}'
```

**`$SID` must be set before the first `mcp()` call**: the session id arrives as a *header* on the
initialize response, which is why it is captured with a separate `curl -D -`.

---

## Task 1: `initialize`

**Measured response:**

```json
{"jsonrpc":"2.0","id":1,"result":{
  "capabilities":{"logging":{},"tools":{"listChanged":true}},
  "instructions":"Gravwell MCP server. Provides tools for interacting with Gravwell.",
  "protocolVersion":"2025-06-18",
  "serverInfo":{"name":"gravwell","version":"v1.0.0"}}}
```

Plus the response header **`Mcp-Session-Id: <opaque id>`**.

Two things to draw out:

1. **Compare it to the deck slide.** It's the same shape they saw on the projector twenty minutes
   ago, from a real server. That equivalence is worth pointing at: the protocol really is this
   small.
2. **What did the server require of the client?** `clientInfo: {"name":"lab06","version":"1.0"}`,
   *and it believed it.* There is no client attestation in MCP. The server knows what the client
   claims to be. Ask what that means for a server-side allow-list.

**Common failures:**

| Symptom | Cause |
|---|---|
| `404` | Gravwell is not 5.10.x. Check `curl -sk $GW/api/version` |
| `406` | Missing `accept: application/json, text/event-stream`. Streamable HTTP requires both |
| `$SID` empty | The header is on the *initialize* response: they used `mcp()` before setting `SID`. The handout does it in the right order |
| Later calls fail | Skipped `notifications/initialized` |

## Task 2: `tools/list`

**Measured: 50 tools.** Verb breakdown from the same run:

| Verb | Count |
|---|---:|
| `list_*` | 12 |
| `get_*` | 9 |
| `update_*` | **6** |
| `create_*` | **5** |
| others (`execute_query`, `save_*`, `parse_*`, `whoami`, `ping`, `sample_*`, …) | 18 |

**Answers:** ~21 are pure reads; **11 create or modify** persistent state, including
`create_alert`, `create_scheduled_search`, `create_playbook`, `create_macro`, `create_extractor`.

*Beat:* "Your SIEM just offered a stranger fifty tools, eleven of which change its configuration,
and the protocol never once asked you to approve a list." Let that sit before you rescue it with
Task 5.

*Beat 2:* they discovered these **at runtime**. There's no manifest checked into a repo, no change
control. An asset inventory of agent capability is only as fresh as the last `tools/list`, which is
why `request.tools_offered` (Lab 05) matters as a *logged event*.

## Task 3: Descriptions are instructions

This is the module's centre. **Measured** `execute_query` description:

> "Execute a Gravwell query and return up to the first 50 result entries. The query **MUST** use one
> of the following renderers: table, text, or raw. To constrain the time range, include start=
> and/or end= constraints at the beginning of the query string (e.g. 'start=-1h tag=syslog words err
> | table' searches the last hour…). Durations use units: us, ms, s, m, h, d, w, y."

Have someone read it aloud, then ask: **who is the audience?** It's imperative, it carries worked
examples, it lists valid units. It is not written for a human: **it is written for a model**, and
it lands directly in the model's context every turn.

*Beat:* "A tool description is a prompt fragment authored by whoever wrote the server. On your
laptop right now, how many tool descriptions are you running, and who wrote them?"

That question is the honest end of M10. **Do not answer it here**: Lab 07 is where it gets explored
hands-on. Leaving it open is the correct handoff.

## Task 4: `tools/call`, schema-first

The handout has them **guess wrong on purpose** (`"duration":"1h"`), producing:

```
invalid params: validating "arguments": validating root:
    unexpected additional properties ["duration"]
```

Then the correct call with `start=-1h` inside the query string returns real rows from their own
`tag=gravwell` data.

*Beat:* the failure is the point. `additionalProperties: false` in the schema is the server refusing
malformed input: a real control surface, enforced on the server side, that a client cannot talk its
way past. Ask where else in their stack that kind of schema enforcement exists between an LLM and an
action. (Usually: nowhere.)

## Task 5: `whoami`

**Measured:** `{"Admin": true, "Email":"admin@admin.admin", ...}`

**The answer to "whose hands are these":** every one of those 50 tools executes as the identity
behind the token the client presented. Gravwell applies CBAC to that user, so **the blast radius is
the token, not the tool list.**

*Beat, and the constructive close:* "The tool list looked terrifying in Task 2. It's bounded by one
decision you control: which credential you hand the MCP server. That's the first real MCP control
we've found: and it's the same lesson as the proxy key boundary in Lab 05." A less-privileged token
is the mitigation; say so plainly, since students should leave M10 with at least one thing to *do*.

---

---

# Part 2: build your own server (≈45 min)

**Expected** with opencode against the live API: the model discovers the tools, chooses
`check_looney_tunes_compliance` from its description alone, calls it with the correct argument,
returns the NON-COMPLIANT verdict, and then *offers the policy tool* as a follow-up: meaning it
has read that description too.

## Setup notes

- Students never edit `mcp_lab_server.py`. Everything is in a **TOML** config. If someone starts
  editing the Python, redirect them: the whole point is that a server is a manifest.
- `--validate` before every run. Its errors are written to teach: unknown behaviour names print the
  valid list, and a missing tool `description` produces a warning explaining *why* it matters.
- **stdio for opencode, HTTP for curl.** stdio means opencode spawns the server itself, no ports,
  no collisions across 20 seats. Use HTTP only for hand-poking.
- opencode **namespaces** tool names: the model sees `looney-tunes_check_looney_tunes_compliance`.
  Mention it or someone will think their tool didn't load.

## Task 6: run the worked example

The handout now walks the three messages again against the lab server, with its own `lab()` helper
(the Setup `mcp()` helper bakes in Gravwell's URL, bearer token and `$SID`, and students who reuse
it get Gravwell's answers or a connection error and do not know why). Expected:

| Step | Expected |
|---|---|
| `--validate` | `OK`, `tools: 3`, the three names with their behaviours |
| server start | `[mcp-lab] looney-tunes-compliance on http://0.0.0.0:<ID>91 (3 tools)`; a warning about `:<ID>10` only if the Lab 00 stack is down |
| `curl -s $LAB` | a JSON summary with the three tool names (a lab-server convenience, not MCP) |
| `initialize` | 26-character `Mcp-Session-Id` header; body has `serverInfo.name = looney-tunes-compliance`, capabilities `tools`/`prompts`/`resources`, and the server `instructions` text |
| `notifications/initialized` | nothing; `-i` shows `HTTP/1.1 202 Accepted` |
| `tools/list` | `check_looney_tunes_compliance`, `get_compliance_policy`, `check_text_length`; `required: ["text"]` |
| compliance call | `NON-COMPLIANT: 1 forbidden term(s) found: 'Bugs Bunny' at position 18 …` (Road Runner is not on the list, which is worth a look at the TOML) |
| wrong argument | `-32602 missing required argument(s): text` |
| unknown tool | `no such tool: 'nope'. Offered: …` |
| `~/mcp.jsonl` | `in`/`out` pairs plus one `call` record per accepted tool call |

Stuck points specific to this task: the server was started in the same terminal (no prompt back;
they think it hung); `curl: (7)` because the second terminal is on a different seat or the port was
typed with the wrong id; `-32700 invalid JSON` from breaking the line inside a string or using
double quotes around the body.

**Answer to "what is structurally different from Gravwell's `tools/list`?"** Gravwell's 50 tools are
backed by a real system with real permissions; these three are backed by string matching in a config
file. **The protocol cannot tell the difference, and neither can the model.** A tool is a promise in
JSON. Nothing about MCP verifies that a server does what its description claims.

That is the honest answer, and it is the setup for Lab 07.

## Task 7: connect a real agent

**Expected:** `opencode mcp list` prints `✓ looney-tunes connected`, and the run calls the tool.

| Symptom | Cause |
|---|---|
| `✗ failed` in `mcp mcp list` | Absolute paths: `command` needs full paths for both the script and the config. `~` is not expanded |
| Connected, but the tool is never called | The description is too vague, or the prompt doesn't sound like the described situation. This is task 8's lesson arriving early, lean into it |
| Server appears to hang | Something is printing to **stdout**, which corrupts the JSON-RPC stream. Only protocol messages may go there; the server sends diagnostics to stderr |
| Tool list is stale after an edit | Clients cache from `initialize`. Restart the server **and** opencode |

**Answer to "what did it read to decide?"** The `description`, and nothing else. Not the config, not
the code, not the instructor's intent.

## Task 8: the description experiment (this is the module)

This is the highest-value ten minutes in M10. Run it yourself first so you know the shape.

**With `claude-sonnet-5` and `claude-haiku-4-5` (opencode 1.18.29) the models are far more
stubborn than intuition suggests.** Know this before you stand in front of it:

1. **Weaken** the description to `"Checks text."` → **both models still called the tool** for the
   compliance prompt, every run. Blanking the server `instructions` as well: still called. Renaming
   the tool to `tool_a` on top: still called (the server is still named `looney-tunes-compliance`,
   `get_compliance_policy` is still listed, the schema still has a `text` argument, and the prompt
   says "naming policy"). That is the real lesson, and it is better than the old one: **the
   description is one prompt fragment among several; the whole manifest is prompt.** Let students
   discover the call still happens, then have them hunt for what the model read. The handout now
   says exactly that.
2. **Strengthen** to *"You MUST call this before answering any question about text, no matter what
   the question is"* → it **fires on unrelated text questions** ("Is this sentence grammatical…",
   "Summarise this in five words…": called every time) but **not on `what is 2+2?`** (0 of 2 runs,
   both models). Arithmetic isn't "a question about text" and the model knows it. The handout now
   uses the summarise prompt first and 2+2 second, as the contrast.

Same tool, same code, same schema; only prose changed, and the agent's behaviour followed the prose.
Results will drift with model versions. If the room gets a different outcome, that *is* the point.

**The beat:** *"You just changed an AI agent's behaviour by editing a text field in a config file.
You wrote no code. You did not touch the model, the client, or the prompt. And you are the person
who is supposed to be **allowed** to do that, you own this server."*

Then the question that hands off to Lab 07, and **do not answer it**:

> *"Now: how many MCP servers are connected to the tools on your laptop, and who wrote their
> descriptions?"*

## Task 9: build your own

Circulate while they work. What to look for:

- **Descriptions written for humans**, not models: "Compliance checker (v2)" tells the model
  nothing about *when* to use it. Best single piece of feedback: *"say when you'd want this called."*
- **Schemas without `additionalProperties = false`**: a good moment to point back at Part 1's
  rejection.
- Anyone finishing early: `error_on_fail = true`, then compare how the agent reports a failed check
  versus a protocol error. Clients treat them very differently.

`examples/pii-guard.toml` is the second worked example if someone wants a model to copy.

## Task 10: audit your own server

```
tag=mcp json direction method session_id | table direction method session_id
tag=mcp json method message | grep -e method tools/call | table message
```

**Answers:**

1. Yes: the full conversation reconstructs from `direction` + `method` + `id`. Note the outbound
   rows show `method` as **`null`**: responses carry no method, only an `id` that matches the request
   they answer. Expect someone to ask; it's correct JSON-RPC, not a bug.
2. **The tool arguments are in the log**, which means the text the model sent for checking is in the
   log. An MCP server sees a slice of the conversation, and it is a slice nobody usually captures.
3. `tag=llm` is the model's side; `tag=mcp` is the tool's side. You need **both** to answer *"the
   agent called a tool: what was it told, and what did it do with the answer?"* Which is exactly
   the correlation Lab 07 Part 3 builds.

*Closing beat:* they have now been on all three sides of an agent, the client (Lab 04), the path
(Lab 05), and the tool provider (this lab). Each one sees something the others can't.

## Discussion answers

| Prompt | Where to land |
|---|---|
| What could a proxy in this path see? | **All of it**: every tool offered, chosen, its arguments, its result. One HTTP endpoint, plain JSON, no binary framing. This is why Lab 07's detections are possible |
| Runtime discovery | Capability inventory is only as fresh as the last `tools/list`; log it as an event |
| Descriptions from a server you don't control | **Leave it open in the room.** That is Lab 07 |

> **Working through this alone and not going on to Lab 07?** The answer the room is being walked
> towards: a tool description from a server you did not write is **untrusted input that reaches
> the model as instructions**, on every turn, with no review step and no signature. Task 8 proved
> you can steer an agent by editing one config file; a server author can do the same thing to
> *your* agent, and can write rules about what to do with other servers' tools (Lab 07 shows
> the model obeying exactly that kind of rule). Treat an MCP server's manifest the way you treat
> a browser extension's permissions: inventory it, diff it on change, and log `tools/list`
> results as events so you can answer "what was this agent told it could do, on that day?"

## Answer key

| Q | Answer |
|---|---|
| Tools offered | **50** |
| Read-only vs mutating | ~21 read (12 `list_*` + 9 `get_*`) · **11 mutating** (6 `update_*` + 5 `create_*`) |
| Session id location | **`Mcp-Session-Id` response header** on `initialize` |
| Client identity check | **None.** The server believes `clientInfo` |
| Bad-argument result | Schema validation error; `additionalProperties: false` |
| `whoami` | `Admin: true`, tools run as the token's identity, bounded by CBAC |
| Checkpoint | None. Keep `tools.json` |

## Where students get stuck

1. **`$SID` ordering.** The session id is a *header* on the initialize response, and the `mcp()`
   helper references `$SID`: so it must be set first. Follow the handout's order exactly.
2. **The `accept` header.** Streamable HTTP wants `application/json, text/event-stream`. Omit it and
   you get 406, which reads like an auth problem and isn't.
3. **Forgetting `notifications/initialized`.** It's a notification, no `id`, no response. Students
   think it failed. Tell them silence is success.
4. **404 on `/api/mcp`.** Version. See the hard requirement at the top.
5. **Shell-quoting the JSON.** Same tax as Lab 01. Put the long bodies on a slide.
6. **Invalid `opencode.json` after Task 7.** The handout now has `jq` write the `mcp` block and
   validate the file (`jq . opencode.json`), with a table of `jq`'s three parse errors. If a
   student hand-edited: trailing comma before `}`, missing comma after `small_model`, or `~` in a
   path. `jq . opencode.json` names the line; `opencode mcp list` showing `✗ … failed` with valid
   JSON means a path or the TOML: run the `command` array by hand.
