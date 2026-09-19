# Full-sequence dry run: how to test this course before you teach it

Material gets validated **module by module** as it is written. Running it **in order, by a person
who didn't write it**, is a different test, and the one that finds the problems that ruin a room.

This document is how to run that test with guidelines on providing feedback so we can further improve the class.

---

## The two roles, and the one rule

| Role | Who | Does |
|---|---|---|
| **Student** | A co-instructor who did *not* author the material | Follows **only** `labs/NN-*/README.md`. Never opens `instructor/`. Reads nothing ahead |
| **Observer** | Whoever authored, or is about to teach, the module | Watches, times, writes. **Does not help** |

> ### If the goal is improving the workshop: do not help.
>
> Every time the Observer wants to lean over and fix something, that is a **finding**, and helping
> destroys it. Write down what the student did instead, and let them stay stuck for a full two
> minutes before intervening. In the real room there will be 20 of them and 4 of you, whatever the
> student can't solve alone here becomes twenty raised hands on the day.
>
> When you *do* intervene, log it as a **BLOCKER** with the exact words you had to say. Those
> sentences belong in the handout.
>
> **One sanctioned exception:** `materials/terminal-cheatsheet.md`. If the Student is stuck on
> *typing* rather than *thinking*, hand it over, that's what it's for. **Log the moment you did
> and which task**, because "how many attendees will need the cheatsheet, and when" is one of the
> things this dry run exists to measure.

The Student should be genuinely naive about the material. If your only available co-instructor
already knows a module cold, have them run it anyway but weight their timings as a **floor**, a
real attendee will be slower.

## Where to run it

**On the real lab host, as a real seat** (`ssh workshopNN@<lab-host>`). Not on a laptop,
not on the authoring workstation. Most of the bugs found so far were environmental, a stale docker
image, a missing `/v1`, a config that only exists on one machine. A dry run on the author's box
tests almost nothing.

## Before you start

- [ ] `preflight.sh` exits **0**. Fix anything red first: a broken pre-flight invalidates the run.
- [ ] The `/api/mcp` check in pre-flight passes (Gravwell **5.10.1**; Lab 06 dies on 5.8.x).
- [ ] The Student's seat has the **real Anthropic key** in `~/.workshop_env`, there is no gateway
      (see `runbook/api-key-architecture.md`); Lab 05 has him build the key boundary himself.
- [ ] Lab 02/03 data **regenerated today** (the window anchors to now).
- [ ] The Anthropic key has quota. **Labs 01, 04 and 05 spend real money**, small, but nonzero.
- [ ] The Student has a fresh seat: no `~/jarvis`, no opencode auth, no prior containers.
- [ ] `build-student-repo.sh` has been run **and** the seat reset after it, so the Student's
      `~/jarvis` is a real clone holding **only Lab 01** (`ls labs/` shows one directory). You
      release each lab as you reach it: `release-stage.sh --next` on the host, then the Student runs
      `cd ~/jarvis && git pull`. Whether *that* handoff is smooth is one of the things being tested.
      Have the Student break a file and run the lab's checkpoint command once (e.g.
      `git checkout stage-fundamentals -- labs/01-fundamentals`) before you start timing, the
      recovery command is load-bearing for the whole dry run.

## Order, and where to break

Run in agenda order. The natural break is after Lab 03 (that is where a multi-session delivery splits, in
practice), and the full sequence doesn't fit in one sitting for two people.

| # | Module | Lab | Budget | Notes |
|---|---|---|---|---|
| 1 | M2 | `01-fundamentals` | 60 (~25 lab) | **Start here.** Pure curl, no Gravwell |
| 2 | Lab A | `00-environment-gravwell` | 60 | The one that decides whether the rest works |
| 3 | M4 | `02-shadow-ai` | 75 | Longest analysis block |
| 4 | M5 | `03-endpoint-sysmon` | 105 | Longest module in the course |
| - | - | - | - | **break here** |
| 5 | M7 | `04-opencode-config` | 60 | First real spend |
| 6 | M8+M9 | `05-llm-proxy` | 135 | The hinge. Budget a whole session |
| 7 | M10 | `06-mcp-deep-dive` | 105 | **Both parts**: Part 2 has him build his own MCP server and connect opencode to it |

