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
SEATS_MODE=fix; DOCS=1; REGEN=""
for a in "$@"; do case "$a" in
    --reset-seats) SEATS_MODE=reset ;; --no-seats) SEATS_MODE=none ;; --no-docs) DOCS=0 ;; --regen) REGEN=1 ;;
    *) sed -n '2,15p' "$0" | sed 's/^# \?//'; exit 1 ;;
esac; done

step() { printf '\n\033[1;35m▶ %s\033[0m\n' "$*"; }

step "1/4 sync authoring repo -> $HOST:/opt/workshop/src"
"$HERE/sync-repo.sh" | tail -2

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

case "$SEATS_MODE" in
  fix)
    step "4/4 update seats in place (keeps student edits)"
    ssh "$HOST" 'set -u; S="${SEATS:-2}"; B="${START_ID:-10}"; ok=0; bad=""
      for i in $(seq "$B" $((B+S-1))); do u=workshop$i; h=/home/$u/jarvis; [ -d "$h/.git" ] || continue
        if sudo -u "$u" bash -c "cd $h && git fetch -q --tags --force origin && git reset -q --keep origin/main" 2>/dev/null; then ok=$((ok+1)); else bad="$bad $u"; fi
      done
      echo "  $ok seat(s) updated in place"
      [ -z "$bad" ] || echo "  NEEDS A LOOK (local edit collides with your change):$bad   -> reset-seats.sh for just that seat, or resolve by hand"' ;;
  reset)
    step "4/4 wipe + re-clone every seat (--reset-seats)"
    ssh "$HOST" "/opt/workshop/src/instructor/runbook/scripts/reset-seats.sh" | tail -2 ;;
  none)
    step "4/4 seats left alone (--no-seats): they cannot pull until you run redeploy.sh again without it, or reset-seats.sh" ;;
esac

step "done"
ssh "$HOST" "/opt/workshop/src/instructor/runbook/scripts/release-stage.sh" | tail -1
