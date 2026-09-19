# Class day - move from testing the environment to "live"

The ordered list of everything that has to happen between the last dry run and the first student
login, plus the commands you run *during* the class to hand out each lab.

Nothing here is new tooling. It is the existing scripts in the order that matters, with the two
places where the obvious command is the wrong one called out.

> **Read §1 first.** It is the state testing leaves a host in, and most of it is something a
> student would notice.

> **Set the seat count before you start.** The scripts default to **2 seats** (ids 10–11), which is
> the development and self-guided default, not a classroom. Export the roster size once and every
> command below picks it up:
>
> ```bash
> export SEATS=20 START_ID=10      # ids 10-29
> ```
>
> `reset-seats.sh`, `preflight.sh` and `rmuser.sh` all read it. A seat that exists but is outside
> the range is simply not touched, which is how you leave one instructor seat alone.

---

## 1. What testing leaves behind

Run `release-stage.sh` (status), `share status`, `seat-survey.sh` and a `docker ps` before anything
else, and expect to find some of these. Each is a thing a student would notice.

| # | Finding | Why it matters | Fixed by |
|---|---|---|---|
| 1 | **Every stage is released.** `release-stage.sh` reports the last stage | A fresh clone hands a student every lab before M2 has started. The whole staged-release design is off | §3 step 3 (rebuild with `INITIAL_STAGE`) |
| 2 | **Documents are live, including walkthroughs** | The walkthroughs are the answer keys, on the share site behind nothing but the class basic-auth password | §3 step 5 (`share unpublish --all`) |
| 3 | **Orphaned documents**: a renamed or removed lab's `.html`/`.pdf` still live but no longer staged | Already-published copies stay live until withdrawn; `share refresh` steps over them | §3 step 5 (same command) |
| 4 | **Used seats**: containers up for hours, volumes and networks left, a home directory containing `moneyprinter`, `.local/share/opencode`, `.config`, `.bash_history` | Student 1 inherits somebody else's `opencode stats`, somebody else's session DB, and, worst, a **stored opencode credential that silently outranks `ANTHROPIC_API_KEY`**: the exact Lab 04 failure mode. A seat with lab data already ingested makes its "prove the data landed" step lie | §3 step 4 (`reset-seats.sh`) |
| 5 | **Stale lab data.** The generated window is anchored to the last build | "Last 48 hours" catches it this morning and stops catching the start of the scenario this afternoon. A day later most of it is outside the window | §3 step 3 (the rebuild regenerates) |

Also check for: stray e2e clones under `/tmp`, a gateway unit left from a demo, anything listening
that is not the LLM relay on `127.0.0.1:9010`, the cert's expiry date, and free disk and memory.

---

## 2. Two commands that are not the ones you would reach for

**`redeploy` will not un-release the labs.** It calls `build-student-repo.sh` without
`INITIAL_STAGE`, and that script defaults to *"keep the students where they were"*, which after a
round of testing means the last stage. Use the explicit build in §3 step 3. `redeploy` is the right tool once the class
is running and you have fixed a typo in a handout; it is the wrong tool this morning.

**`share refresh` will not remove an orphaned document.** It only re-copies files that are *already*
live *and* still staged; a file that is live but no longer staged is stepped over.
`share unpublish --all` is the one that clears them, and it is deliberately asymmetric: `publish
--all` never sweeps in the walkthroughs, `unpublish --all` always does.

---

## 3. The reset, in order

Roughly 20 minutes, most of it the rebuild. **Do it at the venue if you can**, or at least after
you have decided the day's start time, because step 3 anchors the data to the moment you run it.

### Step 0 (authoring box) · confirm what you are about to ship

```bash
cd ~/jarvis/ai-audit-training
git status --short        # want: clean
git log --oneline -3
```

### Step 1 (authoring box) · sync the repo to the host

```bash
. instructor/runbook/.runbookrc
sync-repo
```

Cheap and idempotent. Skip only if `git status` was clean *and* you have changed nothing since the
last sync.

### Step 2 (authoring box) · rebuild and ship the documents

```bash
deploy-share --rebuild
```

Builds 31 PDFs + 31 HTML plus the decks, wipes `staged/` and re-ships. It refuses to ship anything
answer-shaped outside `walkthroughs/`, and refuses on a code line wider than 100 characters.

### Step 3 (host, as root) · regenerate the data and rebuild the student repo, released through Lab 01 only

**This is the important one.**

```bash
ssh jarvis
INITIAL_STAGE=stage-fundamentals /opt/workshop/src/instructor/runbook/scripts/build-student-repo.sh
```

