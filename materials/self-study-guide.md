# Working through this course on your own

This course works two ways: an instructor teaching a room, with lecture and guidance during the
labs, or you, alone, with this guide in place of the instructor. Everything it teaches is
reproducible on one Linux box with docker, and this doc covers how to do that.

Read it once before you start. It will save you the two or three hours that everyone loses to the
same three problems.

---

## 1. What you are signing up for

| | |
|---|---|
| **Time** | Roughly 16 hours of hands-on work, plus setup. Split it however you like; the labs are independent once the environment is up |
| **Money** | A few dollars of Anthropic API spend. Labs 01, 04, 05, 06 and the P2/P4 stretch labs call a real model. Set a spend limit on the key and forget about it |
| **Skills** | Comfortable in a terminal, or willing to become so. You do not need to know Gravwell, MCP, or how an LLM works: that is the course |
| **Hardware** | One Linux box (or VM) with 4 GB RAM free and ~10 GB disk. Everything runs in docker |

**Every module is written up.** Nothing in the course depends on material that is not in this
repository; the walkthroughs stand in for the instructor.

---

## 2. The five things that are different without an instructor

1. **The walkthroughs are your instructor.** `instructor/walkthroughs/NN-*.md` carries every
   command, the exact expected output, and the answer to every task. Do not read one before you
   have tried the handout, it defeats the point. Read it the moment you are stuck for more
   than ten minutes, and after you finish, to check what you missed.
2. **The data is generated, and it expires.** Every scenario is pinned to the previous UTC business
   day. Data generated last week will not appear in a "last 48 hours" search. Regenerate before
   each sitting (§4). This single issue causes more "the query returns nothing" than everything
   else combined.
3. **You are seat one of one.** Set `WORKSHOPUID` yourself. Any two-digit number in 10–49 works;
   `12` is fine. Every port in the course is built from it.
4. **Nothing is released in stages.** In a class the labs appear one at a time. You have the whole
   repository from the start. The `stage-*` checkpoint tags in the student repo are a classroom
   mechanism; working from the authoring repo, `git checkout -- labs/<dir>` against your own
   history does the same recovery job.
5. **The slides are still worth reading.** `slides/*.md` is Marp markdown and reads fine as text.
   Each module's deck carries the *why* that the handout assumes you were told. `AGENDA.md` maps
   modules to labs.

---

## 3. Setting up

### What to install

```bash
sudo apt update && sudo apt install -y docker.io docker-compose-v2 jq netcat-openbsd python3 git
sudo usermod -aG docker "$USER"      # then log out and back in, or docker.sock is denied
```

Anything with docker, `jq`, `nc` and Python 3 works; the commands above are Debian/Ubuntu.

### The repository

```bash
git clone <this repo> ~/jarvis && cd ~/jarvis
cp .env.example .env
```

Edit `.env` and set at least:

```bash
ANTHROPIC_API_KEY="sk-ant-..."     # yours, spend-limited
WORKSHOPUID="12"                   # your seat id, 10-49
GRAVWELL_INGEST_SECRET="IngestSecrets"
```

Leave `WORKSHOP_CERT_DIR` unset. The compose falls back to
`labs/00-environment-gravwell/config/`, so drop a `cert.pem` and `key.pem` there. A self-signed
pair is fine:

```bash
cd ~/jarvis/labs/00-environment-gravwell/config
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
    -keyout key.pem -out cert.pem -subj "/CN=localhost"
```

Then make the two variables available to every shell you work in:

```bash
cat >> ~/.bashrc <<'EOF'
export WORKSHOPUID=12
export ANTHROPIC_API_KEY="sk-ant-..."
EOF
```

### The Gravwell license and the API key

Both are covered step by step in [`SETUP.md`](../SETUP.md): a free **Community Edition** license
from <https://www.gravwell.io/download> saved as `gravwell.license` in the repository root, and an
Anthropic API key with a spend limit. Community Edition is enough for every lab here. Without a
license file the stack starts and immediately stops, with nothing useful in `docker compose logs`,
which is a confusing first hour if you do not know to look for it.

### Bring it up

Follow `labs/00-environment-gravwell/README.md`. It is the one lab that is genuinely about the
environment, so do not skim it. Two adjustments for solo work:

- The UI is at `https://localhost:${WORKSHOPUID}443`, not an instructor's lab host.
- Your browser will complain about the self-signed certificate. Accept it once.

Confirm before you go further:

```bash
docker compose ps                       # both containers Up
ss -ltn | grep -E ":(${WORKSHOPUID}0[1-9])\b"    # the ingest listeners are bound
```

---

## 4. Generating the data (do this before each sitting)

Three generators, all deterministic with `--seed`, all anchored to now:

