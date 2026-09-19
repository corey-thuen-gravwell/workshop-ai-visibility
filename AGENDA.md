# Agenda: Exploring AI Visibility (module-organized)

The course is a **sequence of modules**, not a fixed timetable. Run them in order, insert
**padding modules** where there is room, compress or skip the marked items where there is not.
Nothing below assumes a schedule, a session count, or a break in any particular place: an
instructor with a full room and a reader working alone both start at M0 and stop wherever they
stop. Breaks belong after a lab, not inside one.

The minute counts are **estimates of hands-on effort**, not a clock to keep. They come from
running the material, they have never survived contact with a real room unchanged, and an
experienced instructor reading the room will beat any number in the table. Use them for relative
weight: M10 is twice M3, and the labs are where the time actually goes.

**Narrative arc:** *get visibility from logs you already have* (M1–M6, defensive, analysis-heavy,
gentle Linux ramp) → *active interception and the AI exposure surface* (M7–M11: proxies, the
LLM ingester, MCP, manifests that steer an agent across servers) → *turn it back into detections*
(M12–M13).

Legend, **Build status**: 🟢 material exists, needs formalizing · 🟡 partial · 🔴 to build ·
🧰 tool source. **Flex**: ⏱ can compress · ⤵ can drop ·
🔒 core, never cut.

---

## Attendee network requirements (send with the abstract, weeks ahead)

**[`materials/attendee-prerequisites.md`](materials/attendee-prerequisites.md) is the document to
send**, and it is the only place these details are maintained. It carries the destination table
(the lab host: TCP 22 for SSH, 443 for the course site, 10443-29443 for the per-attendee
UI), a paragraph an attendee can forward to their security team, and self-tests that prove each path
works before they travel. `share.sh publish materials/attendee-prerequisites` puts it on the site,
and the PDF is what goes in the mail.

Send it **weeks** ahead. A corporate exception takes days, and attendees have arrived unable to
open the slides, let alone reach a seat. Nothing else outbound is needed from a
laptop: the calls to Anthropic and to the Gravwell-hosted model are made by the lab host.

## Core sequence

