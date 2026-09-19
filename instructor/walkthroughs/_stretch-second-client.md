# Walkthrough: P4: A second client through the same proxy

> ⛔ **INSTRUCTOR ONLY.** Contains every answer. Student handout:
> [`labs/_stretch/second-client/README.md`](../../labs/_stretch/second-client/README.md).

**Padding module P4** · **~30 min** · insert after M9 · **Flex:** optional
**Numbers below are from `claude` 2.1.263 and `opencode` 1.18.29** against one seat's LLM
ingester; they move with every client release, the shape does not.

## Why it earns 30 minutes

Lab 05 teaches students to read `tag=llm`. It does so with exactly one client, and that quietly
installs four assumptions. This module breaks all four with a second client doing the *same task*
against the *same listener*:

| Assumption from Lab 05 | Reality |
|---|---|
| Session ids mean the same thing | One client supplies them, the other has them inferred |
| One task ≈ one session | opencode opens a second session you didn't ask for |
| Tool names are stable | `Read` vs `read`: a detection keyed on either misses the other |
| Token cost reflects the user's request | ~60k vs ~16k input for the same sentence |

## Setup

`bootstrap-host.sh` now installs `claude` system-wide (native installer, no node needed, same
reasoning as opencode being a static binary). `preflight.sh` reports it as a **warning** if absent,
because P4 is optional and nothing else depends on it.

Claude Code needs no config file, two environment variables and it is pointed at your ingester:

```bash
export ANTHROPIC_BASE_URL="http://localhost:${WORKSHOPUID}81"   # note: NO /v1 suffix here
claude -p "Read notes.md and state the threshold." --allowedTools Read
```

> ⚠️ **Opposite of opencode.** opencode's `baseURL` *must* end in `/v1`; Claude Code's
> `ANTHROPIC_BASE_URL` must *not*. Same listener, two conventions. Expect this to bite.

---

## Task 1: whose session id? · **the core of the module**

The counter tells you, without any guessing:

```bash
docker exec ${WORKSHOPUID}llm grep -c "session id header configured but absent" \
    /opt/gravwell/log/llm_ingester.log
```

**Measured: read the count before and after each client:**

| Client | Delta | Meaning |
|---|---|---|
| **Claude Code** | **0** | It sends `x-claude-code-session-id`; the ingester adopts it |
| **opencode** | **3** | No header; the ingester falls back to prefix matching |

If you want to show *why*, point either client at a header dump and look:

```
x-claude-code-session-id: cba93340-9134-4d32-830e-b4c9588ec318
user-agent: claude-cli/2.1.263 (external, sdk-cli)
x-app: cli
```

*Beat:* the config line `Session-ID-Header = "x-claude-code-session-id"` has been in their stack
since Lab 00 and did nothing all day, because opencode never sends it. **A setting that silently
does nothing is indistinguishable from one that works** until you check.

**Answers:** (2) prefix matching, same system prompt plus the same opening turn inside
`Session-Match-Window` (10) and `Session-TTL` (30m). (3) two users running the same prompt with the
same system prompt inside that window can be **merged into one session**, and one long pause can
split a single conversation into two. Inferred sessions are a heuristic, not a fact.

## Task 2: count the sessions

**Measured:** four sessions for three tasks,
| Session | Events | Client |
|---|---:|---|
| `160a9937…` | 11 | Claude Code |
| `cabfd78b…` | 11 | Claude Code |
| `2d01ebb8…` | 8 | opencode: the actual task |
| `00f54ce3…` | 4 | opencode: **606 input tokens, 8 output** |

**Answer:** the small one is opencode's `small_model` generating a session *title*. The student
never asked for it and it never appears in the UI as a separate task.

*Beat:* "your per-session cost report just grew a row nobody requested." Anyone counting sessions as
a proxy for user activity is now over-counting, for one client and not the other.

## Task 3: the detection-breaker

**Measured:**

```
tool_name,count
Read,2          <- Claude Code
read,1          <- opencode
```

**Answer:** capitalisation. A detection written as `grep -e tool_name "read"` catches opencode and
misses Claude Code; `"Read"` does the reverse. Case-insensitive matching fixes *this* instance and
not the general problem: the next client may call it `view_file`.

*Beat, and it is the one to land:* **tool names are a client-side label, not a protocol
guarantee.** If your detection depends on one, it depends on your developers' choice of editor. Ask
what they would key on instead. (Reasonable answers: the *arguments*, a path, a URL, a command
string: or the effect observed elsewhere, e.g. Sysmon. Not the label.)

## Task 4: same task, same model, different bill

**Measured input tokens for the same one-sentence task:**

| Client | Input | Output |
|---|---:|---:|
| Claude Code | **60,142** | 99 |
| opencode | **15,972** | 91 |

**Nearly 4× the input for an identical request and an identical answer.**

**Answers:** (2) the difference is the client's own system prompt, tool definitions and injected
context: none of it written by the user. (3) worth genuinely arguing. Billing the person punishes
tool choice they may not control; billing the tool hides who is driving. The honest answer is that
you need both dimensions, which they now have, because the proxy records both.

*Beat:* tie it back to M2's `21 → 13 → 35 → 59`. Context is the caller's job, and here the *caller*
is a piece of software choosing on the user's behalf, at 4× the price.

---

## Answer key

| Q | Answer |
|---|---|
| Which client sends the session header? | **Claude Code** (delta 0). opencode does not (delta 3) |
| Where does opencode's session id come from? | Prefix matching within `Session-Match-Window`/`Session-TTL` |
| Sessions vs tasks | opencode adds a ~606-token `small_model` title session |
| Tool names | `Read` (Claude Code) vs `read` (opencode) |
| Input tokens, same task | 60,142 vs 15,972, ~4× |
| `ANTHROPIC_BASE_URL` | **No** `/v1`: the opposite of opencode's `baseURL` |

## Where students get stuck

1. **The `/v1` inversion.** Claude Code with a `/v1` base URL 404s. Put both forms on a slide.
2. **`--allowedTools Read`.** Without it, non-interactive Claude Code will not use tools and the
   comparison has nothing to compare.
3. **Reading the "absent" counter only once.** It is cumulative across the whole day; the delta is
   what matters, so record it before *and* after.
4. **Assuming the small session is an error.** It is real, and it is the finding.
