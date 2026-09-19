# Shadow-AI scenario generator (Lab 02 primary data)

`generate_corelight_logs.py` writes one 24-hour day of Corelight/Zeek logs for a small company
network, built so that **each hunt method finds a different subset and only correlation gets the
right answer**. Schema matches the real sample (`datasets/corelight/real-sample-corelight-ai-events.json`):
ISO `ts`, paired A/AAAA queries, real CDN answer IPs, every SSL/HTTP with its `conn` (same `uid`).

```bash
# the standard lab set (deterministic with --seed), anchored to now, plus the re-timed Sysmon XML
python3 generate_corelight_logs.py --seed 1 \
    --outdir ../../datasets/corelight/generated \
    --answer-key ../../datasets/corelight/generated/answer-key.json \
    --sysmon-in  ../../datasets/sysmon/sysmon-events-jan21-clean.xml \
    --sysmon-out ../../datasets/sysmon/generated/sysmon-retimed.xml
```
`--anchor <YYYY-MM-DD>T17:00:00Z` pins the window end (e.g. generate the night before class).
`--wrapped file.json` also emits Gravwell tagged-export format.

## The cast and what each teaches

| Host | Who | Scenario | DNS | SSL/SNI | conn bytes | HTTP | Verdict |
|---|---|---|---|---|---|---|---|
| 10.13.20.221 | kwatts, marketing | Heavy ChatGPT web user; SSO login 09:xx | ✔ chatgpt/ab/ws | ✔ | ✔ | 1 plaintext GET → 301 | **usage** |
| 10.13.20.112 | rdiaz, finance | Copilot all day, SSO | ✔ | ✔ | ✔ | | **usage**, sanctioned? policy question |
| 10.13.20.140 | psingh, HR | Link previews resolve claude.ai, gemini, perplexity, character.ai | ✔ | ✘ | ✘ | | DNS-only, **not usage** |
| 10.13.20.155 | vuln scanner | Resolves *every* AI domain at 02:00, connects to none | ✔✔✔ | ✘ | ✘ | | DNS-only, **not usage** (biggest DNS hit) |
| 10.13.20.190 | lchen, engineer | DNS-over-HTTPS; api.anthropic.com traffic with **no DNS log** | ✘ (only cloudflare-dns.com) | ✔ | ✔ | | **usage**, invisible to Method 1 |
| 10.13.20.203 | mokafor, engineer | HTTP/3: chatgpt over **QUIC/UDP**, no ssl record | ✔ | ✘ | ✔ (service=quic) | | **usage**, invisible to Method 2 |
| 10.13.20.77 | abrennan, legal | Recipes site on the **same Cloudflare IP** as chatgpt.com | ✘ | ✔ (non-AI SNI) | ✔ | | decoy: IP-only correlation = false positive |
| **10.13.42.42** | ubuntu-sysmon | **Rogue opencode agent**: ~11 api.anthropic.com calls/min over an 8-min burst, orig≫resp bytes, failed conns to 169.254.169.254 and to 185.220.101.47:4444 | ✔ | ✔ | ✔ | | **usage + incident**; same host/window as Sysmon PID 3565 |
| 10.13.42.51 | jpark, dev | Self-hosted **ollama** :11434 + **MCP gateway** :8080/mcp, plaintext | internal DNS | ✘ | ✔ | ✔ POST /api/chat, /mcp | **usage**, only Method 3 sees it |
| 10.13.42.60 | CI runner | 03:12 **48 MB upload** to api.openai.com | ✔ | ✔ | ✔ (huge) | | **usage + outlier**: what left? |
| 4 others | - | benign browsing + O365 background for everyone | | | | | noise |

Instructor answer key (`answer-key.json`): per-host scenarios, the rogue window, counts, and
`found_only_by` (which hosts each method finds alone). Method 4 data: `okta_access.jsonl` has the two
SSO logins (kwatts → chatgpt.com, rdiaz → copilot.microsoft.com) so hosts can be tied to users.

