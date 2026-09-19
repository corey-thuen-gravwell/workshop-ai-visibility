# Walkthrough 01: Under the hood of LLM tooling

> ⛔ **INSTRUCTOR ONLY.** Contains every answer. Student handout:
> [`labs/01-fundamentals/README.md`](../../labs/01-fundamentals/README.md).

**Module:** M2 · **Budget:** 60 min (≈35 lecture + ≈25 mini-lab) · **Checkpoint:** none
**Flex:** 🔒 core, never cut · **Deck:** [`slides/01-fundamentals.md`](../../slides/01-fundamentals.md)

Everything else in the course is a corollary of this module. Shadow AI is findable because it's
HTTP. The proxy works because the client resends everything. MCP is dangerous because tool calls
are executed by *your* code. If M2 lands, the rest is easy; if it doesn't, students spend the course
taking things on faith.

**All numbers below were measured against the live API** (`claude-haiku-4-5`). Yours
will differ by a token or two; the *shape* is what matters, and the shape is stable.

---

## Timing

| Min | Segment |
|---:|---|
| 0–20 | Slides: it's HTTP and JSON. Request anatomy, roles, `max_tokens`, `usage` |
| 20–30 | Tasks 1–2: the statelessness reveal |
| 30–40 | Tasks 3–4: you supply the memory; the meter climbs |
| 40–52 | Task 5: tool calling, and who actually executes |
| 52–60 | Discussion: plant the three seeds the rest of the course harvests |

