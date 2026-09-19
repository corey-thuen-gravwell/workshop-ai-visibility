#!/bin/bash
# seat-survey.sh - where is the room? Runs ON THE LAB HOST as root. READ-ONLY.
#
# Answers the two questions you actually ask mid-class:
#   1. What lab is each seat on?          (evidence columns: containers, ingested data, artifacts)
#   2. Have they pulled the lab I just released?   (CLONE vs the served repo's head)
#   3. Lab 05: which proxies is each seat actually listening on?  (netstat, PROXIES column)
#
# It touches nothing: no git writes, no config, no container changes. Safe to run any time,
# including while students are typing.
#
#   ./seat-survey.sh              full survey (docker exec per seat for ingest volume: ~20s)
#   ./seat-survey.sh --fast       skip the ingest measurement (no docker exec; instant)
#   ./seat-survey.sh --tags       ALSO ask each seat's Gravwell what tags it holds, and how many
#                                 entries in each. Slower (one search per running seat), and the
#                                 precise answer to "has Lab 02 landed on that seat"
#   ./seat-survey.sh --tsv        machine-readable, one line per seat, no colour
#   ./seat-survey.sh 11 14 22     only those seats
#
# With no seat numbers it surveys every workshop<NN> account that exists. SEATS= / START_ID= work
# the way they do in the other scripts if you would rather name a range.
#
# Nothing here is authoritative about what a student has *understood* - only about what their
# filesystem and containers show. The "LAB" column is the furthest lab with evidence, capped by
# what you have released.
set -uo pipefail

ALL="${BARE_ALL:-/opt/gitsrv/jarvis-all.git}"
SERVED="${BARE:-/opt/gitsrv/jarvis.git}"
SRC="${WORKSHOP_SRC:-/opt/workshop/src}"
SHARE_ROOT="${SHARE_ROOT:-/opt/workshop/share}"
# Default: every seat account that exists. A range only if the operator asks for one.
if [ -n "${SEATS:-}" ] || [ -n "${START_ID:-}" ]; then
    START_ID="${START_ID:-10}"; END_ID="${END_ID:-$((START_ID + ${SEATS:-2} - 1))}"
    DISCOVER=""
else
    START_ID=10; END_ID=49; DISCOVER=1
fi
GW_BASELINE_KB="${GW_BASELINE_KB:-720}"     # an untouched seat's /opt/gravwell/storage, measured
GW_INGEST_KB="${GW_INGEST_KB:-400}"         # above baseline before it counts as student ingest:
                                            # Gravwell logs itself to tag=gravwell and a seat that
                                            # has done nothing still creeps up ~150K in an hour
GW_LAB03_KB="${GW_LAB03_KB:-2500}"          # corelight is ~660K raw, sysmon ~3.6M: a crude tier

FAST=""; TSV=""; TAGS=""; SEAT_ARGS=()
for a in "$@"; do case "$a" in
    --fast) FAST=1 ;;
    --tags) TAGS=1 ;;
    --tsv)  TSV=1 ;;
    -h|--help) sed -n '2,26p' "$0" | sed 's/^# \?//'; exit 0 ;;
    [0-9]*) SEAT_ARGS+=("$a") ;;
    *) echo "unknown argument: $a (try --help)" >&2; exit 2 ;;
