# Lab: Shadow AI beyond the wire

## Objective
Same company, same day, the **same fourteen hosts and people** you hunted in Lab 02, seen through
four log sources the network sensor doesn't have. Each one finds something Lab 02 provably could
not, and the biggest exposure of the day turns out to be on a host **you cleared**. By the end you
fill in a host × source matrix and mark the cells that *cannot* be filled.

## Background
Lab 02 taught that DNS, SNI, HTTP and SSO are each a partial view and only correlation is right.
This lab widens the frame: shadow AI is also a model running on a laptop that never touches the
network, an agent's SDK traffic hiding behind a person's proxy identity, an AI feature inside a
SaaS you *can't* block, a developer wiring a model into production inside your own cloud account,
and a user granting an AI vendor a standing key to their Drive. Different evidence, different logs.

The four sources:

| Part | Tag | Source | What it is |
|---|---|---|---|
| A | `tag=osquery` | Endpoint inventory | osquery result log: processes, listening ports, browser extensions, packages |
| B | `tag=swg` | Secure web gateway | Identity-aware forward proxy with TLS inspection: user, full URL, sizes, category, allow/block |
| C | `tag=cloudtrail` | Cloud audit | AWS CloudTrail: who called Bedrock, with which identity, from where; IAM changes |
| D | `tag=gws` | SaaS OAuth audit | Google Workspace token log: third-party app consents (`authorize`) and the API calls those apps then make (`activity`) |

## Setup
- Gravwell up (Lab 00), Lab 02 data already ingested (this lab pivots back to it).
- Ingest the four new files (timestamps are extracted; set the time range to **last 48 hours**, as in Lab 02):
  ```bash
  cd ~/jarvis/datasets/shadow-ai-sources/generated
  nc -q1 localhost ${WORKSHOPUID}11 < osquery_results.jsonl
  nc -q1 localhost ${WORKSHOPUID}12 < swg_access.jsonl
  nc -q1 localhost ${WORKSHOPUID}13 < cloudtrail_events.jsonl
  nc -q1 localhost ${WORKSHOPUID}14 < gws_token_audit.jsonl
  ```
