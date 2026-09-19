# Setup: credentials and where they go

Everything in this course that talks to the outside world needs one of three things: an
**Anthropic API key** (the labs that call a model), a **Gravwell license** (the log-analysis
backend every analysis lab uses), and, for one lab, an **Ollama-shaped model endpoint**. None of
them are in this repository. This page says where to get each one and exactly where to put it,
for both ways of running the course.

| | Self-guided (your own machine) | Instructor-led (a lab host with seats) |
|---|---|---|
| Anthropic API key | `ANTHROPIC_API_KEY` in your `~/.workshop_env` | `ANTHROPIC_API_KEY` in `/opt/workshop/.env`; `makeuser.sh` copies it into every seat |
| Gravwell license | `gravwell.license` at the repo root | `gravwell.license` at the root of the authoring copy on the host; the student repo build ships it to seats |
| Lab 01b model | Ollama on your machine, `GRAVWELL_LLM_URL` pointed at it | `instructor/runbook/gravwell-llm.env`, served to seats through a root-only relay |
| TLS certificate | Self-signed, generated into `labs/00-environment-gravwell/config/` | Let's Encrypt into `/opt/workshop/certs` via `issue-cert.sh` |

All of those paths are git-ignored. Check with `git status` before you commit anything.

---

## 1. The Anthropic API key

Labs 01, 04, 05, 06 and 07, and the optional P2 and P4 labs, send requests to a real model. The
course is written against Anthropic's API; the proxies and the ingester also speak the OpenAI
format, so another provider works with config changes, but the handouts assume Anthropic.

1. Sign in at <https://console.anthropic.com>, or create an account.
2. Under **Billing**, add a payment method and **set a monthly spend limit**. A few dollars covers
   the whole course for one person; the biggest single lab (05) is well under a dollar. The limit
   is your safety net if a key leaks or an agent loops.
3. Under **API Keys**, create a key. Name it for this course so it is obvious what to revoke later.
   Copy it once; the console will not show it again.
4. Put it where the labs read it (next section). **Never** paste it into a handout, a script in the
   repo, or a commit. The repo's `.gitignore` covers `.env`, but a key inside any other file is yours
   to catch.
5. When you finish the course, **revoke the key** in the same console page.

Where the labs expect it: the environment variable `ANTHROPIC_API_KEY`. Lab 01 curls the API with
it directly, Lab 04 puts it in an opencode config, Lab 05's proxies pass it through. Nothing in the
course needs it anywhere else.

### Self-guided: `~/.workshop_env`

In a class, a provisioning script writes each seat a file called `~/.workshop_env` and sources it
from `.bashrc`. Working alone, write it yourself. Pick any two-digit seat id between 10 and 49
(`12` is fine); every port in the course is built from it.

```bash
cat > ~/.workshop_env <<'ENV'
export ANTHROPIC_API_KEY="sk-ant-..."          # your key, spend-limited
export WORKSHOPUID="12"                        # your seat id, 10-49
export GRAVWELL_INGEST_SECRET="IngestSecrets"
# Lab 01b: your Ollama (section 3). In a class this points at a relay instead.
export GRAVWELL_LLM_URL="http://127.0.0.1:11434"
export MODEL="llama3.2"
export EMBED_MODEL="qwen3-embedding"
# Lab 00 writes a Gravwell API token to ~/.gravwell_token; every later lab reads it from here.
if [ -r "$HOME/.gravwell_token" ]; then
    export GRAVWELL_TOKEN="$(cat "$HOME/.gravwell_token")"
fi
ENV
chmod 600 ~/.workshop_env
grep -q workshop_env ~/.bashrc || echo '[ -f ~/.workshop_env ] && . ~/.workshop_env' >> ~/.bashrc
. ~/.workshop_env
```

Leave `WORKSHOP_CERT_DIR` unset: the Lab 00 compose then falls back to the self-signed certificate
you generate in section 4. Also copy `.env.example` to `.env` at the repo root and set the same
`ANTHROPIC_API_KEY`, `WORKSHOPUID` and `GRAVWELL_INGEST_SECRET` there; docker compose reads `.env`,
your shell reads `~/.workshop_env`, and they must agree.

### Instructor-led: `/opt/workshop/.env`

```bash
cp .env.example /opt/workshop/.env && chmod 600 /opt/workshop/.env
$EDITOR /opt/workshop/.env        # ANTHROPIC_API_KEY, LAB_HOST, SEATS, share password, ...
```

