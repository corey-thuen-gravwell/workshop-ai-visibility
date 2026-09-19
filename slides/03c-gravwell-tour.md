---
marp: true
theme: jarvis
paginate: true
header: 'Exploring AI Visibility · Gravwell tour'
---

<!-- _class: lead -->
# Gravwell and this workshop
## A quick tour of the tool we're using to analyze data

<!--
M4b. Runs right after Lab 02, before M5/Lab C. Deliberately a debrief, not a
lecture: by now they have typed json, lookup (vectored), count by, stats, compound queries, regex, eval,
uploaded resources, installed a kit and fought the time picker, all by feel. This hour names what
they did and shows the rest of the room. Instructors are Gravwell experts: the middle of this deck
is ONE slide that says "go to the browser", drive the tour live, then come back.

Design decision: students HAVE Logbot on their seats, but we ask them not to lean on it. Writing
and hand-tweaking the lab queries is where the learning is. If someone is genuinely stuck building
a query, Logbot is a fine way out; say so, then send them back to typing.
-->

---

## What you already did in Lab 02

| You typed | What it is |
|---|---|
| `tag=corelight_dns` | pick a data source and a **time range** |
| `json "id.orig_h" as src_ip query` | **extract** fields from raw entries, at query time |
| `lookup -r AI_DOMAINS xxx yyy` | **enrich** against a resource you uploaded |
| `grep`, `eval` | **filter** |
| `count by`, `stats count` | **aggregate** |
| `table`, `chart` | **render** |
| `table -save` … `lookup -r` | build and use resources on the fly |

<!-- Re-read one Lab 02 query out loud, left to right. That is the whole mental model. -->

---

## Ingest raw data. Schema-on-query formats output

- Entries are stored **exactly as they arrived**. Nothing is normalised on the way in.
- Parsing happens **when you ask**: `json`, `xml`, `syslog`, `csv`, `regex`, `ax`
- So the question you have not thought of yet is still answerable
- Want OCSF, CIM, etc? Transform in the query AND keep the original.

<!-- The ingest-time-normalisation point from Lab 02's detour, stated once more in the abstract. Lab 03 is about to hit them with xml and Data[Name]== syntax; this is the setup. -->

---

## Fundamentals of Search - Module types

| Family | Modules you will meet |
|---|---|
| **Extract** | `json` `xml` `syslog` `csv` `regex` `ax` `intrinsic` |
| **Process / Filter** | `grep` `eval` `lookup -v` |
| **Process / Enrich** | `lookup` `alias` `eval x = …` |
| **Process / Aggregate** | `count` `stats` (`sum`, `min`, `max`, `unique_count`) |
| **Render** | `table` `chart` `text` `raw` |

Reference: **docs.gravwell.io/search/search.html** and **/search/processingmodules.html**

Watch: **Cadet Academy · First Principles: Crafting a Query**, youtu.be/t9FJhFL6QW8

<!-- One example each, on corelight_* data they already have. Do not go deep; the point is the map. The Cadet Academy video is the 20-minute version of this slide, from Gravwell: point at it as homework for anyone who wants the query language properly, and for the self-guided reader it stands in for the instructor's live walk-through. -->

---

<!-- _class: lead -->
# The platform, from where you sit
## What the pieces are called, and which ones a user touches

<!--
Super high level. Not administration: no wells, no replication, no ageout, no cluster layout beyond
the one sentence needed to explain what a tag is. Each of the next six slides is one component
family, in the order a user meets them: data in, search it, save what worked, show it, share it,
automate it. The live browser tour that follows walks these same slides in the UI.
-->

---

## Data in: entries, tags, ingesters

| Term | What it is to you |
|---|---|
| **Entry** | The unit of storage: raw **Data** bytes + **Timestamp** + **Tag** + **SRC**. Stored as it arrived |
| **Tag** | The label an ingester put on the entry. `tag=corelight_dns` is the first word of every query. The only piece of the ingest side you must know |
| **Ingester** | The program that gets data in and tags it: Simple Relay (the `nc` listeners in Lab 00), File Follower, syslog, Kafka, S3, HTTP, Windows events, and the **LLM ingester** you meet in Lab 05 |
| **Indexer / webserver** | Indexers store and search; the webserver is the UI and API you log into. One box in this course |

<!-- The Lab 00 compose file is the smallest possible Gravwell: one indexer+webserver container, a handful of Simple Relay listeners, one LLM ingester. Every dataset in the course arrives through a listener on a per-seat port; that is all "ingest" means here. -->

---

## Search: Query Studio

- The **query bar**: autocomplete (`Ctrl+Space`), errors underlined, hover any module for its docs
- The **time picker**: defaults to *last hour*, which is why your first Lab 02 query returned nothing. Presets, absolute ranges, or `start=`/`end=` in the query itself
- **Renderers** at the end of the pipeline: `table`, `chart`, `text`, `raw`, gauges, maps
- **Zoom the timeline** above the results to re-scope without re-running
- **Background** a slow search, come back later; **live update** re-runs it on a timer
- **Search history** in the right-hand pane. Nothing you typed is lost

<!-- All of this is what they fought through in Lab 02 without names. Say the names. The time picker gets its own sentence because it is the number one support question in every room. -->

---

## Save what worked: library, templates, macros, extractors

