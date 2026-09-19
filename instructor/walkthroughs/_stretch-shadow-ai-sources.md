# Walkthrough: P9: Shadow AI beyond the wire

> ⛔ **INSTRUCTOR ONLY.** Contains every answer. Student handout:
> [`labs/_stretch/shadow-ai-sources/README.md`](../../labs/_stretch/shadow-ai-sources/README.md).

**Padding module P9** · **60–75 min** · insert after **M4 / Lab 02** (or run as Lab 02 Part 2, or
after M6 as the Day-1 closer) · **Checkpoint:** `stage-shadowai-sources` · **Flex:** each Part (A–D)
is independently droppable; Part D is the one to keep if you keep only one.
**Deck:** [`slides/03b-shadow-ai-sources.md`](../../slides/03b-shadow-ai-sources.md)
**Take-home:** [`materials/shadow-ai-detection-matrix.md`](../../materials/shadow-ai-detection-matrix.md)

Lab 02 proves that four network signals are each partial and only correlation is right. This lab
proves the frame itself was too small: the **same fourteen hosts**, seen through endpoint inventory,
an identity-aware proxy, cloud audit and SaaS OAuth logs, and the biggest exposure of the day is on
the host Lab 02 **cleared**. Every number below was run live against Gravwell 5.10.1.

---

## Timing

| Min | Segment |
|---:|---|
| 0–10 | Slides: the frame is too small, five shapes of shadow AI, four more logs |
| 10–15 | Ingest four files, upload two resources, confirm tags |
| 15–30 | Part A: endpoint inventory (tasks 1–3) |
| 30–45 | Part B: the proxy (tasks 4–8). **Task 7 is the payoff; protect it** |
| 45–55 | Part C: CloudTrail (tasks 9–12) |
| 55–65 | Part D: Workspace OAuth (tasks 13–15). **The reveal** |
| 65–75 | Part E: the matrix, on paper, then debrief |

