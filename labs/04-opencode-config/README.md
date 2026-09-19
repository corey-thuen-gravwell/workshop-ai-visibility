# Lab 04: The AI user & opencode config

## Objective
Become the AI user you have spent the first half of this course hunting. Install and configure an agent, point it at a real
project, let it work, then **audit it from the endpoint** and decide whether what it leaves behind
is something a security team could actually use.

## Background
Every host you flagged in Lab 02 had a person like this behind it. Before you can decide what to
collect, you need to know what the tool records on its own: and, more importantly, what's wrong
with that record even when it's complete.

## Setup
- Your Gravwell stack is up (Lab 00).
- `opencode` is installed system-wide on the lab host.
- Your seat's `~/.workshop_env` holds the class Anthropic key as `ANTHROPIC_API_KEY` (a short-lived
  key that is revoked when the class ends).

## Part 1: Configure the agent

Work in the sample project:

```bash
cp -r ~/jarvis/labs/04-opencode-config/moneyprinter ~/moneyprinter && cd ~/moneyprinter
```

Create `opencode.json` **in that directory**:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "provider": { "anthropic": { "options": {
      "baseURL": "http://localhost:<ID>81/v1",
      "apiKey":  "<your ANTHROPIC_API_KEY>" } } },
  "model": "anthropic/claude-sonnet-5",
  "small_model": "anthropic/claude-haiku-4-5"
}
```

That `baseURL` points at the **LLM ingester** already running in your Lab 00 stack, so this
session is captured: you'll go looking for it in Lab 05. Your key passes straight through it.

Two things bite everyone, so get them right the first time:

- **The `/v1` suffix is required.** The SDK appends `/messages` to whatever you put here. Without
  `/v1` every request returns `404 page not found`.
- **The token goes in `options.apiKey`, not the environment.** If you (or anyone) has ever run
  `opencode auth login`, that stored credential wins over `ANTHROPIC_API_KEY` and you'll get
  *"API key is invalid"* even though your token is fine.

Now give it real work:

```
opencode run "Run the tests, find the failing one, explain the bug, and fix it."
```

(`test_bulk_discount_applies_at_threshold` fails: the policy says "at or above 100 units" and the
code says `>`.)

**Checkpoint:** `stage-opencode`.

## Part 2: Audit it from the endpoint

The agent just read your files, ran shell commands, and edited code. **What did it leave behind?**

### Task 1: The log file
```bash
ls -la ~/.local/share/opencode/log/
grep -c "" ~/.local/share/opencode/log/opencode.log
```
Search it for the text of the prompt you just typed. Also search for the model's answer.
**Can you find either?**

### Task 2: The database
```bash
opencode stats
opencode session list -n 5
opencode export <sessionID> > session.json   # the banner goes to stderr; this is clean JSON
```
Open `session.json`. Find:
- (a) your prompt, word for word
- (b) every shell command the agent ran, **and its output**
- (c) every file it read and every edit it made
- (d) what the session cost, in dollars

### Task 3: The uncomfortable part
```bash
du -sh ~/.local/share/opencode/
```
Now answer, in writing, for your own environment:
1. Which machine is this data on, and who controls that machine?
2. How does it reach your SIEM today?
3. What happens to it if the user runs `rm -rf ~/.local/share/opencode/`?
4. You have 500 developers. Two use opencode, some use Cursor, some use Claude Code, and each
   stores its history in its own private format. **How do you collect this?**
5. To collect from a tool, you must know it's installed. How did that go in Lab 02?

## Part 3: "Fine, I'll just collect it off the endpoint" (guidance, not a lab step)

The obvious answer to Task 3 is: *point a log collector at it.* Worth walking through, because
**where it stops is the point.**

With Gravwell that collector is the **file follower** ingester
([docs](https://docs.gravwell.io/ingesters/file_follow.html)). Installed on the developer's
machine, `/opt/gravwell/etc/file_follow.conf` would look roughly like:

```
[Global]
Ingest-Secret = YourSecretHere
Cleartext-Backend-Target = your-indexer:4023
State-Store-Location = /opt/gravwell/etc/file_follow.state

[Follower "opencode"]
	Base-Directory = "/home/USER/.local/share/opencode/log/"
	File-Filter = "*.log"
	Tag-Name = opencode
	Recursive = false
	Attach-Filename = true
```

Any endpoint collector works the same way: Splunk UF `[monitor://]`, Elastic Filebeat's
`filestream` paths, `vector`/`fluent-bit` tail sources. The shape is identical: point it at a
directory, tag it, ship it.

**Now the catch, and it's the whole reason this section exists.** Look back at Task 1 vs Task 2:

| | File follower can collect it? |
|---|---|
| `log/opencode.log`: session ids, model, timings, **no content** | ✅ yes |
| `opencode.db`: prompts, replies, tool calls, cost | ❌ **no** |

A file follower tails **append-only text**. `opencode.db` is a **binary SQLite database with a
write-ahead log**, rewritten in place. Tailing it produces garbage, and a half-copied database is
worse than none. So the collector you'd naturally reach for gets you **exactly the half you already
proved was useless**, and misses the half you want.

To ship the useful half you'd have to build something: a scheduled job running `opencode export`
per session into JSONL, then follow *that* directory. Which means a custom exporter, per tool, that
you maintain against their schema changes: running as the user, on the machine you're auditing.

### Scope note

`~/.local/share/opencode/` is **one tool's answer**. Cursor, Claude Code, Copilot, Windsurf, Zed and
every internal wrapper each store history somewhere else, in their own format, and move it between
releases. **Cataloguing that landscape is not this exercise**, and the fact that it *would* be a
standing research project, per tool, forever, is precisely the finding. Take the pattern (find it,
try to collect it, notice what the collector can't reach) and apply it to whatever your developers
actually run.

## Discussion
Compare your answers with what you'll build in Lab 05. The question this lab settles is **not**
"does the client log enough?": it's *"is the client the right place to collect from?"*

## Checkpoint: if you get lost
Every lab has a **known-good snapshot** you can restore without losing anything you've done:

```bash
cd ~/jarvis && git checkout stage-opencode -- labs/04-opencode-config
```

That overwrites the lab's files with the working versions and leaves you exactly where you are,
no branch switching, no detached HEAD, nothing else touched. Ask an instructor if you're unsure.