## Refreshing the AI domain list
```bash
curl -fsSL https://raw.githubusercontent.com/laylavish/uBlockOrigin-HUGE-AI-Blocklist/main/noai_hosts.txt \
 | sed -E '/^\s*#/d; /^\s*$/d; s/^0\.0\.0\.0[[:space:]]+//' | sed '1s/^/Domain\n/' > ../../datasets/resources/ai_domains.txt
```
Note the internal names (`ollama.dev.acme.corp`, `mcp-gateway.acme.corp`) are deliberately **not**
on the list: Method 3 has to find them by path/port, which is the lesson.

## Known simplifications
`community_id` is omitted; `ssl_history`/`history` are fixed plausible values; the DoH host's
cloudflare-dns.com traffic is TLS, not modelled as HTTP/2 DoH frames. If a scenario needs real
packets (e.g. genuine QUIC), the VM lab is the fallback, ask before going there.

---

# `generate_shadow_ai_sources.py`: the same cast, four more logs

Companion to the Corelight generator for the **beyond-the-wire lab** (`labs/_stretch/shadow-ai-sources/`,
padding module P9). It **imports the cast** from `generate_corelight_logs.py`, so the same fourteen
hosts and people appear in four sources the network sensor doesn't have. Generate both with the same
`--anchor` (or back-to-back anchored to now).

```bash
python3 generate_shadow_ai_sources.py --seed 1 \
    --outdir ../../datasets/shadow-ai-sources/generated \
    --answer-key ../../datasets/shadow-ai-sources/generated/answer-key.json
# ingest: nc -q1 localhost ${WORKSHOPUID}11 < osquery_results.jsonl   (12 swg, 13 cloudtrail, 14 gws)
```
`--seed 1` → osquery=248 swg=305 cloudtrail=244 gws=484.

| File | Tag | Format | Planted findings |
|---|---|---|---|
| `osquery_results.jsonl` | `osquery` | osquery differential result log (`hostIdentifier`, `name`, `columns{}`, `calendarTime` = ANSIC) | **ops-lt-48/gmartin: LM Studio serving on 127.0.0.1:1234, zero network signal in Lab 02**; dev-vm-51: ollama on **0.0.0.0**:11434 + node MCP gateway :8080; eng-lt-190: opencode + anthropic SDK + `cloudflared proxy-dns` (the DoH client); hr-lt-140: an `<all_urls>` AI sidebar extension (the DNS-only "link previews"); mkt-lt-221: ChatGPT app + Grammarly; ubuntu-sysmon: opencode |
| `swg_access.jsonl` | `swg` | Zscaler-NSS-style JSON: `user`, `url`, `method`, `reqsize`, `useragent`, `urlcategory`, `action`, `filename`, `dlp_dictionaries` | kwatts: 2× **Blocked** xlsx upload to chatgpt.com (DLP); lchen: SDK/agent user agents to api.anthropic.com; **dfoster: Notion AI (`/api/v3/runInferenceTranscript`), request size climbs turn over turn, then a 1.9 MB customer CSV goes through Allowed** (category Productivity); blind spots: servers (10.13.42.x) bypass, QUIC not proxied |
| `cloudtrail_events.jsonl` | `cloudtrail` | CloudTrail records (`userIdentity`, `eventSource`, `eventName`, `requestParameters`, `eventCategory`) | jpark: nine-minute enablement chain (ConsoleLogin → model agreement → `AttachRolePolicy AmazonBedrockFullAccess` on `app-prod-ec2-role`); prod role: 35 `InvokeModel*` **data events** from inside the VPC 11 min later; gmartin: 3× `AccessDeniedException` |
| `gws_token_audit.jsonl` | `gws` | Workspace Reports `token` activity (`actor.email`, `events[].parameters[]`) **plus flattened** `event_name`/`app_name`/`scopes`/`api_name`/`num_response_bytes` | **psingh (HR, cleared as DNS-only in Lab 02) authorizes "ChatGPT" with drive.readonly + gmail.readonly from a mobile IP; the app then pulls ≈505 MB in 351 SERVER_TO_SERVER calls over 70 min**; dfoster: AI notetaker with calendar + drive.file; sanctioned-app noise (Slack/Zoom/Figma/Atlassian/Miro) |