What it does, in order: regenerates the Lab 02 / Lab 03 / P8 / P9 datasets with the window anchored
to **now**, replays `student-repo/checkpoints.yaml` into a fresh linear history, runs the leak
assertions (answer sections, `sk-ant-` keys, `answer-key`, the Gravwell LLM token, `instructor/`),
publishes the complete history to the root-only `/opt/gitsrv/jarvis-all.git`, and rebuilds the
served `/opt/gitsrv/jarvis.git` **stopping at `stage-fundamentals`**.

Verify before moving on:

```bash
/opt/workshop/src/instructor/runbook/scripts/release-stage.sh
```

Want exactly one green `●` (`stage-fundamentals`) and a yellow `→ stage-demystify (next)`.

> If it dies on a leak assertion, **do not pass it a flag to get past it.** Read what it found;
> the assertion is almost always right.

### Step 4 (host, as root) · return every seat to never-used

```bash
export SEATS=20 START_ID=10                                            # the roster, not the default 2
/opt/workshop/src/instructor/runbook/scripts/reset-seats.sh --dry-run   # look at it first
/opt/workshop/src/instructor/runbook/scripts/reset-seats.sh
```

Removes every seat container, volume and network (**including the separate `<ID>litellm` compose
project**, which a `docker compose down` in `labs/00` does not touch), clears each home except
`.ssh` / `.workshop_env` / the shell dotfiles, and re-clones `~/jarvis` from the served repo.
Accounts, passwords and instructor keys survive.

Must run **after** step 3, because it clones what step 3 published.

Expected tail: `reset <SEATS> seats`, `<SEATS>/<SEATS> seats have a working ~/jarvis clone`, and
`0 seat container(s) remaining`. If it says `reset 2 seats`, you did not export `SEATS`.

### Step 5 (host, as root) · take the share site back to empty

```bash
/opt/workshop/src/instructor/runbook/scripts/share.sh unpublish --all
/opt/workshop/src/instructor/runbook/scripts/share.sh status
```

Want `0 live · 75 staged and not yet released` and no walkthrough warning. This also clears any
orphaned files (finding 3).

### Step 6 · credentials: nothing to do

**Rotate before a delivery, not the morning of.** If both credentials were set when the host was
provisioned and have not leaked, nothing changes here: no `makeuser.sh` re-run and no relay restart
in the morning sequence.

The two credentials, for the record: the **Anthropic key** in `/opt/workshop/.env` and each seat's
`~/.workshop_env`, and the **Gravwell LLM token** in `instructor/runbook/gravwell-llm.env`, held
only by the root-only loopback relay. Rotating either is a §8 job, after the course. If you ever do
rotate mid-setup, the Anthropic key needs `makeuser.sh` to push it into every seat and the LLM
token needs `start-llm-relay.sh restart`; both are described in
[`api-key-architecture.md`](api-key-architecture.md).

They still get **verified**, not rotated, in §5.

### Step 7 (optional, host, as root) · stand up the P3 semantic-search demo

Only if you intend to run padding module P3. Check whether it is already up
(`/opt/workshop/semantic-demo` exists, `39*` containers running). It takes a few minutes and needs the LLM
token, so do it before the room arrives or not at all.

```bash
/opt/workshop/src/instructor/runbook/scripts/enable-semantic.sh up
/opt/workshop/src/instructor/runbook/scripts/enable-semantic.sh seed
```

The deck (`slides/05b-semantic-search.md`) carries the measured results as backup slides, so P3
still lands as a talk if you skip this.

---

## 4. If you have a Firewall: At the venue, before anyone logs in

**The one thing that cannot be done in advance.** On the wifi/network that will be used by students:

```bash
curl -s ifconfig.me
```

then, on the host:

```bash
WORKSHOP_CLASS_IP=<that ip> /opt/workshop/src/instructor/runbook/scripts/bootstrap-host.sh
```

Student seats share one NAT egress IP, password auth is on, and the passwords are predictable. Left
undone, fail2ban bans the whole room after a handful of mistyped passwords **collectively**, and
its nftables rule drops established sessions too: everyone loses their shell mid-lab for five
minutes. Right now `ignoreip` is `127.0.0.1/8 ::1` only.

Confirm:

```bash
fail2ban-client get sshd ignoreip
```

---

## 5. Final check

```bash
/opt/workshop/src/instructor/runbook/scripts/preflight.sh          # exits non-zero on any ❌
```

Then three things preflight does not cover, all worth the two minutes. Preflight checks that the
credentials are *present and well-formed*; it never spends a token proving either one still works, though.

