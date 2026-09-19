#!/bin/bash
# Tear down workshop seats: stop their containers, remove their volumes, delete users + homes.
# Run as root. Same SEATS/START_ID/END_ID semantics as makeuser.sh (default 2 seats, ids 10-11).
#
# Usage:  ./rmuser.sh            SEATS=5 START_ID=30 ./rmuser.sh
set -uo pipefail

SEATS="${SEATS:-2}"
START_ID="${START_ID:-10}"
END_ID="${END_ID:-$((START_ID + SEATS - 1))}"

for i in $(seq "$START_ID" "$END_ID"); do
    USERNAME="workshop$i"
    if ! id "$USERNAME" &>/dev/null; then echo "$USERNAME not found, skipping."; continue; fi
    echo "== $USERNAME"
    # Compose projects are named after WORKSHOPUID (see Lab 00 compose: `name: ${WORKSHOPUID}`),
    # so tear down by project label, then anything else the user owns.
    # Lab 05's litellm stack is its own compose project, named "${i}litellm", it survived teardown
    # until this loop covered it (port <ID>00 was left listening otherwise).
    for proj in "$i" "${i}litellm"; do
        docker ps -aq --filter "label=com.docker.compose.project=$proj" | xargs -r docker rm -f
        docker volume ls -q --filter "label=com.docker.compose.project=$proj" | xargs -r docker volume rm -f
        docker network ls -q --filter "label=com.docker.compose.project=$proj" | xargs -r docker network rm 2>/dev/null
    done
    pkill -u "$USERNAME" 2>/dev/null; sleep 1
    userdel -r -f "$USERNAME" 2>/dev/null
done
echo "Done."
