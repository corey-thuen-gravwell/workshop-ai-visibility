---
marp: true
theme: jarvis
paginate: true
header: 'Exploring AI Visibility · Semantic search over LLM logs'
---

<!-- _class: lead -->
# Search by meaning
## Semantic search over your LLM logs

<!--
P3, 20–30 min, instructor demo. Slot after M9 (Lab 05 Part 2a, the ingester) or after M12. Students
have just searched tag=llm by keyword; this deck shows the same data searched by meaning, on the
instructor stack (seat 39). Before the session: enable-semantic.sh up && enable-semantic.sh seed.
The deck carries measured results so it stands alone if the demo is unavailable.
Lab page: labs/_stretch/semantic-search (P3). Walkthrough: instructor/walkthroughs/_stretch-semantic-search.md.
-->

---

## The question text search cannot answer

*"Has anyone asked our AI about credentials?"*

```
tag=llm grep "credential"     →  0 rows
tag=llm grep "leaked"         →  0 rows
```

- Nobody phrases a prompt the way you phrase the question
- Keyword search finds what you can **spell**; the analyst's question is about **meaning**
- The prompt that matters read: *"I accidentally committed an API key to a public git repository, what now?"*

<!-- Straw man first, always. Ask the room: "so nobody has asked our AI about credentials, right?" Let them sit with the zero. -->

---

## Embeddings, in one slide (you met them in Lab 01b)

- An embedding is a **vector**: `"potato"` → `[0.0116, 0.0175, 0.0087, …]`, thousands of numbers
- A model turns any text into one; texts that **mean** similar things land **close together**
- Closeness is **cosine similarity**, high-school geometry, no model involved in the comparison

| In Lab 01b you measured | |
|---|---|
| `king` vs `queen` | **0.907** |
| `potato` vs `fries` | 0.737 |
| `firewall` vs `syslog` | 0.639 |

Whole sentences embed the same way as single words, which is what makes them searchable.

<!-- Callback to embed.bash / similar.bash. Same idea, bigger inputs: a whole prompt instead of one word. The numbers on the next slides are the same kind of number as 0.907. -->

---

## How Gravwell does it: two halves

| Where | What | Config |
|---|---|---|
| **Ingester** | embed each entry as it arrives; attach the vector as the `embeddings` enumerated value | `vector` preprocessor on the listener |
| **Webserver** | embed *your search phrase* at query time, compare against stored vectors | `[AI]` block: `Embedding-URL`, `Embedding-Model`, `Embedding-Token` |

```
tag=llm intrinsic embeddings | semantic -t 45 "someone leaked a credential"
| sort by score desc | table score DATA
```

`intrinsic embeddings` loads the stored vectors · `semantic` embeds the phrase and attaches a `score` · `-t` is the cutoff in percent (default **75**)

<!-- Both halves or nothing works, and they are configured in different places. The most common failure in the field is one half. Passthrough-On-Error=true on the preprocessor keeps ingest flowing when the embeddings endpoint is slow or down. -->

---

## Gotchas, part 1: the model

- **Same model, both halves, forever.** The query vector must come from the model that made the stored vectors. A different model (or a different dimension count) **fails the whole query**; `-p` only skips the entries it cannot score
- **Change the model, re-embed everything.** Stored vectors from the old model are worthless to the new one. That is a full re-ingest, not a config edit
- **Default threshold is 75.** On `qwen3-embedding` almost nothing clears it and the room decides the feature is broken. Demo at **45**; calibrate at **0** first

<!-- The model-change point is the one people get bitten by: the config looks right, the query fails or returns garbage, and the fix is a re-ingest. -->

---

## Gotchas, part 2: cost and data

- **Vectors are big and compared on the webserver.** 10–20 KB per entry, and every candidate is shipped to the webserver for scoring. **Narrow first** (tag, time, user), then search by meaning
- **Embedding is synchronous at ingest.** Throughput is bounded by your embeddings endpoint. Every entry is an API call: cost and latency are real. `Passthrough-On-Error=true` keeps ingest flowing when the endpoint is slow or down
- **You now hold a second copy of every prompt**, as vectors, in the SIEM. Put it in the retention conversation

---

<!-- _class: lead -->
# Live demo
## Instructor stack · `tag=llm` · eight seeded prompts

