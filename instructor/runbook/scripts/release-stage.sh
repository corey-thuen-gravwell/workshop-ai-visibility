#!/bin/bash
# Release the next lab to the students. Runs ON THE LAB HOST as root.
#
# build-student-repo.sh writes the complete, linear student history to $ALL (root-only) and the
# students clone $SERVED, which only reaches as far as you have released. Each release
# fast-forwards $SERVED to a later stage and pushes its tag; students then run
#       cd ~/jarvis && git pull
# and the new lab directory appears. THIS IS THE ONE COMMAND THAT RELEASES A LAB: it also puts
# the lab's web page (NAME.html) on the share site, so the handout and the files arrive together.
# share.sh on its own only moves documents; publishing a lab page there does NOT give seats the
# files (found the hard way). Take-home PDFs stay a share.sh decision (publish --all pdf). Nothing they have done is touched: a stage only ADDS files,
# so the pull succeeds even with their edits in place (the build script enforces add-only).
#
#   release-stage.sh                    # what is released, what is next
#   release-stage.sh --next             # release the next stage
#   release-stage.sh stage-shadowai     # release everything up to and including that stage
#   release-stage.sh --all              # release every built stage (end of course / dry run)
#
# Releasing is one-way. To take a lab back you would have to rewrite the students' clones; if you
# really need that, rebuild + reset-seats.sh (which re-clones and loses their work).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ALL="${BARE_ALL:-/opt/gitsrv/jarvis-all.git}"
SERVED="${BARE:-/opt/gitsrv/jarvis.git}"

die() { printf '\033[1;31m%s\033[0m\n' "$*" >&2; exit 1; }
[ -d "$ALL" ]    || die "no complete history at $ALL, run build-student-repo.sh first"
[ -d "$SERVED" ] || die "no served repo at $SERVED, run build-student-repo.sh first"
[ -f "$ALL/stages.txt" ] || die "$ALL/stages.txt missing: rebuild with the current build-student-repo.sh"

mapfile -t STAGES < "$ALL/stages.txt"                       # in order, one tag per line
served_head=$(git --git-dir="$SERVED" rev-parse -q --verify refs/heads/main 2>/dev/null || true)

released_idx=-1
for i in "${!STAGES[@]}"; do
    c=$(git --git-dir="$ALL" rev-parse -q --verify "refs/tags/${STAGES[$i]}^{commit}")
    if [ -n "$served_head" ] && git --git-dir="$ALL" merge-base --is-ancestor "$c" "$served_head" 2>/dev/null; then
        released_idx=$i
    fi
done

status() {
    echo "students clone: $SERVED"
    for i in "${!STAGES[@]}"; do
        if [ "$i" -le "$released_idx" ]; then printf '  \033[32m●\033[0m %s\n' "${STAGES[$i]}"
        elif [ "$i" -eq $((released_idx + 1)) ]; then printf '  \033[33m→\033[0m %s   (next)\n' "${STAGES[$i]}"
        else printf '    \033[90m%s\033[0m\n' "${STAGES[$i]}"; fi
    done
    echo
    if [ "$released_idx" -ge 0 ]; then
        echo "  released through ${STAGES[$released_idx]}. Students get the next lab with:  cd ~/jarvis && git pull"
    else
        echo "  nothing released yet"
    fi
}

release_to() {   # index
    local target=$1 t c
    [ "$target" -gt "$released_idx" ] || { echo "  ${STAGES[$target]} is already released"; return 0; }
    t="${STAGES[$target]}"
    c=$(git --git-dir="$ALL" rev-parse "refs/tags/$t^{commit}")
    # Fast-forward only. If the served main is not an ancestor, the history was rebuilt underneath
    # the students and a push here would strand every clone, stop and say so.
    if [ -n "$served_head" ] && ! git --git-dir="$ALL" merge-base --is-ancestor "$served_head" "$c"; then
        die "served main ($served_head) is not an ancestor of $t: history was rebuilt since the students cloned.
      Either rebuild and reset-seats.sh (loses student work), or release from the rebuilt history only after re-cloning."
    fi
    git --git-dir="$ALL" push -q "$SERVED" "$c:refs/heads/main"
    for i in $(seq 0 "$target"); do
        git --git-dir="$ALL" push -q "$SERVED" "refs/tags/${STAGES[$i]}:refs/tags/${STAGES[$i]}" 2>/dev/null || true
    done
    chmod -R a+rX "$SERVED"
    for i in $(seq $((released_idx + 1)) "$target"); do
        printf '  released  %s\n' "${STAGES[$i]}"
        # ...and the matching handout page(s) on the share site, html only
        while IFS=$'\t' read -r st doc; do
            [ "$st" = "${STAGES[$i]}" ] || continue
            [ -n "${NO_SHARE:-}" ] && { printf '            (share: %s.html skipped, NO_SHARE set)\n' "$doc"; continue; }
            "$HERE/share.sh" publish "$doc" html 2>/dev/null | grep -E "published|nothing" | sed 's/^/            share: /' \
                || printf '            share: %s.html not staged (run deploy-share.sh), page NOT published\n' "$doc"
        done < <("$HERE/lab-stage-map.py" 2>/dev/null)
    done
    released_idx=$target; served_head=$c
    echo
    echo "  Students: cd ~/jarvis && git pull        (new directory: see the lab's README)"
}

case "${1:-}" in
    ""|status) status ;;
    --next)
        [ $((released_idx + 1)) -lt "${#STAGES[@]}" ] || die "everything is already released"
        release_to $((released_idx + 1)) ;;
    --all)  release_to $((${#STAGES[@]} - 1)) ;;
    stage-*)
        idx=-1; for i in "${!STAGES[@]}"; do [ "${STAGES[$i]}" = "$1" ] && idx=$i; done
        [ "$idx" -ge 0 ] || die "unknown stage '$1'. Built stages: ${STAGES[*]}"
        release_to "$idx" ;;
    *) sed -n '2,18p' "$0" | sed 's/^# \?//' ;;
esac
