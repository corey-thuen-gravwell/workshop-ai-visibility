# Instructor walkthroughs (INSTRUCTOR-ONLY)

Complete step-by-step for each lab: every command, expected output, common failures, and the
answers to every lab task. **Not distributed to students during a delivery**: they get the lighter
handout in `labs/NN-*/README.md`, and the difference between the two is the deliberate friction
that makes the terminal practice stick.

**Two readers, not one.** The obvious reader is an instructor with a room in front of them, and
the standard is that they can copy-paste their way from an empty seat to a finished lab without
opening anything else. The second reader arrives later: someone working through this course alone
from the published repo, with no one to ask. So a walkthrough must not leave an answer implied by
a teaching beat ("let the room argue"), and must not point at a file only the instructor has for
the copy-pasteable version of anything. Every query, config and command a task needs goes in the
walkthrough itself, and room management sits *around* that, clearly marked, never in place of it.
`materials/self-study-guide.md` is what points a solo reader here.

One file per module: `NN-name.md`, matching the lab directory name. Validation notes never go in
the handouts; they belong here, in each walkthrough's failure tables.

| Walkthrough | Module | Lab |
|---|---|---|
| [`00-environment-gravwell.md`](00-environment-gravwell.md) | Lab A | `labs/00-environment-gravwell/` |
| [`01-fundamentals.md`](01-fundamentals.md) | M2 | `labs/01-fundamentals/` |
| [`01b-demystifying-ai.md`](01b-demystifying-ai.md) | M2b | `labs/01b-demystifying-ai/` |
| [`02-shadow-ai.md`](02-shadow-ai.md) | M4 | `labs/02-shadow-ai/` |
| [`03-endpoint-sysmon.md`](03-endpoint-sysmon.md) | M5 | `labs/03-endpoint-sysmon/` |
| [`04-opencode-config.md`](04-opencode-config.md) | M7 | `labs/04-opencode-config/` |
| [`05-llm-proxy.md`](05-llm-proxy.md) | M8 + M9 | `labs/05-llm-proxy/` |
| [`06-mcp-deep-dive.md`](06-mcp-deep-dive.md) | M10 | `labs/06-mcp-deep-dive/` |
| `07-mcp-tool-interaction.md` | M11 + M12 | Lab 07: the query advisor chained with Gravwell's MCP server, manifests that reach across servers, and the `tag=llm` detections |
| [`_stretch-ai-assistant-audit.md`](_stretch-ai-assistant-audit.md) | P8 | `labs/_stretch/ai-assistant-audit/` |
| [`_stretch-extend-the-proxy.md`](_stretch-extend-the-proxy.md) | P2 | `labs/_stretch/extend-the-proxy/` |
| [`_stretch-second-client.md`](_stretch-second-client.md) | P4 | `labs/_stretch/second-client/` |
| [`_stretch-semantic-search.md`](_stretch-semantic-search.md) | P3 | `labs/_stretch/semantic-search/` |
| [`_stretch-shadow-ai-sources.md`](_stretch-shadow-ai-sources.md) | P9 | `labs/_stretch/shadow-ai-sources/` |

## Before you teach: run the dry run

Walk the full sequence in order, with a co-instructor **who didn't write it**, before teaching it.
[`../dry-run-protocol.md`](../dry-run-protocol.md) specifies it: roles, what to record, and the H1–H7 handoff
assertions. Do it before the room does it for you.

## Conventions

Each walkthrough carries, in this order:

1. **Timing table**: minute-by-minute segments against the module's budget, and what to drop when
   you're running late.
2. **Before class**: data regeneration, resource uploads, pre-flight.
3. **Step-by-step**: the command, the *exact* expected output where it's known, and a failure
   table (symptom → cause → fix).
4. **Answer key**: every task, with the teaching beat to land after each one.
5. **Where students get stuck**: the specific typos and misconceptions to watch for.