```bash
cd ~/jarvis/src/log-generator

# Lab 02 (Corelight/Zeek + Okta) and the re-timed Sysmon file for Lab 03
python3 generate_corelight_logs.py --seed 1 \
    --outdir ../../datasets/corelight/generated \
    --answer-key ../../datasets/corelight/generated/answer-key.json \
    --sysmon-in  ../../datasets/sysmon/sysmon-events-jan21-clean.xml \
    --sysmon-out ../../datasets/sysmon/generated/sysmon-retimed.xml

# P9, the beyond-the-wire sources: same cast, four more logs
python3 generate_shadow_ai_sources.py --seed 1 \
    --outdir ../../datasets/shadow-ai-sources/generated

# P8, the AI assistant's own logs
python3 generate_logbot_logs.py --seed 1 \
    --out ../../datasets/gravwell-ai-assistant/generated/logbot.log
```

Generate Lab 02's and P9's data **in the same sitting**: P9 is the same fourteen hosts on the same
day, and the two stop lining up if they are anchored hours apart. `--anchor <YYYY-MM-DD>T17:00:00Z`
pins the window end explicitly if you would rather control it.

`answer-key.json` is exactly what it sounds like. Do not open it until you have finished Lab 02.

Then ingest as each lab tells you (`nc -q1 localhost <port> < file`), and **set the Gravwell time
range to last 48 hours**. Say that out loud once, because you will forget it once.

---

## 5. A route through the material

The course is a sequence, not a Day-1/Day-2 script. This order is the one the narrative assumes.

| Order | Read | Then do | Hours |
|---|---|---|---|
| 1 | `slides/00-intro.md` | nothing, this is the "why" | 0.5 |
| 2 | `slides/01-fundamentals.md` | **Lab 01**: curl the API by hand | 1.0 |
| 3 | `slides/01b-demystifying-ai.md` | **Lab 01b**: tokens, embeddings, logprobs (needs §7) | 1.0 |
| 4 | `slides/02-audit-gap.md` | nothing | 0.5 |
| 5 | | **Lab 00**: stand up Gravwell | 1.0 |
| 6 | `slides/03-shadow-ai.md` | **Lab 02**: hunt shadow AI in network logs | 2.0 |
| 7 | `slides/03c-gravwell-tour.md` | poke at the UI: kits, dashboards, resources | 0.5 |
| 8 | `slides/03b-shadow-ai-sources.md` | **P9**: beyond the wire (optional, and the best optional one) | 1.5 |
| 9 | `slides/04-sysmon.md` | **Lab 03**: find the rogue agent on the endpoint | 2.0 |
| 10 | `materials/questions-for-the-ciso.md` | answer all ten for your own org, in writing | 0.5 |
| 11 | `slides/05-opencode-proxy.md` | **Lab 04**: be the AI user, audit it from the endpoint | 1.0 |
| 12 | | **Lab 05**: litellm, then the two content-capturing proxies | 2.0 |
| 13 | | **P2**: extend the proxy · **P4**: a second client (both optional) | 1.5 |
| 14 | `slides/06-mcp.md` | **Lab 06**: MCP by hand, then build a server | 2.5 |
| 15 | | **P8**: audit an AI assistant from its own logs (optional) | 0.75 |
| 16 | `materials/ai-audit-checklist.md` | write your own version for your own environment | 0.5 |

Labs 01 and 01b need nothing but a network connection, so they are a good first evening. Lab 00
through Lab 03 is a coherent second block. Labs 04 to 06 are the second half and want a clear run.

---

## 6. How to use a walkthrough without spoiling the lab

Each lab has two documents and they are deliberately different:

- `labs/NN-*/README.md`: goals, background, the tasks. Enough to do the work, not a script.
- `instructor/walkthroughs/NN-*.md`: every command, the exact output to expect, the failure table,
  and the answer to every task.

The walkthroughs are written for someone teaching, so they contain notes about pacing and about
where a room gets stuck. Read past those; the technical content underneath is complete, and the
"where students get stuck" section at the bottom of each one is the single most useful part of
this repository when you are working alone. Check it *first* when something does not behave.

A working rhythm that holds up:

1. Read the handout's Objective, Background and Setup. Run the setup.
2. Attempt every task from the handout alone. Write your answers down; several labs ask you to
   carry a finding forward into the next one.
3. Stuck for ten minutes on *mechanics* (syntax, a port, a flag): open the walkthrough, take the
   command, keep going. Being stuck on plumbing teaches nothing.
4. Stuck on *interpretation* (which host, why is it invisible): sit with it longer. That part is
   the course.
5. When you finish, read the whole walkthrough. It will tell you at least one thing you missed.

---

## 7. Lab-by-lab notes for solo work

**Lab 01 (curl the API).** Works as written. Your own Anthropic key, no proxy, nothing else.

