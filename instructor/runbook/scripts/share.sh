#!/bin/bash
# Release workshop material to the students, one piece at a time. Runs ON THE LAB HOST.
#
# staged/  everything that has been built and shipped   (not served)
# live/    what students can actually download          (this is the web root)
#
#   TO RELEASE A LAB, USE release-stage.sh: it gives the seats the files AND publishes the page
#   here. Publishing a lab page with this tool alone leaves students reading a handout for files
#   they don't have (it warns). This tool is for slides, materials, take-home PDFs, walkthroughs.
#
#   share status                 what is live, what is still staged
#   share publish 02-shadow-ai   release one item (substring match; its .html AND .pdf)
#   share publish 02-shadow-ai html      ...just the web page   (during the lab)
#   share publish --labs         release a whole category: --labs --slides --materials
#   share publish --labs html    ...web pages only; "pdf" for the take-home copies
#   share publish --all          release everything EXCEPT the walkthroughs
#   share publish --all pdf      end of day: every take-home PDF, still no walkthroughs
#   share publish --walkthroughs release the full step-by-step, answers included
#   share unpublish 02-shadow-ai
#   share refresh                re-copy every live file from staged (after a rebuild; releases nothing new)
#   share url                    print the URL to read out to the room
#
# Every document exists twice: NAME.html (rendered for the browser, Copy button on each code block,
# what students work from during a lab) and NAME.pdf (the take-home). Copying commands out of a
# PDF inserts a newline at every visual line and breaks them, so release the .html first.
#
# Walkthroughs carry every answer, so --all deliberately leaves them out: releasing everything is
# a thing you do at the end of a day, and it should never quietly hand over the answer keys.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${SHARE_ROOT:-/opt/workshop/share}"
STAGED="$ROOT/staged"; LIVE="$ROOT/live"
# Public name of the lab host: SHARE_HOST or LAB_HOST in the environment, else LAB_HOST from .env.
HOSTNAME_PUB="${SHARE_HOST:-${LAB_HOST:-$(sed -n 's/^LAB_HOST="\(.*\)"$/\1/p' /opt/workshop/.env 2>/dev/null)}}"
HOSTNAME_PUB="${HOSTNAME_PUB:-$(hostname -f)}"
install -d -m 755 "$STAGED" "$LIVE" 2>/dev/null || true

rel()  { find "$1" \( -name '*.pdf' -o -name '*.html' \) -printf '%P\n' 2>/dev/null | sort; }
is_live() { [ -f "$LIVE/$1" ]; }

cmd_status() {
    local n_live=0 n_staged=0
    echo "live at https://$HOSTNAME_PUB/"
    while read -r f; do
        [ -z "$f" ] && continue
        if is_live "$f"; then printf '  \033[32m●\033[0m %s\n' "$f"; n_live=$((n_live+1))
        else                  printf '    \033[90m%s\033[0m\n' "$f"; n_staged=$((n_staged+1)); fi
    done <<< "$(rel "$STAGED")"
    echo
    local wt_live
    wt_live=$(rel "$LIVE" | grep -c '^walkthroughs/' || true)
    echo "  $n_live live · $n_staged staged and not yet released"
    if [ "$wt_live" -gt 0 ]; then
        printf '  \033[33m%s walkthrough(s) live: those contain every answer\033[0m\n' "$wt_live"
    else
        echo "  walkthroughs (answers) are staged but not released; --all will not release them"
    fi
    # anything live that is no longer staged (e.g. renamed upstream) is worth surfacing
    while read -r f; do
        [ -z "$f" ] && continue
        [ -f "$STAGED/$f" ] || printf '  \033[33m?\033[0m %s (live but not in staged)\n' "$f"
    done <<< "$(rel "$LIVE")"
}

matches() {  # substring -> staged paths
    local q="$1"
    rel "$STAGED" | grep -i -- "$q" || true
}

