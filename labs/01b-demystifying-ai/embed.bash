#!/usr/bin/env bash
# Lab 01b, turn text into a vector (slide: "What's an embedding?")
#
# An embedding model returns one big list of numbers for a piece of text. That's it. That's the
# "meaning".
#
# Usage:
#   ./embed.bash                                   # the deck's sentence
#   ./embed.bash "potato"
#   ./embed.bash "potato" | jq '.embeddings[0] | length'     # how many dimensions?
set -euo pipefail
# A relay on this host adds the credential for the model. You never see a token; you never need one.
GRAVWELL_LLM_URL="${GRAVWELL_LLM_URL:-http://127.0.0.1:9010}"
MODEL="${EMBED_MODEL:-qwen3-embedding}"
TEXT="${1:-The quick brown fox jumps over the lazy dog.}"

payload=$(jq -n --arg m "$MODEL" --arg t "$TEXT" '{model:$m, input:$t}')
{ echo "request  POST ${GRAVWELL_LLM_URL}/api/embed"; echo "$payload"; echo "response"; } >&2   # stderr: pipes still get clean JSON

curl -sS --fail-with-body "${GRAVWELL_LLM_URL}/api/embed" \
    -H 'content-type: application/json' -d "$payload"
echo