```bash
# a real seat can log in and its clone stops at Lab 01
ssh workshop11@<lab-host> 'ls ~/jarvis/labs; echo $WORKSHOPUID; echo ${ANTHROPIC_API_KEY:0:12}'
```
Want `01-fundamentals` and nothing else under `labs/`.

On the host (`ssh jarvis`), spend one token proving the provider key is alive:

```bash
sudo -u workshop11 bash -lc 'curl -sS https://api.anthropic.com/v1/messages \
    -H "x-api-key: $ANTHROPIC_API_KEY" -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d "{\"model\":\"claude-haiku-4-5\",\"max_tokens\":8,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}" \
    | head -c 200'
```

Want a JSON body with a `content` block. An `authentication_error` here means every AI lab is
dead, and you find that out now rather than at M2 with twenty people watching.

Same idea for Lab 01b, which has no fallback if the relay's upstream token has expired:

```bash
curl -s http://127.0.0.1:9010/api/tags | head -c 200
```

Want a JSON model list.

```bash
# the share site is up, asks for a password, and has nothing on it yet
curl -s -o /dev/null -w '%{http_code}\n' https://<lab-host>/           # want 401
/opt/workshop/src/instructor/runbook/scripts/share.sh url
```

And read the room's URL and password off `share url` / `/opt/workshop/.env` onto the first slide.

---

## 6. During the class: handing out each lab

**One command releases a lab**: `release-stage.sh` (short name `release` from the authoring box).
It fast-forwards the served repo **and** publishes that lab's `.html` on the share site, so the
files and the handout arrive together. Students then run `cd ~/jarvis && git pull`.

`share.sh` alone only moves documents. Publishing a lab page with it does not give the seats the
files, and it warns you when you try.

### The sequence, in course order

| When | Command | What the students get |
|---|---|---|
| **Lab 01 starts (M2)** | `share publish labs/01-fundamentals html` | Already in their clone; this only puts the page up. **The one lab whose page you publish by hand**, because it was released at build time |
| Lab 01b (M2b) | `release --next` | `stage-demystify` + `labs/01b-demystifying-ai.html` |
| Lab 00 / Lab A | `release --next` | `stage-gravwell` + `labs/00-environment.html` |
| Lab 02 (M4) | `release --next` | `stage-shadowai` + `labs/02-shadow-ai.html` |
| *P9, if you run it* | `release --next` | `stage-shadowai-sources` + `labs/p9-shadow-ai-sources.html` |
| Lab 03 (M5) | `release --next` | `stage-sysmon` + `labs/03-endpoint-sysmon.html` |
| Lab 04 (M7) | `release --next` | `stage-opencode` + `labs/04-opencode-config.html` |
| Lab 05, both parts (M8 + M9) | `release --next` | `stage-llm-proxy` + `labs/05-llm-proxy.html` and `labs/p8-ai-assistant-audit.html`. One release for the whole lab: litellm, `testai.sh`, the reference captures, P8 and `src/logging-proxy` |
| Lab 06 (M10) | `release --next` | `stage-mcp` + `labs/06-mcp-deep-dive.html` |

`release` on its own prints the status board: green `●` released, yellow `→` next.

### The padding labs are share-only

P2, P3 and P4 have **no stage of their own** (their files already arrived with earlier stages, or
they need no files). `release --next` will never publish them. Hand them out with:

```bash
share publish labs/p2-extend-the-proxy html     # after M9, if the room is fast
share publish labs/p3-semantic-search html      # the P3 demo page
share publish labs/p4-second-client html        # needs `claude` on the host: it is installed (2.1.263)
```

### Slides and take-home materials

```bash
share publish slides/03-shadow-ai        # as you present each deck, if you want them to follow along
share publish --materials html           # questions-for-the-ciso at M6, the checklist at M13
share publish materials/terminal-cheatsheet html   # to one struggling table, or to the room, your call
```

End of each day, when the typing is done:

```bash
share publish --all pdf                  # every take-home PDF. Never includes the walkthroughs
```

End of the course, and only if you mean it:

```bash
share publish --walkthroughs             # every answer, every task. One-way in practice
```

### Where is the room? `survey`

```bash
survey                 # from the authoring box; on the host it is seat-survey.sh
survey --tags          # ...and ask each seat's Gravwell what it actually holds
survey --fast 14 17    # two seats, no storage measurement, instant
```

Read-only, safe to run while people are typing. One row per seat: which stage their clone is on and
whether they have pulled the release you just made, open SSH shells, their Gravwell and ingester
containers, which of Lab 05's proxies are actually listening, how much they have ingested, and the
furthest lab with evidence on disk. It ends with the lists you act on: who has not pulled, who has
no clone, which seats nobody has ever logged into.

