# Lab 02: Shadow-AI from network logs

## Objective
Hunt shadow/unsanctioned AI usage in Corelight/Zeek logs, and learn to **correlate** across logs so
a DNS lookup alone isn't mistaken for real usage. The dataset is built so each single method is
wrong in a different way and only correlation gets the right answer.

## Background
Every method here is a *visibility signal*, not proof. A host can resolve an AI domain and never use
it; it can use AI with no DNS you can see (DoH) or no TLS you can parse (QUIC); a non-AI site can
share an IP with one. The skill is combining signals.

## Setup
- (Pre-requisite) Gravwell up (Lab 00, `stage-gravwell`).
- Ingest the generated data (Lab 00 listeners; timestamps are extracted: set the time range to **last 48 hours**, not the default. The scenario is the previous UTC business day, so "last 24 hours" loses the morning):
  ```bash
  cd ~/jarvis/datasets/corelight/generated
  nc -q1 localhost ${WORKSHOPUID}01 < corelight_dns.jsonl
  nc -q1 localhost ${WORKSHOPUID}02 < corelight_ssl.jsonl
  nc -q1 localhost ${WORKSHOPUID}03 < corelight_conn.jsonl
  nc -q1 localhost ${WORKSHOPUID}04 < corelight_http.jsonl
  nc -q1 localhost ${WORKSHOPUID}06 < okta_access.jsonl
  ```
> **Struggling with the terminal or the query syntax?** Ask for the **Terminal & Query
> Cheatsheet** (`materials/terminal-cheatsheet.md`): it has every command and query for this lab
> written out. Using it is not cheating; the point of the lab is the reasoning, not the typing.

## First, a ten-minute Gravwell detour: raw data, kits, and charts

Before hunting anything, prove the data landed and learn three things about the tool you will use
for the rest of the course. In Query Studio, time range **last 48 hours**:

```
tag=corelight_conn
```

You should see a few hundred entries, each one a raw JSON record exactly as Corelight wrote it.
**That rawness is the best thing about this data.** Nothing has been normalised, translated into a
"common schema", or thrown away on the way in; every field the sensor emitted is still there, so
every question you have not thought of yet can still be answered. Gravwell parses at *query* time,
so if you want OCSF-shaped output you ask for it in the query and keep the original too. Pipelines
that normalise on ingest decide for you, once, forever, what you are allowed to ask.

Now get the parsing for free. Gravwell **kits** package searches, dashboards and field extractors for
a data source. In the left navigation open **Kits**, browse the kit server, find **Gravwell
Corelight** and install it (it pulls in one dependency, the network-enrichment resources; say yes).
It takes about a minute. Then:

```
tag=corelight_conn ax | table
```

Same raw records, now presented as a table with every field as a column (`ts`, `id.orig_h`,
`id.resp_h`, `proto`, `service`, `orig_bytes`, `conn_state`, …). `ax` is the **autoextractor**: the
kit told Gravwell how these records are shaped, so you no longer have to spell out `json "id.orig_h"
as src_ip` yourself. The raw data did not change; only the presentation did. (Every query later in
this lab still works with the explicit `json` module, and the cheatsheet uses that form so it works
with or without the kit.)

Third thing: a chart.

```
tag=corelight_conn ax
| alias "id.orig_h" srcip
| count by srcip
| chart count by srcip
```

That renders a time series: connections per source host over the day. Useful for *when*, less so
for *who*. Click the **gear** on the right of the results (visualization options) and switch the
chart type to **pie**. Now it is a top-talkers chart, and one host is a much bigger slice than the
rest. Remember its address; you will meet it again at the end of this lab, from a different angle.

The kit also installed two dozen Corelight dashboards (**Dashboards** in the left nav). Look at one.
Everything on it is a saved query over this same raw data.

- Upload the two lookup files as Gravwell **resources**. Methods 1, 2 and 4 and the correlation
  query all fail without them.

  **In the UI:** *Resources* (left nav) → **Add resource** → name it exactly `AI_DOMAINS` → upload
  `~/jarvis/datasets/resources/ai_domains.txt`. Repeat with `AI_DOMAINS_PLUS_API` and
  `ai_domains_plus_api.txt`.

  **Or from the shell** (a helper is provided, because it is a two-step API call):
  ```bash
  cd ~/jarvis
  ./labs/02-shadow-ai/upload-resource.sh AI_DOMAINS          datasets/resources/ai_domains.txt
  ./labs/02-shadow-ai/upload-resource.sh AI_DOMAINS_PLUS_API datasets/resources/ai_domains_plus_api.txt
  ```
  The names must match exactly, the searches reference them. `AI_DOMAINS` is a browser-facing
  blocklist that does **not** contain provider API hosts; `AI_DOMAINS_PLUS_API` adds them. Which
  method uses which list changes what you find, and that is not an accident.

  **Where the list came from:** `ai_domains.txt` is the `noai_hosts.txt` file of the open-source
  **uBlock Origin HUGE AI Blocklist**, <https://github.com/laylavish/uBlockOrigin-HUGE-AI-Blocklist>,
  reformatted as a one-column CSV with a `Domain` header. Refresh it the same way at work; the
  reformatting recipe is one `curl | sed` line in `src/log-generator/README.md`. It is a
  browser-blocking list by design, which is exactly why it lacks the API hosts.

