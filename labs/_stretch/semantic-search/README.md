# Semantic search over LLM logs
**Padding module P3.** Instructor-led demonstration, plus the config to take home.

## What you're about to see

Every prompt and reply your proxy captured is text. Text search finds what you can spell. The
question a security team actually asks is *"has anyone asked our AI about credentials?"*, and
nobody phrases it the way the prompt was phrased.

Gravwell can embed each log entry as it arrives and then search those entries **by meaning**.

## Why you're watching rather than typing

Two components need an embeddings model: the **ingester** (to embed each entry at ingest) and the
**webserver** (to embed your search phrase at query time). Both need a credential for that model,
and the workshop's model token deliberately never reaches your seat. So this runs on the
instructor's stack. Everything below is what you'd configure at home.

## The two halves

**1. Embed at ingest**, a `vector` preprocessor on the ingester, attached to the listener:

```
[Listener "anthropic"]
	...
	Preprocessor=embed

[Preprocessor "embed"]
	Type=vector
	Model=qwen3-embedding
	Endpoint=https://your-model-host/v1/embeddings
	Token=...
	Timeout=60
	Passthrough-On-Error=true
```

Each entry gains an `embeddings` enumerated value. Entries with no text, token-usage records,
empty payloads: pass through unembedded, which is why only `request.user_message` and
`response.assistant_message` end up searchable.

**2. Embed the query**, an `[AI]` block on the webserver, so `semantic` can vectorise your phrase:

```
[AI]
	Embedding-URL = "https://your-model-host/v1/embeddings"
	Embedding-Model = "qwen3-embedding"
	Embedding-Token = "..."
```

Both halves, or nothing works. They are configured in different places and it is easy to do one.

## The search

```
tag=llm intrinsic embeddings | semantic -t 45 "someone leaked a credential"
| sort by score desc | table score DATA
```

`intrinsic embeddings` loads the vectors; `semantic` compares your phrase against them and attaches
a cosine-similarity `score`. `-t` is a percentage cutoff (default 75).

## What to watch for

**It finds things keyword search cannot.** `grep "leaked"` and `grep "credential"` both return
nothing on the demo data. The semantic query returns the prompt *"I accidentally committed an API
key to a public git repository"*, no shared words at all.

**It is not magic, and your phrasing matters.** On the same data:

| Query | Top result | Score |
|---|---|---|
| `"quiet places to visit in Italy"` | the travel prompt | 0.72 |
| `"travel recommendations for autumn"` | the travel prompt | 0.59 |
| `"planning a trip"` | **the wrong entry** | 0.40 |

Short abstract phrases perform badly. Below roughly 0.5 the scores bunch together and the ranking
stops meaning anything: that band is noise, not weak matches.

**Calibrate before you trust it.** Run with `-t 0`, sort by score, look at where relevance actually
falls off, and set your threshold there. The right number depends on your embedding model, not on
this handout.

## Take it home

- Every entry embedded is one API call to your model host. Embedding *all* your LLM traffic costs
  real money and adds ingest latency: `Passthrough-On-Error=true` keeps ingest flowing when the
  endpoint is slow or down.
- Embeddings are a **derived copy of your prompts** sitting in your SIEM. That is the point, and it
  is also a thing to put in your data-retention conversation.
- The useful pairing is narrow-then-semantic: filter by tag, time and user first, then search the
  survivors by meaning.
