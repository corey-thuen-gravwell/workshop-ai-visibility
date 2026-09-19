# Datasets

What each file is, which lab uses it, and where it came from.

| Path | Lab | What it is | Real or generated |
|---|---|---|---|
| `resources/ai_domains.txt` | 02 | 2,221-line Gravwell lookup table (`Domain` header) of AI provider/app domains, derived from `laylavish/uBlockOrigin-HUGE-AI-Blocklist` `noai_hosts.txt`. Upload as resource **`AI_DOMAINS`**. Refresh recipe in `src/log-generator/README.md`. | real list |
| `corelight/generated/` *(git-ignored, regenerate)* | 02 | **Primary Lab 02 data.** Per-tag Zeek JSONL from `src/log-generator/`: 14 hosts, 11 correlated shadow-AI scenarios, 24-hour window anchored to generation time, plus `okta_access.jsonl` (Method 4) and `answer-key.json` (instructor). | generated |
| `shadow-ai-sources/generated/` *(git-ignored, regenerate)* | P9 | **Primary data for the beyond-the-wire lab.** Four JSONL files for the SAME 14 hosts as Lab 02: `osquery_results.jsonl` (endpoint inventory), `swg_access.jsonl` (identity-aware TLS-inspecting proxy), `cloudtrail_events.jsonl` (Bedrock + IAM), `gws_token_audit.jsonl` (Workspace OAuth consent + app activity), plus `answer-key.json` (instructor). From `src/log-generator/generate_shadow_ai_sources.py`; use the same `--anchor` as the Lab 02 generator. | generated |
| `resources/ai_software.txt` | P9 | `Name,Kind` lookup of AI software as inventory tools report it (local model servers, coding agents, SDKs, desktop apps, DoH clients, browser extensions). Upload as **`AI_SOFTWARE`**. Names are comma-free on purpose (CSV). | curated |
| `resources/sanctioned_apps.txt` | P9 | `App,Owner` lookup of IT-approved OAuth apps; used inverted (`lookup -v`) to surface unsanctioned consents. Upload as **`SANCTIONED_APPS`**. | curated |
| `corelight/real-sample-corelight-ai-events.json` | 02 (ref) | 16 real Corelight records (12 dns, 3 ssl, 1 http) of two hosts hitting chatgpt.com, Gravwell tagged-export format. The **schema reference** the generator is aligned to. Too small to be lab data. | real |
| `sysmon/sysmon-events-jan21-clean.xml` | 03 | **Primary Lab 03 data.** 3,599 real Sysmon-for-Linux events (1,081 ProcessCreate) from an Ubuntu VM capturing a rogue opencode agent for detection. The agent is **PID 3565**: 109 children, 73 `bash -c` (reconnaissance IOCs: `/etc/passwd`, ssh keys, cloud metadata, port scan, repeated outbound attempts to an unusual host). `ParentImage` is empty on every one of them (the Sysmon race condition). Answer key + 4 canonical queries: `sysmon/gravwell-queries.txt`; provenance: `sysmon/how-this-data-was-made.md`. | real |
| `sysmon/generated/sysmon-retimed.xml` *(git-ignored)* | 02+03 | The same real XML with every timestamp shifted so PID 3565's burst lands inside the generated network window for host `10.13.42.42`: lets students correlate Sysmon ↔ Zeek. Produced by the generator's `--sysmon-in/--sysmon-out`. | real, re-timed |
| `sysmon/generated/sysmon-now.xml` *(git-ignored)* | 03 | Same real XML re-timed so the capture ends **now** (standalone Lab 03 ingest, fresh timestamps). Produced by `src/log-generator/retime_datasets.py`. | real, re-timed |
| `gravwell-ai-assistant/generated/logbot.log` *(git-ignored)* | P8 | **Primary data for the AI-assistant-audit lab.** Generated Logbot audit trail (MCP tool calls, token usage, failures) with the `evan` token/tool outlier, raw RFC5424 syslog anchored to now → `tag=logbot`. From `src/log-generator/generate_logbot_logs.py`. | generated |
| `proxy-captures/opencode-through-proxy-legacy.json` | 05 (ref) | 4 records from the original Go proxy: two opencode requests (full system prompt, 12-tool list, `stream_options.include_usage`) and their 404s. Legacy wire format; today's data comes from the LLM ingester / Python proxy. Useful for the "what an agent sends" slide. | real |
| `gravwell-ai-assistant/webserver-ai-logs-{a,b}.json` | 03 (M3) / 10 | ~1,450 real Gravwell webserver log lines from Gravwell's own AI assistant ("logbot"): `MCP tool call tool="list_queries"`, `logbot token usage prompt-tokens=…`, LLM request failures. A vendor's *own* AI audit trail: the schema reference + reference data for the **AI-assistant-audit lab** (P8) and its generator; also M3/M10 material ("good-faith product logging, still content-blind"). | real |

## Ingest (per seat, from Lab 00's listeners)
```bash
cd ~/jarvis/datasets/corelight/generated
nc -q1 localhost ${WORKSHOPUID}01 < corelight_dns.jsonl
nc -q1 localhost ${WORKSHOPUID}02 < corelight_ssl.jsonl
nc -q1 localhost ${WORKSHOPUID}03 < corelight_conn.jsonl
nc -q1 localhost ${WORKSHOPUID}04 < corelight_http.jsonl
nc -q1 localhost ${WORKSHOPUID}06 < okta_access.jsonl
nc -q1 localhost ${WORKSHOPUID}07 < ../../sysmon/generated/sysmon-retimed.xml
nc -q1 localhost ${WORKSHOPUID}08 < ../../gravwell-ai-assistant/generated/logbot.log   # tag=logbot (P8)
cd ~/jarvis/datasets/shadow-ai-sources/generated                                        # P9
nc -q1 localhost ${WORKSHOPUID}11 < osquery_results.jsonl
nc -q1 localhost ${WORKSHOPUID}12 < swg_access.jsonl
nc -q1 localhost ${WORKSHOPUID}13 < cloudtrail_events.jsonl
nc -q1 localhost ${WORKSHOPUID}14 < gws_token_audit.jsonl
```
Timestamps are extracted from the records, so search **last 24 hours** (generate the data the day
you ingest). The legacy/Gravwell-wrapped files are in Gravwell's
tagged-export format (`{TS,Tag,SRC,Data(base64)}`): import those through the UI or decode first.

