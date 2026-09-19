#!/usr/bin/env bash
# Lab 01b, watch the model "pick" (slides: "Isn't it thinking?" / "Doesn't it always take the
# most predictable token?")
#
# Asks the model to complete a sentence and to return, for every token it produced, the five
# candidates it was choosing between and their probabilities. Left column: the token it picked.
# Right: the top five it could have picked. TEMP=0 (the default here) always takes the top one.
#
# Usage:
#   ./logprobs.bash                                     # the deck's sentence
#   ./logprobs.bash "Complete the sentence: The capital of Idaho is"
#   TEMP=1.5 ./logprobs.bash                            # same distribution, different picks
#   TOP=10 ./logprobs.bash                              # show more candidates
#   MAX=200 ./logprobs.bash                             # let it run longer (default 60 tokens)
#   RAW=1 ./logprobs.bash                               # the untouched JSON
set -euo pipefail
# A relay on this host adds the credential for the model. You never see a token; you never need one.
GRAVWELL_LLM_URL="${GRAVWELL_LLM_URL:-http://127.0.0.1:9010}"
MODEL="${MODEL:-logbot}"
PROMPT="${1:-Complete the sentence without annotation, just complete the sentence: My boss, Alex, is a}"
TEMP="${TEMP:-0}"
TOP="${TOP:-5}"
MAX="${MAX:-60}"          # cap on tokens generated, high temperatures ramble

payload=$(jq -n --arg m "$MODEL" --arg p "$PROMPT" --argjson t "$TEMP" --argjson k "$TOP" --argjson n "$MAX" \
          '{model:$m, prompt:$p, stream:false, think:false, logprobs:true, top_logprobs:$k,
            options:{temperature:$t, num_predict:$n}}')
{ echo "request  POST ${GRAVWELL_LLM_URL}/api/generate"; echo "$payload"; echo "response"; } >&2

out=$(curl -sS --fail-with-body "${GRAVWELL_LLM_URL}/api/generate" \
    -H 'content-type: application/json' -d "$payload")

if [ -n "${RAW:-}" ]; then printf '%s\n' "$out" | jq .; exit 0; fi

printf '%s\n' "$out" | jq -r --arg t "$TEMP" --arg p "$PROMPT" '
  if .error then "error: \(.error)" else
  "prompt:      \($p)",
  "temperature: \($t)",
  "response:    \(.response)",
  "",
  "picked            candidates (probability)",
  (.logprobs[] |
     (.token | @json | .[0:16] | . + (" " * (18 - length))) +
     ([.top_logprobs[] | "\(.token | @json) \((.logprob | exp * 1000 | round) / 10)%"] | join("   ")))
  end'
