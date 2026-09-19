#!/bin/bash
# Stand up the P3 demo: a Gravwell stack whose LLM ingester embeds every prompt and reply, so
# `semantic` search works over tag=llm. Run as root on the lab host.
#
# WHY THIS IS AN INSTRUCTOR STACK AND NOT A SEAT
# Two containers need the embeddings endpoint: the ingester (to embed each entry at ingest) and
# the webserver (to embed the SEARCH PHRASE at query time). Both would therefore need the Gravwell
# LLM token. Seats deliberately never receive that token: they reach the model through a
# loopback-only relay, and that relay refuses to bind anything but 127.0.0.1 because it holds a
# credential. A container cannot reach 127.0.0.1 on the host. So P3 runs on a stack the instructor
# owns, and is projected. See instructor/runbook/gravwell-llm.env and the walkthrough.
#
#   ./enable-semantic.sh up      # build + start the demo stack (default seat id 39)
#   ./enable-semantic.sh seed    # push a handful of semantically distinct prompts through it
#   ./enable-semantic.sh down
set -euo pipefail

ID="${SEMANTIC_UID:-39}"
DIR="${SEMANTIC_DIR:-/opt/workshop/semantic-demo}"
REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
ENV_FILE="${ENV_FILE:-/opt/workshop/.env}"
LLM_ENV="${LLM_ENV:-$REPO/instructor/runbook/gravwell-llm.env}"
MODEL="${EMBED_MODEL:-qwen3-embedding}"

[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }
set -a; . "$ENV_FILE"; . "$LLM_ENV"; set +a
: "${LLM_UPSTREAM_URL:?missing from $LLM_ENV}"; : "${LLM_UPSTREAM_TOKEN:?missing from $LLM_ENV}"

case "${1:-up}" in
down) cd "$DIR" 2>/dev/null && WORKSHOPUID="$ID" docker compose down -v 2>&1 | tail -2; exit 0 ;;

seed)
    : "${ANTHROPIC_API_KEY:?missing from $ENV_FILE}"
    echo "==> seeding the demo stack with semantically distinct prompts"
    while IFS='|' read -r label prompt; do
        [ -z "${label:-}" ] && continue
        code=$(curl -sS -o /dev/null -m 90 -w '%{http_code}' "http://localhost:${ID}81/v1/messages" \
            -H "x-api-key: $ANTHROPIC_API_KEY" -H 'anthropic-version: 2023-06-01' \
            -H 'content-type: application/json' \
            -d "{\"model\":\"claude-haiku-4-5\",\"max_tokens\":60,\"messages\":[{\"role\":\"user\",\"content\":\"$prompt\"}]}")
        printf '  %s  %s\n' "$code" "$label"
    done <<'SEED'
disk full|My laptop has run out of disk space and will not boot.
storage full|The storage volume is completely full, how do I free space?
db refused|The database server keeps refusing connections on port 5432.
password reset|How do I reset a forgotten password for a user account?
leaked key|I accidentally committed an API key to a public git repository, what now?
exfil-ish|What is the fastest way to copy our customer table to an external host?
sourdough|What is a good recipe for sourdough bread?
holiday|Suggest three quiet places to visit in northern Italy in October.
SEED
    echo "  give it ~10s, then search"
    exit 0 ;;

up) ;;
*) echo "usage: $0 [up|seed|down]" >&2; exit 1 ;;
esac

echo "==> building the demo stack in $DIR (seat id $ID)"
rm -rf "$DIR"; mkdir -p "$DIR/config"
cp "$REPO/labs/00-environment-gravwell/docker-compose.yml" "$DIR/"
cp "$REPO"/labs/00-environment-gravwell/config/*.conf "$DIR/config/"

# [AI] on the WEBSERVER: used by the `semantic` module to embed the search phrase
cat > "$DIR/config/ai.conf" <<AI
# Enables the \`semantic\` search module. Gravwell embeds the *search phrase* here and compares it
# against the per-entry vectors the ingester attached. Both halves are required.
[AI]
	Embedding-URL = "${LLM_UPSTREAM_URL}/v1/embeddings"
	Embedding-Model = "${MODEL}"
	Embedding-Token = "${LLM_UPSTREAM_TOKEN}"
AI

# vector preprocessor on the INGESTER: embeds each entry as it arrives
python3 - "$DIR/config/llm_ingester.conf" "$LLM_UPSTREAM_URL" "$LLM_UPSTREAM_TOKEN" "$MODEL" <<'PY'
import sys, re
path, url, tok, model = sys.argv[1:5]
s = open(path).read()
if "Preprocessor=embed" not in s:
    s = re.sub(r'(\[Listener "anthropic"\]\n)', r'\1\tPreprocessor=embed\n', s)
    s += (f'\n[Preprocessor "embed"]\n\tType=vector\n\tModel={model}\n'
          f'\tEndpoint={url}/v1/embeddings\n\tToken={tok}\n'
          f'\tTimeout=60\n\tRetry-Attempts=3\n\tPassthrough-On-Error=true\n')
    open(path, "w").write(s)
PY

python3 - "$DIR/docker-compose.yml" "$REPO" <<'PY'
import sys
p, repo = sys.argv[1:3]; s = open(p).read()
s = s.replace("      - ./config/https.conf:/opt/gravwell/etc/gravwell.conf.d/https.conf:ro",
              "      - ./config/https.conf:/opt/gravwell/etc/gravwell.conf.d/https.conf:ro\n"
              "      - ./config/ai.conf:/opt/gravwell/etc/gravwell.conf.d/ai.conf:ro")
s = s.replace("      - ../../gravwell.license:/opt/gravwell/etc/license:ro",
              f"      - {repo}/gravwell.license:/opt/gravwell/etc/license:ro")
s = s.replace("      - ${WORKSHOP_CERT_DIR:-./config}/cert.pem", "      - /opt/workshop/certs/cert.pem")
s = s.replace("      - ${WORKSHOP_CERT_DIR:-./config}/key.pem", "      - /opt/workshop/certs/key.pem")
open(p, "w").write(s)
PY
chmod 600 "$DIR/config/ai.conf" "$DIR/config/llm_ingester.conf"   # both now contain the token

cd "$DIR"
WORKSHOPUID="$ID" GRAVWELL_INGEST_SECRET="${GRAVWELL_INGEST_SECRET:-IngestSecrets}" \
    docker compose up -d 2>&1 | tail -3

for i in $(seq 1 24); do
    [ "$(curl -sk -o /dev/null -w '%{http_code}' "https://localhost:${ID}443/" 2>/dev/null)" = 200 ] && break
    sleep 10
done
echo
echo "  UI:        https://${LAB_HOST:-$(hostname -f)}:${ID}443  (admin/changeme)"
echo "  ingester:  http://localhost:${ID}81/v1/messages"
echo "  next:      $0 seed     then search:"
echo "             tag=llm intrinsic embeddings | semantic -t 45 \"running out of storage\" | sort by score desc | table score DATA"