| # | Module | Min | Σ | Format | Checkpoint | Flex | Build |
|---|---|---|---|---|---|---|---|
| M0 | **Welcome & attendee poll**: host intros, gauge room (Linux/SIEM/IR/RE/AI), logistics | 30 | 30 | Slides, discussion | - | ⏱ | 🟢 |
| M1 | **Why AI auditing matters**: Cursor prod-DB deletion case study; "AI tooling is software and has bugs"; the visibility problem | 45 | 75 | Slides, discussion | - | ⏱ | 🟢 |
| M2 | **Under the hood of LLM tooling**: stateless HTTP API, context as the caller's job, tokens & cost, tool calling, request schemas. *Mini-lab:* curl the API and prove it has no memory (21→13→35→59 input tokens), then offer it a tool and watch it ask for `/etc/passwd` while nothing executes | 60 | 135 | Slides + mini-lab | - | 🔒 | 🟢 validated live |
| M2b | **Demystifying how AI "thinks"**, tokens, embeddings, next-token prediction; seed, temperature and logprobs shown live against a **Gravwell-hosted model**; "it's a regular program"; anthropomorphism as marketing. *Mini-lab:* seven `cat`-able scripts, count tokens, compare vectors, prove determinism with a seed, print the probability table behind every pick, turn the temperature up until it says potato | 45 | 180 | Slides + mini-lab | `stage-demystify` | ⏱ (lab → demo) | 🟢 validated live |
| M3 | **The audit gap**: vendor logs are billing-shaped; dashboard limits; no security-grade sub-keys | 30 | 210 | Slides | - | ⏱ | 🟢 |
| Lab A | **Environment onboarding & stand up Gravwell (docker)**: SSH in, verify env (`WORKSHOPUID`, docker), `docker compose up`, reach the UI, first `tag=` search | 60 | 270 | Guided lab | `stage-gravwell` | 🔒 | 🟢 validated |
| M4 + Lab B | **Shadow-AI from network logs**: ingest Corelight/Zeek; Method 1 DNS + `AI_DOMAINS`, 2 SSL SNI, 3 HTTP host, 4 SSO; **correlate DNS ↔ SSL/conn** to separate real usage from DNS-only noise | 75 | 345 | Slides + lab | `stage-shadowai` | 🔒 (Method 4 ⤵) | 🟢 |
| M4b | **Gravwell tour**: debrief of what Lab 02 just used (the pipeline model, module families, raw-in / shaped-out), then a live browser tour (Query Studio, time picker, the Corelight kit's dashboards, resources, saved searches), Community Edition and the open docs. Deck `03c-gravwell-tour.md`: light by design (the instructor drives the browser), plus a high-level map of the platform's user-facing components and the *Cadet Academy: Crafting a Query* video for homework. Logbot is available on every seat but students are asked not to lean on it: they write and hand-tweak the lab queries, and reach for Logbot only when stuck | 60 | 405 | Slides + live demo | - | ⏱ (→ 30: skip the browser tour) | 🟢 |
| M5 + Lab C | **Endpoint detection with Sysmon**: process creation, the ParentImage race condition, child-count clustering per ParentProcessId, high-bash-spawner signature; find the rogue agent PID and pivot to its commands | 105 | 510 | Slides + lab | `stage-sysmon` | 🔒 | 🟢 |
| M6 | **Checkpoint & re-center**: what existing logs can/can't reveal; **"Questions for the CISO"** one-pager (`materials/`) worked through as a group; preview of interception | 45 | 555 | Discussion | - | ⏱ | 🟢 |
| R | **Recap & re-center**: floating 30-min module, run whenever the course resumes after a long break (a second session, a second day, a week later) | 30 | 585 | Slides | - | ⏱ | 🟢 |
| M7 + Lab D | **The AI user & opencode config**, install opencode, connect a provider, let an agent fix a real bug, then **audit it from the endpoint**: the log has no content, the local SQLite DB has *everything* (prompts, tool calls + outputs, cost), and all five properties a SOC needs are still wrong. Motivates the proxy | 60 | 645 | Lab | `stage-opencode` | 🔒 | 🟢 validated live |
| M8 + Lab E | **LLM proxies, part 1 (litellm)**: litellm in docker, route a request, syslog to Gravwell, see how weak generic gateway logs are | 60 | 705 | Lab | `stage-llm-proxy` | ⏱ | 🟢 validated live |
| M9 + Lab F | **LLM proxies, part 2: content-capturing proxies.** (a) the **Gravwell LLM ingester** (OpenAI + Anthropic listeners; prompts, replies, tool calls, usage, sessions) as the primary path; (b) the **vendor-agnostic Python proxy** (`src/logging-proxy/`) emitting the same event schema as JSONL/syslog for any SIEM. Point opencode at each; explore `tag=llm` / `tag=proxy`; (c) install Gravwell's **LLM Observability kit** and read the same traffic through dashboards, searches and a conversation-replay template somebody else wrote, the one kit in the course that fits the data with no macro edit; (d) **the system prompt**: read the ~9,700 characters nobody typed, measure it against the 23 they did, find the `<env>` block describing their box, and edit the agent's instructions by writing `AGENTS.md` | 105 | 810 | Lab | `stage-llm-proxy` | 🔒 | 🟢 validated live |
| M10 + Lab G | **MCP deep dive, read it, then write it.** *Part 1:* speak MCP by hand to **your own Gravwell's** MCP server (`/api/mcp`), 50 tools, 11 mutating, `whoami` bounds the blast radius. *Part 2:* **write your own MCP server** from a TOML config (`src/mcp-lab-server/`), connect opencode to it, then change a tool **description** and watch the agent's behaviour change with no code edited. Ships its own JSON-RPC to `tag=mcp` | 105 | 915 | Slides + protocol walkthrough + build | - | ⏱ (Part 1 → demo) | 🟢 validated live |
| M11 + Lab H | **MCP tool interaction across servers.** Put Gravwell's own MCP server next to the one you wrote (Lab 06); build a query-advisor tool whose manifest makes the model call Gravwell's `parse_query` **first**, and a threat-hunt **stub** (APT Cherdenko, last seen in space) that receives ten raw Gravwell entries the model fetched with `sample_tag_entries`; then watch one sentence in a description, and then the server's `instructions`, make the model call another server's tools that nobody asked for; a control prompt shows the rule stays dormant until the tool is used | 60 | 975 | Lab | `stage-mcp-tools` | 🔒 | 🟢 validated live |
| M12 | **Detect it in the ingester's data** (Lab 07 Part 3, `tag=llm`): tool calls by server, sessions that touched more than one server, the chain in order, tools nobody asked for (a compound query, the Lab 02 skill), first-seen tool names, and why the server's own log cannot see any of it; stretch: schedule one as a Gravwell scheduled search | 45 | 1020 | Lab | `stage-mcp-tools` | ⏱ (→ guided demo) | 🟢 validated live |
| M13 | **Wrap & next steps**, the **AI Audit Checklist** one-pager (`materials/`) as the spine: what to collect in four tiers, first detections, architecting for auditability; where research is heading; Q&A | 30 | 1050 | Discussion | - | ⏱ | 🟢 |

Core total: **1050 min**, plus the padding modules below.

**Treat every duration as an estimate, not a schedule.** The ⏱ column marks what compresses
gracefully (≈145 min recoverable) and the compression plan below lists the specific cuts in the
order we would make them. Work down that list when time is short; insert the padding modules when
there is time to spare. A reader working alone can ignore both columns and simply take as long as
each lab takes.

## Padding / optional modules (insert when the room is fast)

| Module | Min | Insert after | What it is | Build |
|---|---|---|---|---|
| P1 · **AI tooling as vulnerable software** | 20 | M1 | Unauthenticated local agent servers → RCE. **The core of this already ships inside M1**: `slides/00-intro.md` carries the opencode-ai < 1.0.216 slide (unauthenticated localhost HTTP server → arbitrary shell commands, CVSS 8.8), the Amazon Q booby-trapped-repo flaw, and the prompt-manipulation genre, all with screenshots. The padding module is the *deeper dive* off those slides when the room bites | 🟢 slides in M1; expansion optional |
| P2 · **Vibe-code your own proxy** | 45 | M9 | Students extend their own copy of `src/logging-proxy/` **using opencode, routed through the proxy**, so it records the conversation in which they modify it: add a dropped field (`temperature`, the envelope cherry-picks, so it takes two edits), add a webhook sink, add a secret-shape detector (**log the shape, never the secret**). `labs/_stretch/extend-the-proxy/` | 🟢 solutions written + validated |
| P3 · **Semantic search over LLM logs** | 20–30 | M9 or M12 | **Instructor demo.** Embed every prompt/reply at ingest (ingester `vector` preprocessor) and search `tag=llm` **by meaning**: `grep "credential"` returns nothing while `semantic "someone leaked a credential"` finds *"I accidentally committed an API key…"* at 0.72. Includes the failure case, so the room doesn't over-trust it. `labs/_stretch/semantic-search/` · `slides/05b-semantic-search.md` · `scripts/enable-semantic.sh` | 🟢 validated live |
| P4 · **A second client through the same proxy** | 30 | M9 | Run **Claude Code** at the same ingester listener, same task, and compare: it **sends** `x-claude-code-session-id` where opencode doesn't (so one client's sessions are supplied and the other's are *inferred*), opencode opens an extra ~606-token session you never asked for, tool names differ by case (`Read` vs `read`, detection-breaking), and the same one-sentence task costs **60,142 vs 15,972** input tokens. `labs/_stretch/second-client/` | 🟢 validated live |
| P9 · **Shadow AI beyond the wire** | 60–75 | M4 (or run as Lab B Part 2; or after M6) | The **same fourteen hosts** as Lab B through four logs the network sensor lacks: osquery inventory (a local model with zero network signal), an identity-aware TLS-inspecting proxy (a blocked upload, SDK user agents, an AI feature inside sanctioned Notion found by request-size growth), CloudTrail (a developer wiring Bedrock into prod in nine minutes), and Workspace OAuth audit (HR consents to "ChatGPT" from a phone → 505 MB of Drive pulled server-to-server, the host Lab B *cleared*). Ends with a host × source matrix. `labs/_stretch/shadow-ai-sources/`, take-home `materials/shadow-ai-detection-matrix.md` | 🟢 validated live |
| P8 · **Audit an AI assistant from its own logs** | 45 | M10 (or M3) | Reconstruct a real MCP-enabled assistant (Gravwell Logbot) from its app logs: tool calls, token spend, a UEBA outlier, and where content-blind logging stops. `labs/_stretch/ai-assistant-audit/` | 🟢 |

### Not included

- **P5 · OpenTelemetry GenAI telemetry**, cut. The GenAI semconv work
  is real but it is a different course; nothing else in the sequence depends on it.
- **P6 · RAG / vector-DB data leakage**, cut. It never had assets, and **P3 now covers
  embeddings-as-an-exposure-surface better**: students watch their own prompts get vectorised and
  searched, on data they generated, instead of discussing a retrieval pipeline nobody has built.

`labs/_stretch/opentelemetry/` and `labs/_stretch/rag-vectordb/` are removed. If either comes back,
start from the deck's stretch section rather than these stubs.

## Compression plan (room is slow)

1. Run the M2b mini-lab as a front-of-room demo instead of hands-on (−20); the deck's three "Demo!"
   slides were written for that. Keep the deck: "how AI works" is the first thing this course must teach.
2. Drop Method 4 (SSO) from Lab B (−15).
3. M12 becomes a guided demo instead of a lab (−30).
4. Trim M0/M1/M3/M6 discussion (−30 total).
5. Skip litellm (M8) entirely and go straight to the LLM ingester in M9 (−60). The "generic
   proxies log too little" point can be made in one slide.
6. Run **M10 Part 1 as a front-of-room demo** rather than hands-on (−20).
7. M4b Gravwell tour: skip the browser tour and keep the four slides (−30). Never cut it entirely;
   Lab 03's `xml` syntax is the first thing students cannot guess, and this is where they learn
   where the docs are. Protocol *reading* works
   fine as a demonstration. Keep **Part 2 hands-on**, protocol *authoring* doesn't demo.

## Take-home materials (assembled from the repo)

**The student lab repo** (`build-student-repo.sh` → cloned to `~/jarvis`): all lab handouts, the
Lab 00 compose + configs, the litellm stack, `llm_audit_proxy.py`, the moneyprinter project, and
every dataset: released **stage by stage** as the course reaches each lab (`release-stage.sh`;
students `git pull`). Each `stage-*` tag is also that lab's recovery point
(`git checkout stage-x -- labs/<dir>`).

**Distributed separately as materials** (with the slides, *not* in the lab repo):
`materials/questions-for-the-ciso.md` (M6) and `materials/ai-audit-checklist.md` (M13).

## Dependencies & open items

- **M2b needs an Ollama-shaped model endpoint and, in a class, the loopback relay.** An instructor
  puts the upstream URL and token in `instructor/runbook/gravwell-llm.env` (git-ignored; copy the
  `.example`; rotate the token after every delivery). `start-llm-relay.sh` runs a root-only relay on
  `127.0.0.1:9010` that adds the token; seats get only that URL in `~/.workshop_env` and the scripts
  send no credential, so nothing `cat`-able on a seat holds a secret. `build-student-repo.sh` refuses
  to publish if the token string appears in the student repo; `preflight.sh` checks the relay (active,
  loopback-only, root:600 token file, 200 without a credential, 403 off-allowlist, no seat holds the
  token). A self-guided reader points the scripts at a local Ollama instead (`SETUP.md`).

- **Gravwell image is PINNED to `gravwell/gravwell:5.10.1`.** Lab 06 needs the MCP server at
  `/api/mcp`, which only exists on 5.10.x: a stale `:latest` (5.8.13) 404s. `preflight.sh` runs a
  real MCP `initialize` and fails if it doesn't get 200.
- **Gravwell runs in docker, one stack per attendee** (Lab A compose, ports derived from
  `WORKSHOPUID`). Validated on a lab host.
- **LLM ingester runs as a sidecar in the same compose** (`llm-ingester` service, the official
  `gravwell/llm_ingester:5.10.1` image). Ingests to the student's indexer over the compose
  network on 4023. Needs `GRAVWELL_INGEST_AUTH` **and** `GRAVWELL_INGEST_SECRET` set to the same
  value on the gravwell service (setting only one is what desynced simple_relay earlier).
- **Shadow-AI data: attendees ingest it themselves** via the per-tag `simple_relay` listeners
  (`nc localhost ${WORKSHOPUID}01 < corelight_dns.jsonl`, validated).
- **Data source:** the synthetic generator (`src/log-generator/`) is primary; a real Corelight
  sample in `datasets/corelight/` anchors its schema.
- **Datasets.** `ai_domains.txt` (+ an `ai_domains_plus_api.txt`
  with provider API hostnames), the real Sysmon XML (rogue PID 3565), the legacy proxy capture, the
  and Gravwell's own AI-assistant logs are in `datasets/`. Lab 02's data is now
  a **scenario generator** (`src/log-generator/`) with 11 correlated shadow-AI scenarios across 14
  hosts; all hunt + correlation searches were run against a live Gravwell. The generator can re-time
  the real Sysmon burst onto the same host/window as the network data for cross-source correlation.
- **Seat count:** default 2 (ids 10–11), which is the development and self-guided default. A
  delivery sets the roster size: `SEATS=20 ./makeuser.sh`. Host scripts take `SEATS`/`START_ID`.
- **Data generators** (`src/log-generator/`, all validated in Gravwell): `generate_corelight_logs.py`
  (Lab 02 shadow-AI), `generate_shadow_ai_sources.py` (P9: osquery/SWG/CloudTrail/Workspace for the same cast),
  `generate_logbot_logs.py` (P8 assistant audit), and `retime_datasets.py` (refresh
  any real capture to "now"). Regenerate before you start so every 24h window is "today". Lab 07 needs no
  dataset: its detection data is the `tag=llm` traffic the room produces in Parts 1 and 2.

## Port map (per seat, `<ID>` = `WORKSHOPUID`, 10–49)

| Port | Service |
|---|---|
| `<ID>443` | Gravwell UI (HTTPS) |
| `<ID>514/udp` | Gravwell syslog, UDP (image default listener: unused by the labs) |
| `<ID>01`–`<ID>04` | Corelight ingest listeners (dns/ssl/conn/http) |
| `<ID>05` | Ingest listener for the Python proxy (`--tcp localhost:<ID>05`, tag=proxy) |
| `<ID>06` | Ingest listener: Okta SSO (Lab 02 Method 4, tag=okta) |
| `<ID>07` | Ingest listener: Sysmon XML (Lab 03, tag=sysmon) |
| `<ID>08` | Ingest listener: Gravwell AI-assistant / Logbot (P8, tag=logbot) |
| `<ID>09` | Ingest listener: litellm container logs, **raw text, no parsing** (M8, tag=syslog) |
| `<ID>10` | Ingest listener: the student's own MCP server's JSON-RPC traffic (M10, tag=mcp) |
| `<ID>11` | Ingest listener: osquery endpoint inventory (P9, tag=osquery) |
| `<ID>12` | Ingest listener: secure web gateway access log (P9, tag=swg) |
| `<ID>13` | Ingest listener: AWS CloudTrail (P9, tag=cloudtrail) |
| `<ID>14` | Ingest listener: Google Workspace token audit (P9, tag=gws) |
| `<ID>00` | litellm (Lab 05 Part 1) |
| `<ID>80` | LLM ingester: OpenAI-compatible listener (`/v1/chat/completions`) |
| `<ID>81` | LLM ingester: Anthropic Messages listener (`/v1/messages`) |
| `<ID>90` | Vendor-agnostic Python logging proxy |
| `<ID>91` | The student's own MCP lab server, HTTP transport (M10) |

Host-wide (not per-seat): **80/443**, the share site (course documents over HTTPS, basic auth);
**127.0.0.1:9010**, the loopback LLM relay for Lab 01b (root-only holder of the model token).
