# Walkthrough 04: The AI user & opencode config

> ⛔ **INSTRUCTOR ONLY.** Contains every answer. Student handout:
> [`labs/04-opencode-config/README.md`](../../labs/04-opencode-config/README.md).

**Module:** M7 + Lab D · **Budget:** 60 min · **Checkpoint:** `stage-opencode` · **Flex:** 🔒 core
**Deck:** [`slides/05-opencode-proxy.md`](../../slides/05-opencode-proxy.md) (opening section)

---

## The point of this module

The obvious framing, "the client-side logs are sparse, so we need a proxy," is half true and the
false half will get you corrected by someone in the room. Measured against a real opencode session:

| Source | What's in it |
|---|---|
| `~/.local/share/opencode/log/opencode.log` | Operational only: session ids, provider, model, timings. **Zero prompt or reply text.** Sparse, as advertised. |
| `~/.local/share/opencode/opencode.db` (SQLite) | **Everything.** Full prompts, full replies, reasoning, every tool call *with arguments and outputs*, per-session token counts, and **cost in dollars**. |

The client-side record isn't sparse. **It is richer than the vendor dashboard**, richer, in some
ways, than what the proxy captures, because it also holds tool *outputs* from the endpoint.

So the motivation for the proxy is not "the client logs too little." It's:

> **The data is all there. Every property that makes it useful to a SOC is wrong.**

1. **It lives on the endpoint**: the same machine running the agent you're investigating. The
   thing being audited controls the audit trail.
2. **It is shipped nowhere.** No syslog, no forwarder, no API. Collecting it means an agent on
   every developer laptop that speaks an undocumented SQLite schema.
3. **It is app-specific.** This is opencode's schema. Cursor, Claude Code, and Copilot each have
   their own. Your parser breaks on their next release.
4. **The user controls retention.** One `rm -rf` and it's gone, with no tamper-evidence.
5. **You only get it from tools you know about**, which is exactly the Lab 02 problem. You cannot
   collect from clients you failed to discover.

That is the argument for the proxy, and it has the advantage of being true. It also closes the
loop from the earlier labs: shadow-AI discovery isn't an academic exercise, it's the prerequisite for endpoint
collection ever working.

---

## Timing

| Min | Segment |
|---:|---|
| 0–10 | Slides: meet the AI user. Who was behind each host in Lab 02? |
| 10–25 | Part 1: configure opencode, run the agent on `moneyprinter` |
| 25–35 | Task 1: hunt the log file, find nothing |
| 35–50 | Task 2: find *everything* in the database. The turn |
| 50–60 | Task 3: the five problems, and the handoff to Lab 05 |

Running late: cut Task 3's written answers to a two-minute verbal round. Do **not** cut Task 2:
the reversal is the module.

## Before class

- `opencode` installed system-wide (`bootstrap-host.sh` does this). Check: `opencode --version`.
- Seats have the real `ANTHROPIC_API_KEY` in `~/.workshop_env`
  ([`../runbook/api-key-architecture.md`](../runbook/api-key-architecture.md) explains why we don't
  proxy it, and that Lab 05 is where the key boundary gets taught).
- The LLM-ingester sidecar is up, so this lab's traffic is *also* captured under `tag=llm`, that
  is deliberate. In Lab 05 you'll show them the same session from the proxy side.
- The handout points them at the **ingester** (`<ID>81`), so Lab 05 opens with data they generated
  here. The key passes straight through it.

---

## Part 1: Configure the agent (15 min)

The two failure modes below account for essentially every hand that will go up. Put both on a slide
*before* anyone types.

| Symptom | Cause | Fix |
|---|---|---|
| `Error: Not Found: 404 page not found` | `baseURL` missing the **`/v1`** suffix | `http://localhost:<ID>81/v1`. The SDK appends `/messages` |
| `Error: API key is invalid.` | A stored credential from a previous `opencode auth login` outranks `ANTHROPIC_API_KEY` | Put the token in `options.apiKey` in `opencode.json`. (`opencode auth logout` also works, but the config is what we want anyway) |
| Hangs forever, no output, when scripted | `opencode run` waits on stdin | Only bites automation: `opencode run "..." < /dev/null`. Interactive students never see it |
| `provider/model not found` | Model id typo | `opencode models anthropic` lists them. `claude-sonnet-5`, `claude-haiku-4-5`, `claude-opus-5` are all present on 1.18.25 |

The agent's task, *"run the tests, find the failing one, explain the bug, and fix it"*, is real
work: it lists the directory, reads two files, runs the tests, and edits `pricing.py`.

**The bug:** `bulk_price()` uses `if quantity > BULK_THRESHOLD`, but the docstring and the test say
*"at or above"*. Fix is `>=`. Any competent model finds it in one pass.

> **Why a real bug and not "say hello":** every artifact in Part 2 gets more convincing the more the
> agent actually did. A session with four tool calls and a file edit makes the point that a session
> with one text reply cannot.

## Part 2: The audit (25 min)

### Task 1: The log file *(answer: you find nothing)*

```bash
grep -i "bulk_price\|threshold" ~/.local/share/opencode/log/opencode.log
```

**Expected:** operational lines only,
```
timestamp=... level=INFO message=stream providerID=anthropic modelID=claude-haiku-4-5
    session.id=ses_...
timestamp=... level=INFO message="llm runtime selected" llm.runtime=ai-sdk llm.provider=anthropic
```

Session ids, provider, model, timings. **No prompt text, no reply text.** In testing, the phrase
from the prompt returned **0 hits** in 1,441 log lines.

*Beat:* "This is the log. This is what a log-shipper on that laptop would collect. Is anyone
comfortable telling their CISO what that agent did, from this?" Let them agree it's useless. Then
turn it over.

