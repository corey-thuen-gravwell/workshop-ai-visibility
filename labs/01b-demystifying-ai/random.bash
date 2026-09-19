#!/usr/bin/env bash
# Lab 01b, "isn't it non-deterministic?" (slide: "But isn't it non-deterministic? Stochastic?")
#
# Same input + same seed + temperature 0 => the same output, every time. Run it twice and diff.
# (The default question is about pineapple on pizza. The model has opinions.)
# The "randomness" is a random NUMBER that the caller hands in (the seed). Change the number,
# change the output. Raise the temperature and see where the seed stops mattering.
#
# Usage:
#   ./random.bash                 # temperature 0: run it twice
#   TEMP=1 ./random.bash          # let it sample, no seed, run it twice
#   TEMP=1 SEED=42 ./random.bash  # sampling with a fixed random number, run it twice
#   TEMP=1 SEED=7 ./random.bash   # a different random number
#   ./random.bash "Say something random."      # your own prompt
set -euo pipefail
# A relay on this host adds the credential for the model. You never see a token; you never need one.
GRAVWELL_LLM_URL="${GRAVWELL_LLM_URL:-http://127.0.0.1:9010}"
MODEL="${MODEL:-logbot}"
PROMPT="${1:-In one sentence, give me your honest opinion of pineapple on pizza.}"
TEMP="${TEMP:-0}"
SEED="${SEED:-}"          # empty => the server picks a random one, like a normal chat client

payload=$(jq -n --arg m "$MODEL" --arg p "$PROMPT" --arg s "$SEED" --argjson t "$TEMP" \
          '{model:$m, prompt:$p, stream:false, think:false, options:{temperature:$t}}
           | if $s != "" then .options.seed = ($s|tonumber) else . end')
{ echo "request  POST ${GRAVWELL_LLM_URL}/api/generate"; echo "$payload"; echo "response"; } >&2

curl -sS --fail-with-body "${GRAVWELL_LLM_URL}/api/generate" \
    -H 'content-type: application/json' -d "$payload" \
| jq -r '.response // .error'