esac; done
if [ ${#SEAT_ARGS[@]} -gt 0 ]; then
    SEATS=("${SEAT_ARGS[@]}")
elif [ -n "$DISCOVER" ]; then
    # every workshop<NN> account on the box, in order. No range to remember, no empty rows.
    SEATS=($(getent passwd | sed -n 's/^workshop\([0-9][0-9]*\):.*/\1/p' | sort -n))
    [ ${#SEATS[@]} -eq 0 ] && { echo "no workshop<NN> accounts on this host" >&2; exit 1; }
else
    SEATS=($(seq "$START_ID" "$END_ID"))
fi

if [ -n "$TSV" ]; then G=""; Y=""; R=""; D=""; B=""; N=""
else G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[1;31m'; D=$'\033[90m'; B=$'\033[1m'; N=$'\033[0m'; fi

[ -d "$ALL" ]    || { echo "no complete history at $ALL" >&2; exit 1; }
[ -d "$SERVED" ] || { echo "no served repo at $SERVED" >&2; exit 1; }

# ---- listening ports, one snapshot for the whole survey (netstat -tlnp, root sees the owners) --
# docker-published ports show up as docker-proxy listeners on 0.0.0.0; the Python proxy binds
# 0.0.0.0:<ID>90 itself; the gateway stretch binds 127.0.0.1:<ID>92.
LISTEN_PORTS=" $( (netstat -tlnp 2>/dev/null || ss -tlnp 2>/dev/null) | awk 'NR>1 {print $4}' | sed 's/.*://' | grep -E '^[0-9]+$' | sort -un | tr '\n' ' ') "
listening() { case "$LISTEN_PORTS" in *" $1 "*) return 0;; *) return 1;; esac; }

# ---- the class's own state ---------------------------------------------------------------------
mapfile -t STAGES < "$ALL/stages.txt"
served_head=$(git --git-dir="$SERVED" rev-parse -q --verify refs/heads/main 2>/dev/null || true)

released_idx=-1
for i in "${!STAGES[@]}"; do
    c=$(git --git-dir="$ALL" rev-parse -q --verify "refs/tags/${STAGES[$i]}^{commit}" 2>/dev/null) || continue
    if [ -n "$served_head" ] && git --git-dir="$ALL" merge-base --is-ancestor "$c" "$served_head" 2>/dev/null; then
        released_idx=$i
    fi
done

# stage -> "Lab 02 (M4)", straight out of the checkpoint manifest so it cannot drift
declare -A MODULE
if [ -f "$SRC/student-repo/checkpoints.yaml" ]; then
    tag=""
    while IFS= read -r line; do
        case "$line" in
            *"- tag:"*)    tag="${line#*- tag: }"; tag="${tag%% *}" ;;
            *"module:"*)   [ -n "$tag" ] && MODULE[$tag]="$(echo "${line#*module: }" | sed 's/[[:space:]]*$//')" ;;
        esac
    done < "$SRC/student-repo/checkpoints.yaml"
fi
mod() { echo "${MODULE[$1]:-$1}"; }

# how far each stage index is "worth" as a lab label, for the evidence -> lab mapping
stage_idx() { local t="$1" i; for i in "${!STAGES[@]}"; do [ "${STAGES[$i]}" = "$t" ] && { echo "$i"; return; }; done; echo -1; }

ago() {  # unix ts -> "4m" / "2h10" / "-"
    local t="$1" now s
    if [ -z "$t" ] || [ "$t" = 0 ]; then echo "-"; return; fi
    now=$(date +%s); s=$((now - t))
    if   [ "$s" -lt 90 ];   then echo "${s}s"
    elif [ "$s" -lt 5400 ]; then echo "$((s/60))m"
    else echo "$((s/3600))h$(( (s%3600)/60 ))"; fi
}

if [ -z "$TSV" ]; then
    printf '%s\n' "${B}class state${N}   $(date -u '+%Y-%m-%d %H:%MZ')"
    if [ "$released_idx" -ge 0 ]; then
        printf '  released through  %s%s%s   (%s)\n' "$G" "${STAGES[$released_idx]}" "$N" "$(mod "${STAGES[$released_idx]}")"
    else
        printf '  %snothing released yet%s\n' "$R" "$N"
    fi
    nx=$((released_idx + 1))
    if [ "$nx" -lt "${#STAGES[@]}" ]; then
        printf '  next up           %s%s%s   (%s)   <- release-stage.sh --next\n' "$Y" "${STAGES[$nx]}" "$N" "$(mod "${STAGES[$nx]}")"
    else
        printf '  next up           %severything is released%s\n' "$D" "$N"
    fi
    if [ -d "$SHARE_ROOT/live" ]; then
        nlive=$(find "$SHARE_ROOT/live" \( -name '*.html' -o -name '*.pdf' \) 2>/dev/null | wc -l)
        nwt=$(find "$SHARE_ROOT/live/walkthroughs" -type f 2>/dev/null | wc -l)
        printf '  share site        %s document(s) live' "$nlive"
        [ "$nwt" -gt 0 ] && printf '   %s%s walkthrough(s) LIVE - those are the answers%s' "$R" "$nwt" "$N"
        printf '\n'
    fi
    echo
    printf '%s\n' "${B}SEAT  SH   CLONE              SYNC        PULLED  WORK  GW   LLM  PROXIES  DATA     LAB${N}"
fi

# ---- per seat ----------------------------------------------------------------------------------
behind_seats=(); dirty_seats=(); dead_seats=(); unused_seats=()
no_litellm=(); no_ingester=(); no_pyproxy=(); all_proxies=(); up_seats=()
declare -A TAGLINE

for i in "${SEATS[@]}"; do
    u="workshop$i"; h="/home/$u"; d="$h/jarvis"
    if ! id "$u" >/dev/null 2>&1; then
        [ -z "$TSV" ] && printf '%-5s %s(no such account)%s\n' "$i" "$D" "$N"
        continue
    fi

    # --- git: what have they got, and is it current? ---
    clone="-"; sync="?"; sync_col="$D"; pulled="-"; work="-"; extra=""
    if [ -d "$d/.git" ]; then
        desc=$(sudo -u "$u" git -C "$d" describe --tags 2>/dev/null || echo "")
        near=$(sudo -u "$u" git -C "$d" describe --tags --abbrev=0 2>/dev/null || echo "")
        head=$(sudo -u "$u" git -C "$d" rev-parse -q --verify HEAD 2>/dev/null || echo "")
        clone="${near:-<no tag>}"
        [ "$desc" != "$near" ] && extra="+own"      # they have committed on top
        si=$(stage_idx "$near")
        if [ "$head" = "$served_head" ]; then
            sync="current"; sync_col="$G"
        elif [ "$si" -ge 0 ] && [ "$si" -lt "$released_idx" ]; then
            n=$((released_idx - si)); sync="-${n} stage$([ $n -gt 1 ] && echo s)"; sync_col="$R"
            # a seat nobody has ever logged into is spare, not behind: no fetch and no container
            if [ ! -f "$d/.git/FETCH_HEAD" ] && ! docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "${i}gravwell"; then
                sync="unused"; sync_col="$D"; unused_seats+=("$i")
            else
                behind_seats+=("$i:$clone")
            fi
        elif [ "$si" -gt "$released_idx" ]; then
            sync="AHEAD"; sync_col="$R"            # should be impossible; means a rebuild drifted
        else
            sync="current"; sync_col="$G"           # at the released stage, plus own commits
        fi
        [ -f "$d/.git/FETCH_HEAD" ] && pulled=$(ago "$(stat -c %Y "$d/.git/FETCH_HEAD" 2>/dev/null)")
        work=$(sudo -u "$u" git -C "$d" status --porcelain 2>/dev/null | wc -l)
        [ "$work" -gt 0 ] && dirty_seats+=("$i:$work")
    else
        clone="${R}NO CLONE${N}"; sync="-"
        dead_seats+=("$i")
    fi

    # --- sessions ---
    # OpenSSH 9.8+ splits the per-connection process out as sshd-session, and these do not land in
    # utmp on this host, so `who` shows nothing even with the room logged in. Count the processes.
    nshell=$(pgrep -u "$u" -x sshd-session 2>/dev/null | wc -l)
    nshell=$((nshell + $(pgrep -u "$u" -x sshd 2>/dev/null | wc -l)))
    nproc=$(pgrep -u "$u" 2>/dev/null | wc -l)
    if   [ "$nshell" -gt 0 ]; then ssh_col="$G"; ssh_m="$nshell"
    elif [ "$nproc"  -gt 2 ]; then ssh_col="$Y"; ssh_m="bg"    # no shell, but something is running
    else ssh_col="$D"; ssh_m="-"; fi

    # --- containers ---
    gw="-"; llm="-"; prox="-"
    running=$(docker ps    --format '{{.Names}}' 2>/dev/null | grep -E "^${i}(gravwell|llm|litellm)$" || true)
    everall=$(docker ps -a --format '{{.Names}}' 2>/dev/null | grep -E "^${i}(gravwell|llm|litellm)$" || true)
    grep -qx "${i}gravwell" <<<"$running" && gw="up"   || { grep -qx "${i}gravwell" <<<"$everall" && gw="DOWN"; }
    grep -qx "${i}llm"      <<<"$running" && llm="up"  || { grep -qx "${i}llm"      <<<"$everall" && llm="DOWN"; }
    grep -qx "${i}litellm"  <<<"$running" && prox="up" || { grep -qx "${i}litellm"  <<<"$everall" && prox="DOWN"; }

    [ "$gw" = "up" ] && up_seats+=("$i")

    # --- Lab 05 proxies, by what is actually LISTENING (netstat), not by container names ---
    #   L = litellm          <ID>00        (Part 1)
    #   I = LLM ingester     <ID>80 + <ID>81 (Part 2a; both listeners or it is not "hot")
    #   P = Python proxy     <ID>90        (Part 2b)
    #   G = gateway stretch  <ID>92        (Part 2b step 4, optional)
    pl="."; pi="."; pp="."; pg="."
    listening "${i}00" && pl="L" || no_litellm+=("$i")
    listening "${i}80" && listening "${i}81" && pi="I" || no_ingester+=("$i")
    listening "${i}90" && pp="P" || no_pyproxy+=("$i")
    listening "${i}92" && pg="G"
    proxies="${pl}${pi}${pp}${pg}"
    if   [ "$pl$pi$pp" = "LIP" ]; then prox_col="$G"; all_proxies+=("$i")
    elif [ "$pl$pi$pp" = "..." ]; then prox_col="$D"
    else prox_col="$Y"; fi

    # --- ingested data (the Lab 02 / Lab 03 "prove it landed" step) ---
    data="-"; kb=0; ingested=""; data_col=""
    if [ -z "$FAST" ] && [ "$gw" = "up" ]; then
        kb=$(docker exec "${i}gravwell" du -sk /opt/gravwell/storage 2>/dev/null | cut -f1)
        kb=${kb:-0}
        over=$((kb - GW_BASELINE_KB)); [ "$over" -lt 0 ] && over=0
        if   [ "$over" -gt "$GW_LAB03_KB" ];  then data="$((over/1024))M"; ingested=bulk
        elif [ "$over" -gt "$GW_INGEST_KB" ]; then data="${over}K";        ingested=yes
        elif [ "$over" -gt 0 ];               then data="${over}K"; data_col="$D"  # self-logs only
        else data="empty"; fi
    fi

    # --- what Gravwell actually holds (--tags). Better evidence than storage size, so it is read
    #     here, inside the loop, and feeds the LAB column as well as the summary below. ---
    tagline=""
    if [ -n "$TAGS" ] && [ "$gw" = "up" ]; then
        tokf="/home/$u/.gravwell_token"
        if [ -s "$tokf" ]; then
            gstart=$(date -u -d '-7 days' +%Y-%m-%dT%H:%M:%SZ); gend=$(date -u -d '+1 day' +%Y-%m-%dT%H:%M:%SZ)
            tq=$(curl -sk -m 30 -X POST "https://127.0.0.1:${i}443/api/search/direct" \
                 -H "Gravwell-Token: $(cat "$tokf")" -H 'content-type: application/json' \
                 -d "{\"SearchString\":\"tag=* count by TAG | table TAG count\",\"SearchStart\":\"$gstart\",\"SearchEnd\":\"$gend\",\"Format\":\"csv\"}" 2>/dev/null)
            if printf '%s' "$tq" | grep -q '"error"'; then tagline="!query failed"
            else tagline=$(printf '%s\n' "$tq" | awk -F, 'NR>1 && $1!="gravwell" && $1!="" {printf "%s %s  ", $1, $2}')
            fi
        else
            tagline="!no token"
        fi
        TAGLINE[$i]="$tagline"
    fi

    # --- artifacts that pin a specific lab ---
    oc=""; [ -d "$h/.local/share/opencode" ] && oc=1
    [ -f "$d/labs/04-opencode-config/moneyprinter/opencode.json" ] && oc=1
    mcp=""; [ -d "$d/labs/06-mcp-deep-dive" ] && \
        [ -n "$(sudo -u "$u" git -C "$d" status --porcelain -- labs/06-mcp-deep-dive src/mcp-lab-server 2>/dev/null)" ] && mcp=1
    p05=""; [ -n "$(sudo -u "$u" git -C "$d" status --porcelain -- labs/05-llm-proxy 2>/dev/null)" ] && p05=1

    # --- furthest lab with evidence, capped by what is released ---
    ev=-1; ev_why=""
    [ "$gw" != "-" ]                       && { ev=$(stage_idx stage-gravwell);      ev_why="gravwell"; }
    [ "$ingested" = yes ]                  && { ev=$(stage_idx stage-shadowai);     ev_why="data"; }
    [ "$ingested" = bulk ]                 && { ev=$(stage_idx stage-sysmon);       ev_why="bulk data"; }
    case "$tagline" in *corelight_*|*okta*) ev=$(stage_idx stage-shadowai);          ev_why="tag=corelight";; esac
    case "$tagline" in *osquery*|*swg*|*cloudtrail*|*gws*) ev=$(stage_idx stage-shadowai-sources); ev_why="tag=osquery";; esac
    case "$tagline" in *sysmon*)           ev=$(stage_idx stage-sysmon);            ev_why="tag=sysmon";; esac
    [ -n "$oc" ]                           && { ev=$(stage_idx stage-opencode);      ev_why="opencode"; }
    { [ "$prox" != "-" ] || [ -n "$p05" ]; } && { ev=$(stage_idx stage-llm-proxy);    ev_why="litellm"; }
    case "$tagline" in *" llm "*|*proxy*|*syslog*) ev=$(stage_idx stage-llm-proxy);   ev_why="tag=llm";; esac
    [ -n "$mcp" ]                          && { ev=$(stage_idx stage-mcp);           ev_why="mcp edits"; }
    case "$tagline" in *" mcp "*)          ev=$(stage_idx stage-mcp);               ev_why="tag=mcp";; esac
    if [ "$ev" -lt 0 ]; then lab="Lab 01/01b"
    else
        [ "$ev" -gt "$released_idx" ] && ev="$released_idx"
        lab="$(mod "${STAGES[$ev]}")"
        [ -n "$ev_why" ] && [ -z "$TSV" ] && lab="$lab ${D}($ev_why)${N}"
    fi

    if [ -n "$TSV" ]; then
        printf '%s\t%s\t%s%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$i" "$ssh_m" "$clone" "$extra" "$sync" "$pulled" "$work" "$gw" "$llm" "$proxies" "$kb" "${lab}"
    else
        printf '%-5s %s%-4s%s %-18s %s%-11s%s %-7s %-5s %-4s %-4s %s%-8s%s %s %s\n' \
            "$i" "$ssh_col" "$ssh_m" "$N" "${clone#stage-}${extra}" "$sync_col" "$sync" "$N" \
            "$pulled" "$work" "$gw" "$llm" "$prox_col" "$proxies" "$N" "${data_col}$(printf '%-8s' "$data")${data_col:+$N}" "$lab"
    fi
