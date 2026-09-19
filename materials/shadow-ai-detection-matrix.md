# Shadow-AI detection matrix
### *Exploring AI Visibility*: take-home one-pager (M4 / Lab B, extended by the "beyond the wire" lab)

Shadow AI is not one thing. It is a person in a browser, an agent in a terminal, a model on a
laptop, a workload in a cloud account, and a SaaS integration that reads your files server-to-server,
and each of those leaves evidence in a **different** log. No single source sees more than a slice.
This page lists the indicators that actually work, what you need to collect to see each one, and
what each one is blind to. The right-hand column says where the course proves it.

## 1. Indicators, techniques and the logs they need

| # | Indicator | Technique | Log source(s) required | Catches | Blind to | Where in the course |
|---|---|---|---|---|---|---|
| 1 | Name resolution of AI domains | Match `query` against a maintained AI-domain list | DNS (Zeek `dns`, resolver logs, Windows DNS client) | The honest majority; cheapest signal there is | DoH/DoT clients; internal names; **resolving ≠ using** (link previews, scanners, prefetch) | Lab 02 Method 1 |
| 2 | TLS handshake to an AI hostname | Match SNI `server_name` against the list | TLS metadata (Zeek `ssl`, firewall TLS logs) | Confirms a **connection**, even with DoH | QUIC/HTTP-3 (no parseable handshake); ECH; shared-CDN IPs; internal names | Lab 02 Method 2 |
| 3 | Plaintext HTTP to model / MCP paths | Match `host` **or URI shape** (`/api/generate`, `/v1/chat/completions`, `/mcp`) | HTTP metadata (Zeek `http`) | **Self-hosted models and MCP gateways** that no list contains | Anything encrypted | Lab 02 Method 3 |
| 4 | SSO login to an AI application | IdP app-access events matched against the list | IdP system log (Okta, Entra sign-in) | Ties a **person** to the usage | Only apps behind your IdP: shadow AI is by definition the rest | Lab 02 Method 4 |
| 5 | DNS answer ↔ connection, same host, bytes moved | Correlation query: inner `@ai_resolved { … }` of DNS answers, vectored `lookup` against `conn` | DNS **and** conn (Zeek) | Separates real usage from DNS-only noise; survives QUIC | DoH hosts; internal names; still no content | Lab 02 correlation query |
| 6 | Volume / time outliers | `max(orig_bytes)`, off-hours, `orig ≫ resp` | Flow/conn logs, firewall, NetFlow | Bulk uploads, automation, agent loops | Which *data* left | Lab 02 tasks 7–8 |
| 7 | Process-tree shape of an agent | Child count per parent; many short `bash`/`node` children | Endpoint process telemetry (Sysmon, auditd, EDR) | Agents running on the box, and **what they ran** | Anything not on an instrumented endpoint | Lab 03 |
| 8 | **AI software installed / running** | Inventory processes, packages, apps, browser extensions against an **AI software** list | Endpoint inventory (osquery, Intune/Jamf, SCCM, EDR software inventory) | Local models (LM Studio, ollama) that **never touch the wire**; agents and SDKs; AI browser extensions; DoH clients that explain DNS blind spots | Portable binaries; unmanaged devices | *Beyond the wire* Part A |
| 9 | **Local inference server listening** | `listening_ports` on 11434 / 1234 / 8000 / 7860, esp. bound to `0.0.0.0` | osquery `listening_ports` ⨝ `processes`; EDR network inventory | Models exposed to the network from a laptop or dev VM | Ephemeral processes between snapshots | Part A |
| 10 | **User-attributed web access** to AI apps | Proxy log with authenticated `user` matched against the list / vendor category | Secure web gateway / forward proxy (Zscaler, Netskope, Squid + auth, PAN URL-filter) | **Who**, not just which IP; vendor URL categories as a second list | Servers and CI that **bypass the proxy**; QUIC when not forced to TCP; personal devices | Part B |
| 11 | **File upload to an AI app** | `POST` to upload endpoints, `reqsize`, `filename`/`filetype` (needs TLS inspection), DLP verdict | SWG with SSL inspection + DLP | The exact file that left, and whether policy stopped it | Pasted text (not a "file"); uninspected categories; API traffic | Part B |
| 12 | **Non-browser user agent** to an AI provider | `useragent` ∉ browsers → SDK/agent/CI | SWG / HTTP metadata | Scripted and agentic usage hiding behind a "person" | Spoofed UAs | Part B |
| 13 | **LLM conversation shape**, growing request sizes | Successive `POST`s to one URL from one user whose `reqsize` climbs turn over turn | SWG with SSL inspection (or any per-request size log) | **AI features embedded in sanctioned SaaS** (Notion AI, Slack AI, Zoom AI) that no domain list can block; unknown AI tools | Streaming/websocket transports; tiny prompts | Part B, links back to Lab 01's token growth |
| 14 | **Cloud AI service invoked** | `eventSource = bedrock / sagemaker / aiplatform / openai.azure`, by identity | Cloud audit (CloudTrail **incl. data events**, Azure Activity + Diagnostic, GCP Audit) | Workloads and developers using AI **inside your own cloud account**; which identity, which model, from where | Off-cloud providers; data events **not enabled by default** (Bedrock `InvokeModel` is a data event) | Part C |
| 15 | **Enablement chain** | Model-access agreement + IAM policy attach by a human, followed minutes later by a workload invoking | CloudTrail management events + IAM | The person who *wired* AI into production, and when | Pre-existing entitlements | Part C |
| 16 | **Denied AI attempts** | `errorCode = AccessDenied*` on AI APIs | Cloud audit | Intent: who is *trying* | Nothing, that's the point of collecting failures | Part C |
| 17 | **OAuth consent to a third-party AI app** | `authorize` events: app name/client id ∉ sanctioned list, **data scopes** (`drive`, `gmail`, `calendar`, `Files.Read`) | Google Workspace token audit; Entra "Consent to application"; Okta app grants | Users handing an AI vendor a **standing** key to corporate data | Apps consented from personal accounts | Part D |
| 18 | **Server-to-server data pull by a consented app** | `activity` events: `api_name`, `method_name`, `sum(num_response_bytes)` by app | Google Workspace token audit (`activity`), Microsoft Graph activity logs | **The data leaving via a path no network sensor you own can see** | Apps that pull from IPs you don't log | Part D |
| 19 | AI feature usage inside sanctioned SaaS | Vendor audit logs (Copilot activity, Gemini usage, Slack AI) | M365 unified audit, Workspace reports, vendor admin logs | Sanctioned-but-ungoverned usage, per user | Only what the vendor chooses to log | M3 / P8 (the vendor's own AI logs) |
| 20 | What was actually *said* | Proxy in the path capturing prompts, replies, tools | LLM proxy / Gravwell LLM ingester | Content, tools offered/called, tokens, sessions | Traffic that doesn't route through it | Labs 04–05 |

## 2. Strategies (how to combine them)

1. **Correlate, don't grep.** Every row above is a *signal*. Lab 02's whole lesson is that the
   loudest single signal (DNS) named a scanner, and the most trustworthy one (the correlation query) still
   missed two real users. Require two independent sources before a name goes to the CISO.
2. **Inventory beats blocklists for the long tail.** Domain lists (rows 1, 2, 10) cover the
   famous providers. Local models (8–9), embedded SaaS features (13, 19) and cloud services (14)
   are never on them. Hunt those by *shape*: ports, paths, request-size growth, event sources.
3. **Identity is the pivot.** IP → host → user → cloud principal → OAuth client. Rows 4, 10, 14,
   17 each add one hop. The "beyond the wire" lab is built so the same fourteen people appear in
   every source; the exercise is joining them.
4. **Look where the data actually leaves.** Rows 11 and 18 are the only two that show *data*
   moving. In this course's dataset the largest exposure of the day (an HR Drive pulled server-to-
   server by a consented app) produces **zero** bytes on the corporate network and **zero** rows in
   the proxy. If you only watch the wire you will clear that host.
5. **Log the failures and the enablements.** Denied invocations (16) and policy attachments (15)
   precede usage. They are cheap, they are management events you already have, and they are the
   earliest warning you will get.
6. **Know your own blind spots and write them down.** Servers bypassing the proxy, QUIC not forced
   to TCP, DoH allowed, data events not enabled, unmanaged devices. Each is a row you can't fill.
   The lab ends by filling a host × source matrix and marking the cells that *cannot* be filled.

## 3. Minimum collection plan (in priority order)

| Tier | Collect | Rows it unlocks |
|---|---|---|
| 1: you already have it | DNS, TLS metadata, conn/flow, IdP sign-ins | 1–6 |
| 2: usually available, rarely searched | Web gateway logs **with user and full URL**, endpoint process telemetry | 7, 10–13 |
| 3: turn it on | Endpoint software/extension inventory (osquery pack), cloud **data events** for AI services, Workspace/Graph token & consent audit | 8–9, 14–18 |
| 4: build it | An LLM proxy in the path | 20 |

Everything in this course is reachable with Tiers 1–3 plus one Python file for Tier 4.
