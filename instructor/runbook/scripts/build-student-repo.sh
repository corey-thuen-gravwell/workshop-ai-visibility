#!/bin/bash
# Build the student checkpoint repo from the authoring repo.
#
# Produces two bare repos:
#   $BARE_ALL  (default /opt/gitsrv/jarvis-all.git, root-only)  the complete linear history
#   $BARE      (default /opt/gitsrv/jarvis.git, world-readable)  what students clone, only as far
#                                                                 as an instructor has RELEASED
# makeuser.sh / reset-seats.sh clone $BARE into each seat's ~/jarvis. release-stage.sh moves $BARE
# forward one stage at a time; students pick the new lab up with `git pull`.
#
# Re-run this whenever content changes, and ALWAYS on the morning of class (Lab 02/03 data anchors
# its time window to generation time). A rebuild keeps the served repo released to the same stage
# it was before: but it REWRITES history from the first changed stage onward, so seats that
# already cloned must be re-cloned (reset-seats.sh) before they can pull again.
#
# DESIGN (checkpoints must not ship the future):
#  - student-repo/checkpoints.yaml lists the stages in order, each with the paths it ADDS.
#  - One commit per stage, cumulative and add-only: a stage never modifies or deletes a file an
#    earlier stage introduced (enforced below). That is what makes `git pull` safe on a seat with
#    uncommitted edits: incoming commits only ever create new paths.
#  - Each commit is tagged stage-<name>. The tag is also the lab's recovery point:
#        cd ~/jarvis && git checkout stage-<name> -- labs/<dir>
#  - The repo is an ALLOWLIST (the manifest). instructor/, slides/, AGENDA.md, the generators and
#    every answer artifact stay out, and the script REFUSES to publish if a leak assertion trips.
#
# Usage:
#   ./build-student-repo.sh                 # generate data, build, publish
#   SKIP_GENERATE=1 ./build-student-repo.sh # reuse existing datasets/**/generated
#   INITIAL_STAGE=stage-gravwell ./build-student-repo.sh   # first publish: release through here
#   BARE=/tmp/jarvis.git BARE_ALL=/tmp/jarvis-all.git ./build-student-repo.sh
#   DRY_RUN=1 ./build-student-repo.sh       # build + verify, don't publish (prints the staging dir)
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
HERE="$(cd "$(dirname "$0")" && pwd)"
BARE="${BARE:-/opt/gitsrv/jarvis.git}"
BARE_ALL="${BARE_ALL:-/opt/gitsrv/jarvis-all.git}"
STAGE="$(mktemp -d)"
MANIFEST="$REPO/student-repo/checkpoints.yaml"
trap '[ -n "${KEEP_STAGE:-}" ] || rm -rf "$STAGE"' EXIT

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mFATAL: %s\033[0m\n' "$*" >&2; exit 1; }
note() { printf '    %s\n' "$*"; }

[ -f "$MANIFEST" ] || die "manifest not found: $MANIFEST"
command -v git >/dev/null || die "git required"

# ---------------------------------------------------------------- 1. lab data
if [ -z "${SKIP_GENERATE:-}" ]; then
    log "Regenerating Lab 02/03 data (window anchors to NOW: this is why we rebuild per class)"
    ( cd "$REPO/src/log-generator" && python3 generate_corelight_logs.py --seed 1 \
        --outdir "$REPO/datasets/corelight/generated" \
        --answer-key "$REPO/datasets/corelight/generated/answer-key.json" \
        --sysmon-in  "$REPO/datasets/sysmon/sysmon-events-jan21-clean.xml" \
        --sysmon-out "$REPO/datasets/sysmon/generated/sysmon-retimed.xml" )
    ( cd "$REPO/src/log-generator" && python3 generate_shadow_ai_sources.py --seed 1 \
        --outdir "$REPO/datasets/shadow-ai-sources/generated" \
        --answer-key "$REPO/datasets/shadow-ai-sources/generated/answer-key.json" )
    ( cd "$REPO/src/log-generator" && python3 generate_logbot_logs.py \
        --out "$REPO/datasets/gravwell-ai-assistant/generated/logbot.log" \
        --answer-key "$REPO/datasets/gravwell-ai-assistant/generated/answer-key.json" --seed 1 )
else
    note "SKIP_GENERATE set: reusing datasets/**/generated"
fi
[ -f "$REPO/datasets/corelight/generated/corelight_dns.jsonl" ] \
    || die "no generated Lab 02 data; run without SKIP_GENERATE"

# ---------------------------------------------------------------- 2. manifest
# One line per stage, in `order`: tag<TAB>path<TAB>path...   Stages with no paths are placeholders.
log "Reading $MANIFEST"
STAGES_TSV=$(python3 - "$MANIFEST" <<'PY'
import sys, re
txt = open(sys.argv[1], encoding="utf-8").read()
out = []
for m in re.finditer(r'^\s*-\s*tag:\s*(\S+)\s*$(.*?)(?=^\s*-\s*tag:|\Z)', txt, re.M | re.S):
    tag, body = m.group(1), m.group(2)
    body = re.sub(r'#.*', '', body)                      # drop comments
    order = re.search(r'^\s*order:\s*(\d+)', body, re.M)
    paths = []
    pm = re.search(r'^\s*paths:\s*(.*?)(?=^\s*\w+:|\Z)', body, re.M | re.S)
    if pm:
        blob = pm.group(1).strip()
        if blob.startswith('['):
            paths = [p.strip() for p in blob.strip('[]').split(',') if p.strip()]
        else:
            paths = [l.strip()[1:].strip() for l in blob.splitlines() if l.strip().startswith('-')]
    out.append((int(order.group(1)) if order else 9999, tag, paths))
for _, t, ps in sorted(out):
    print("\t".join([t] + ps))
PY
)
ORDERED_TAGS=()
declare -A STAGE_PATHS
while IFS=$'\t' read -r tag rest; do
    [ -n "$tag" ] || continue
    ORDERED_TAGS+=("$tag"); STAGE_PATHS[$tag]="$rest"
done <<< "$STAGES_TSV"
[ "${#ORDERED_TAGS[@]}" -gt 0 ] || die "no stages parsed from the manifest"
for tag in "${ORDERED_TAGS[@]}"; do
    if [ -z "${STAGE_PATHS[$tag]}" ]; then note "$tag  (placeholder, no content yet, skipped)"; continue; fi
    for p in ${STAGE_PATHS[$tag]}; do
        [ -e "$REPO/$p" ] || die "$tag: path listed in the manifest does not exist: $p"
    done
    note "$tag  ← ${STAGE_PATHS[$tag]}"
done

# ---------------------------------------------------------------- 3. redactions
# Instructor-only artifacts that live INSIDE allowlisted directories. Applied after every copy.
REMOVE=(
    "datasets/corelight/generated/answer-key.json"
    "datasets/gravwell-ai-assistant/generated/answer-key.json"
    "datasets/shadow-ai-sources/generated/answer-key.json"
    "datasets/sysmon/how-this-data-was-made.md"   # states "The answer: PID 3565" (not shipped: only generated/ is)
    "datasets/sysmon/gravwell-queries.txt"        # example query names the answer PID (same)
    "datasets/README.md"                          # per-host verdicts for Lab 02; replaced below
)
redact() {
    for f in "${REMOVE[@]}"; do [ -e "$STAGE/$f" ] && rm -rf "$STAGE/$f"; done
    find "$STAGE" -path "$STAGE/.git" -prune -o -name '*-wrapped.json' -type f -print0 2>/dev/null | xargs -0 -r rm -f
    find "$STAGE" -path "$STAGE/.git" -prune -o -name '__pycache__' -type d -print0 2>/dev/null | xargs -0 -r rm -rf
    return 0
}

write_datasets_readme() {
cat > "$STAGE/datasets/README.md" <<'EOF'
# Datasets

The log data you ingest during the labs. Each lab tells you which files it needs and which port to
send them to. Directories appear here as the course reaches the lab that uses them.

| Path | Lab |
|---|---|
| `corelight/generated/` | 02: network logs (dns / ssl / conn / http) + `okta_access.jsonl` |
| `corelight/real-sample-corelight-ai-events.json` | 02: a small real capture, for reference |
| `resources/ai_domains.txt` | 02: upload as the `AI_DOMAINS` lookup resource |
| `resources/ai_domains_plus_api.txt` | 02: upload as `AI_DOMAINS_PLUS_API` (adds provider API hosts) |
| `shadow-ai-sources/generated/` | beyond-the-wire lab: osquery / web-gateway / CloudTrail / Workspace logs for the same hosts as Lab 02 |
| `resources/ai_software.txt` | beyond-the-wire lab: upload as `AI_SOFTWARE` |
| `resources/sanctioned_apps.txt` | beyond-the-wire lab: upload as `SANCTIONED_APPS` |
| `sysmon/generated/sysmon-retimed.xml` | 03: real Linux Sysmon events, re-timed to line up with Lab 02 |
| `proxy-captures/` | 05: reference capture of an agent's traffic |
| `gravwell-ai-assistant/` | reference: a real product's AI audit logs |

Data is regenerated for each class. Its timestamps are the **previous UTC business day**, so set
the time range to **last 48 hours**. If a search returns nothing, check your time range first.
EOF
}

write_root_docs() {
cat > "$STAGE/README.md" <<'EOF'
# Exploring AI Visibility: lab repo

Everything you need for the hands-on labs. You already have this cloned at `~/jarvis`.

## Labs appear as we reach them

This repo only contains the labs we have covered so far. When an instructor releases the next
one, pick it up with:

```bash
cd ~/jarvis && git pull
```

A new directory appears under `labs/`; its `README.md` is the handout. Nothing you have changed is
touched: a release only ever adds files.

| Lab | Module |
|---|---|
| `labs/01-fundamentals/` | Under the hood of LLM tooling |
| `labs/01b-demystifying-ai/` | Demystifying how AI "thinks": tokens, vectors, seeds, temperature |
| `labs/00-environment-gravwell/` | Stand up your Gravwell |
| `labs/02-shadow-ai/` | Hunting shadow AI in network logs |
| `labs/03-endpoint-sysmon/` | Finding a rogue agent on the endpoint |
| `labs/04-opencode-config/` | Being the AI user, and auditing it |
| `labs/05-llm-proxy/` | LLM proxies: seeing what was actually said |
| `labs/06-mcp-deep-dive/` | Speaking MCP by hand |
| `labs/_stretch/shadow-ai-sources/` | *Optional:* shadow AI beyond the wire, the same hosts as Lab 02, four more logs |

## Your seat

Your seat number is in `$WORKSHOPUID`. Every port you type is built from it, if your id is 14,
`${WORKSHOPUID}443` means port `14443`.

```bash
echo $WORKSHOPUID        # if this is empty, run:  . ~/.workshop_env
```

## If you get lost

Every lab has a known-good snapshot. This **restores that one lab's files** and changes nothing
else, not your other labs, not where you are in the course:

```bash
cd ~/jarvis && git checkout stage-<name> -- labs/<lab directory>
```

The exact command is at the bottom of each lab's README. `git status` shows what you have changed;
`git tag` lists the snapshots you have. Ask an instructor if you're unsure, that's what we're
here for.

## Slides and handouts

The slides, every lab handout and the take-home one-pagers are published as the course runs:

    __SHARE_URL__

Ask an instructor for the password. Material appears there as we cover it, so if something you
expect is missing, we haven't got to it yet.

## Take-home

`src/logging-proxy/llm_audit_proxy.py` (arrives with Lab 05) is yours to keep: one Python file, no
dependencies, that logs prompts, tool calls and token usage from any OpenAI- or
Anthropic-compatible client into any SIEM. It is the smallest useful thing you can take back to
work on Monday.
EOF
sed -i "s|__SHARE_URL__|https://${LAB_HOST:-$(hostname -f)}/|" "$STAGE/README.md"   # LAB_HOST from the environment or /opt/workshop/.env
printf '__pycache__/\n*.pyc\n.env\nsession.json\ntools.json\nproxy.jsonl\n' > "$STAGE/.gitignore"
}

# ---------------------------------------------------------------- 4. history + tags
log "Building history (one add-only commit per stage)"
cd "$STAGE"
git init -q -b main
git config user.email "instructors@gravwell.io"
git config user.name  "Exploring AI Visibility"
# Deterministic dates: identical content => identical hashes, so a rebuild that changes only a late
# stage leaves the earlier commits (and released clones) intact.
epoch=1767225600   # 2026-01-01T00:00:00Z
BUILT=()
first=1
for tag in "${ORDERED_TAGS[@]}"; do
    [ -n "${STAGE_PATHS[$tag]}" ] || continue
    for p in ${STAGE_PATHS[$tag]}; do
        mkdir -p "$STAGE/$(dirname "$p")"
        cp -r "$REPO/$p" "$STAGE/$(dirname "$p")/"
    done
    # Every script must be executable regardless of how the tree reached this host: the handouts
    # say ./tokens.bash, and git records the mode. (Lost once through a permission-normalising sync.)
    { grep -rlZ --exclude-dir=.git '^#!' "$STAGE" || true; } | xargs -0 -r chmod 755
    redact                                   # also drops the authoring datasets/README.md ...
    if [ "$first" = 1 ]; then write_root_docs; first=0; fi
    [ -d "$STAGE/datasets" ] && write_datasets_readme   # ... so re-emit the student one (same bytes => no diff)
    epoch=$((epoch + 60))
    export GIT_AUTHOR_DATE="@$epoch +0000" GIT_COMMITTER_DATE="@$epoch +0000"
    git add -A
    git commit -qm "$tag" --allow-empty
    if [ "${#BUILT[@]}" -gt 0 ]; then
        changed=$(git diff --name-status --diff-filter=MD HEAD~1 HEAD)
        [ -z "$changed" ] || die "$tag modifies or deletes files from an earlier stage (stages must be add-only, or git pull breaks on seats):
$changed"
    fi
    git tag -f "$tag" -m "checkpoint: $tag" >/dev/null
    BUILT+=("$tag")
    note "$(git rev-parse --short HEAD)  $tag  (+$(git show --name-only --diff-filter=A --format= HEAD | grep -c . || true) files)"
done
unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE
[ "${#BUILT[@]}" -gt 0 ] || die "no stage had content"
printf '%s\n' "${BUILT[@]}" > "$STAGE/.stages.txt"   # copied into the bare repo, not committed

# ---------------------------------------------------------------- 5. leak assertions (final tree)
log "Leak assertions"
fail=0
assert_absent() {  # [-F] pattern, human description   (-F = fixed string, not a regex)
    local hits flag=""
    [ "$1" = "-F" ] && { flag="-F"; shift; }
    hits=$(grep -rIl $flag --exclude-dir=.git -- "$1" "$STAGE" 2>/dev/null || true)
    if [ -n "$hits" ]; then
        printf '\033[1;31m    LEAK: %s\033[0m\n' "$2"; echo "$hits" | sed "s|$STAGE|      |"; fail=1
    else note "ok: no $2"; fi
}
assert_absent "Expected answers (instructor)"   "instructor answer sections"
assert_absent "sk-ant-api"                      "Anthropic API keys"
assert_absent "answer-key"                      "answer-key references"
# Lab 01b: the Gravwell LLM token lives only in the root-owned relay on the host, never in a shipped
# file. Read the real value from the committed instructor file and make sure it isn't in the stage.
llm_tok=$(sed -n 's/^LLM_UPSTREAM_TOKEN="\(.*\)"$/\1/p' "$REPO/instructor/runbook/gravwell-llm.env" 2>/dev/null || true)
if [ -n "$llm_tok" ]; then
    assert_absent -F "$llm_tok"                 "Gravwell LLM token"
else
    printf '\033[1;33m    WARN: could not read LLM_UPSTREAM_TOKEN from instructor/runbook/gravwell-llm.env\033[0m\n'
fi
if hits=$(grep -rIlE --exclude-dir=.git 'Bearer +[A-Za-z0-9][A-Za-z0-9_.-]{7,}' "$STAGE" 2>/dev/null) && [ -n "$hits" ]; then
    printf '\033[1;31m    LEAK: hardcoded bearer token\033[0m\n'; echo "$hits" | sed "s|$STAGE|      |"; fail=1
else note "ok: no hardcoded bearer tokens"; fi
for d in instructor slides student-repo src/log-generator; do
    [ -e "$STAGE/$d" ] && { printf '\033[1;31m    LEAK: %s present\033[0m\n' "$d"; fail=1; } || note "ok, $d excluded"
done
for f in AGENDA.md CONTRIBUTING.md SETUP.md; do
    [ -e "$STAGE/$f" ] && { printf '\033[1;31m    LEAK: %s present\033[0m\n' "$f"; fail=1; } || note "ok, $f excluded"
done
# The license is the one credential-shaped file we DO ship, and Lab 00 is dead without it.
if [ -s "$STAGE/gravwell.license" ]; then
    note "ok: gravwell license present ($(wc -c < "$STAGE/gravwell.license") bytes)"
else
    printf '\033[1;31m    MISSING: gravwell.license, Gravwell will not start\033[0m\n'; fail=1
fi
[ "$fail" -eq 0 ] || die "leak assertions failed, refusing to publish"

# ---------------------------------------------------------------- 6. publish
if [ -n "${DRY_RUN:-}" ]; then
    KEEP_STAGE=1
    log "DRY_RUN: not publishing"
    note "staging dir: $STAGE"
    note "stages: ${BUILT[*]}"
    note "size: $(du -sh "$STAGE" | cut -f1)"
    exit 0
fi

# Which stage was released before this rebuild? Keep the students where they were.
released=""
if [ -d "$BARE" ]; then
    for t in "${BUILT[@]}"; do
        git --git-dir="$BARE" rev-parse -q --verify "refs/tags/$t" >/dev/null 2>&1 && released="$t"
    done
fi
target="${INITIAL_STAGE:-${released:-${BUILT[0]}}}"
case " ${BUILT[*]} " in *" $target "*) ;; *) die "INITIAL_STAGE '$target' is not a built stage: ${BUILT[*]}";; esac

