# Stretch / Padding lab: Auditing an AI assistant from its own logs

## Objective
Audit a real, MCP-enabled AI assistant using nothing but the application logs it already writes.
Reconstruct *who used it, which MCP tools it called, and how many tokens it burned*, then find the
one user whose session is a behavioral outlier. Along the way, see exactly where app-log visibility
**stops**: you get tool names and token counts, never prompt or response **content**. That gap is
the whole argument for the proxy (M9).

## Background
Gravwell ships **Logbot**, a built-in AI assistant that answers questions by calling MCP tools
against your data (list tags, search knowledge bases, sample entries, build extractors, …). Every
LLM round-trip and every MCP tool call is logged by the webserver (`webserver/ai.go`). This is a
vendor logging its *own* AI, the good-faith version of what M3 said vendors don't give you, and
it's still content-blind. The data is real in shape; the sample is generated so the lab has a
planted answer.

## Setup
- Gravwell up (Lab 00).
- Ingest a day of the assistant's logs (raw RFC5424 syslog → `tag=logbot`). The file is in your
  repo:
  ```bash
  nc -q1 localhost ${WORKSHOPUID}08 < ~/jarvis/datasets/gravwell-ai-assistant/generated/logbot.log
  ```
  (In production these live in `tag=gravwell` filtered by `MsgID ~ "ai.go"`; we isolate them to
  `tag=logbot` so they don't drown in the seat's own Gravwell logs.) Set the time range to **last 48 hours** (the scenario is the previous UTC business day).

## Tasks

1. **Who is using the assistant, and how hard?** Token spend per user:
   ```
   tag=logbot syslog Message=="logbot token usage" "total-tokens" as tok user
   | stats sum(tok) as total_tokens count by user
   | sort by total_tokens desc | table user total_tokens count
   ```
   One user is a clear outlier (≈2× the platform admin). Who?

2. **What can the assistant actually do?** Tool-call frequency:
   ```
   tag=logbot syslog Message=="MCP tool call" tool
   | count by tool | sort by count desc | table tool count
   ```
   Note which tools only *read metadata* vs. which *touch stored data* (`knowledge_base_*`,
   `sample_tag_entries`).

3. **The outlier's behavior.** For the user from task 1, what were they doing?
   ```
   tag=logbot syslog Message=="MCP tool call" tool user
   | grep -e user evan | grep -e tool knowledge_base
   | count by tool | sort by count desc | table tool count
   ```
   An off-hours burst hammering data-access tools with climbing token counts, the AI-UEBA signal.

4. **Where the logs go blind.** Try to answer "*what did they actually ask, and what data came
   back?*" from `tag=logbot`. You can't: there is no prompt or response content, only tool names
   and counts. Write one sentence on what you'd need instead (answer: the proxy / LLM ingester, M9).

5. **The ops signal in the noise.** Find the health-check failures:
   ```
   tag=logbot syslog Message=="ai health check request failed" | table TIMESTAMP Message
   ```
   The LLM backend (`zek:8081`) flapped. Even content-blind logs carry real operational value.

## Discussion
- This is the **best case** for vendor-side AI logging: the vendor's own product, logging itself,
  and it still can't answer the security question ("what left?"). Everything richer needs *your*
  interception.
- Tool names are a capability inventory: `knowledge_base_get_data` and `sample_tag_entries` are how
  an assistant (or a compromised account driving it) reaches real data. Baseline them per user.
- Same UEBA idea you'd apply anywhere: per-identity normal, alert on deviation, here on an
  assistant's own audit trail.


## About the data
`logbot.log` is generated: real Logbot syslog shape, planted scenario, timestamps in the previous
UTC business day. Two real Logbot captures are alongside it for schema reference,
`datasets/gravwell-ai-assistant/webserver-ai-logs-{a,b}.json`. In a classroom the file is
regenerated for you before the day starts.

> **Running this self-driven?** Regenerate first so the timestamps land in the search window:
> `cd src/log-generator && python3 generate_logbot_logs.py --seed 1 --out ../../datasets/gravwell-ai-assistant/generated/logbot.log`