This is the first time most of the room types `curl`. Budget for that: put the `ask()` helper on a
slide, and have a copy-pasteable version in the handout (it's there).

## Before class

- Nothing to stand up: this module talks **straight to the provider**. No Gravwell, no proxy.
  That is deliberate: bare HTTP first, and it's the truest version of "there's no magic here."
- `jq` installed (pre-flight checks it).
- Seats already have `ANTHROPIC_API_KEY` in `~/.workshop_env`; the handout uses `$ANTHROPIC_API_KEY`
  so nobody has to be told a value.
- **No Gravwell required.** M2 runs before Lab A. Don't let anyone start docker yet.

> **Nothing is capturing this.** These requests go straight to Anthropic and leave no trace you
> control: which is exactly the point to make at the end of M2. *"You just sent five prompts to a
> provider. Where is the record? There isn't one. Hold that thought."* The proxy labs are where they put
> something in the path and the record starts existing.

---

## Task 1: One request, one response

**Measured:** `text: "noted."` · `stop_reason: "end_turn"` · **`input_tokens: 21`, `output_tokens: 5`**

Walk the response object on the projector. Three fields matter and the rest is noise right now:
`content[]` (a *list* of typed blocks: this matters in Task 5), `stop_reason`, `usage`.

## Task 2: The reveal

**Measured:** **`input_tokens: 13`**, *fewer than Task 1*, and the model replied:

> *"I don't have any information about your favorite color. **We haven't spoken before**, and I
> don't have access to personal information about you unless you share it with me in our
> conversation."*

Read that sentence out loud. "We haven't spoken before": thirty seconds after they spoke to it.

*Beat:* "There is no conversation on the server. There is no session. The thing you think of as a
chat is a fiction your client maintains." Ask who expected it to remember. Most hands go up. Good.

Point at the token count: **21 → 13**. Fewer tokens because they sent less. The API charged for
exactly what was in the envelope, because the envelope is all there is.

## Task 3: You supply the memory

**Measured:** **`input_tokens: 35`**, reply *"Your favorite color is chartreuse."*

Nothing changed server-side between Task 2 and Task 3. The only difference is what they put in the
POST body. **The client is the database.**

## Task 4: The meter

**Why Task 4 uses a file.** Typing a five-message JSON body into the shell as a quoted argument
was the hardest thing in the first three hours and none of the difficulty was the lesson: an apostrophe in the question they
invented closed the quote and left them at a `>` prompt they read as a hang, and a missing comma
came back as a provider 400 that says nothing about commas. So the body lives in a file. The lab ships
`conversation.json` (Task 3's body), they copy it to `turn4.json`, add two messages in `nano`,
validate with `jq . turn4.json`, and send it with the `askf` helper (`curl -d @file`).

**What to watch for:**

- They edit `turn4.json`, never `conversation.json`. If someone mangles their copy, `cp
  conversation.json turn4.json` starts over, and the lab's checkpoint restores the original.
- The comma. The line above the two new ones needs one; the last `}` must not have one. `jq .`
  catches both, which is the habit worth teaching here: validate the payload before blaming the API.
- `nano` is not universal knowledge. `Ctrl-O`, `Enter`, `Ctrl-X` is in the handout; say it out loud
  anyway.
- The handout offers a `jq '.messages += [...]'` one-liner for anyone who would rather not open an
  editor. It is a legitimate route, not a shortcut around the lesson, and it is pure copy-paste.

If the room is drowning anyway, this is the body that produced the numbers below, as one paste:

```bash
ask '{"model":"claude-haiku-4-5","max_tokens":64,"messages":[
  {"role":"user","content":"My favorite color is chartreuse. Reply with just: noted."},
  {"role":"assistant","content":"noted."},
  {"role":"user","content":"What is my favorite color?"},
  {"role":"assistant","content":"Your favorite color is chartreuse."},
  {"role":"user","content":"Name one flower that color. Two words max."}]}'
```

*Beat, worth thirty seconds:* they now have a file on disk holding the entire conversation, which
they resend in full every turn. That is what "memory" is, and it is the same shape as the
`opencode.db` they will open in Lab 04.

**Measured progression**, put this table on the board as they call out their numbers:

| Turn | What was sent | `input_tokens` | `output_tokens` |
|---|---|---:|---:|
| 1 | one message | 21 | 5 |
| 2 | one message, no history | **13** | 48 |
| 3 | 3 messages | **35** | 11 |
| 4 | 5 messages | **59** | 11 |

**Input climbs; output is flat.** That's the entire economics of agents in one table.

*Beat:* extrapolate out loud. A coding agent runs 30–50 turns and re-sends everything each time, so
cost grows roughly with the **square** of conversation length, not linearly. Then hand them the
measured number from Lab 05: **one trivial opencode task, list a directory, read a three-line file,
cost 22,393 input tokens against 350 output.** Sixty-four to one.

> Someone will ask about prompt caching. Correct answer: it makes it *cheaper*, not *smaller*,
> the whole conversation still crosses the wire every turn, which is the part that matters to us.
> (They'll see `cache_read` tokens in Lab 04's `opencode stats`.) Don't rabbit-hole.

## Task 5: Tool calling, and who executes

**Measured:** `stop_reason: "tool_use"` · `content` types `["text", "tool_use"]` ·
tool_use block: `{"name": "read_file", "input": {"path": "/etc/passwd"}}` ·
**`input_tokens: 575`**, `output_tokens: 69`

### Answers

1. **`stop_reason` is `tool_use`**: not `end_turn`. The model stopped to ask for something.
2. The `tool_use` block names `read_file` with `{"path": "/etc/passwd"}`. **It asked for
   `/etc/passwd`**: unprompted by any mention of that path in the tool definition.
3. **Nothing read the file.** Nothing could have. The API returned JSON describing a request. There
   is no execution anywhere in this exchange.
4. **13 → 575 input tokens.** One tool definition cost ~44× the bare question.

### The three beats, in order

**Execution is yours.** The model emits a *request*; a loop in the client decides whether to run
it, runs it, and posts the result back as a `tool_result`. "The AI deleted the production
database" always means *a program ran a command the model asked for*. The model has no hands. The
agent framework is the hands, and that's the thing you can instrument, gate, and log.

**It reached for `/etc/passwd` on its own.** Nobody suggested that path. Hold it up against Lab 03,
where they'll watch a real agent do exactly this on a real endpoint, and against Labs 06 and 07, where
the tool list comes from an MCP server someone else wrote.

**Tool definitions dominate the payload.** 575 vs 13 tokens for *one* tool. Real agents advertise
ten or more, measured in Lab 05: an opencode session offered **10 tools** (`bash`, `edit`, `glob`,
`grep`, `read`, `skill`, `task`, `todowrite`, `webfetch`, `write`) on every single turn. So most of
what an agent sends is a description of its own capabilities. **Anything sitting in the path learns
exactly what that agent is able to do**, which is `request.tools_offered` in Lab 05, and it starts
here.

## Discussion (8 min): plant three seeds

Ask, don't tell. Each maps to a later module:

1. *"The client sends the whole conversation every turn. What does something in the network path
   see?"* → **everything.** → the proxy, in Lab 05. Don't resolve it; let it sit.
2. *"The model asked to read a file and nothing happened. Which component decided?"* → the agent
   loop → **that's where a control goes** → MCP, Labs 06 and 07.
3. *"Your input tokens climbed every turn. Who in your org sees that number today?"* → usually
   finance, monthly, in aggregate → **the audit gap**, M3, next module.

---

## Answer key

| Q | Answer |
|---|---|
| Does the API remember Task 1? | **No.** *"We haven't spoken before"* |
| What changed between Tasks 2 and 3? | Only the request body. The client supplied the history |
| Input tokens, turns 1–4 | **21 → 13 → 35 → 59** |
| Output tokens, turns 1–4 | 5 → 48 → 11 → 11 (flat) |
| `stop_reason` with a tool | **`tool_use`** |
| What did it ask to read? | **`/etc/passwd`**, unprompted |
| Did anything execute? | **No.** The API returns a request; your code executes |
| Cost of one tool definition | **13 → 575** input tokens |

## Where students get stuck

1. **Quoting.** Single-quoted JSON inside a shell command is the #1 time sink. The `ask()` helper
   in the handout exists for this; make sure everyone pastes it before Task 1.
2. **`jq` missing or output too wide.** `| jq '.usage'` narrows it. Pre-flight checks for `jq`.
3. **Building the multi-turn array by hand** (Tasks 3–4). Expect malformed JSON. Have the full
   Task 3 body on a slide to copy.
4. **`max_tokens` is required** on this API: omitting it is a 400, not a default.
5. **Assuming `content[0]` is always text.** In Task 5 it's `[text, tool_use]`. That's why the
   handout has them list `content` *types*, not index blindly.