`makeuser.sh` writes the key into every seat's `~/.workshop_env` (mode 0600). Seats hold the real
key on purpose; `instructor/runbook/api-key-architecture.md` explains why it is not proxied and
how to rotate it (edit `.env`, re-run `makeuser.sh`, revoke the old key). Treat it as a
per-delivery key: created before the class, spend-limited, revoked the day the class ends.

---

## 2. The Gravwell license

Gravwell will not start without a license file. Without one the stack starts and immediately
stops, with nothing useful in `docker compose logs`, which is a confusing first hour if you do not
know to look for it.

1. Get a free **Community Edition** license from <https://www.gravwell.io/download>. It arrives
   by email as a file. Community Edition is enough for every lab in this course: one node per
   instance, which is exactly what each seat runs.
2. Save it at the **root of this repository** as `gravwell.license`. The Lab 00 compose mounts
   `../../gravwell.license` into the container read-only, and the student repo build refuses to
   publish without it.
3. Check it is ignored: `git status` should not list it.

The same file works for every seat on a lab host: the `MaxNodes: 1` limit is per standalone
instance, and each seat's container is its own instance. Note the expiry date in the email; a
Community license lasts long enough for a course, but a repo checked out months later may need a
fresh one. `preflight.sh` checks the file is present on a lab host; the licensed state itself
shows up as a working login and `tag=gravwell` returning rows in Lab 00.

---

## 3. The Lab 01b model (tokens, embeddings, logprobs)

Lab 01b does not use the Anthropic API. Its seven scripts talk to an **Ollama-shaped** endpoint
(`/api/generate`, `/api/embed`, `/api/tags`) because they need raw token counts, embeddings and
per-token probabilities, which a hosted chat API does not return.

### Self-guided: Ollama

```bash
curl -fsSL https://ollama.com/install.sh | sh      # or your package manager
ollama pull llama3.2                                # generation
ollama pull qwen3-embedding                         # embeddings (nomic-embed-text also works)
```

`~/.workshop_env` from section 1 already points `GRAVWELL_LLM_URL` at `http://127.0.0.1:11434`
and names the two models. `logprobs.bash` and its siblings need an Ollama build recent enough to
return `logprobs` on `/api/generate`; if the candidates column comes back empty, update Ollama.

### Instructor-led: a hosted endpoint behind the relay

Seats never hold this credential. Put the endpoint in `instructor/runbook/gravwell-llm.env`:

```bash
cp instructor/runbook/gravwell-llm.env.example instructor/runbook/gravwell-llm.env
$EDITOR instructor/runbook/gravwell-llm.env     # LLM_UPSTREAM_URL, LLM_UPSTREAM_TOKEN
instructor/runbook/scripts/start-llm-relay.sh   # root systemd relay on 127.0.0.1:9010
```

Any Ollama-compatible server works as the upstream: a hosted model with a bearer token, or an
Ollama instance on the lab host itself with the token left empty. The relay adds the token on the
way out and only forwards the three paths the lab uses; seats get
`GRAVWELL_LLM_URL=http://127.0.0.1:9010` and the scripts send no credential. Rotate the token after
every delivery (edit the file, `start-llm-relay.sh restart`). `build-student-repo.sh` reads the
file and refuses to publish a student repo that contains the token string.

---

## 4. The TLS certificate

Gravwell's UI is served over HTTPS on port `<seat id>443`.

**Self-guided:** leave `WORKSHOP_CERT_DIR` unset and generate a self-signed pair where the compose
looks for it. Your browser will warn once; accept it.

```bash
cd labs/00-environment-gravwell/config
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
    -keyout key.pem -out cert.pem -subj "/CN=localhost"
```

**Instructor-led:** attendees browse from the venue network to the host's public name, so the
cert must be browser-trusted. `instructor/runbook/scripts/issue-cert.sh` issues a Let's Encrypt
cert for `LAB_HOST` by manual DNS-01 into `/opt/workshop/certs`, root-owned, and the docker daemon
mounts it into every seat's container without the seat being able to read the private key.

---

## 5. Check before you start

```bash
. ~/.workshop_env
echo "$WORKSHOPUID"                                   # your seat id
echo "${ANTHROPIC_API_KEY:0:10}"                      # sk-ant-... and nothing more on screen
ls -l gravwell.license                                # present at the repo root
curl -s "$GRAVWELL_LLM_URL/api/tags" | jq '.models[].name'    # Lab 01b's models answer
git status --short | grep -E 'license|\.env|gravwell-llm' && echo "STOP: a credential file is not ignored"
```

If all four lines behave, go to `labs/00-environment-gravwell/README.md` (or, working alone,
`materials/self-study-guide.md` first).