### Task 2: The database *(answer: you find everything)*

Start with the friendly path, this room is weak on SQL and doesn't need it:

```bash
opencode stats
opencode session list -n 5
opencode export <sessionID> > session.json
```

**`opencode stats`** prints an overview, a **COST & TOKENS** panel, and tool usage. On the
authoring workstation it reported *20 sessions, 610 messages, **$58.05 total cost**, 59.6M cache-read
tokens*: across 140 days, unprompted, on by default.

**`opencode export <id>`** writes JSON with `info` and `messages`; each message carries `parts` of
type `text`, `tool`, `reasoning`, `step-start`, `step-finish`.

> The `Exporting session: ses_...` banner goes to **stderr**, so stdout is clean JSON and `| jq`
> works directly. Do not `tail -n +2` the output: that strips the opening `{` and breaks the parse.

**Answers:**

| | Where |
|---|---|
| (a) The prompt, verbatim | `messages[0].parts[].text` |
| (b) Shell commands **and their output** | `parts[].type == "tool"` → `state.input.command`, `state.output` (the full `ls` output is stored) |
| (c) Files read / edits made | `tool` parts named `read`, `edit`, `write` |
| (d) Cost in dollars | `session` row: `cost`, `tokens_input`, `tokens_output`, `tokens_cache_read` (a typical session: `cost=0.0344`, `cache_read=10893`) |

Stretch, for anyone who wants it (no `sqlite3` binary needed on the host, Python has it built in):

```bash
python3 - <<'PY'
import sqlite3, os, json
db = os.path.expanduser('~/.local/share/opencode/opencode.db')
con = sqlite3.connect(f'file:{db}?mode=ro&immutable=1', uri=True)
for sid, title, cost, tin, tout in con.execute(
        "SELECT id,title,cost,tokens_input,tokens_output FROM session "
        "ORDER BY time_created DESC LIMIT 5"):
    print(f"{sid}  ${cost:.4f}  in={tin} out={tout}  {title}")
PY
```

Tables that matter: `session` (19 rows on the test machine), `message` (606), `part` (1780).

*Beat: this is the module's turn:* "Twenty minutes ago you decided the client tells you nothing.
It told you **everything**: including a dollar figure the vendor dashboard won't break out per
session. So why are we building a proxy tomorrow?"

Let the room argue. Steer, don't lecture.

### Task 3: The five problems (10 min)

Whatever order they arrive in, land all five:

1. **Trust boundary.** The record lives on the machine you're investigating. An agent with file
   access, which is the entire point of an agent, can read, alter, or delete its own history.
2. **No transport.** Nothing ships it. There is no syslog, no forwarder, no export hook.
3. **No standard.** `opencode.db` is opencode's schema. There is no GenAI equivalent of Zeek or
   Sysmon here.
4. **User-controlled retention.** `rm -rf ~/.local/share/opencode/`, gone, silently.
5. **Discovery first.** You can only collect from tools you know exist. **Point back at Lab 02.**

### The endpoint-collector detour (5 min, guidance only: do not run it)

Someone will say *"just point a log collector at it."* Take the detour; it lands the module.

Sketch a Gravwell **file follower** config on the whiteboard (`[Follower "opencode"]`,
`Base-Directory = /home/USER/.local/share/opencode/log/`, `File-Filter = "*.log"`,
`Tag-Name = opencode`): or the Splunk UF / Filebeat / vector equivalent, whichever the room uses.
Full syntax is in the handout and at
<https://docs.gravwell.io/ingesters/file_follow.html>.

Then ask what it actually gets you:

| | Collectable by a file follower? |
|---|---|
| `log/opencode.log` (no content) | ✅ |
| `opencode.db` (everything) | ❌ binary SQLite + WAL, rewritten in place, not tailable |

**The collector reaches exactly the half they already proved was worthless.** Shipping the useful
half means writing a scheduled `opencode export` job per tool and maintaining it against schema
changes: running as the user, on the machine under investigation.

> **Hold the scope line here.** Do not let this become "where does Cursor keep its history?" Every
> tool differs and moves between releases; enumerating that landscape is a standing research
> project and is **out of scope for this course**. The transferable lesson is the *method*, find
> it, try to collect it, notice what the collector cannot reach, not a directory list. Say that
> out loud; it saves you fifteen minutes of tool trivia.

*Closing beat, and the bridge to Lab 05:* "Everything you want is in that file. It's on the wrong
machine, in the wrong format, with the wrong retention, for tools you may not know you have. Move
one hop upstream, into the network path, and every one of those five problems disappears at
once."

---

## Answer key

| Q | Answer |
|---|---|
| Prompt text in `opencode.log`? | **No.** Operational only |
| Prompt text in `opencode.db` / `export`? | **Yes**, verbatim |
| Tool calls with args and outputs? | **Yes**, including full shell output |
| Cost per session? | **Yes**: `session.cost`, in dollars |
| The planted bug | `bulk_price()` uses `>` where policy says "at or above" → `>=` |
| Where does it ship? | **Nowhere** |
| Survives `rm -rf`? | **No**, and leaves no trace |
| Collect across 500 laptops? | Custom agent per tool per schema, only for tools you've discovered |

## Where students get stuck

1. **The `/v1` suffix.** Slide it.
2. **`options.apiKey` vs the env var.** Slide it.
3. **Editing JSON in a terminal.** Ship a pre-written `opencode.json` they copy and edit two
   fields in, rather than authoring from scratch. This is the most config-heavy moment in the course.
4. **`opencode export ... | jq` parse errors.** Someone trimmed the first line with `tail -n +2`,
   expecting the banner on stdout. It is on stderr; pipe the output straight into `jq`.
5. **Finding their own session id.** `opencode session list -n 5`, newest first.