Running short: drop Part C first (it's the least surprising), then Part A. Never drop D or task 7.

## Before class

Generate with the **same `--anchor`** as the Lab 02 generator (or both anchored to now, run
back-to-back), or the two datasets won't share a day:

```bash
cd src/log-generator
python3 generate_shadow_ai_sources.py --seed 1 \
    --outdir ../../datasets/shadow-ai-sources/generated \
    --answer-key ../../datasets/shadow-ai-sources/generated/answer-key.json
```

Prints per-tag counts: **osquery=248 swg=305 cloudtrail=244 gws=484** with `--seed 1`. The
answer key JSON has the per-host findings and the four blind spots. `build-student-repo.sh` runs
this alongside the Lab 02 generator.

Two extra lookup resources: `AI_SOFTWARE` (`Name,Kind`) and `SANCTIONED_APPS` (`App,Owner`), from
`datasets/resources/`. Students upload them with Lab 02's helper. `AI_DOMAINS_PLUS_API` is reused.

## Ingest

```bash
cd ~/jarvis/datasets/shadow-ai-sources/generated
nc -q1 localhost ${WORKSHOPUID}11 < osquery_results.jsonl
nc -q1 localhost ${WORKSHOPUID}12 < swg_access.jsonl
nc -q1 localhost ${WORKSHOPUID}13 < cloudtrail_events.jsonl
nc -q1 localhost ${WORKSHOPUID}14 < gws_token_audit.jsonl
```

Confirm: `tag=osquery,swg,cloudtrail,gws count by TAG | table TAG count` → 248 / 305 / 244 / 484.
Timestamps are extracted (osquery's `calendarTime` is Go's ANSIC form plus a zone; the listener
uses `Timestamp-Format-Override="AnsiC"`; check with `min/max(TIMESTAMP)` that the entries
span the 24 h). Set the time range to **last 48 hours**, as in Lab 02.

---

## Answer key

### Part A: osquery

**Task 1: AI software by host**
```
tag=osquery json hostIdentifier name columns.name as software
| lookup -s -r AI_SOFTWARE software Name Kind as kind
| count by hostIdentifier software kind | table hostIdentifier software kind count
```
Six hosts match. The one that was **benign in every Lab 02 method** is **`ops-lt-48` (gmartin, IT
Ops)**: `lm-studio` package, `lms` process (`lms server start --port 1234`), `llama_cpp_python`. A
local model. It never resolved or connected to anything AI, because the model is *on the laptop*.
*Beat:* zero network signal is not zero AI. Inventory is the only source that sees this shape.

Also on the list: `dev-vm-51` (ollama, langchain), `eng-lt-190` (opencode-ai, anthropic SDK,
cloudflared), `mkt-lt-221` (ChatGPT desktop app, Grammarly), `ubuntu-sysmon` (opencode, the Lab 03
agent), `fin-lt-112` (Microsoft 365 Copilot, sanctioned).

**Task 2: who is serving a model**
```
tag=osquery json name hostIdentifier columns.port as port columns.address as address
    columns.name as process
| grep -e name listening_ports | grep -v -e process sshd svchost.exe System avahi-daemon
| table hostIdentifier process port address
```
| Host | Process | Port | Bind |
|---|---|---|---|
| `dev-vm-51` | `ollama` | 11434 | **`0.0.0.0`**: reachable from the whole LAN |
| `dev-vm-51` | `node` (MCP gateway) | 8080 | `0.0.0.0` |
| `ops-lt-48` | `lms` | 1234 | `127.0.0.1`, local only |
| `eng-lt-190` | `cloudflared` | 53/udp | `127.0.0.1` |

Lab 02 Method 3 saw dev-vm-51's *traffic*; this shows the *exposure*: anyone on the LAN can use
that model (and that gateway).

**Task 3: two Lab 02 mysteries**
(a) `eng-lt-190`: process `cloudflared`, `cmdline` = `cloudflared proxy-dns --port 53 --upstream
https://cloudflare-dns.com/dns-query`. That is the DoH client that made the host invisible to Method 1.
(b) `hr-lt-140`: Chrome extension **"AI Sidebar - ChatGPT Claude & Gemini"**, permissions
`tabs, storage, contextMenus, <all_urls>`. It pre-resolves the AI backends, the "link preview"
DNS from Lab 02, and it can read every page the user opens. *Beat:* "DNS-only, not usage" was the
right call on the **network** evidence and still leaves a data-handling finding on the endpoint.
(Grammarly on `mkt-lt-221` also has `<all_urls>`; both surface with the extension query.)

### Part B: the web gateway

**Task 4: names on IPs**
```
tag=swg json user host appname action | lookup -s -r AI_DOMAINS_PLUS_API host Domain
| count by user host action | table user host action count
```
`kwatts@acme.corp` → chatgpt.com (37 allowed, **2 blocked**), `lchen@acme.corp` → api.anthropic.com
(37), `rdiaz@acme.corp` → copilot.microsoft.com (28). Three Lab 02 IPs now have people.

**Task 5: what files left**
```
tag=swg json user host url method reqsize filename action
| grep -e method POST | eval reqsize > 1000000
| table TIMESTAMP user host url reqsize filename action
```
| When | Who | Where | File | Size | Verdict |
|---|---|---|---|---|---|
| 15:22 + 15:23 | kwatts | `chatgpt.com/backend-api/files` | `Q3-pipeline-forecast.xlsx` | 2.4 MB | **Blocked** ×2 (DLP: Financial Statements) |
| 14:48 | dfoster | `www.notion.so/api/v3/runInferenceTranscript` | `ACME-Q3-customer-pipeline.csv` | 1.9 MB | **Allowed** |

Same policy ("block uploads to *AI & ML Applications*"), two outcomes: the policy is keyed on
**URL category**, and Notion is *Productivity*. The customer list went into an AI feature inside a
sanctioned app. *Beat:* you cannot block Notion. Category-based controls end exactly here.

**Task 6: people or programs**
```
tag=swg json user host useragent | lookup -s -r AI_DOMAINS_PLUS_API host Domain
| grep -v -e useragent Mozilla | count by user host useragent | table user host useragent count
```
Only `lchen` → `api.anthropic.com`: `anthropic-sdk-python/0.42.0` (15), `python-httpx/0.28.1` (13),
`opencode/1.18.25` (9). An agent and scripts, not a browser. Matches the osquery inventory.

**Task 7: the conversation shape (the payoff)**
```
tag=swg json user url method reqsize | grep -e method POST
| stats count min(reqsize) as first max(reqsize) as biggest by user url
| eval count > 5 | eval growth = biggest / first
| sort by growth desc | table user url count first biggest growth
```
Top: `dfoster` → `https://www.notion.so/api/v3/runInferenceTranscript` (14 POSTs, growth ≈ 590×,
the CSV inflates it; without the CSV the turns still grow 4×). Next: `lchen` → `/v1/messages`
(≈11×) and `kwatts` → `/backend-api/conversation` (≈5×), also real LLM conversations, so the
heuristic is *correct* on all three. Then in time order:
```
tag=swg json user url method reqsize filename | grep -e url runInferenceTranscript
| sort by TIMESTAMP asc | table TIMESTAMP user reqsize filename
```
4,278 → 7,398 → 9,601 → 12,486 → 13,862 → 15,757 → 18,209 bytes over seven turns. **That is Lab 01
Task 4 measured from the outside**: the client re-sends the whole transcript every turn, so request
size climbs monotonically. No list contains `www.notion.so`; the *shape* found it.

**Task 8, who is missing.** One compound query (the old two-search `table -save` form
and its "wait for A" gotcha are gone, same as Lab 02):
```
@swg_ai {
  tag=swg json src_ip host | lookup -s -r AI_DOMAINS_PLUS_API host Domain
  | count by src_ip | table src_ip count
};
tag=corelight_ssl json "id.orig_h" as src_ip server_name
| lookup -s -r AI_DOMAINS_PLUS_API server_name Domain
| count by src_ip | lookup -s -v -r @swg_ai src_ip src_ip () | table src_ip count
```
→ **`10.13.42.42`** (the rogue agent, 79 conns) and **`10.13.42.60`** (the CI runner, the day's
48 MB upload). Both on `10.13.42.x`: **servers bypass the proxy**. Run B against `corelight_conn`
keyed on the AI answer IPs instead and `10.13.20.203` (the QUIC user, UDP/443 isn't proxied) and
`10.13.20.77` (the shared-CDN decoy) appear too. *Beat:* your proxy log's blind spots are your
biggest upload, your rogue agent, and HTTP/3. Write them down; that's the Part E matrix.

### Part C: CloudTrail

**Task 9: who calls Bedrock**
```
tag=cloudtrail json eventSource eventName userIdentity.arn as who sourceIPAddress as ip errorCode
| grep -e eventSource bedrock | count by who eventName errorCode
| table who eventName errorCode count
```
| Identity | What | Verdict |
|---|---|---|
| `assumed-role/app-prod-ec2-role/i-0f3a9c2e7b1d4e5f6` | `InvokeModel` ×24 + `InvokeModelWithResponseStream` ×11, from `10.42.1.87` | **machine**, a prod workload |
| `AWSReservedSSO_DeveloperAccess_…/jpark@acme.corp` | `ListFoundationModels`, `PutUseCaseForModelAccess`, `CreateFoundationModelAgreement`, `PutFoundationModelEntitlement` | **person**, enabling |
| `AWSReservedSSO_AdministratorAccess_…/gmartin@acme.corp` | `InvokeModel` ×3, `AccessDeniedException` | never succeeded |

**Task 10, the enablement chain.** `grep -e eventName` takes several values:
```
tag=cloudtrail json eventName userIdentity.arn as who requestParameters.policyArn as policy
  requestParameters.roleName as role requestParameters.modelId as model
| grep -e eventName ConsoleLogin PutUseCaseForModelAccess CreateFoundationModelAgreement
    PutFoundationModelEntitlement AttachRolePolicy
| table TIMESTAMP who eventName role policy model
```
All **jpark@acme.corp**, console, from the office NAT `203.0.113.10`: `ConsoleLogin` 13:47 →
`PutUseCaseForModelAccess` 13:51 → `CreateFoundationModelAgreement` + `PutFoundationModelEntitlement`
(`anthropic.claude-3-7-sonnet-20250219-v1:0`) 13:51 → **`AttachRolePolicy` `AmazonBedrockFullAccess`
onto `app-prod-ec2-role`** 13:56. **Nine minutes** from login to a production role with model access.
```
tag=cloudtrail json eventName userIdentity.arn as who requestParameters.modelId as model
    sourceIPAddress as ip
| grep -e eventName InvokeModel
| stats min(TIMESTAMP) as first_seen max(TIMESTAMP) as last_seen count by who model ip
| table who model ip first_seen last_seen count
```
First `InvokeModel` from the prod role at **14:07**, eleven minutes after the policy, from
`10.42.1.87` (inside the VPC), 35 calls through 16:53. jpark is **`dev-vm-51`'s owner** from Lab 02:
the person self-hosting ollama and an MCP gateway on-prem is the same person who wired Claude into
production. *Beat:* not one of these events crossed a sensor you own. (Times shift with the anchor;
the *gaps*, 9 min, 11 min, are fixed.)

**Task 11: intent**
```
tag=cloudtrail json eventName userIdentity.arn as who errorCode errorMessage
    requestParameters.modelId as model userAgent
| grep -e errorCode AccessDenied | table TIMESTAMP who eventName model userAgent errorMessage
```
`gmartin@acme.corp`, `aws-cli/2.22.7`, `meta.llama3-1-70b-instruct-v1:0`, 3× within 80 s at 10:14.
Nothing happened, and it is still a finding: the LM Studio user (Part A) is shopping for bigger
models. Denials are the earliest warning you get.

**Task 12: the fine print**
```
tag=cloudtrail json eventName eventCategory managementEvent
| grep -e eventName InvokeModel AttachRolePolicy
| count by eventName eventCategory managementEvent
| table eventName eventCategory managementEvent count
```
`InvokeModel*` → `eventCategory: Data`, `managementEvent: false`. `AttachRolePolicy` → `Management`.
**With CloudTrail defaults you get the enablement chain and the denials but *none* of the 35
invocations.** Bedrock data-event logging is opt-in (and billed). Same story for S3/Lambda.

### Part D: Workspace OAuth (the reveal)

**Task 13: who authorized what**
```
tag=gws json event_name actor_email app_name scopes ipAddress | grep -e event_name authorize
| lookup -v -r SANCTIONED_APPS app_name App | table TIMESTAMP actor_email app_name scopes ipAddress
```
Twenty-two `authorize` events; after dropping IT-approved apps, **two** remain:

| Who | App | Scopes | From |
|---|---|---|---|
| **psingh@acme.corp** (HR) | **ChatGPT** | **`drive.readonly`**, **`gmail.readonly`**, userinfo | `172.58.44.219`, a **mobile-carrier** address, i.e. a phone, not the corporate network |
| dfoster@acme.corp (Sales) | Fireflies.ai Notetaker | `calendar.readonly`, `drive.file`, userinfo | office NAT |

**Task 14: what the apps then did**
```
tag=gws json event_name actor_email app_name api_name num_response_bytes
| grep -e event_name activity
| stats sum(num_response_bytes) as bytes count by actor_email app_name | sort by bytes desc
| table actor_email app_name bytes count
```
**psingh / ChatGPT: ≈505 MB in 351 calls** (`drive.files.list/get/export` ≈ 499 MB in 316 calls,
`gmail.users.messages.*` ≈ 6 MB in 35) between 13:41 and 14:51, **seventy minutes**, every row
`ipAddress: SERVER_TO_SERVER`. Next-largest is the notetaker at 0.4 MB. Everything else is
kilobytes of `userinfo`/`calendar` noise.

**Task 15, back to Lab 02.** `10.13.20.140` in `tag=corelight_*`: ordinary O365/Teams/NYT browsing
plus the four AI-name resolutions with **no connection** → Lab 02 verdict "DNS-only, not usage".
In `tag=swg`: ordinary browsing, **no AI rows**. Bytes of the exposure seen by any network source:
**zero.** The consent came from a phone; the data moved Google → OpenAI, server to server. *Beat:*
this is the slide the whole lab exists for, say it slowly. The host you cleared with the most
rigorous method in Lab 02 is the largest data exposure of the day, and it was never going to be on
the wire. Only the SaaS audit log sees it.

### Part E: the matrix (expected shape)

| Host | dns | ssl | conn | http | okta | osquery | swg | cloudtrail | gws |
|---|---|---|---|---|---|---|---|---|---|
| mkt-lt-221 kwatts | seen | seen | seen | seen | seen | seen (app+ext) | seen + **blocked upload** | - | - |
| fin-lt-112 rdiaz | seen | seen | seen | - | seen | seen | seen | - | - |
| hr-lt-140 psingh | cleared | cleared | cleared | - | - | seen (extension) | cleared | - | **seen, 505 MB** |
| sec-scan-155 | cleared | cleared | cleared | - | - | - | - | - | - |
| eng-lt-190 lchen | **blind** (DoH) | seen | seen | - | - | seen (+ cloudflared) | seen (SDK UAs) | - | - |
| eng-lt-203 mokafor | seen | **blind** (QUIC) | seen | - | - | - | **blind** (UDP) | - | - |
| legal-lt-77 abrennan | cleared | cleared | decoy | - | - | - | cleared (Food) | - | - |
| ubuntu-sysmon | seen | seen | seen | - | - | seen (opencode) | **blind** (server subnet) | - | - |
| dev-vm-51 jpark | internal | **blind** | seen | seen | - | seen (**exposed**) | **blind** | **seen (enabled prod)** | - |
| ci-runner-60 | seen | seen | seen (48 MB) | - | - | - | **blind** | - | - |
| ops-lt-48 gmartin | **blind** | **blind** | **blind** | **blind** | - | **seen (LM Studio)** | - | seen (denied) | - |
| sales-lt-66 dfoster | cleared | cleared | cleared | - | - | - | **seen (Notion AI, CSV)** | - | seen (notetaker) |

Answers: most blind cells yet biggest exposure → **hr-lt-140/psingh** (blind in every network column
for the thing that mattered). Blind in *every* network column → **ops-lt-48** (local model) and the
psingh exposure itself. Needed exactly two sources → **jpark**: CloudTrail shows the enablement,
Lab 02 / osquery show who he is and what else he runs; or **gmartin**: osquery + the denied calls.

---

## Where students get stuck

| Symptom | Cause | Fix |
|---|---|---|
| `lookup` on `AI_SOFTWARE` returns nothing | Resource not uploaded, or field name typo | Upload with the helper; the column is `Name` (capital N) |
| Extension never matches the list | Name has a comma → CSV column split | The shipped names are comma-free; if they add their own, quote or rename |
| `grep -e eventName "A\|B"` returns nothing | Gravwell `grep` isn't regex | Give several values: `grep -e eventName A B C`, or use `regex -e` |
| Task 8 returns nothing | Typo in the inner query, or the `;` between the queries is missing | The inner query must end in `table`; run it alone first |
| `growth` won't render | Usually a missing `by` field in `stats`, so `biggest`/`first` don't exist | `eval growth = biggest / first` is correct; `eval setEnum(...)` is the legacy spelling |
| `columns.name` comes back empty | They quoted the nested path | Nested paths are **unquoted**; only literal-dot keys (`"id.orig_h"`) are quoted |
| Times don't match this document | Anchor differs | Only the *gaps* are fixed (9 min, 11 min, 70 min); clock times shift with the anchor |

## Debrief (5 min)

Ask: *which single source would you add first on Monday?* Steer toward: it depends on which shape
of shadow AI they fear, but the two places **data** was seen moving (proxy uploads, Workspace
`activity` bytes) were the two places the network had nothing, and the OAuth log is the one almost
nobody is reading. Then hand out `materials/shadow-ai-detection-matrix.md`.