| Component | One line |
|---|---|
| **Query Library** | Save a query with a name, description and labels; share it by URL; **Schedule** it from here |
| **Templates** | A saved query with **variables** (`%%ip%%`). Fill the value at run time |
| **Actionables** | Right-click a value in results, matched by regex, and run a template, open a dashboard, or hit a URL with it |
| **Macros** | `$NAME` text substitution, expanded before the search runs. How kits avoid hard-coding your tag names |
| **Auto-extractors** | The extraction for a tag, defined once; then `tag=x ax \| table` instead of the regex every time |

<!-- Templates + actionables together are the "click an IP, get the investigation" workflow. The kit they installed in Lab 02 used macros for exactly the reason on the slide: it did not know their tag names in advance. -->

---

## Show it: dashboards

- A dashboard is a grid of **tiles**; every tile is a query with a renderer
- One **timeframe** for the whole dashboard, overridable per tile; **live update** on a timer
- A tile can **reference** a library query (edit the query, every dashboard follows) or **copy** it
- Tiles built from **templates** prompt for their variables when the dashboard opens: an **investigative dashboard**
- Download a tile's results as JSON or CSV; share by URL

<!-- The Corelight kit's dashboards are the example: open one, show that a tile is a saved query, edit it live. That is the whole trick. -->

---

## Share it: resources and kits

**Resources** are files a query can reach. `AI_DOMAINS` was one.
- Made by **uploading** a file, or by a search: `table -save NAME`
- Used by `lookup -r`, `ipexist`, `geoip`, and scripts. Owned by you, shareable to a group or globally

**Kits** are the packaging: dashboards, library queries, templates, actionables, macros, resources, auto-extractors, playbooks, scheduled searches, in one installable bundle.
- The **Corelight kit** and the **LLM Observability kit** are both from **kits.gravwell.io**
- Install asks you for the **configuration macros** (your tag names). Build and export your own from the same page

<!-- Resource first because they built one in Lab 02 (table -save, then lookup -r). Kits second because they installed one. Neither is abstract by this point. -->

---

## Automate it: scheduled searches, alerts, flows

1. A **scheduled search** runs a library query on a cron schedule
2. An **alert** names that search as a **dispatcher**: each result becomes an **event**, recorded to a tag
3. Each event fires the alert's **consumers**: **flows**, no-code graphs of nodes that run a query, format it, and send email, Slack, Teams, PagerDuty, a PDF, or **re-ingest** it as a new entry

Flows run **as their owner**. Same rule as every automation in this course: whoever owns the schedule owns the blast radius.

<!-- Lab 07 Part 3's stretch is "schedule one detection". This is the slide that says where that path leads: scheduled search -> alert -> flow. Do not build one here. -->

---

## Three more you will meet

- **Playbooks**: a document with runnable queries in it. Kits ship them as their "start here"; you can write your own investigation notes the same way
- **Data Explorer**: click a word in raw results to include or exclude it, click a field to extract it. Query building without knowing the syntax, then read the query it wrote
- **Logbot & the MCP server**: the built-in AI assistant can explain entries and write queries; the same tools are exposed at `/api/mcp` for external agents. You speak that protocol **by hand** in Lab 06. **Logbot is on your seat, but try not to use it**: writing the queries yourself is the point. Stuck on one? Ask it, read what it wrote, then go back to typing

<!-- The Logbot line closes the loop on the design decision in the title slide notes. In Lab 06 they will list the MCP server's 50 tools and find the 11 that mutate; this is the first time they hear the server exists. -->

---

<!-- _class: lead -->
# A quick platform tour
## Query Studio · time picker · kits · dashboards · resources · saved searches · search history

<!--
Drive it live on your own instance (or a seat's). Stops, in order:
 1. Query Studio: the query bar, the time picker they have been fighting, result renderers.
 2. The Corelight kit they installed: open a dashboard, show it is saved queries; open one and edit it.
 3. Resources: the AI_DOMAINS list they uploaded; a resource is just a file the query can reach.
 4. Saved searches / search history: nothing they typed is lost.
 5. Anything the room asks for. Then come back to the slides.
-->

---

## Take it home

- **Gravwell Community Edition is free**, for personal *and* commercial use, with a daily ingest cap that easily covers a home lab, a small team, or a proof of concept
- Same product you used today: kits, dashboards, the query language, the MCP server
- **www.gravwell.io/community-edition**

<!-- The recruiting moment. It lands better after they have done real work in it, which is why this module sits here and not before Lab 02. -->

---

## Where to look things up

| Need | Go to |
|---|---|
| The query modules | docs.gravwell.io/search/search.html |
| Getting data in (ingesters, file follower, syslog) | docs.gravwell.io/ingesters/ingesters.html |
| Kits | docs.gravwell.io/kits/kits.html |
| Standing up your own | docs.gravwell.io/quickstart/quickstart.html |
| The REST API | api.docs.gravwell.io |
| Learn the query language properly (video) | youtu.be/t9FJhFL6QW8 · *Cadet Academy: Crafting a Query* |

The docs are open. Vendors who gate tech docs are shitheads.

---

<!-- _class: lead -->
# Back to the labs
## Next: find a rogue agent in Sysmon data

<!-- Hand-off to M5 / Lab C. The first module they cannot guess is xml with Data[Name]==; they have just seen where the docs for it live. -->
