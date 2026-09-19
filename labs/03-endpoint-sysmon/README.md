# Lab 03: Endpoint detection with Sysmon

## Objective
Find a rogue AI coding agent on a Linux endpoint using Sysmon process-creation events, working
around a Sysmon-for-Linux quirk, then pivot from "which process" to "what it actually did."

## Background
An AI coding agent doesn't run one command: it spawns **hundreds** of short-lived children (bash,
cat, node) from one parent. That shape is the signature. But Sysmon-for-Linux has a **race
condition**: when a parent spawns children fast, the parent's metadata isn't cached yet, so
`ParentImage` and `ParentCommandLine` come back **empty** even though `ParentProcessId` is set. You
can't identify the agent by parent *name*, so cluster by **child count per `ParentProcessId`**
instead. (This is real, observed behavior, not a data error.)

## Setup
Gravwell up (Lab 00). Ingest the Sysmon events under `tag=sysmon`. The file is one `<Event>` per
line, re-timed so the story lines up with the network data from Lab 02:

```bash
nc -q1 localhost ${WORKSHOPUID}07 < ~/jarvis/datasets/sysmon/generated/sysmon-retimed.xml
```

Time range **last 48 hours**, then confirm the data landed:

```
tag=sysmon
```

## Two ways to read Windows-style events

Each entry is a Windows event log record in XML (Sysmon for Linux writes the same schema as Sysmon
for Windows). Gravwell gives you two extractors. The general one is `xml`, where you spell out the
full path to every field:

```
tag=sysmon xml Event.System.EventID as EventID
  Event.EventData.Data[Name]=="ParentProcessId" as ParentPID
| eval EventID == "1"
| count by ParentPID | sort by count desc | table ParentPID count
```

The one built for this job is `winlog`: it knows the schema, so the common `System` fields have
short names (`EventID`, `Computer`, `Provider`, …), **any other name you give it is looked up in
`EventData` for you**, and you can filter inline as you extract. The same query:

```
tag=sysmon winlog EventID == 1 ParentProcessId
| count by ParentProcessId | sort by count desc | table ParentProcessId count
```

Run both. Same answer. **Use `winlog` for the rest of this lab**; keep `xml` in your pocket for the
day you meet XML that isn't a Windows event. Inline filters on `winlog` fields: `==`, `!=`, and `~`
(contains) for text; `==`, `<`, `>` for numbers such as `EventID`.

**Adding a field.** Gravwell parses at query time, and nothing is extracted unless you ask for it.
Every field you want to filter on, count by, or show in the table must be named on the `winlog`
line first; a name that appears only later in the query is an error. Want to know *what* those
parents are, not just their PIDs? Add `ParentImage`:

```
tag=sysmon winlog EventID == 1 ParentProcessId ParentImage
| count by ParentProcessId | sort by count desc | table ParentProcessId ParentImage count
```

Two things to notice. First, `count by ParentProcessId` groups on one field, and any other field
you table (`ParentImage` here) shows **one sample value per group**, whichever row came first or
last in sort order. That is a feature, not a bug: when you need the count per *pair* of values,
name both, `count by ParentProcessId ParentImage`, and each distinct pair becomes its own row. That
tuple form is the general tool and worth remembering. Here we take the shortcut, because a PID and
its image do not change independently of each other. Second, the second row, the busiest parent
after `systemd`, has **no image at all**, just `-`. Hold that thought; the tasks come back to it. Field names come from the event itself: open a raw entry in the
`tag=sysmon` results and any `<Data Name="XXXX">` you see there is a name `winlog XXXX` will give you.

## Install the Sysmon kit

Gravwell publishes a **Sysmon kit** with dashboards, saved searches and investigation templates. In
the left navigation open **Kits**, browse the kit server, find **Windows Sysmon**, and install it
(it brings in two small dependencies; say yes; give it a minute). Then open **Dashboards** →
**Sysmon Process Overview**.

