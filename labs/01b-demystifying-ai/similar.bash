#!/usr/bin/env bash
# Lab 01b, "close" vectors mean "similar" text (slide: "What's an embedding?")
#
# Embeds every word you give it in ONE request, then prints the cosine similarity between each
# pair (1.0 = identical direction, 0.0 = unrelated) and each word's nearest neighbour. Plain
# high-school geometry on the vectors from embed.bash, no model involved in the comparison.
#
# Usage:
#   ./similar.bash                                # the deck's examples
#   ./similar.bash cat dog kitten firewall
set -euo pipefail
# A relay on this host adds the credential for the model. You never see a token; you never need one.
GRAVWELL_LLM_URL="${GRAVWELL_LLM_URL:-http://127.0.0.1:9010}"
MODEL="${EMBED_MODEL:-qwen3-embedding}"

[ $# -gt 0 ] || set -- king queen throne potato fries Idaho firewall syslog

payload=$(jq -n --arg m "$MODEL" '{model:$m, input:$ARGS.positional}' --args "$@")
{ echo "request  POST ${GRAVWELL_LLM_URL}/api/embed"; echo "$payload"; echo "response  (one vector per word: cosine similarity computed locally)"; echo; } >&2

curl -sS --fail-with-body "${GRAVWELL_LLM_URL}/api/embed" \
    -H 'content-type: application/json' -d "$payload" \
| python3 -c '
import json, math, sys
words = sys.argv[1:]
E = json.load(sys.stdin)["embeddings"]
def cos(a, b):
    return sum(x*y for x, y in zip(a, b)) / math.sqrt(sum(x*x for x in a) * sum(y*y for y in b))
w = max(len(x) for x in words) + 1
print(f"{len(E)} vectors x {len(E[0])} dimensions\n")
print(" " * w + "".join(f"{x[:8]:>9}" for x in words))
for i, a in enumerate(words):
    print(f"{a:>{w}}" + "".join(f"{cos(E[i], E[j]):9.3f}" for j in range(len(words))))
print()
for i, a in enumerate(words):
    j = max((j for j in range(len(words)) if j != i), key=lambda j: cos(E[i], E[j]))
    print(f"{a:>{w}}  is nearest to  {words[j]}  ({cos(E[i], E[j]):.3f})")
' "$@"