## The four hunt data sources

Each method looks at a different log and answers a different question. The shape is always the
same: *extract fields → match against the AI-domain list → count by host*. The first two are
written out for you; read them left to right, run them, then build 3 and 4 by changing what you
extract and what you match against.

**Method 1: DNS.** Who *asked* about an AI domain?
```
tag=corelight_dns json "id.orig_h" as src_ip query
| lookup -s -r AI_DOMAINS query Domain
| count by src_ip query
| table src_ip query count
```
Line by line: pick the tag; pull two fields out of the JSON (`id.orig_h` needs quotes because the
key really contains a dot, and we rename it `src_ip`); keep only rows whose `query` is in the
`AI_DOMAINS` resource (`-s` means *strict*: drop non-matches); count per host and domain; render.

**Method 2: TLS SNI.** Who actually *connected*, and to which server name?
```
tag=corelight_ssl json "id.orig_h" as src_ip "id.resp_h" as dst_ip server_name
| lookup -s -r AI_DOMAINS_PLUS_API server_name Domain
| count by src_ip server_name
| table src_ip server_name count
```
Same shape, different log, different field to match, and a different list (this one includes the
provider API hosts).

Now yours:

| # | Log | Field(s) that matter | Lookup to use |
|---|---|---|---|
| 3 | `tag=corelight_http` | `id.orig_h`, `host`, `uri`, `method` | *(none: look at what you get)* |
| 4 | `tag=okta` | `application_hostname`, `client_ip`, `actor.alternateId` | `AI_DOMAINS_PLUS_API` |

> ⚠️ **Quoting matters in the `json` module.** Quote a field name only when the key *literally
> contains a dot*: Zeek does that (`json "id.orig_h" as src_ip`). Okta nests instead
> (`{"actor":{"alternateId":…}}`), so the path must be **unquoted**: `json actor.alternateId as
> user`. Quoting a nested path returns an empty column with no error.

You have every module you need in Methods 1 and 2. Method 3 has no list to match, so drop the
`lookup` and just look at what hosts and paths come back. Method 4 changes the tag and the fields.

> **Note the two different lookups.** `AI_DOMAINS` is a browser-facing blocklist, it does **not**
> contain provider API hosts like `api.anthropic.com`. `AI_DOMAINS_PLUS_API` adds them. Which
> method you point at which list changes what you find, and that is not an accident.

## The correlation query: DNS joined to connections (the whole point)

Any single method above produces false positives. The question that doesn't is:

> **Did this host connect to an IP that *this same host* resolved as an AI domain, and move bytes?**

That needs two data sources in one answer. Gravwell does it with a **compound query**: an inner
query in `@name { … }` builds a temporary table, and the main query after the `;` uses it like a
resource. Here it is; read the inner query first, then the main one:

```
@ai_resolved {
  tag=corelight_dns json "id.orig_h" as src_ip query answers
  | lookup -s -r AI_DOMAINS_PLUS_API query Domain
  | regex -e answers "(?P<ip>\d+\.\d+\.\d+\.\d+)"
  | table src_ip ip query
};
tag=corelight_conn json "id.orig_h" as src_ip "id.resp_h" as dst_ip orig_bytes resp_bytes service
| lookup -s -r @ai_resolved [src_ip dst_ip] [src_ip ip] (query)
| stats count sum(orig_bytes) as up sum(resp_bytes) as down by src_ip query service
| table src_ip query service count up down
```

What is new here:

| Piece | What it does |
|---|---|
| `@ai_resolved { … };` | an inner query whose `table` becomes a temporary resource named `@ai_resolved`, gone when the query ends |
| `regex -e answers "(?P<ip>…)"` | pulls the answer IP out of the DNS `answers` array into a new field `ip` |
| `lookup … [src_ip dst_ip] [src_ip ip]` | a **vectored** match: this row's `src_ip` **and** `dst_ip` must equal a row's `src_ip` **and** `ip` in the table, both at once |
| `(query)` | on a match, also pull the `query` column (the AI domain) into the row |
| `-s` | strict: rows with no match are dropped |

