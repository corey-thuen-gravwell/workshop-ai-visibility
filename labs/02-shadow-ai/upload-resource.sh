#!/bin/bash
# Upload a lookup file as a Gravwell resource. Lab 02 needs two of these.
#
#   ./upload-resource.sh AI_DOMAINS          datasets/resources/ai_domains.txt
#   ./upload-resource.sh AI_DOMAINS_PLUS_API datasets/resources/ai_domains_plus_api.txt
#
# It is a two-step API call, create the resource, then PUT the file content, which is why this
# script exists rather than a one-liner in the handout. The UI path (Resources -> Add resource)
# does the same thing.
set -euo pipefail

NAME="${1:?usage: $0 <RESOURCE_NAME> <file>}"
FILE="${2:?usage: $0 <RESOURCE_NAME> <file>}"
: "${WORKSHOPUID:?not set, run '. ~/.workshop_env' first}"
GW="https://localhost:${WORKSHOPUID}443"

[ -f "$FILE" ] || { echo "no such file: $FILE" >&2; exit 1; }

# Authenticate with the API token Lab 00 minted (make-token.sh), not with a login. A login is tied
# to the admin password, so it breaks the moment you change that password; the token does not.
TOKEN="${GRAVWELL_TOKEN:-$(cat "$HOME/.gravwell_token" 2>/dev/null || true)}"
if [ -z "$TOKEN" ]; then
    echo "No Gravwell API token. Mint one, it takes a second:" >&2
    echo "  ~/jarvis/labs/00-environment-gravwell/make-token.sh && . ~/.workshop_env" >&2
    exit 1
fi
AUTH=(-H "Gravwell-Token: $TOKEN")

# Already there? Gravwell allows duplicate names; re-uploading is confusing, so stop.
if curl -sk "$GW/api/resources" "${AUTH[@]}" | grep -q "\"$NAME\""; then
    echo "resource '$NAME' already exists, nothing to do."
    exit 0
fi

guid=$(curl -sk -X POST "$GW/api/resources" "${AUTH[@]}" \
    -H 'content-type: application/json' \
    -d "{\"ResourceName\":\"$NAME\",\"Description\":\"$NAME lookup (Lab 02)\",\"Global\":true}" \
    | sed -n 's/.*"GUID":"\([^"]*\)".*/\1/p')
[ -n "$guid" ] || { echo "could not create it: is Gravwell up, and your token valid?" >&2; exit 1; }

code=$(curl -sk -o /dev/null -w '%{http_code}' -X PUT "$GW/api/resources/$guid/raw" \
    "${AUTH[@]}" -F "file=@$FILE")
[ "$code" = "200" ] || { echo "upload failed (HTTP $code)" >&2; exit 1; }

echo "$NAME uploaded ($(wc -l < "$FILE") lines). Use it as: lookup -s -r $NAME <field> Domain"
