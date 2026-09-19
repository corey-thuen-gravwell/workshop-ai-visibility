---
marp: true
theme: jarvis
paginate: true
header: 'Exploring AI Visibility · Shadow AI beyond the wire'
---

<!-- _class: lead -->
# Shadow AI beyond the wire
## Same fourteen hosts. Four more logs.

<!--
Lab 02 ended with "we can enumerate hosts that probably used AI." This module widens the frame: the network is one view. We look at the same day through the logs the sensor doesn't have.
-->

---

## Five shapes of shadow AI

| Shape | Example | Network sees… |
|---|---|---|
| A person in a browser | ChatGPT, Copilot | DNS + SNI ✔ |
| An agent in a terminal | opencode, SDK scripts | API SNI ✔ (if not DoH) |
| **A model on the laptop** | LM Studio, ollama | **nothing** |
| **AI inside a sanctioned SaaS** | Notion AI, Slack AI | a sanctioned domain |
| **AI in your own cloud account** | Bedrock, Vertex | **nothing** |
| **A SaaS integration reading your data** | OAuth'd "ChatGPT" connector | **nothing** |

<!-- Lab 02 covered the first two. The rest are structurally invisible to a network sensor, not "hard", invisible. -->

---

## Four more sources

| Tag | Source | Adds |
|---|---|---|
| `osquery` | Endpoint inventory | what's **installed and listening**, regardless of traffic |
| `swg` | Identity-aware proxy w/ TLS inspection | **who**, full URL, sizes, files, allow/block |
| `cloudtrail` | Cloud audit | which **identity** invoked which model, and who enabled it |
| `gws` | Workspace token audit | OAuth **consents** and the API calls the app then makes |

Same cast as Lab 02. The exercise is joining them.

---

## Inventory beats blocklists for the long tail

```
tag=osquery json hostIdentifier columns.name as software
| lookup -s -r AI_SOFTWARE software Name Kind as kind
| count by hostIdentifier software kind
```

- A list of **software names** (processes, packages, extensions), not domains
- `listening_ports` + bind address: `0.0.0.0:11434` is an exposure, `127.0.0.1:1234` is a policy question
- Explains Lab 02's blind spots from the other side: `cloudflared proxy-dns`, an `<all_urls>` extension

<!-- The host that was benign in every Lab 02 method is running a local model. Zero network signal ≠ zero AI. -->

---

## The proxy: identity, files, and shape

- **Who**: `user`, not `src_ip`
- **What left**: `POST` + `reqsize` + `filename`, and whether policy stopped it
- **People or programs**: `useragent` without `Mozilla`
- **The conversation shape**: no list required

```
tag=swg json user url method reqsize | grep -e method POST
| stats count min(reqsize) as first max(reqsize) as biggest by user url
| eval count > 5 | eval growth = biggest / first | sort by growth desc
```

<!-- Lab 01 Task 4 seen from the outside: the client re-sends the transcript every turn, so request size climbs. That's how you find Notion AI: you will never block notion.so. -->

---

## Category controls end at the category

Same policy: *block uploads to "AI & ML Applications."*

| | Category | Result |
|---|---|---|
| `Q3-pipeline-forecast.xlsx` → chatgpt.com | AI & ML | **Blocked** |
| `ACME-Q3-customer-pipeline.csv` → notion.so `/runInferenceTranscript` | Productivity | **Allowed** |

And the proxy never saw the CI runner's 48 MB, the rogue agent, or the QUIC user at all.

<!-- Servers bypass the proxy; UDP/443 isn't proxied. Your proxy's blind spots are your biggest upload and your rogue agent. -->

---

## Your own cloud account

```
tag=cloudtrail json eventSource eventName userIdentity.arn as who errorCode
| grep -e eventSource bedrock | count by who eventName errorCode
```

- A **person** enables a model and attaches `AmazonBedrockFullAccess` to a prod role, 9 minutes
- A **machine** starts invoking it 11 minutes later, from inside the VPC
- Someone else is **denied** three times, intent

`InvokeModel` is a **data event**. Default CloudTrail shows you the enablement and none of the usage.

---

## The one the network can never see

```
tag=gws json event_name actor_email app_name scopes ipAddress | grep -e event_name authorize
| lookup -v -r SANCTIONED_APPS app_name App
```

An HR user consents to "ChatGPT" with `drive.readonly` + `gmail.readonly`, **from a phone**.

```
tag=gws json event_name actor_email app_name num_response_bytes | grep -e event_name activity
| stats sum(num_response_bytes) as bytes count by actor_email app_name | sort by bytes desc
```

**≈505 MB in 70 minutes, `SERVER_TO_SERVER`.** Lab 02 cleared this host as DNS-only. It was right.

<!-- This is the slide the module exists for. The data moved Google → OpenAI. Not one byte crossed the corporate network. -->

---

## Fill the matrix

Host × source · **seen / cleared / blind**

- *Blind* = the source **structurally cannot** see it, not "didn't"
- The host with the most blind cells was the biggest exposure
- Two hosts are blind in every network column
- Two findings needed exactly two sources

> Correlate, don't grep · inventory for the long tail · identity is the pivot · look where the **data** actually leaves · log the failures and the enablements

<!-- Hand out materials/shadow-ai-detection-matrix.md here. -->

---

<!-- _class: lead -->
# Lab: Shadow AI beyond the wire
## Ingest four sources, pivot on the Lab 02 cast, fill the matrix

<span class="muted">`git checkout stage-shadowai-sources -- labs/_stretch/shadow-ai-sources`</span>