Modules M0/M1/M3/M6/M13 are discussion: read the decks aloud for timing, don't dry-run them.
Lab 07 (M11 + M12) is a seat lab like Lab 06; dry-run it the same way.

## What to record

One line per task. Plain text is fine; a shared doc is better.

```
LAB 01 / Task 3
  budget:, actual: 6m20s
  stumbles: built the messages array by hand, got a JSON syntax error twice
  verbatim: "Invalid JSON: expected , or } after object value"
  questions: "wait, do I have to type the assistant's reply back in myself?"
  verdict: SLOW      (handout should ship this body pre-written)
```

Four verdicts, and only these:

- **CLEAN**: worked, on time, no help.
- **SLOW**: worked, but over budget. Record by how much.
- **STUMBLE**: needed a re-read or a retry, got there alone.
- **BLOCKER**: needed the Observer. **Record the exact words that unstuck them.**

Also capture, at the end of each module:
- **Total wall-clock** vs budget.
- One sentence from the Student: *"what was this module about?"* If that sentence isn't the module's
  actual point, the teaching failed even if every command worked.

## The handoff assertions: the real reason for a full sequence

Individual labs pass. What's untested is whether they **connect**. Check these explicitly; each one
is a claim the material makes across module boundaries:

| # | Assertion | Check at | Fails if |
|---|---|---|---|
| H1 | Lab 01's "the client resends everything" is *recalled unprompted* when the proxy appears | Lab 05 Part 2a | Student is surprised the proxy sees prompts |
| H2 | Lab 01's tool-call beat ("nothing executed") makes MCP feel familiar | Lab 06 Task 4 | Student treats `tools/call` as new material |
| H3 | Lab 02 task 8's host + time window is **written down** and still to hand | Lab 03 task 6 | Student can't do the cross-source pivot without re-running Lab 02 |
| H4 | Lab 03's "we can't see what it *said*" lands as an open wound | Lab 04 intro | The pivot from reading logs to intercepting traffic feels arbitrary |
| H5 | Lab 04's five problems predict what the proxy fixes | Lab 05 debrief | Student can't say why a proxy beats endpoint collection |
| H6 | Lab 01's token growth is recognised in real numbers | Lab 05 task (c) | The 22,393-vs-350 figure lands as trivia, not payoff |
| H7 | Lab 05's `request.tools_offered` connects to MCP tool discovery | Lab 06 Task 2 | The 50-tool count doesn't feel like a security finding |
| H8 | Lab 01b's "the table didn't change, the pick did" is recalled when an agent "decides" something | Lab 04 debrief / Lab 07 | Student describes the agent's tool choice as intent rather than a sampled token |

Ask these as **questions to the Student at the moment**, not as a quiz afterwards. "Does anything
about this look familiar?" is enough. If they don't make the connection unprompted, the callback
needs to be louder in the earlier module: that's the fix, and it's cheap to make.

## Known-unverified spots: confirm or kill these

Anything a walkthrough marks ✋ *Verify on the host before class* was not run on a live host when
it was written.
Resolve each to a yes/no, fold the answers into the walkthrough, and drop its ✋ markers.

## Cost and time

- Two people, roughly **9 hours** of wall clock to cover the seven modules above. Budget two
  sessions.
- API spend is small (Labs 01/04/05 are a few hundred short calls) but **not zero**. Set a spend
  alert if you have one.
- Run the Student on **one seat**; the Observer can watch over their shoulder or via a second SSH
  session to the same seat.

## What to hand back to the author

Whatever's easiest to write: a text file, a doc, pasted notes. The most valuable parts, in order:

1. **Every BLOCKER**, with the words/guiding that unstuck the Student.
2. **Which handoff assertions failed** (H1–H7). These are cheap to fix and can only be found this
   way.
3. **Rough timings, for calibration only.** Note where you ran long, but don't optimise the run
   around the clock: the durations in `AGENDA.md` are unvalidated estimates and experienced
   instructors adjust live. A module running 40% over is worth knowing; a module running 10% over
   is noise.
4. The Student's one-sentence summary per module.
5. Any command that didn't behave as the handout said, verbatim, including the error.

Don't polish it. Raw notes are more useful than a written-up report; the Student's actual confused
question beats a summary of it.
