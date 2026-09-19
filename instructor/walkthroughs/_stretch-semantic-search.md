# Walkthrough: P3: Semantic search over LLM logs

> ⛔ **INSTRUCTOR ONLY.** Student handout:
> [`labs/_stretch/semantic-search/README.md`](../../labs/_stretch/semantic-search/README.md).

**Padding module P3** · **20–30 min as a demo** · insert after M9 or M12 · **Flex:** optional
**Deck:** [`slides/05b-semantic-search.md`](../../slides/05b-semantic-search.md): embeddings recap, the
two halves, gotchas, a "Live demo" kick slide, then the measured results below as backup slides for
when the stack is down or someone runs the course self-driven.
**Scores below are from the lab host's embedding model**; they shift if the model changes.

## Demo runbook, in order

1. **Before the session** (the night before is fine; ~3 min), as root on the lab host:
   `enable-semantic.sh up`, then `enable-semantic.sh seed`. Leave the stack up.
2. **Check it took**: log in at `https://<lab-host>:39443` (`admin`/`changeme`), time
   range last 24 hours, run query 1 below. You want 10 embedded entries. If you get 0, the seed
   ran before the ingester was hot: run `seed` again.
3. **In the room**: open the deck `slides/05b-semantic-search.md` (also `slides/05b-semantic-search.pdf`
   on the share site). Slides 1 to 6 are talk. At the **Live demo** slide switch to the browser
   and run queries 2 to 5 below, in that order; the straw-man greps come first.
4. **If the stack is down or the room has no network**: keep going in the deck. Slides 7 to 10 are
   those same queries with their measured output.
5. **After**: `enable-semantic.sh down` when the module is finished for the delivery (it holds a
   copy of the model token in `/opt/workshop/semantic-demo/`, `chmod 600`).

## Why this is a demo and not a seat lab

Two components need an embeddings model, and both would need the Gravwell LLM token:

| Component | Needs embeddings for | Config |
|---|---|---|
| **LLM ingester** | embedding each entry at ingest | `vector` preprocessor on the listener |
| **Gravwell webserver** | embedding the **search phrase** | `[AI]` block in `gravwell.conf.d/` |

Seats never receive that token: they reach the model through a loopback-only relay, and
`llm_relay.py` **refuses to bind anything but 127.0.0.1** because it holds a credential. A container
cannot reach the host's loopback. So P3 runs on an instructor stack.

That guard is deliberate; don't route around it to make P3 hands-on. If you ever want per-seat
semantic search, the honest options are a relay reachable on a shared docker network (which means
relaxing that bind guard behind an explicit flag) or giving seats a token of their own.

## Setup: one command, run it before the session

```bash
/opt/workshop/src/instructor/runbook/scripts/enable-semantic.sh up     # ~2 min
/opt/workshop/src/instructor/runbook/scripts/enable-semantic.sh seed  # 8 prompts via the ingester
```

Stack lands on seat id **39**, UI `https://<lab-host>:39443`, `admin`/`changeme`.
Tear down with `enable-semantic.sh down`. The script writes the token into two config files and
`chmod 600`s them; they live in `/opt/workshop/semantic-demo/`, not in the repo.

The seed set is eight deliberately spread prompts: two about storage, one database, one password
reset, one leaked API key, one "copy the customer table to an external host", one sourdough recipe,
one about travel in Italy.

## Run it on the projector

### 1. Show that the vectors exist

```
tag=llm intrinsic embeddings event_type | eval len(embeddings) > 0
| count by event_type | table event_type count
```

**Measured:** `request.user_message` 5, `response.assistant_message` 5, **10 of 15 entries**. Usage
and system records have no text, so the preprocessor passes them through unembedded. Worth saying
out loud: *only the content-bearing events get embedded, which is exactly what you want to pay for.*

### 2. The keyword straw man: do this first

```
tag=llm grep "leaked"      →  0 rows
tag=llm grep "credential"  →  0 rows
```

Ask the room: *"so nobody has asked our AI about credentials, right?"*

### 3. Then the same question, semantically

```
tag=llm intrinsic embeddings | semantic -t 45 "someone leaked a credential"
| sort by score desc | table score DATA
```

**Measured: 7 rows, top three:**

| Score | Entry |
|---|---|
| **0.72** | "I accidentally committed an API key to a public git repository, what now?" |
| 0.57 | "How do I reset a forgotten password for a user account?" |
| 0.51 | the model's reply listing immediate actions |

*Beat:* **not one word of the query appears in the top hit.** No "leaked", no "credential". That is
the entire pitch for this module, and it takes ten seconds to land.

### 4. A second example, because one could be luck

```
semantic -t 45 "running out of storage"
```

**Measured:** 0.80 *"The storage volume is completely full, how do I free space?"* · 0.69 *"My laptop
has run out of disk space and will not boot."* · 0.58 the model's own answer.

Two different phrasings of the same problem, plus the reply, none sharing the query's wording.

### 5. Now break it: this is what makes the module credible

```
semantic -t 0 "planning a trip" | sort by score desc | table score DATA
```

**Measured:** the top hit is **the wrong entry**, *"My laptop has run out of disk space"* at
**0.398**: and the actual travel prompt is *fourth* at 0.385. Everything is bunched at 0.38–0.40.

Then show the fix:

| Query | Top result | Score |
|---|---|---|
| `"planning a trip"` | wrong entry | 0.40 |
| `"travel recommendations for autumn"` | the travel prompt | 0.59 |
| `"quiet places to visit in Italy"` | the travel prompt | **0.72** |

*Beat:* below about **0.5** on this model the scores bunch and the ranking is noise, not weak
matches. Short abstract queries do badly; queries phrased like the content do well. **Calibrate with
`-t 0`, look at where relevance falls off, then set the threshold**, and the number is a property
of your embedding model, not something to copy from a slide.

Do not skip this step. A demo that only shows the wins teaches people to trust a tool that will
quietly fail on them.

## Discussion: three things worth landing

1. **Cost and latency are real.** Every embedded entry is an API call to your model host. Embedding
   all LLM traffic is a bill and an ingest-latency decision, which is why
   `Passthrough-On-Error=true` matters: it keeps ingest flowing when the endpoint is slow.
2. **You have just made a second copy of every prompt**, as vectors, in your SIEM. That is the
   point, and it belongs in the retention conversation.
3. **Narrow first, then search by meaning.** Filter by tag, time and user, then semantic-search the
   survivors. It is cheaper and the ranking is more meaningful over a smaller set.

## Answer key

| Q | Answer |
|---|---|
| Entries embedded | 10 of 15, only `request.user_message` and `response.assistant_message` |
| Why the rest aren't | No text payload; the preprocessor passes them through untouched |
| `grep "leaked"` / `"credential"` | **0 rows each** |
| `semantic -t 45 "someone leaked a credential"` | 7 rows, top 0.72 on the API-key prompt |
| Best storage hit | 0.80 |
| Noise floor on `qwen3-embedding` | ~0.5; below it the ranking is meaningless |
| Both halves required? | Yes: preprocessor **and** `[AI]`, configured in different places |

## Where it goes wrong

- **Only one half configured.** Preprocessor but no `[AI]` → `semantic` cannot embed your phrase.
  `[AI]` but no preprocessor → `intrinsic embeddings` yields nothing to compare against.
- **Threshold left at the default 75.** With this model almost nothing clears it; the room concludes
  the feature is broken. Demo at `-t 45` and explain why.
- **Forgetting `intrinsic embeddings`.** `semantic` has no vectors to read and returns nothing.