`--tags` is the one that answers "did the lab I just taught land". It queries each seat's Gravwell
with that seat's own API token and prints the tags it holds with entry counts, so a seat that has
done Lab 02 reads `corelight_conn 431  corelight_dns 420  corelight_ssl 374  corelight_http 39
okta 2`, and one that has not reads `nothing but Gravwell talking to itself`.

The LAB column is evidence on disk, not comprehension. It tells you who is stuck on infrastructure,
which is the thing you can actually fix from the front of the room.

### Two things to say out loud

- **`.html` during a lab, `.pdf` for the plane.** Copying a command out of a PDF inserts a newline
  at every visual line break and silently breaks it. The HTML pages have a Copy button per block.
- **Releasing is one-way.** Taking a lab back means rebuilding and re-cloning every seat, which
  loses student work. If you release the wrong stage, keep going; it is not worth the recovery.

### If you have to fix a handout mid-class

```bash
redeploy                    # sync + rebuild docs + rebuild the student repo at the SAME released
                            # stage + update every seat in place, keeping their edits
redeploy --no-docs          # faster, if you only touched a lab file
```

It reports any seat whose own edits collide with your fix; `reset-seat <N>` is the blunt fix for
that one seat. **Do not pass `--regen` mid-class**: it re-anchors every timestamp, which changes
the dataset files and therefore every stage hash from Lab 02 on, for no benefit.

---

## 7. Between sessions, and the data window

If you are running the course over more than one sitting, **leave everything up**. Seats keep their
containers, their volumes, their Gravwell data and their work, so people come back to the
environment they left. There is no teardown between sessions and no restore to run. If one seat
dies overnight, rebuild that seat (`reset-seat <N>`, then it repeats Lab 00) rather than touching
the room.

### The data window

The generators write a **24-hour window ending at the moment you run them**, and every lab tells
students to search **last 48 hours**. So a dataset generated at 07:00 covers the 24 hours before
that, and it stays fully inside a 48-hour lookback for the two days that follow.

That is fine for everything in the first arc. The two labs that read a *file* and might land a day
or more later are **P8** (`tag=logbot`) and **P9** (the beyond-the-wire sources): by then a 48-hour
lookback has eaten the first several hours of the scenario.

**Do not regenerate to fix that.** Re-anchoring changes the dataset files, which changes every
stage hash from Lab 02 on, and P9 has to stay aligned with Lab 02's data (same cast, same window)
or its whole premise breaks. Instead, tell the room to widen the time picker: **last 3 days**, or an
absolute range. It costs one sentence and risks nothing.

Resuming after a break is worth five minutes:

```bash
ssh jarvis 'docker ps --format "{{.Names}}" | grep -c "^[0-9]"'   # seats that left stacks running
ssh jarvis 'df -h / | tail -1; free -g | head -2'
/opt/workshop/src/instructor/runbook/scripts/preflight.sh
survey                                                            # where did everyone get to
```

and re-confirm the class IP if the venue's egress changed while you were away.

---

## 8. After the course

```bash
share publish --all pdf                  # take-home
share publish --walkthroughs             # optional
```

Then, in this order:

1. **Revoke the Anthropic key.** It is short-lived by design; make that true.
2. **Rotate the Gravwell LLM token** in `instructor/runbook/gravwell-llm.env` (git-ignored) and
   `start-llm-relay.sh restart`.
3. `reset-seats.sh`, or `rmuser.sh` if the host is going away.
4. Record what actually happened, especially anything that failed in front of the room, and fold
   it into the walkthroughs' failure tables and make an issue on our public repo. That is what makes the next delivery better.

---

## Rollback

| It went wrong | Do this |
|---|---|
| Rebuild released too much | Re-run step 3 with the right `INITIAL_STAGE`, then step 4. Seats must re-clone; do it before anyone starts |
| A seat is wedged | `reset-seat <N>` from the authoring box (`START_ID=<N> SEATS=1 reset-seats.sh` on the host) |
| Everyone is locked out at once | fail2ban banned the room's shared IP. `fail2ban-client set sshd unbanip <ip>`, then do §4 properly |
| Walkthroughs went live by accident | `share unpublish --walkthroughs`. Assume anyone who was looking already has them |
| Gravwell will not start on a seat | Almost always the licence or a duplicate 514/601 bind. `docker exec <ID>gravwell /opt/gravwell/bin/gravwell_simple_relay -validate`, then the `down -v` / `up -d` nuke in `walkthroughs/00-environment-gravwell.md` § Triage |