**It is empty.** Why? Open one of its panels and read the query: every kit search starts with
`tag=$SYSMON winlog $PROVIDER …`. Those `$NAMES` are **macros**, the knobs a kit exposes so you can
fit it to your environment without editing fifty searches. Open **Macros** in the left navigation:
`PROVIDER` expands to `Provider=="Microsoft-Windows-Sysmon"`. Our events came from Sysmon **for
Linux**, whose provider name is `Linux-Sysmon`. Edit the macro's expansion to
`Provider=="Linux-Sysmon"`, save, and reload the dashboard. Now it populates (our data covers only
process events, so the network, registry and DNS dashboards stay empty; that is the data, not you).
Look at the "top parent processes" panel: the biggest bar is `-`, an empty parent image. You will
find out why in task 2.

Everything on those dashboards is a `winlog` query you could have written. All of Gravwell's kits
are open source at <https://github.com/gravwell/kits>; when you want an example query for a data
source, that is the place to look.

## The data
3,599 real Linux-Sysmon events from an Ubuntu VM (1,081 ProcessCreate / EventID 1; the rest are
mostly EventID 5 process-terminate). One user session. Somewhere in it, opencode was told to "go
rogue."

## Tasks
1. **Find the high spawners**: child count per `ParentProcessId` for EventID 1 (the `winlog` query
   above). A few parents sit above the routine system daemons. The top one is `systemd` (PID 1180)
   and is expected; find the one that isn't. Raw child count only narrows it to a shortlist; task 5
   is what isolates it.
2. **Confirm the race condition**: for the suspect PID, extract `ParentImage` and
   `ParentCommandLine`. Both are empty (`-`) on every child. That's the quirk, not a data error.
   *Hint: filter inline: `winlog EventID == 1 ParentProcessId == NNNN ParentImage …`*
3. **What did it spawn?**: `Image` breakdown for that PID. You'll see 73 `/usr/bin/bash`, plus
   `cat`, `node`, and `opencode` binaries: an AI agent driving a shell.
4. **What did it actually run?**: pull `CommandLine` for its bash children (`Image ~ bash`). Recon
   in the clear: `cat /etc/passwd`, `cat ~/.ssh/id_rsa`, cloud-metadata curls to `169.254.169.254`,
   a localhost port scan, `env | grep -iE 'password|secret|key|token'`, and a script making repeated
   outbound connection attempts to an unusual host, interleaved with ordinary developer work.
5. **Turn it into a detection**, the high-bash-spawner rule: EventID 1, `Image ~ bash`, count by
   `ParentProcessId`, keep parents with more than 10. One row comes back.
6. **Cross-source:** the suspect PID's burst and host `10.13.42.42`'s api.anthropic.com burst fall
   in the **same ~8-minute window**. Get the Sysmon window with `stats min(TIMESTAMP) max(TIMESTAMP)`
   and line it up with the network window from Lab 02 task 8. One host, one story: the agent read
   secrets locally *and* shipped context to the model *and* tried to call home.

## Checkpoint: if you get lost
Every lab has a **known-good snapshot** you can restore without losing anything you've done:

```bash
cd ~/jarvis && git checkout stage-sysmon -- labs/03-endpoint-sysmon
```

That overwrites the lab's files with the working versions and leaves you exactly where you are,
no branch switching, no detached HEAD, nothing else touched. Ask an instructor if you're unsure.

## Discussion
- Your detection content almost certainly keys on `ParentImage`. On Linux, against exactly the
  fast-spawning workload you most want to catch, that field is empty. What else in your rule set
  depends on a field that goes blank under load?
- Task 5's rule names no process and no signature: it describes a *shape*. What does that buy you
  against an agent that does not exist yet, and what does it cost you on a build server?
- Network or Endpoint logs can indicate AI activity but cannot tell you
  you **what the agent sent to the model**. That's what the rest of the course is about.