move() {     # publish|unpublish, file
    local action="$1" f="$2"
    if [ "$action" = publish ]; then
        install -D -m 644 "$STAGED/$f" "$LIVE/$f"
        printf '  published  %s\n' "$f"
        # A lab handout whose stage the students don't have yet: say so, loudly.
        case "$f" in labs/*)
            local stage
            stage=$("$HERE/lab-stage-map.py" 2>/dev/null | awk -F'\t' -v d="${f%.*}" '$2==d{print $1}')
            if [ -n "$stage" ] && ! git --git-dir="${BARE:-/opt/gitsrv/jarvis.git}" rev-parse -q --verify "refs/tags/$stage" >/dev/null 2>&1; then
                printf '  \033[33m!! %s is live but its stage %s is NOT released: students can read it and have none of the files.\033[0m\n' "$f" "$stage"
                printf '  \033[33m   run:  release-stage.sh %s   (it publishes this page too)\033[0m\n' "$stage"
            fi ;;
        esac
    else
        # -mindepth 1: never delete live/ itself, it is the server's bind-mount target,
        # and removing it breaks the mount on the next container restart.
        rm -f "$LIVE/$f"; find "$LIVE" -mindepth 1 -type d -empty -delete 2>/dev/null || true
        printf '  withdrawn  %s\n' "$f"
    fi
}

cmd_move() {
    local action="$1"; shift
    [ $# -gt 0 ] || { echo "what? try: share $action --all | --labs | <name> [html|pdf]   (share status to list)" >&2; exit 1; }
    local sel=() SRC="$STAGED" fmt="${2:-}"
    case "$fmt" in ""|html|pdf) ;; *) echo "second word must be html or pdf, not '$fmt'" >&2; exit 1 ;; esac
    # withdrawing operates on what is actually live; publishing on what is staged
    [ "$action" = unpublish ] && SRC="$LIVE"
    case "$1" in
        # ASYMMETRIC ON PURPOSE. Publishing everything must never sweep in the answer keys, but
        # WITHDRAWING everything must never leave them behind: the unsafe direction has to be the
        # one that takes an extra word, not the one that happens by default.
        --all)  if [ "$action" = publish ]; then
                    mapfile -t sel < <(rel "$STAGED" | grep -v '^walkthroughs/')
                else
                    mapfile -t sel < <(rel "$LIVE")
                fi ;;
        --labs)         mapfile -t sel < <(rel "$SRC" | grep '^labs/') ;;
        --slides)       mapfile -t sel < <(rel "$SRC" | grep '^slides/') ;;
        --materials)    mapfile -t sel < <(rel "$SRC" | grep '^materials/') ;;
        --walkthroughs) mapfile -t sel < <(rel "$SRC" | grep '^walkthroughs/') ;;
        --everything)   mapfile -t sel < <(rel "$SRC") ;;   # including the answers
        *)
            mapfile -t sel < <(rel "$SRC" | grep -i -- "$1" || true)
            if [ "${#sel[@]}" -eq 0 ]; then
                echo "nothing staged matches '$1'. Try: share status" >&2; exit 1
            # one document = its .html and its .pdf; anything beyond that one stem is ambiguous
            elif [ "$(printf '%s\n' "${sel[@]}" | sed 's/\.[a-z]*$//' | sort -u | wc -l)" -gt 1 ]; then
                echo "'$1' matches several, be more specific:" >&2
                printf '  %s\n' "${sel[@]}" >&2; exit 1
            fi ;;
    esac
    [ -n "$fmt" ] && mapfile -t sel < <(printf '%s\n' "${sel[@]}" | grep "\.$fmt\$" || true)
    [ "${#sel[@]}" -gt 0 ] || { echo "nothing to do" >&2; exit 1; }
    for f in "${sel[@]}"; do [ -n "$f" ] && move "$action" "$f"; done
    echo
    echo "  $(rel "$LIVE" | wc -l) items now live at https://$HOSTNAME_PUB/"
}

cmd_refresh() {
    local n=0
    while read -r f; do
        [ -n "$f" ] && [ -f "$STAGED/$f" ] || continue
        cmp -s "$STAGED/$f" "$LIVE/$f" || { install -D -m 644 "$STAGED/$f" "$LIVE/$f"; n=$((n+1)); }
    done <<< "$(rel "$LIVE")"
    echo "  refreshed $n live file(s) from staged; $(rel "$LIVE" | wc -l) live, nothing newly released"
}

case "${1:-status}" in
    status|"")  cmd_status ;;
    refresh)    cmd_refresh ;;
    publish)    shift; cmd_move publish "$@" ;;
    unpublish)  shift; cmd_move unpublish "$@" ;;
    url)        echo "https://$HOSTNAME_PUB/  (user: ${SHARE_USER:-workshop})" ;;
    *)          sed -n '2,20p' "$0" | sed 's/^# \?//' ;;
esac