log "Publishing complete history to $BARE_ALL (root-only)"
mkdir -p "$(dirname "$BARE_ALL")"
[ -d "$BARE_ALL" ] && rm -rf "$BARE_ALL"
git init -q --bare -b main "$BARE_ALL"
git push -q "$BARE_ALL" main
git push -q --tags "$BARE_ALL"
git --git-dir="$BARE_ALL" symbolic-ref HEAD refs/heads/main
cp "$STAGE/.stages.txt" "$BARE_ALL/stages.txt"
chmod -R go-rwx "$BARE_ALL" 2>/dev/null || true

log "Publishing the served repo $BARE, released through: $target"
[ -d "$BARE" ] && { note "removing previous served repo"; rm -rf "$BARE"; }
# -b main matters: `git init --bare` otherwise points HEAD at refs/heads/master, which we never
# push, and every clone comes out EMPTY with only a warning.
git init -q --bare -b main "$BARE"
git --git-dir="$BARE" symbolic-ref HEAD refs/heads/main
chmod -R a+rX "$BARE"
BARE="$BARE" BARE_ALL="$BARE_ALL" "$HERE/release-stage.sh" "$target" | sed 's/^/  /'

# Verify a clone is populated and stops where it should.
_check="$(mktemp -d)"
git clone -q "$BARE" "$_check/seat" 2>/dev/null
[ -f "$_check/seat/README.md" ] || { rm -rf "$_check"; die "published repo clones EMPTY: check HEAD in $BARE"; }
ntags=$(git -C "$_check/seat" tag | wc -l | tr -d ' ')
last_built="${BUILT[${#BUILT[@]}-1]}"
if [ "$target" != "$last_built" ]; then
    # something from a later stage must NOT be in the clone
    later="${STAGE_PATHS[$last_built]%% *}"
    [ -e "$_check/seat/$later" ] && { rm -rf "$_check"; die "clone contains $later, which belongs to an unreleased stage"; }
fi
note "verified: a fresh clone has $(find "$_check/seat" -type f -not -path '*/.git/*' | wc -l | tr -d ' ') files, $ntags stage tag(s), released through $target"
rm -rf "$_check"

log "Done"
note "complete history: $BARE_ALL   (${#BUILT[@]} stages: ${BUILT[*]})"
note "students clone:   $BARE       (through $target)"
note "release the next lab:  $HERE/release-stage.sh --next      students then:  cd ~/jarvis && git pull"
[ -n "$released" ] && [ -z "${INITIAL_STAGE:-}" ] && \
    note "NOTE: history was rebuilt, seats that cloned before this need reset-seats.sh before they can pull"
true
