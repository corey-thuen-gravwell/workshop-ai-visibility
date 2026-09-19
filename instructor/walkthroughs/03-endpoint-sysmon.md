# Walkthrough 03: Endpoint detection with Sysmon

> ⛔ **INSTRUCTOR ONLY.** Contains every answer and every query. Student handout:
> [`labs/03-endpoint-sysmon/README.md`](../../labs/03-endpoint-sysmon/README.md).

**Module:** M5 + Lab C · **Budget:** 105 min (the longest module in the course)
**Checkpoint:** `stage-sysmon` (`git checkout stage-sysmon -- labs/03-endpoint-sysmon`) · **Flex:** 🔒 core
**Deck:** [`slides/04-sysmon.md`](../../slides/04-sysmon.md)
**Data:** real, 3,599 Linux-Sysmon events from an actual opencode session, re-timed onto the Lab 02
window. Provenance: [`datasets/sysmon/how-this-data-was-made.md`](../../datasets/sysmon/how-this-data-was-made.md)
(instructor-side only; the student repo ships just `datasets/sysmon/generated/`).

Lab 02 was synthetic. **This data is real**, including the bug at the centre of it. Say that out
loud: it changes how the room treats the exercise.

**Design:** the lab uses **`winlog`**, shows `xml` once so students know the
general tool exists, installs the **Sysmon kit** through the UI, and ships **only the re-timed
file**. The January capture stays here; two files in the student repo only invited ingesting the
wrong one.

---

## Executive summary: what is in the data, and what students should find

**One file, one host, one hour.** `sysmon-retimed.xml` is a real Sysmon-for-Linux capture from an
Ubuntu VM (`ubuntu-sysmon`, user `ubuntu`) taken while an opencode session was deliberately driven
to misbehave, re-timed by the Lab 02 generator so its climax lands inside Lab 02's network story.
Nothing in it is synthetic except the clock.

