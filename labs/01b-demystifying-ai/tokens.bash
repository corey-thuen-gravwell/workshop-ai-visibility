#!/usr/bin/env bash
# Lab 01b: how many tokens is that? (slide: "What's in a token?")
#
# The most honest script in this lab: it shows you the exact curl it runs, then the model's
# whole answer as JSON. Nothing is parsed or hidden. The number you are after is
# prompt_eval_count: how many tokens the tokenizer made of your text. (We send raw=true so no
# chat template is wrapped around it, and ask for a single token back so it returns quickly.)
#
# Usage:
#   ./tokens.bash                          # the deck's examples
#   ./tokens.bash "I am a potato!" "supercalifragilistic" "rm -rf /"
set -euo pipefail
# A relay on this host adds the credential for the model. You never see a token; you never need one.
GRAVWELL_LLM_URL="${GRAVWELL_LLM_URL:-http://127.0.0.1:9010}"
MODEL="${MODEL:-logbot}"

[ $# -gt 0 ] || set -- "I am a potato!" "unbelievable" "Hello world" "cat"

for text in "$@"; do
    payload=$(jq -cn --arg m "$MODEL" --arg p "$text" \
              '{model:$m, prompt:$p, raw:true, stream:false, options:{num_predict:1}}')
    echo
    echo "### $text"
    echo "curl -sS ${GRAVWELL_LLM_URL}/api/generate -H 'content-type: application/json' -d '$payload'"
    echo
    curl -sS --fail-with-body "${GRAVWELL_LLM_URL}/api/generate" \
        -H 'content-type: application/json' -d "$payload" | jq .
done