One query, two logs, no intermediate resources to save and wait for. From here on the handout calls
this **the correlation query**. (The older two-search form, `table -save NAME` in one search and
`lookup -r NAME` in the next, still works and is what the saved-resource menu does for you; the
compound form is what you want when the answer needs both.)

## Tasks (outcome-oriented)

**Before the tasks.** You should now have four searches that return rows: the DNS query (Method 1)
and the SNI query (Method 2) exactly as written above, your own HTTP query (Method 3: no lookup,
just hosts, ports and URI paths), and the correlation query from the previous section. If any of
them returns nothing, fix that first: check that the time range is **last 48 hours** and that both
resources uploaded. Every task below starts from one of those four searches; the task tells you
which, and what to change.

Write down your answers: you will need some of them again in Lab 03.

1. **Start from the DNS query.** Change `count by src_ip query` to
   `stats unique_count(query) as domains by src_ip`, and fix the `table` line to match. **Which host
   resolved the most _different_ AI domains?** (Distinct domains per host, not total queries: the
   loudest host by total and the loudest by distinct domains are different machines, and that
   difference is itself worth a moment.) Now look for your answer in the SNI results. It is not
   there. *Hint: one host resolves an implausible number of AI domains, all at once, in the middle
   of the night, and connects to none of them. What kind of machine does that?*
2. **Start from the correlation query.** Its output is the list of hosts that moved bytes to an IP
   they themselves resolved as an AI domain. **Write down those hosts.** This is the most trustworthy
   list in the lab, and it still **misses two hosts that really are using AI.** Tasks 3–6 find
   them. Which two, and why they are invisible, is the actual lesson.
3. One host in the correlation results has `service=quic` and **never appears in the SNI
   results**. **Why is it invisible to SNI?** *Hint: what does the SNI query read, and does that
   field exist for this protocol?*
4. One host in the correlation results reaches `api.anthropic.com` but is **absent from the DNS
   results entirely**. **How is it resolving names?** *Hint: look at the one DNS query it did
   make.*
5. `legal-lt-77` connects to `104.18.32.47`: the same address `chatgpt.com` resolves to. **Is this
   AI usage?** Check its SNI, and check whether *it* ever resolved chatgpt.com. *Hint: how many
   different sites can share one CDN address?*
6. Your HTTP query (Method 3) finds a host no domain list ever could. **What is `dev-vm-51`
   running, and why can't the DNS and SNI queries see it?** *Hint: look at the ports and the URI
   paths.*
7. **Volume and time.** Find the largest single upload of the day, `max(orig_bytes) by src_ip`.
   **Who, when, and to where?** Does the hour tell you anything?
8. **Find the incident.** One host's traffic doesn't look like a person using a chatbot: a tight
   burst of connections to a provider API, `orig_bytes` far exceeding `resp_bytes`, plus failed
   connections to an address that isn't a provider at all. **Which host, and what time window?**
   *Hint: `169.254.169.254` is not on the internet.*
   **Write the host and the window down.** You will meet this same eight minutes again in Lab 03,
   from a completely different log source.

## About the data
The five files are generated: the record formats are real Zeek/Corelight and Okta, the scenario is
planted, and every timestamp sits in the previous UTC business day, which is why the labs say
**last 48 hours**. In a classroom the data is regenerated for you before the day starts; there is
nothing you need to do. A real Corelight sample for schema reference is in
`datasets/corelight/real-sample-corelight-ai-events.json`.

> **Running this workshop self-driven from the public repo?** Regenerate the data first so the
> timestamps land inside the search window, then re-ingest:
> `cd src/log-generator && python3 generate_corelight_logs.py --seed 1 --outdir ../../datasets/corelight/generated`
> (see `src/log-generator/README.md` for the Sysmon and other outputs).

If your class runs the optional **Shadow AI beyond the wire** lab, these same fourteen hosts come
back through four more log sources, keep your notes.

## Checkpoint: if you get lost
Every lab has a **known-good snapshot** you can restore without losing anything you've done:

```bash
cd ~/jarvis && git checkout stage-shadowai -- labs/02-shadow-ai
```

That overwrites the lab's files with the working versions and leaves you exactly where you are,
no branch switching, no detached HEAD, nothing else touched. Ask an instructor if you're unsure.