| | |
|---|---|
| Events | 3,599 (3,598 land in the search window) |
| Process creates (EventID 1) | 1,081 |
| Process terminates (EventID 5) | 2,516 (70% of the file: noise, and a lesson) |
| Service state (EventID 4, 16) | 2 |
| Hosts / users | one VM, one interactive user, plus `root` daemons |
| Provider | `Linux-Sysmon` (not `Microsoft-Windows-Sysmon`: this is what breaks the kit's macro) |
| Window of interest | **11:07:53 to 11:14:55**, the same eight minutes as Lab 02's `10.13.42.42` burst (11:07:56 to 11:15:48) |

**The cast, by parent PID.** Three parents spawn most of the machine's children and only one of
them matters:

| ParentProcessId | Children | What it is |
|---|---:|---|
| 1180 | 134 | `systemd`, user session manager. Loud, boring, expected |
| **3565** | **109** | **opencode**, the AI coding agent. The target |
| 1 | 85 | `init` |
| 854, 2862, 1348, 1172 | 33, 30, 29, 26 | ordinary daemons and shells |

Raw child count puts the agent second, not first. That is deliberate honesty in the data: the
first query produces a shortlist, and the bash-filtered rule in task 5 is what isolates it (3565
has 73 bash children; the runner-up has 3).

**What the agent did**, all visible in `CommandLine` on its 73 `bash -c` children, interleaved with
normal developer work (`npm install`, `npm test`, linters, `git status`, `cat`/`ls`/`grep` on a
JavaScript project):

- user enumeration: `cat /etc/passwd`, `/etc/group`, `id`, logged-in users, sudo checks
- credential hunting: shell history, attempted `~/.ssh/id_rsa` reads, `env | grep -iE 'password|secret|key|token'`, config-file searches across the home directory
- environment probing: cloud metadata calls to `169.254.169.254` (AWS and Azure paths), a localhost port scan, a check for monitoring processes (it found Sysmon)
- persistence and exfiltration shapes: a script making repeated outbound connection attempts to an unusual host, a helper that collected system info, a `package.json` install hook, a `.env` secret swap, an attempted cron entry

None of it is malware. Every command is one a developer could type. The finding is the sequence,
the speed, and the fact that a language model chose it.

**The quirk that is the module's thesis.** Every one of the 109 children has an empty `ParentImage`
and `ParentCommandLine`. Sysmon for Linux has a race: a parent that spawns children fast has no
cached metadata yet. So the field most detection content keys on is blank for exactly the workload
you most want to catch. Students must cluster by `ParentProcessId` instead, and the kit's own
"Top 100 Parent Processes" panel shows the same thing as a bar labelled `-` with 553 events.

**What students are expected to find, task by task**

| Task | Expected finding |
|---|---|
| 1 | PID 3565 is the non-system high spawner (109), behind systemd (134) |
| 2 | `ParentImage` and `ParentCommandLine` are `-` on all 109 children |
| 3 | 73 bash, 9 cat, 5 env, 5 node, 4 opencode, 4 realpath, 3 ls, 2 chmod, 1 rg, 1 id |
| 4 | the reconnaissance command lines above, in the clear |
| 5 | the high-bash-spawner rule (EventID 1, `Image ~ bash`, `count > 10`) returns exactly one PID |
| 6 | the PID's window is the Lab 02 rogue host's window: one machine, one incident, two logs |
| kit | dashboards empty until `PROVIDER` is `Provider=="Linux-Sysmon"`; then they fill |

**What is not in the data, and why that matters.** No network events (the capture is process-only,
so the kit's network, DNS and registry dashboards stay empty), no file contents, and above all
**no prompts, no model responses, no tool-call arguments**. Sysmon can tell you which process ran
`cat /etc/passwd` and when; it cannot tell you what the agent sent to the model afterwards. That gap
is what M6 names and the proxy labs close.

**Provenance and answer key** (instructor-side only, not in the student repo):
`datasets/sysmon/how-this-data-was-made.md`, `datasets/sysmon/gravwell-queries.txt`, and the
original capture `datasets/sysmon/sysmon-events-jan21-clean.xml`.

---

## Timing

| Min | Segment |
|---:|---|
| 0–25 | Slides: why agents look different on an endpoint; process-tree shape |
| 25–32 | Ingest, confirm the tag, `xml` vs `winlog` side by side |
| 32–42 | Install the Sysmon kit; dashboard is empty; fix the `PROVIDER` macro; it fills |
| 40–52 | Task 1: cluster by parent, find the high spawners |
| 52–60 | Task 2: the race condition (the "wait, that's broken" moment) |
| 60–72 | Task 3: what it spawned |
| 72–87 | Task 4: what it actually ran. **This is the payoff; protect the time** |
| 87–95 | Task 5: turn it into a detection rule |
| 95–105 | Task 6: cross-source pivot back to Lab 02, and debrief |

`winlog` took most of the syntax pain out of this module: the field names are the ones in the XML
and the filters are inline. Expect typos on `ParentProcessId` (capital I, lower-case d) and on
`~` versus `==`.

---

## Data prep

Students ingest the one file they have:

```bash
nc -q1 localhost ${WORKSHOPUID}07 < ~/jarvis/datasets/sysmon/generated/sysmon-retimed.xml
```

It is produced by the Lab 02 generator (`--sysmon-in/--sysmon-out`) on every
`build-student-repo.sh` run, so its timestamps sit on the Lab 02 rogue window of the same build.
**One `<Event>` per line**, 3,599 lines, which is why it feeds a line-delimited listener over `nc`
with no preprocessing. Don't let anyone "fix" it by pretty-printing.

> ⚠️ **The data must come from the same build as the Lab 02 data.** In one build the served repo
> briefly carried two-day-old generated files (the authoring box's copy had been synced over the
> host's); `sync-repo.sh` now refuses to ship `generated/` and `redeploy.sh --regen` is the
> morning-of rebuild. If `tag=sysmon` returns nothing over 48 hours, that is the first thing to check.

Confirm, over **last 48 hours**:

```
tag=sysmon
```

## What's actually in the file

| | Count |
|---|---:|
| Total events | 3,599 (`tag=sysmon count` reports **3,598** after ingest: one event lands outside the window; harmless) |
| EventID 1 (ProcessCreate) | 1,081 (1,080 in the 48 h window) |
| EventID 5 (ProcessTerminate) | 2,516 |
| Other (EventID 4, 16: service state) | 2 |

```
tag=sysmon winlog EventID | count by EventID | sort by count desc | table EventID count
```

Every task filters `EventID == 1` first. Roughly 70% of the file is process-*termination* noise: a
useful observation to make out loud, since it's why a naive "count events per PID" gives the wrong
shape.

## `xml` versus `winlog` (say this once, at the start)

Both of these return the identical table. The first is the general XML extractor with full paths;
the second is the Windows-event-schema extractor: `System` fields by short name, anything else looked
up in `EventData`, filters inline.

```
tag=sysmon xml Event.System.EventID as EventID
  Event.EventData.Data[Name]=="ParentProcessId" as ParentPID
| eval EventID == "1"
| count by ParentPID | sort by count desc | table ParentPID count
```
```
tag=sysmon winlog EventID == 1 ParentProcessId
| count by ParentProcessId | sort by count desc | table ParentProcessId count
```

**Beat:** "the second one is what you write when the tool knows your data; the first is what you
write when it doesn't. Both are fine. Knowing that the second exists is worth ten minutes an hour."
Everything below is `winlog`.

**Adding a field.** The handout then makes the query-time-parsing point
explicit: nothing is extracted unless it is named on the `winlog` line, and a name used only later
in the query is a parse error (`invalid token: expected (` from `count by`). The example adds
`ParentImage`, which also walks them up to the race condition before task 2:

```
tag=sysmon winlog EventID == 1 ParentProcessId ParentImage
| count by ParentProcessId | sort by count desc | table ParentProcessId ParentImage count
```

Measured as a seat:

```
ParentProcessId,ParentImage,count
1180,/usr/lib/systemd/systemd,134
3565,-,109
1,-,85
854,-,33
2862,/usr/bin/snap,30
1348,/usr/libexec/gnome-session-binary,29
```

`count by ParentProcessId` carries one sample `ParentImage` per group (first or most recent,
depending on sort order). Safe here because PID and image are naturally linked in Sysmon data. If
someone asks why `count by ParentProcessId ParentImage` gives systemd 118 instead of 134: the race
condition hits systemd's children too, so 16 of its rows carry `-` and split into their own group.
That is a fine detour if there is time, and a preview of task 2 either way.

## The Sysmon kit

Kits → browse the kit server → **Windows Sysmon** (`io.gravwell.windows.sysmon`) → Install; it
brings in `io.gravwell.windows.resource` and `io.gravwell.networkenrichment`, then installs in
about 15 seconds after the dependencies. It provides **8 dashboards, 52 library searches, 24
templates, 4 pivots, a playbook**, two macros, and **no autoextractors** (so `ax` does not work on
`tag=sysmon`; that's why the lab uses `winlog`).

**Every dashboard is empty on our data, on purpose in the lab.** The kit's searches are
`tag=$SYSMON winlog $PROVIDER …` and the macro `PROVIDER` is `Provider=="Microsoft-Windows-Sysmon"`;
our provider is `Linux-Sysmon` (3,598 of 3,598 events). The handout walks them to **Macros**, has
them change the expansion to `Provider=="Linux-Sysmon"`, and the dashboards fill. Measured after
the change, the kit's own "Top 100 Parent Processes": **`-` 553**, `/usr/bin/bash` 138,
`/usr/lib/systemd/systemd` 118, `/usr/bin/dash` 71; "Process Creation by User" (it filters
`TerminalSessionId==1`): `ubuntu` 24, `root` 3. Point at the `-` bar: the race condition from task 2
is sitting on a stock dashboard. Network, registry and DNS dashboards stay empty (no such events in
a Linux process capture).

**Beat:** a kit is someone else's queries plus the knobs they left you. The knob here is one macro;
in a real shop it's usually the tag. All kits are open source at
<https://github.com/gravwell/kits>; the Sysmon kit's searches are the model for anything you want
to add.

---

## Task 1: Find the high spawners

```
tag=sysmon winlog EventID == 1 ParentProcessId
| count by ParentProcessId | sort by count desc | table ParentProcessId count
```

**Exact expected output (top rows):**

| ParentProcessId | count | What it is |
|---|---:|---|
| 1180 | 134 | `systemd`: expected, boring |
| **3565** | **109** | **the agent** |
| 1 | 85 | init |
| 854 | 33 | |
| 2862 | 30 | |
| 1348 | 29 | |

> ⚠️ **Set expectations honestly.** 3565 (109) is only modestly above PID 1 (85): it does *not* leap
> off the page. Say so: raw child count gets you a shortlist, not an answer. That's exactly why task
> 5's bash-filtered version exists, and it's a better lesson than pretending the first query solved
> it.

**Common failures:**

| Symptom | Cause |
|---|---|
| Zero results | Time range (last 48 hours), or the data is from a different build than Lab 02's. `tag=sysmon` alone should show ~3,600 entries |
| Every PID has count 1 or 2 | Forgot `EventID == 1`: they're counting terminations too |
| `ParentProcessID` returns nothing | Case: it is `ParentProcessId`, lower-case d. `winlog` looks the name up in `EventData` verbatim |

## Task 2: Confirm the race condition

```
tag=sysmon winlog EventID == 1 ParentProcessId == 3565 ParentImage ParentCommandLine
| count by ParentImage ParentCommandLine | table ParentImage ParentCommandLine count
```

**Expected: one row:** `ParentImage` `-`, `ParentCommandLine` `-`, **count 109**. Empty on every
child.

This is the teaching moment of the module. Sysmon-for-Linux has a race: when a parent spawns
children fast, its metadata isn't cached yet, so `ParentImage` and `ParentCommandLine` come back
empty even though `ParentProcessId` is populated. **Real observed behaviour in a real capture, not
corrupted lab data.**

*Beat:* "Your detection content probably keys on `ParentImage`. On Linux, against exactly the
workload you most want to catch, that field is empty. The faster the thing spawns, the blinder your
rule gets." Let that sit.

## Task 3: What did it spawn?

```
tag=sysmon winlog EventID == 1 ParentProcessId == 3565 Image
| count by Image | sort by count desc | table Image count
```

**Exact expected output:**

| Image | count |
|---|---:|
| `/usr/bin/bash` | **73** |
| `/usr/bin/cat` | 9 |
| `/usr/bin/env` | 5 |
| `/usr/bin/node` | 5 |
| `…/opencode-linux-x64/bin/opencode` | 4 |
| `/usr/bin/realpath` | 4 |
| `/usr/bin/ls` | 3 |
| `/usr/bin/chmod` | 2 |
| `…/opencode/bin/rg` | 1 |
| `/usr/bin/id` | 1 |

Point at the `opencode` and `rg` (ripgrep) entries: the agent is *right there in the process list*,
named, alongside its own search tooling. It was never hiding. Nobody was looking.

Also worth one line, from `winlog … Computer User`: every one of the 109 children ran as user
`ubuntu` on `ubuntu-sysmon`. A person's account, a person's laptop.

## Task 4: What did it actually run? (protect this time)

```
tag=sysmon winlog EventID == 1 ParentProcessId == 3565 Image ~ bash CommandLine
| table TIMESTAMP CommandLine
```

**Expected:** 73 command lines, in the clear, newest first. Among them:

- `cat /etc/passwd`, `/etc/group`, user enumeration
- shell history reads; attempted reads of `~/.ssh/id_rsa`
- searches for credential/config files across the home directory
- `env | grep -iE 'password|secret|key|token'`
- cloud metadata curls to `169.254.169.254`
- a localhost port scan
- checks for monitoring processes (it found sysmon running)
- sudo/privilege and logged-in-user checks
- a script making repeated outbound connection attempts to an unusual host (beaconing-style IOC)

Interleaved with genuinely benign developer work: `npm install`, `npm test`, linters, `git
status`, ordinary `cat`/`ls`/`grep` on the project. **That's deliberate.** Detection isn't trivial
when 60% of what the agent does is exactly what a developer does.

Two useful narrowings for the projector (`~` is *contains*):

```
tag=sysmon winlog EventID == 1 ParentProcessId == 3565 Image ~ bash CommandLine ~ passwd
| table CommandLine
```
```
tag=sysmon winlog EventID == 1 ParentProcessId == 3565 Image ~ bash CommandLine ~ 169.254
| table CommandLine
```

> Note: `winlog` returns the command lines with XML entities intact (`&quot;`, `&amp;&amp;`). It is
> the raw text of the record. Say so if someone asks; don't spend time on it.

*Beat:* let them read the command list in silence for thirty seconds. It lands harder than
anything you can say over it. Then: "every one of those is a normal command. There is no malware
here. The finding is the *sequence*, and the fact that a language model chose it."

## Task 5: Turn it into a detection

```
tag=sysmon winlog EventID == 1 Image ~ bash ParentProcessId
| count by ParentProcessId | eval count > 10 | sort by count desc | table ParentProcessId count
```

**Exact expected output: one row:** `3565  73`.

Drop the `eval count > 10` and show the runner-up: PID 1180 with **3** bash children; nothing else
above 2. A threshold of 10 isolates the agent with zero false positives on this data.

*Beat:* this is the module's real deliverable. Not "we found PID 3565": **"we wrote a rule that
finds this class of thing without knowing the process name, without `ParentImage`, and without a
signature."** It generalizes to agents that don't exist yet.

Ask the room what the threshold should be in *their* environment, and how they'd baseline it.
There's no right answer and the discussion is worth two minutes. A build server would blow straight
through 10, which is the honest caveat.

## Task 6: Cross-source pivot

```
tag=sysmon winlog EventID == 1 ParentProcessId == 3565
| stats min(TIMESTAMP) as first max(TIMESTAMP) as last count | table first last count
```

and the network side, from Lab 02:

```
tag=corelight_conn json "id.orig_h" as src_ip "id.resp_h" as dst_ip
| eval src_ip == "10.13.42.42" | eval dst_ip == "160.79.104.10"
| stats min(TIMESTAMP) as first max(TIMESTAMP) as last count | table first last count
```

**Measured (same build):** PID 3565 ran **11:07:53 → 11:14:55** (109 events); the network burst to
`api.anthropic.com` ran **11:07:56 → 11:15:48** (79 connections). Three seconds apart at the start.

Put the two side by side on the projector:

| Source | What it saw |
|---|---|
| Corelight (Lab 02) | 8 minutes, ~10 conns/min to `api.anthropic.com`, `orig_bytes` ≫ `resp_bytes`, 2 failed conns to `169.254.169.254`, 4 to `185.220.101.47:4444` |
| Sysmon (Lab 03) | PID 3565, 109 children, 73 bash, reading `/etc/passwd` and SSH keys, curling the metadata service, scanning localhost |

**One host. One eight-minute window. Two completely different stories, and neither is complete
alone.** The network knew something bursty talked to Anthropic and probed metadata. The endpoint
knew which process and every command. Together you have an incident.

*And then the question that carries the rest of the course:* **neither source can tell you what it
sent to the model.** Not one prompt, not one response, not one tool call. That's the gap M6 names
and the proxy modules close.

---

## Answer key (short form)

| Q | Answer |
|---|---|
| Rogue parent PID | **3565** (opencode) |
| Children (EventID 1) | **109** |
| bash children | **73** |
| Benign top spawner | PID **1180** (systemd), 134 children |
| `ParentImage` on the children | **Empty on all 109**, Sysmon-for-Linux race condition |
| Detection rule result | PID 3565 only; runner-up has 3 bash children |
| Cross-source | Same host `10.13.42.42`, same ~8-min window as the Lab 02 network burst |
| Kit | Windows Sysmon, 8 dashboards, no autoextractors; empty until `PROVIDER` macro = `Provider=="Linux-Sysmon"` |

## Where students get stuck

1. **`ParentProcessId` capitalisation**, and `~` (contains) versus `==` (equals) on `winlog`.
2. **Forgetting `EventID == 1`.** Terminations are 70% of the file; without the filter the counts
   are meaningless.
3. **Kit install "did nothing".** It installs two dependencies first; give it a minute and refresh
   Dashboards. Then they are empty until the `PROVIDER` macro is changed, which is the exercise. It
   adds no `ax` extractors for `tag=sysmon`; that is expected.
4. **Time range**, again. Always time range. And, new this week: if the whole tag is empty over 48
   hours, the data is from a different build than the rest of the repo.