Lookups: `datasets/resources/ai_software.txt` (`Name,Kind`, upload as `AI_SOFTWARE`, names are
comma-free because the resource is CSV) and `datasets/resources/sanctioned_apps.txt` (`App,Owner`,
`SANCTIONED_APPS`, used inverted with `lookup -v`).

**Lab 02 tie-in:** the Corelight generator gained one scenario, `s_embedded_saas_ai` (dfoster →
`www.notion.so`), appended *after* the others so every pre-existing record is byte-identical for a
given seed/anchor (verified by set-difference). It is invisible to all four Lab 02 methods
and the two-step by design: Lab 02's answers are unchanged; only raw counts grew (dns 416→420,
ssl 350→374, conn 407→431).

Gravwell notes learned validating this: `grep -e field A B C` matches any value (no regex, use
`regex -e` for that); `lookup -v -r RES field Col` inverts a lookup; osquery's `calendarTime`
parses with `Timestamp-Format-Override="AnsiC"`; `table -save` needs ~15 s before the resource is
usable from a second search.

---

# Other generators in this directory

Three more tools so every dataset ingests with **fresh "now" timestamps** (students search
"last 24h" instead of a fixed 2026 date), and so the data-dependent labs have a planted scenario.
All are stdlib-only Python 3 and deterministic with `--seed`.

## `retime_datasets.py`: shift a real capture to end "now"
Preserves every relative interval; places the newest event at `--anchor` (default now). Shifts both
the envelope `TS` **and** the inner timestamps students actually search.
```bash
./retime_datasets.py --in ../../datasets/sysmon/sysmon-events-jan21-clean.xml \
                     --out ../../datasets/sysmon/generated/sysmon-now.xml
./retime_datasets.py --in ../../datasets/gravwell-ai-assistant/webserver-ai-logs-a.json \
                     --out ../../datasets/gravwell-ai-assistant/generated/logbot-a-now.json
```
Handles: Sysmon XML (`SystemTime`/`UtcTime`), `tag=gravwell` RFC5424 syslog (inner `<PRI>1 <ts>`),
`tag=corelight_*` Zeek JSON (`ts`/`_write_ts`); anything else = envelope `TS` only (opaque payloads
are left byte-for-byte). Use this to refresh the **real** data as-is;
use the scenario generators below when you want a planted answer.

## `generate_logbot_logs.py`: Gravwell AI-assistant ("Logbot") audit trail
Reproduces the real `webserver/ai.go` syslog (MCP tool calls, token usage, failures, health checks)
with a planted UEBA scenario: user **evan** runs an off-hours burst on `knowledge_base_*` tools with
token spend ≈2× the admin baseline. Powers the **AI-assistant-audit lab**
(`labs/_stretch/ai-assistant-audit/`).
```bash
./generate_logbot_logs.py --out ../../datasets/gravwell-ai-assistant/generated/logbot.log \
    --answer-key ../../datasets/gravwell-ai-assistant/generated/answer-key.json --seed 1
# ingest (raw RFC5424 -> tag=logbot):  nc -q1 localhost ${WORKSHOPUID}08 < logbot.log
# --wrapped also emits Gravwell tagged-export for UI import / parity with the real dump
```
Validated searches: token-spend-by-user (evan the outlier), tool-call frequency, the data-access
burst. Teaching point built in: tool names + token counts only, **no prompt/response content**.

## Gravwell query gotchas (learned validating all of the above)
- `syslog` module extracts RFC5424 **structured-data** params by name: `tag=logbot syslog
  Message=="MCP tool call" tool user` gives `tool`/`user` directly. Hyphenated names need aliasing:
  `"total-tokens" as tok`.
- `grep` filters on an enumerated value with `grep -e <field> "pattern"` (bare `grep "pattern"` is
  raw-text). `regex -e <field> "(?P<name>...)"` pulls a capture into a new field.
- `stats` aggregates are: `count sum total mean stddev variance min max unique_count` (no `values()`,
  no `count(predicate)`); build set-membership with the `table -save` → `lookup -r` two-step (see Lab 02's DNS↔conn correlation).
- `/api/search/direct` needs RFC3339 times and `Format:"csv"` for the `table` renderer.