<!--
https://<lab-host>:39443, admin/changeme. Run, in order:
 1. tag=llm intrinsic embeddings event_type | eval len(embeddings) > 0 | count by event_type | table event_type count
 2. tag=llm grep "leaked"  and  tag=llm grep "credential"   (0 rows each)
 3. tag=llm intrinsic embeddings | semantic -t 45 "someone leaked a credential" | sort by score desc | table score DATA
 4. semantic -t 45 "running out of storage"
 5. semantic -t 0 "planning a trip"  then "travel recommendations for autumn" then "quiet places to visit in Italy"
If the stack is down or you are reading this self-driven, the next four slides are those results.
-->

---

## 1 · The vectors exist

```
tag=llm intrinsic embeddings event_type | eval len(embeddings) > 0
| count by event_type | table event_type count
```

| event_type | count |
|---|---|
| `request.user_message` | 5 |
| `response.assistant_message` | 5 |

**10 of 15 entries** carry a vector. Usage and system records have no text, so the preprocessor passes them through unembedded. You only pay to embed the content-bearing events.

<!-- Backup slide: measured on the instructor stack. Say out loud: only content-bearing events get embedded, which is exactly what you want to pay for. -->

---

## 2 · The same question, by meaning

```
tag=llm intrinsic embeddings | semantic -t 45 "someone leaked a credential"
| sort by score desc | table score DATA
```

| score | entry |
|---|---|
| **0.72** | "I accidentally committed an API key to a public git repository, what now?" |
| 0.57 | "How do I reset a forgotten password for a user account?" |
| 0.51 | the model's reply listing immediate actions |

**Not one word of the query appears in the top hit.** No "leaked", no "credential". Seven rows cleared the threshold; `grep` returned zero.

<!-- This is the whole pitch and it lands in ten seconds. -->

---

## 3 · A second example, because one could be luck

```
tag=llm intrinsic embeddings | semantic -t 45 "running out of storage"
| sort by score desc | table score DATA
```

| score | entry |
|---|---|
| **0.80** | "The storage volume is completely full, how do I free space?" |
| 0.69 | "My laptop has run out of disk space and will not boot." |
| 0.58 | the model's own answer |

Two phrasings of one problem, plus the reply, none sharing the query's wording.

---

## 4 · Now break it

```
tag=llm intrinsic embeddings | semantic -t 0 "planning a trip"
| sort by score desc | table score DATA
```

Top hit: **the wrong entry**, *"My laptop has run out of disk space"* at **0.398**. The travel prompt is fourth at 0.385. Everything sits between 0.38 and 0.40.

| Query | Top result | Score |
|---|---|---|
| `"planning a trip"` | wrong entry | 0.40 |
| `"travel recommendations for autumn"` | the travel prompt | 0.59 |
| `"quiet places to visit in Italy"` | the travel prompt | **0.72** |

<!-- Do not skip this. A demo that only shows wins teaches people to trust a tool that will quietly fail on them. Short abstract phrases do badly; phrases shaped like the content do well. -->

---

## Calibrate, then set the threshold

- Below about **0.5** on this model the scores bunch together and the ranking is **noise**, not weak matches
- Run with **`-t 0`**, sort by score, find where relevance actually falls off, set `-t` there
- The number is a property of **your embedding model**, not something to copy from a slide
- Phrase the query like the content you expect to find, not like the question in your head

---

## Take it home

```
# ingester: on the listener             # webserver: gravwell.conf.d/
[Preprocessor "embed"]                  [AI]
Type=vector                             Embedding-URL   = "https://host/v1/embeddings"
Model=qwen3-embedding                   Embedding-Model = "qwen3-embedding"
Endpoint=https://host/v1/embeddings     Embedding-Token = "..."
Token=...
Timeout=60
Passthrough-On-Error=true
```

- Narrow first, then search by meaning
- Budget the embeddings endpoint like any other ingest dependency
- Lab page: **Semantic search over LLM logs (P3)** on the share site, config included
- Docs: **docs.gravwell.io/search/semantic/semantic.html** · **docs.gravwell.io/ingesters/preprocessors/vector.html**

---

<!-- _class: lead -->
# Back to the labs

<!-- Hand back to wherever this was slotted: Lab 05 Part 2b (the vendor-agnostic proxy) if run after M9, or the wrap if run after M12. -->