done

# ---- what to do about it -----------------------------------------------------------------------
[ -n "$TSV" ] && exit 0
echo
if [ ${#behind_seats[@]} -gt 0 ]; then
    printf '%shave not pulled the current release:%s %s\n' "$R" "$N" "$(printf '%s ' "${behind_seats[@]%%:*}")"
    printf '  tell them:  %scd ~/jarvis && git pull%s\n' "$B" "$N"
fi
[ ${#unused_seats[@]} -gt 0 ] && \
    printf '%sspare seats (nobody has ever logged in):%s %s\n' "$D" "$N" "$(printf '%s ' "${unused_seats[@]}")"
[ ${#dead_seats[@]} -gt 0 ] && \
    printf '%sno ~/jarvis clone (never logged in, or wedged):%s %s\n' "$Y" "$N" "$(printf '%s ' "${dead_seats[@]}")"
[ ${#dirty_seats[@]} -gt 0 ] && \
    printf '%sseats with local edits (a mid-class redeploy may collide):%s %s\n' "$D" "$N" "$(printf '%s ' "${dirty_seats[@]}")"
echo
printf '%sLab 05 proxies listening (netstat):%s  all three on %s%d%s seat(s)' "$B" "$N" "$G" "${#all_proxies[@]}" "$N"
[ ${#all_proxies[@]} -gt 0 ] && printf ': %s' "$(printf '%s ' "${all_proxies[@]}")"
printf '\n'
[ ${#no_litellm[@]}  -gt 0 ] && printf '  no litellm      (:<ID>00)       %s\n' "$(printf '%s ' "${no_litellm[@]}")"
[ ${#no_ingester[@]} -gt 0 ] && printf '  no ingester     (:<ID>80 + 81)  %s%s%s\n' "$R" "$(printf '%s ' "${no_ingester[@]}")" "$N"
[ ${#no_pyproxy[@]}  -gt 0 ] && printf '  no python proxy (:<ID>90)       %s\n' "$(printf '%s ' "${no_pyproxy[@]}")"
# ---- what is actually in each seat's Gravwell (--tags) ------------------------------------------
# The DATA column is a storage heuristic. This is the real answer, and it is the one that tells you
# whether the lab you just taught actually landed. It authenticates with the seat's own API token
# (Lab 00 mints it), so it survives a student changing their Gravwell password.
if [ -n "$TAGS" ]; then
    echo
    printf '%swhat each seat has ingested%s   (tag counts over the last 7 days, via the seat API token)\n' "$B" "$N"
    if [ ${#up_seats[@]} -eq 0 ]; then
        printf '  %sno seat has Gravwell running%s\n' "$D" "$N"
    fi
    for i in "${up_seats[@]}"; do
        case "${TAGLINE[$i]:-}" in
            "!no token")     printf '  %-5s %sno API token yet (Lab 00 task 5 not run)%s\n' "$i" "$D" "$N" ;;
            "!query failed") printf '  %-5s %squery failed (token revoked, or Gravwell still starting)%s\n' "$i" "$R" "$N" ;;
            "")              printf '  %-5s %snothing but Gravwell talking to itself: no lab data ingested yet%s\n' "$i" "$Y" "$N" ;;
            *)               printf '  %-5s %s\n' "$i" "${TAGLINE[$i]}" ;;
        esac
    done
fi

cat <<'LEGEND'

SH     open ssh shells right now ("bg" = no shell but processes still running)
CLONE  the stage tag at their HEAD ("+own" = they have committed on top)
SYNC   HEAD vs the served repo. "-N stages" means they owe you a git pull
PULLED how long since their last fetch      WORK  modified + untracked files in the clone
GW/LLM the seat's Gravwell and its ingester sidecar (containers)
PROXIES what is LISTENING per netstat: L litellm :<ID>00 · I ingester :<ID>80+81 · P python :<ID>90
       · G gateway stretch :<ID>92. A dot is not listening. Green = L, I and P all up (Lab 05 done)
DATA   /opt/gravwell/storage above an empty seat's baseline. "empty" = nothing ingested;
       a dim number is Gravwell's own logs, not student data; a bright one is a real ingest.
       --tags replaces the guesswork: it asks each seat's Gravwell which tags it actually holds
LAB    furthest lab with evidence on disk, capped by what you have released. A guess, not a grade
LEGEND
