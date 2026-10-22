#!/bin/bash
# You edited a lab. Push everything that depends on it, in one go. Run FROM THE AUTHORING BOX.
#
#   redeploy.sh                # sync repo -> host, rebuild docs + ship, rebuild student repo,
#                              #   refresh the live share files, update every seat IN PLACE
#   redeploy.sh --reset-seats  # ...and instead wipe + re-clone every seat (loses student work)
#   redeploy.sh --no-seats     # ...and leave seats alone (they can't pull until fixed/reset)
#   redeploy.sh --no-docs      # skip the PDF/HTML build (fast: repo + seats only)
#   redeploy.sh --regen        # ALSO regenerate the Lab 02/03/P8/P9 data (morning of class).
#                              # Default is to reuse the data already on the host: regenerating
#                              # re-anchors every timestamp, which changes the dataset files and
#                              # therefore every stage hash from Lab 02 on, for no benefit mid-class.
#
# What "update in place" means: the student repo is rebuilt (its history changes shape), so each
# seat gets `git fetch` + `git reset --keep origin/main`: HEAD moves to the rebuilt history at the
# SAME released stage, tags are refreshed, and uncommitted student edits are kept. A seat whose
# edited file was itself changed by your fix is reported and left for a manual look.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
HOST="${HOST:-jarvis}"
# Seat range. Whatever is set here travels to the host (the host-side scripts fall back to
# /opt/workshop/.env, then to 2 seats from id 10). An unset range used to mean "2 seats" on the
# host whatever the class size, which updated two seats in place and stranded the rest.
SEAT_ENV=""; for v in SEATS START_ID END_ID; do [ -n "${!v:-}" ] && SEAT_ENV+="$v=${!v} "; done   # empty when none set (a bare "= " used to run as a command)
SEATS_MODE=fix; DOCS=1; REGEN=""
for a in "$@"; do case "$a" in
    --reset-seats) SEATS_MODE=reset ;; --no-seats) SEATS_MODE=none ;; --no-docs) DOCS=0 ;; --regen) REGEN=1 ;;
    *) sed -n '2,15p' "$0" | sed 's/^# \?//'; exit 1 ;;
esac; done

step() { printf '\n\033[1;35m▶ %s\033[0m\n' "$*"; }

step "1/4 sync authoring repo -> $HOST:/opt/workshop/src"
sync_log="$(mktemp)"; "$HERE/sync-repo.sh" | tee "$sync_log" | tail -2
# A running seat stack does not pick up a changed compose or listener config on its own: the
# container keeps the old inode of a bind-mounted file, and `up -d` sees nothing to recreate.
if grep -qE '^\s*[>.*c<]\S* +labs/00-environment-gravwell/' "$sync_log"; then
    printf '\n\033[1;33m  Lab 00 compose/config changed. Seats with a running stack need, as the seat user:\n'
    printf '    cd ~/jarvis/labs/00-environment-gravwell && docker compose up -d --force-recreate gravwell\n'
    printf '  (preflight.sh checks for stale stacks; reset-seats.sh recreates them)\033[0m\n'
fi
rm -f "$sync_log"

if [ "$DOCS" = 1 ]; then
    step "2/4 rebuild handouts + decks, ship to staged/, refresh what is live"
    "$HERE/deploy-share.sh" --rebuild 2>&1 | grep -E "rendered|shipping|FAIL|chars|refusing" || true
    ssh "$HOST" "/opt/workshop/src/instructor/runbook/scripts/share.sh refresh" | tail -2
else
    step "2/4 docs skipped (--no-docs)"
fi

step "3/4 rebuild the student repo on $HOST (keeps the released stage$([ -n "$REGEN" ] && echo ', regenerating data' || echo ', data reused'))"
SKIP="SKIP_GENERATE=1"; [ -n "$REGEN" ] && SKIP=""
ssh "$HOST" "cd / && $SKIP /opt/workshop/src/instructor/runbook/scripts/build-student-repo.sh" 2>&1 \
    | grep -E "Regenerating|SKIP_GENERATE|released|verified|FATAL|LEAK|NOTE|stage-.*\(\+" || true
# A failed build (leak assertion, add-only violation, missing license) must stop here: step 4 would
# otherwise move every seat onto whatever half-built history is on the host and print "done".
[ "${PIPESTATUS[0]}" -eq 0 ] || { printf '\n\033[1;31mbuild-student-repo.sh failed on %s; seats left untouched\033[0m\n' "$HOST" >&2; exit 1; }

case "$SEATS_MODE" in
  fix)
    step "4/4 update seats in place (keeps student edits)"
    ssh "$HOST" "$SEAT_ENV"' set -u; [ -f /opt/workshop/.env ] && { S=$(sed -n "s/^SEATS=\"\{0,1\}\([0-9]*\).*/\1/p" /opt/workshop/.env); B=$(sed -n "s/^START_ID=\"\{0,1\}\([0-9]*\).*/\1/p" /opt/workshop/.env); }
      S="${SEATS:-${S:-2}}"; B="${START_ID:-${B:-10}}"; ok=0; bad=""
      for i in $(seq "$B" $((B+S-1))); do u=workshop$i; h=/home/$u/jarvis; [ -d "$h/.git" ] || continue
        if sudo -u "$u" bash -c "cd $h && git fetch -q --tags --force origin && git reset -q --keep origin/main" 2>/dev/null; then ok=$((ok+1)); else bad="$bad $u"; fi
      done
      echo "  $ok seat(s) updated in place"
      [ -z "$bad" ] || echo "  NEEDS A LOOK (local edit collides with your change):$bad   -> reset-seats.sh for just that seat, or resolve by hand"' ;;
  reset)
    step "4/4 wipe + re-clone every seat (--reset-seats)"
    ssh "$HOST" "$SEAT_ENV /opt/workshop/src/instructor/runbook/scripts/reset-seats.sh" | tail -2 ;;
  none)
    step "4/4 seats left alone (--no-seats): they cannot pull until you run redeploy.sh again without it, or reset-seats.sh" ;;
esac

step "done"
ssh "$HOST" "/opt/workshop/src/instructor/runbook/scripts/release-stage.sh" | tail -1
