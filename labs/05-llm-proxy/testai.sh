#!/usr/bin/env bash
# Lab 05 (M8): drive the litellm gateway so there is traffic to look at in Gravwell.
#
# Checkpoint: stage-llm-proxy
#
# Usage:
#   ./testai.sh                 # 4 prompts through the gateway
#   N=10 ./testai.sh            # more traffic
#   MODEL=claude-fast ./testai.sh
#   PROXY=http://localhost:1290 ./testai.sh    # point at the Python proxy instead (Part 2b)
set -euo pipefail

: "${WORKSHOPUID:?not set, run '. ~/.workshop_env' first}"
PROXY="${PROXY:-http://localhost:${WORKSHOPUID}00}"
KEY="${LITELLM_MASTER_KEY:-sk-workshop}"
MODEL="${MODEL:-claude}"
N="${N:-1}"

PROMPTS=(
    "Which model are you running? Answer in one short sentence."
    "In one sentence: what is a reverse proxy?"
    "List three log sources a SOC should collect. Just the list."
    "What is the capital of Idaho? One word."
)

echo "==> ${PROXY}  model=${MODEL}  rounds=${N}"

# The routing table is the one genuinely useful thing a generic gateway gives you.
echo "--- models the gateway advertises:"
curl -sS "${PROXY}/v1/models" -H "Authorization: Bearer ${KEY}" \
    | { jq -r '.data[].id' 2>/dev/null || cat; }

for round in $(seq 1 "$N"); do
    for p in "${PROMPTS[@]}"; do
        printf '\n--- [%s/%s] %s\n' "$round" "$N" "$p"
        curl -sS "${PROXY}/v1/chat/completions" \
            -H "Authorization: Bearer ${KEY}" \
            -H 'content-type: application/json' \
            -d "$(jq -n --arg m "$MODEL" --arg p "$p" \
                  '{model:$m, max_tokens:200, messages:[{role:"user",content:$p}]}')" \
            | { jq -r '.choices[0].message.content // .error.message // .' 2>/dev/null || cat; }
    done
done

cat <<'NOTE'

==> Done. Now go look at what the gateway actually recorded:

      tag=syslog grep HTTP

    You should be able to see THAT these requests happened. See if you can find:
      - the text of any prompt you just sent
      - the model's answer
      - which tools the caller was offered

    (You can't. That's the module.)
NOTE