- Upload two more lookup resources (Lab 02's `AI_DOMAINS_PLUS_API` is reused too):
  ```bash
  cd ~/jarvis
  ./labs/02-shadow-ai/upload-resource.sh AI_SOFTWARE     datasets/resources/ai_software.txt
  ./labs/02-shadow-ai/upload-resource.sh SANCTIONED_APPS datasets/resources/sanctioned_apps.txt
  ```
  `AI_SOFTWARE` has columns `Name,Kind`: names of AI processes, packages, apps and extensions as
  inventory tools report them. `SANCTIONED_APPS` has `App,Owner`: the OAuth apps IT approved.

> Struggling with syntax? Ask for the **cheatsheet**: every query in this lab is written out there.
> The reasoning is the lab, not the typing.

### Field guide

| Tag | Extract with | Fields you'll need |
|---|---|---|
| `osquery` | `json` | `hostIdentifier`, `name` (the query), `columns.name`, `columns.port`, `columns.address`, `columns.cmdline`, `columns.permissions` |
| `swg` | `json` | `user`, `host`, `url`, `method`, `reqsize`, `useragent`, `urlcategory`, `action`, `filename`, `src_ip` |
| `cloudtrail` | `json` | `eventSource`, `eventName`, `userIdentity.arn`, `sourceIPAddress`, `errorCode`, `requestParameters.modelId`, `requestParameters.policyArn`, `requestParameters.roleName` |
| `gws` | `json` | `event_name`, `actor_email`, `app_name`, `scopes`, `ipAddress`, `api_name`, `num_response_bytes` |

Nested paths are **unquoted** (`json columns.name as software`, `json userIdentity.arn as who`).
New tricks: `grep -v -e <field> <text>` keeps rows that *don't* match; `lookup -v -r <RES> ...`
keeps rows *not* in the list; `grep -e <field> a b c` matches any of several values.

---

## Part A: Endpoint inventory (`tag=osquery`)

1. **What AI software is installed anywhere?** Match `columns.name` against `AI_SOFTWARE` (pull
   `Kind` along: `lookup -s -r AI_SOFTWARE software Name Kind as kind`), count by host. **One host
   on this list was completely benign in Lab 02.** Which, what's on it, and why did every network
   method miss it? *Hint: where does a model have to be for its traffic to never cross a sensor?*
2. **Which hosts are serving a model?** From the `listening_ports` rows, list process / port /
   bind address. Two hosts run inference servers. **Which one is reachable from the rest of the
   LAN, and which is not?** *Hint: `0.0.0.0` vs `127.0.0.1`.* Compare with what Lab 02 Method 3 saw.
3. **Explain two Lab 02 mysteries from the endpoint.** (a) `eng-lt-190` was invisible to DNS:
   find the process on it that explains why, and read its `cmdline`. (b) `hr-lt-140` resolved four
   AI names and connected to none: find the browser extension responsible and read its
   `permissions`. Is (b) still "not usage"?

## Part B: The web gateway (`tag=swg`)

4. **Put names on Lab 02's IPs.** Match `host` against `AI_DOMAINS_PLUS_API`, count by `user`,
   `host`, `action`. Which Lab 02 hosts now have a person attached, and what did the proxy
   **block**?
5. **What files left?** `POST`s with `reqsize` over a megabyte. For each: who, to where, filename,
   allowed or blocked. **Two files, two users, one policy: why did the policy stop one and not the
   other?** *Hint: look at `urlcategory`. What is the policy keyed on?*
6. **People or programs?** For traffic to AI hosts, keep rows whose `useragent` does **not**
   contain `Mozilla`. Who is it, and what is actually making the requests?
7. **Find an AI conversation without a domain list.** Take every `POST`, then per `user` + `url`
   compute `count`, `min(reqsize)`, `max(reqsize)`; keep groups with more than 5 requests, and
   build `growth = max / min` (`eval growth = biggest / first`). Sort by growth. **What
   is at the top, and why does its request size climb turn after turn?** *Hint: Lab 01, Task 4.
   Then look at the same URL over time.* Would any domain list ever contain this host?
8. **Who is missing?** A compound query, like Lab 02's correlation query: the inner `@swg_ai { … }`
   builds the set of AI-talking `src_ip`s the proxy saw; the main query takes the AI-talking hosts
   from `tag=corelight_ssl` and keeps the ones **not** in that set (`lookup -s -v -r @swg_ai
   src_ip src_ip ()`: `-v` inverts, `()` extracts nothing). Two Lab 02 hosts, including the day's
   biggest upload, never appear in the proxy log at all. **Why?** *Hint: which subnet are they on,
   and what does the proxy cover?*

## Part C: Your own cloud account (`tag=cloudtrail`)

9. **Who is calling a model service?** Filter `eventSource` for `bedrock`, count by
   `userIdentity.arn`, `eventName`, `errorCode`. Three identities. **Which is a person, which is a
   machine, and which never succeeded?**
10. **The enablement chain.** Find `ConsoleLogin`, `PutUseCaseForModelAccess`,
    `CreateFoundationModelAgreement`, `PutFoundationModelEntitlement` and `AttachRolePolicy` and
    table them with `roleName`, `policyArn`, `modelId` and time. **Who did what, in what order, and
    how many minutes passed** between the first click and a production role gaining model access?
    Now find the first `InvokeModel` from that role (`min(TIMESTAMP)` by identity + `modelId`). How
    long after the policy landed? **Which Lab 02 person is this, and what else do they run?**
11. **Intent.** Table the `AccessDenied*` rows: who, which model, which user agent. Nothing
    happened: is it a finding? *(Cross-reference Part A.)*
12. **Read the fine print.** Look at `eventCategory` on the `InvokeModel` rows versus the
    `AttachRolePolicy` row. **Which of these would you have if you turned on CloudTrail with the
    defaults?**

## Part D: SaaS consent (`tag=gws`)

13. **Who authorized what?** `event_name == authorize`: table `actor_email`, `app_name`, `scopes`,
    `ipAddress`. Now drop the apps IT approved (`lookup -v -r SANCTIONED_APPS app_name App`). **Two
    consents remain.** Which scopes did each grant, and from what kind of IP address?
14. **What did the apps then do?** `event_name == activity`: `sum(num_response_bytes)` and count by
    `actor_email`, `app_name`, sorted. **How much data did the top app pull, through which API, in
    how long?** Look at `ipAddress` on those rows.
15. **Go back to Lab 02.** Find this user's host in `tag=corelight_dns` / `corelight_ssl` /
    `corelight_conn` and in `tag=swg`. **What did every one of those sources conclude about this
    host: and how many bytes of the exposure you just measured did any of them see?**

## Part E: Synthesis (10 min, on paper)

Fill in the matrix. One row per Lab 02 host; one column per source (`dns`, `ssl`, `conn`, `http`,
`okta`, `osquery`, `swg`, `cloudtrail`, `gws`). Mark each cell **seen / cleared / blind**, *blind*
meaning the source structurally cannot see that activity, not merely that it didn't. Then answer:

- Which host has the **most** blind cells and still turned out to be the day's biggest exposure?
- Which two hosts are blind in *every* network column?
- Which finding needed exactly **two** sources to be actionable, and which two?

Write your matrix down. It is the shape of the collection plan you'd take back to work; the
take-home version is `materials/shadow-ai-detection-matrix.md`.

## About the data
The four files are generated with the same cast and the same day as Lab 02. Formats are real
(osquery result log, CloudTrail record, Workspace Reports `token` activity, a Zscaler-style SWG
feed); the Workspace `parameters[]` array is also flattened to top-level fields the way Lab 02's
Okta records are. In a classroom the data is regenerated for you before the day starts.

> **Running this self-driven?** Regenerate before ingesting so the timestamps land in the search
> window: `cd src/log-generator && python3 generate_shadow_ai_sources.py --seed 1 --outdir ../../datasets/shadow-ai-sources/generated`
> (Lab 02's data must be regenerated in the same sitting so the two line up).

## Checkpoint: if you get lost
```bash
cd ~/jarvis && git checkout stage-shadowai-sources -- labs/_stretch/shadow-ai-sources
```
Restores this lab's files in place; nothing else is touched. Ask an instructor if you're unsure.

## Discussion
- A domain list is a **known-provider** detector. Everything in this lab that mattered, the
  local model, the SaaS AI feature, the cloud service, the OAuth grant, is off-list by nature.
  Hunt those by *shape*: ports, paths, request-size growth, event sources, scopes.
- Identity is the pivot: IP → host → user → cloud principal → OAuth client. Each source added one hop.
- The two places you saw **data** move (the proxy upload and the Workspace `activity` bytes) are the
  two places your network sensor had **nothing**. Where does your collection plan need to go?
- Denials and enablements come *before* usage. They are the earliest, cheapest warning you get.
