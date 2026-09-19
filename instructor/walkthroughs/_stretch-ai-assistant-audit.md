# Walkthrough: P8: Audit an AI assistant from its own logs

> ⛔ **INSTRUCTOR ONLY.** Student handout:
> [`labs/_stretch/ai-assistant-audit/README.md`](../../labs/_stretch/ai-assistant-audit/README.md).

**Padding module P8** · **45 min** · insert after M10 (or M3) · **Flex:** optional throughout

P8 is padding, run only when the room is fast. This file holds the answer key, kept out of the
student handout so the handout does not spoil itself.

## The scenario

Students reconstruct a real MCP-enabled assistant, **Gravwell's own Logbot**, from nothing but its
application logs (`tag=logbot`, RFC5424 syslog in the real `webserver/ai.go` format). Data comes from
`src/log-generator/generate_logbot_logs.py`, anchored to now, ingested on `<ID>08`.

## Answer key

| Q | Answer |
|---|---|
| Token-spend outlier | **`evan`**: ~560k tokens vs. the admin baseline of ~250k |
| What the outlier was doing | An **off-hours burst** starting **03:12**, 14 turns over about six minutes, on `knowledge_base_*` plus `sample_tag_entries`, with `prompt_tokens` climbing 20k → 39k as it pulled data |
| The decoy | Service account **`svc-reporting`**: regular and small, meta tools only, one session every six hours. Frequent ≠ expensive |
| Content in the logs | **None.** Tool names and token counts only. That is the whole point |
| Health-check failures | Four, at ~02:00 (×2), ~03:00 and ~18:00: `Get "http://zek:8081/v1/health": dial tcp 10.0.8.20:8081: connect: connection refused` |
| Full key | The generator's `--answer-key` JSON (instructor-side only; never ships to students) |
| Real reference data | `datasets/gravwell-ai-assistant/webserver-ai-logs-{a,b}.json` |

### Task by task, with the query

All four users are `admin`, `evan`, `priya`, `svc-reporting`. Time range **last 48 hours**.

**Task 1: token spend per user.**
```
tag=logbot syslog Message=="logbot token usage" "total-tokens" as tok user
| stats sum(tok) as total_tokens count by user
| sort by total_tokens desc | table user total_tokens count
```
`evan` on top at roughly twice `admin`. `admin` is the heavier *user*; `evan` is the heavier
*spender*, which is the distinction the module is about.

**Task 2: what the assistant can do.**
```
tag=logbot syslog Message=="MCP tool call" tool
| count by tool | sort by count desc | table tool count
```
Split the list out loud into metadata readers (`list_tags`, `get_*`) and the two that reach stored
data: `knowledge_base_*` and `sample_tag_entries`.

**Task 3: the outlier's behaviour.**
```
tag=logbot syslog Message=="MCP tool call" tool user
| grep -e user evan | grep -e tool knowledge_base
| count by tool | sort by count desc | table tool count
```
Then show *when*, which is the part that makes it a finding rather than a heavy user:
```
tag=logbot syslog Message=="logbot token usage" "total-tokens" as tok user
| grep -e user evan | sort by TIMESTAMP asc | table TIMESTAMP tok
```
Fourteen turns bunched from 03:12, `tok` climbing monotonically. The daytime sessions are three
scattered turns each.

**Task 4: where the logs go blind.** There is no query that answers it, and that is the answer.
Have someone try `tag=logbot grep credential` or dump a raw entry; the structured-data params are
`user`, `tool`, `total-tokens`, `prompt-tokens`, `completion-tokens`, session and container ids.
No prompt, no response, no tool arguments, no result. Write on the board: *"we know he asked the
knowledge base 14 times at 3am and it cost 560k tokens; we cannot say what he asked or what came
back."* That sentence is the module.

**Task 5: the ops signal.**
```
tag=logbot syslog Message=="ai health check request failed" | table TIMESTAMP Message
```
Four rows. The LLM backend (`zek:8081`) refused connections twice around 02:00, once around 03:00
and once around 18:00. Worth thirty seconds: the same content-blind log stream that cannot answer
the security question answers an availability question cleanly, and the 03:00 flap sits right
next to the burst, which is a nice coincidence to let someone in the room notice.

## The teaching point (don't lose this one)

Logbot logs **tool names and token counts, and no prompt or response content**. It is a vendor
logging its own AI assistant in good faith, and it is still **content-blind**. Students can see
*that* `evan` hammered the knowledge base and *what it cost*, and cannot see *what he asked* or
*what came back*.

That is the same gap as M3's vendor dashboards and the same gap the proxy closes in M9, arriving
from a third direction. If you run P8 before M9 it primes the proxy; after M9 it confirms it.

## Query gotchas

The `syslog` module pulls RFC5424 structured-data params by name, `tag=logbot syslog
Message=="MCP tool call" tool user` gives `tool`/`user` directly. Hyphenated names need aliasing:
`"total-tokens" as tok`. Full set in `src/log-generator/README.md`.