**Lab 01b (demystifying AI).** The scripts talk to an **Ollama-shaped** API: `/api/generate`,
`/api/embed`, `/api/tags`. In class that is a Gravwell-hosted model behind a local relay. Install
[Ollama](https://ollama.com) and point the scripts at it:

```bash
ollama pull llama3.2
ollama pull qwen3-embedding          # or: nomic-embed-text
export GRAVWELL_LLM_URL=http://127.0.0.1:11434
export MODEL=llama3.2
export EMBED_MODEL=qwen3-embedding
cd ~/jarvis/labs/01b-demystifying-ai && ./tokens.bash
```

`logprobs.bash` and its siblings need an Ollama build recent enough to return `logprobs` /
`top_logprobs` on `/api/generate`. If your output has an empty candidates column, update Ollama.
Everything else in the lab works on any build.

**Lab 00 (Gravwell).** See §3. The only lab where solo setup differs materially.

**Lab 02 (shadow AI).** Regenerate the data first (§4). Everything else is as written. This is the
lab where the answer key exists; resist it.

**Lab 03 (Sysmon).** The Sysmon file is re-timed by the Lab 02 generator, so regenerate both
together or the cross-source pivot in task 6 will not line up.

**Lab 04 (opencode).** Install opencode yourself: <https://opencode.ai>. The handout's config
points `baseURL` at your own LLM ingester (`http://localhost:<ID>81/v1`) so the session is captured
for Lab 05. Two things bite everyone: the `/v1` suffix is required, and the key goes in
`options.apiKey`, not the environment.

**Lab 05 (proxies).** Works as written; both proxies are in the repo and the ingester sidecar is
already in your Lab 00 compose. Part 2a2 installs Gravwell's **LLM Observability** kit over the
traffic you just generated: it comes off the kit server, or from
<https://github.com/gravwell/kits/tree/main/llm_observability> if your instance has no egress. The finished-early pointer to semantic search is P3, below.

**Lab 06 (MCP).** Works as written against your own Gravwell. Part 2 needs opencode from Lab 04.
For Lab 07's remote Gravwell MCP server you will need `export NODE_TLS_REJECT_UNAUTHORIZED=0`
because of the self-signed certificate, in a shell that has `$GRAVWELL_TOKEN`.

**Lab 07 (MCP tool interaction).** Works as written: it reuses the Lab 06 servers and opencode
config, and Part 3 searches the `tag=llm` traffic you generated in Parts 1 and 2.

**M12 (detections).** Is Lab 07 Part 3 plus the `slides/08-detections.md` deck; treat writing your own
scheduled search from one of those queries as the capstone.

**P2 (extend the proxy).** Works as written, and is the most fun of the optional labs alone,
because the agent doing the editing is logged by the thing it is editing.

**P3 (semantic search).** Needs an embeddings model reachable from **both** the ingester and the
Gravwell webserver, and both halves configured (a `vector` preprocessor on the listener, and an
`[AI]` block on the webserver). Ollama on the docker host works: use
`http://host.docker.internal:11434/v1/embeddings` from inside the containers, with no token. The
handout at `labs/_stretch/semantic-search/README.md` has both config blocks and the measured
results, so you can read the lesson even if you never wire it up.

**P4 (second client).** Needs Claude Code installed as well as opencode. Note the asymmetry the
lab is about: `ANTHROPIC_BASE_URL` for Claude Code must **not** have `/v1`, and opencode's
`baseURL` must.

**P8 (AI assistant logs).** Regenerate `logbot.log` first (§4); it is anchored to now like
everything else.

**P9 (beyond the wire).** Generate it in the same sitting as Lab 02.

---

## 8. When something does not work

`materials/terminal-cheatsheet.md` has every command in the course written out and a symptom table
at the bottom, and `materials/linux-cheatsheet.md` covers the terminal itself if that is the part
that is new. Before anything else, check these four:

1. **Time range.** Last 48 hours. This is most of them.
2. **Did the data get generated today?** See §4.
3. **Is `$WORKSHOPUID` set in *this* shell?** Ports come from it, and a new terminal may not have it.
4. **Did the resource upload?** `lookup` silently returns nothing when the resource does not exist.

Then the walkthrough's "where students get stuck" section, then
`instructor/runbook/gravwell-provisioning.md` for behaviours of a live Gravwell that the vendor
docs do not spell out.

For Gravwell itself, the documentation is open and needs no login:

- Query language and one page per search module: <https://docs.gravwell.io>
- REST API reference: <https://api.docs.gravwell.io>
- Every published kit, with its saved searches and dashboards: <https://github.com/gravwell/kits>

---

## 9. What to do when you finish

The course ends on `materials/ai-audit-checklist.md`, which is a four-tier collection plan and a
list of first detections. Working alone, the checklist is the deliverable: fill it in for your own
environment, name the log sources you actually have, and mark the rows you cannot fill yet. The
matrix in `materials/shadow-ai-detection-matrix.md` is the same exercise at indicator granularity.

The two things worth building immediately, in whatever stack you run:

1. **One proxy in one path.** `src/logging-proxy/llm_audit_proxy.py` is a single stdlib Python
   file with no dependencies. Put it in front of one team's agent traffic and look at what comes
   out for a week.
2. **One inventory query.** Whatever your equivalent of Lab 02 Method 3 is: the AI usage that no
   domain list contains, because it is running inside your own network.
