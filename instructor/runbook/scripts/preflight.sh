#!/bin/bash
# Day-of pre-flight checklist for the lab host. Run as root. Read-only: reports, never fixes.
# Usage: ./preflight.sh            (SEATS/START_ID as in makeuser.sh; default 2 seats, ids 10-11)
set -uo pipefail
SEATS="${SEATS:-2}"; START_ID="${START_ID:-10}"; END_ID="${END_ID:-$((START_ID + SEATS - 1))}"
ENV_FILE="${ENV_FILE:-/opt/workshop/.env}"
# The lab host's public DNS name: LAB_HOST in .env, or HOST= on the command line.
HOST="${HOST:-${LAB_HOST:-$(sed -n 's/^LAB_HOST="\(.*\)"$/\1/p' "$ENV_FILE" 2>/dev/null)}}"
HOST="${HOST:-$(hostname -f)}"
CERT_DIR="${CERT_DIR:-/opt/workshop/certs}"
REPO_DIR="${REPO_DIR:-$(cd "$(dirname "$0")/../../.." && pwd)}"
pass=0; fail=0; warn=0
ok()   { echo "  ✅ $*"; pass=$((pass+1)); }
bad()  { echo "  ❌ $*"; fail=$((fail+1)); }
meh()  { echo "  ⚠️  $*"; warn=$((warn+1)); }

echo "== Host"
command -v docker >/dev/null && ok "docker $(docker --version | awk '{print $3}')" || bad "docker missing"
docker compose version >/dev/null 2>&1 && ok "docker compose plugin" || bad "docker compose plugin missing"
systemctl is-active --quiet docker && ok "docker running" || bad "docker not running"
for t in git python3 nc jq curl opencode; do command -v $t >/dev/null && ok "$t" || bad "$t missing"; done
command -v claude >/dev/null && ok "claude (P4, optional)" || meh "claude not installed, padding module P4 unavailable"
free_g=$(free -g | awk '/Mem:/{print $7}'); [ "$free_g" -ge 6 ] && ok "${free_g}G RAM available" || meh "only ${free_g}G RAM available"
disk=$(df --output=avail -BG / | tail -1 | tr -dc 0-9); [ "$disk" -ge 30 ] && ok "${disk}G disk free" || meh "only ${disk}G disk free"
ip=$(getent hosts "$HOST" | awk '{print $1}'); myip=$(curl -fsS -m 5 https://api.ipify.org || true)
[ -n "$ip" ] && ok "$HOST -> $ip" || bad "$HOST does not resolve"
[ -n "$ip" ] && [ "$ip" = "$myip" ] && ok "DNS points at this host ($myip)" || meh "DNS ($ip) != public IP ($myip)"

echo "== SSH (20 people, one NAT egress, all day)"
alive=$(sshd -T 2>/dev/null | awk '/^clientaliveinterval/{print $2}')
cmax=$(sshd -T 2>/dev/null | awk '/^clientalivecountmax/{print $2}')
if [ "${alive:-0}" -gt 0 ] 2>/dev/null; then
    ok "sshd keepalive every ${alive}s, survives $((alive*cmax))s of silence"
else
    bad "ClientAliveInterval is 0: idle sessions die at the venue's NAT timeout and students reconnect all day (bootstrap-host.sh)"
fi
starts=$(sshd -T 2>/dev/null | awk '/^maxstartups/{print $2}' | cut -d: -f1)
if [ "${starts:-0}" -ge "$SEATS" ] 2>/dev/null; then ok "MaxStartups $starts covers $SEATS seats connecting at once"
else meh "MaxStartups ${starts:-?} < $SEATS seats, some students get randomly refused in the 09:00 rush"; fi
if systemctl is-active --quiet fail2ban 2>/dev/null; then
    retry=$(fail2ban-client get sshd maxretry 2>/dev/null)
    if [ "${retry:-0}" -ge "$SEATS" ] 2>/dev/null; then ok "fail2ban maxretry $retry covers $SEATS seats behind one IP"
    else meh "fail2ban maxretry ${retry:-?} with $SEATS seats on one IP, a few mistyped passwords ban the room"; fi
    # A ban here rejects ESTABLISHED sessions too (input-hook reject, no ct-state match), so an
    # un-whitelisted class IP does not just block reconnects, it drops everyone mid-lab.
    # Strip the whole 127/8 loopback range, not the literal 127.0.0.1: the jail is configured with
    # `ignoreip = 127.0.0.1/8` and fail2ban-client normalises that to the NETWORK address,
    # 127.0.0.0/8. Matching only '^127.0.0.1' left the loopback entry looking like a class IP, so
    # this check reported a green tick with nothing whitelisted.
    extra=$(fail2ban-client get sshd ignoreip 2>/dev/null \
            | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?' | grep -v '^127\.' | tr '\n' ' ')
    if [ -n "$extra" ]; then ok "fail2ban ignoreip includes the class IP: $extra"
    else meh "CLASS IP NOT WHITELISTED, from inside the room: curl -s ifconfig.me, then
        WORKSHOP_CLASS_IP=<ip> $REPO_DIR/instructor/runbook/scripts/bootstrap-host.sh
      (a ban rejects live sessions too, so this drops the whole room mid-lab, not just reconnects)"; fi
else
    meh "fail2ban not running: fine for the class, but this box is public and takes constant bot traffic"
fi

echo "== Secrets & config"
if [ -f "$ENV_FILE" ]; then
    ok "$ENV_FILE present ($(stat -c %a "$ENV_FILE"))"
    grep -q 'REPLACE-ME' "$ENV_FILE" && bad "$ENV_FILE still has REPLACE-ME placeholders" || ok "no placeholders in .env"
    grep -q '^ANTHROPIC_API_KEY="sk-ant-' "$ENV_FILE" && ok "ANTHROPIC_API_KEY set" || bad "ANTHROPIC_API_KEY missing/malformed"
else bad "$ENV_FILE missing"; fi
echo "== Seats must not read instructor material"
seat0="workshop${START_ID}"
if id "$seat0" >/dev/null 2>&1; then
    for p in /opt/workshop/src /opt/workshop/share/staged /opt/workshop/.env /opt/workshop/gravwell-llm.env /opt/gitsrv/jarvis-all.git; do
        [ -e "$p" ] || continue
        if sudo -u "$seat0" test -r "$p" 2>/dev/null; then bad "$seat0 can read $p (chmod 750 /opt/workshop; see bootstrap-host.sh)"
        else ok "$p unreadable by seats"; fi
    done
    own=$(stat -c %U /opt/workshop/share/staged 2>/dev/null || echo none)
    [ "$own" = root ] && ok "share/staged owned by root" || bad "share/staged owned by $own, a seat could edit the unreleased answer keys (deploy-share.sh)"
fi
echo "== Lab 01b LLM relay (root-only token, loopback)"
relay_env="${RELAY_ENV:-/opt/workshop/gravwell-llm.env}"; relay="${LLM_RELAY_LISTEN:-127.0.0.1:9010}"
if [ -f "$relay_env" ]; then
    [ "$(stat -c '%U:%a' "$relay_env")" = "root:600" ] && ok "$relay_env is root:600" || bad "$relay_env is $(stat -c '%U:%a' "$relay_env") (want root:600)"
    grep -q '^LLM_UPSTREAM_TOKEN=.\+' "$relay_env" && ok "relay token file populated" || bad "relay token file has no LLM_UPSTREAM_TOKEN"
else bad "$relay_env missing, run start-llm-relay.sh"; fi
systemctl is-active --quiet workshop-llm-relay && ok "workshop-llm-relay running" || bad "workshop-llm-relay not running (start-llm-relay.sh)"
bound=$(ss -ltnH "sport = :${relay##*:}" 2>/dev/null | awk '{print $4}' | tr '\n' ' ')
case "$bound" in
    "") bad "nothing listening on port ${relay##*:}" ;;
    *0.0.0.0*|*'*:'*|*'[::]'*) bad "relay bound to a non-loopback address: $bound" ;;
    *) ok "relay bound to $bound only" ;;
esac
code=$(curl -sS -o /dev/null -m 10 -w '%{http_code}' "http://$relay/api/tags" 2>/dev/null || echo 000)
[ "$code" = "200" ] && ok "relay answers /api/tags without a client credential" || bad "relay /api/tags returned $code (upstream token rotated? journalctl -u workshop-llm-relay)"
code=$(curl -sS -o /dev/null -m 10 -w '%{http_code}' "http://$relay/api/version" 2>/dev/null || echo 000)
[ "$code" = "403" ] && ok "relay refuses non-allowlisted paths" || meh "relay /api/version returned $code (want 403)"

echo "== Secrets & config (cont.)"
lic="$REPO_DIR/gravwell.license"
[ -s "$lic" ] && ok "gravwell license present" || bad "gravwell license missing at $lic"

echo "== TLS cert"
if [ -f "$CERT_DIR/cert.pem" ] && [ -f "$CERT_DIR/key.pem" ]; then
    end=$(openssl x509 -in "$CERT_DIR/cert.pem" -noout -enddate | cut -d= -f2)
    days=$(( ( $(date -d "$end" +%s) - $(date +%s) ) / 86400 ))
    [ "$days" -gt 3 ] && ok "cert valid $days more days ($(openssl x509 -in "$CERT_DIR/cert.pem" -noout -subject | sed 's/subject=//'))" || bad "cert expires in $days days"
    [ "$(stat -c %a "$CERT_DIR/key.pem")" = "600" ] && ok "key.pem is 0600 root" || meh "key.pem perms $(stat -c %a "$CERT_DIR/key.pem")"
    openssl verify -untrusted "$CERT_DIR/cert.pem" "$CERT_DIR/cert.pem" >/dev/null 2>&1 && ok "cert chain verifies" || meh "cert chain does not verify locally (self-signed?)"
else bad "no cert at $CERT_DIR"; fi

echo "== Images"
for img in gravwell/gravwell:5.10.1 gravwell/llm_ingester:5.10.1 hello-world:latest ghcr.io/berriai/litellm:main-latest; do
    docker image inspect "$img" >/dev/null 2>&1 && ok "$img" || meh "$img not pulled/built"
done

echo "== Gravwell MCP (Lab 06 needs 5.10.x; /api/mcp 404s on older builds)"
mcp_seat="${MCP_SEAT:-$START_ID}"
if curl -sk -o /dev/null -m 5 "https://localhost:${mcp_seat}443/" 2>/dev/null; then
    # Prefer the seat's API token (Lab 00 mints it): a seat that changed its admin password still
    # answers the token, and the login below would fail for a reason that is not our problem.
    tok=$(cat "/home/workshop${mcp_seat}/.gravwell_token" 2>/dev/null || true)
    if [ -n "$tok" ]; then
        gwauth=(-H "Gravwell-Token: $tok")
    else
        jwt=$(curl -sk -m 5 -X POST "https://localhost:${mcp_seat}443/api/login" -H 'content-type: application/json' \
              -d '{"User":"admin","Pass":"changeme"}' 2>/dev/null | sed -n 's/.*"JWT":"\([^"]*\)".*/\1/p')
        gwauth=(); [ -n "$jwt" ] && gwauth=(-H "Authorization: Bearer $jwt")
    fi
    if [ "${#gwauth[@]}" -gt 0 ]; then
        code=$(curl -sk -o /dev/null -m 5 -w '%{http_code}' -X POST "https://localhost:${mcp_seat}443/api/mcp" \
               "${gwauth[@]}" -H 'content-type: application/json' \
               -H 'accept: application/json, text/event-stream' \
               -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","clientInfo":{"name":"preflight","version":"1"},"capabilities":{}}}')
        [ "$code" = "200" ] && ok "/api/mcp reachable on seat $mcp_seat" || bad "/api/mcp returned $code on seat $mcp_seat (need Gravwell 5.10.x for Lab 06)"
    else meh "no token and no login for seat $mcp_seat, skipped /api/mcp"; fi
else meh "seat $mcp_seat not running, skipped /api/mcp check"; fi

echo "== Share server (course PDFs over HTTPS)"
if docker inspect -f '{{.State.Status}}' workshop-share 2>/dev/null | grep -q running; then
    ok "workshop-share container running"
    sc_no=$(curl -sk -o /dev/null -m 5 -w '%{http_code}' https://127.0.0.1/ 2>/dev/null)
    [ "$sc_no" = "401" ] && ok "share site requires a password (401)" \
                         || bad "share site returned $sc_no without credentials (want 401)"
        # read the two share values out of the env file rather than sourcing it, so a SEATS= or
    # START_ID= in .env cannot override what the operator passed on the command line
    SHARE_USER="${SHARE_USER:-$(sed -n 's/^SHARE_USER="\(.*\)"$/\1/p' "$ENV_FILE" 2>/dev/null)}"
    SHARE_PASSWORD="${SHARE_PASSWORD:-$(sed -n 's/^SHARE_PASSWORD="\(.*\)"$/\1/p' "$ENV_FILE" 2>/dev/null)}"
    if [ -n "${SHARE_USER:-}" ] && [ -n "${SHARE_PASSWORD:-}" ]; then
        sc_yes=$(curl -sk -o /dev/null -m 5 -w '%{http_code}' -u "$SHARE_USER:$SHARE_PASSWORD" https://127.0.0.1/ 2>/dev/null)
        [ "$sc_yes" = "200" ] && ok "share site serves with the workshop password" \
                             || bad "share site returned $sc_yes with credentials (want 200)"
    else meh "SHARE_USER/SHARE_PASSWORD not in $ENV_FILE: cannot test the login"; fi
    st=$(find "${SHARE_ROOT:-/opt/workshop/share}/staged" -type f \( -name '*.pdf' -o -name '*.html' \) 2>/dev/null | wc -l)
    lv=$(find "${SHARE_ROOT:-/opt/workshop/share}/live" -type f \( -name '*.pdf' -o -name '*.html' \) 2>/dev/null | wc -l)
    [ "$st" -gt 0 ] && ok "$st files staged (html + pdf), $lv released" \
                    || bad "nothing staged: run deploy-share.sh from the authoring box"
else
    meh "share server not running (start-share-server.sh): optional, but no URLs to hand out"
fi

echo "== Student repo"
if [ -d /opt/gitsrv/jarvis.git ]; then
    tags=$(git --git-dir=/opt/gitsrv/jarvis.git tag -l 'stage-*' | wc -l); ok "/opt/gitsrv/jarvis.git with $tags stage-* tags"
    # The license arrives with stage-gravwell, so check the complete history, not the served repo,
    # which may legitimately stop at Lab 01 before class.
    ALLREPO="${BARE_ALL:-/opt/gitsrv/jarvis-all.git}"
    if git --git-dir="$ALLREPO" cat-file -e stage-gravwell:gravwell.license 2>/dev/null; then
        ok "stage-gravwell ships the Gravwell license (Lab 00 dies without it)"
    elif git --git-dir=/opt/gitsrv/jarvis.git cat-file -e main:gravwell.license 2>/dev/null; then
        ok "student repo ships the Gravwell license (Lab 00 dies without it)"
    else bad "no Gravwell license in stage-gravwell: every seat's Gravwell will fail with 'missing license'"; fi
else bad "/opt/gitsrv/jarvis.git missing (build-student-repo.sh)"; fi

echo "== Seats workshop$START_ID..$END_ID"
missing=0; nogrp=0; noenv=0; nollm=0; leaktok=0
for i in $(seq "$START_ID" "$END_ID"); do
    u="workshop$i"
    id "$u" &>/dev/null || { missing=$((missing+1)); continue; }
    id -nG "$u" | grep -qw docker || nogrp=$((nogrp+1))
    [ -f "/home/$u/.workshop_env" ] || noenv=$((noenv+1))
    grep -q '^export GRAVWELL_LLM_URL=' "/home/$u/.workshop_env" 2>/dev/null || nollm=$((nollm+1))
    grep -qi 'TOKEN=' "/home/$u/.workshop_env" 2>/dev/null && grep -qi 'LLM_UPSTREAM_TOKEN\|GRAVWELL_LLM_TOKEN' "/home/$u/.workshop_env" && leaktok=$((leaktok+1))
done
[ $missing -eq 0 ] && ok "all seats exist" || bad "$missing seats missing"
[ $nogrp -eq 0 ] && ok "all seats in docker group" || bad "$nogrp seats not in docker group"
[ $noenv -eq 0 ] && ok "all seats have ~/.workshop_env" || bad "$noenv seats lack ~/.workshop_env"
[ $nollm -eq 0 ] && ok "all seats have GRAVWELL_LLM_URL (Lab 01b relay)" || bad "$nollm seats lack GRAVWELL_LLM_URL, re-run makeuser.sh"
[ $leaktok -eq 0 ] && ok "no seat holds the Gravwell LLM token" || bad "$leaktok seats have the LLM token in ~/.workshop_env: re-run makeuser.sh (it must stay root-only)"
nokey=0
for i in $(seq "$START_ID" "$END_ID"); do
    grep -q '^export ANTHROPIC_API_KEY="sk-ant-' "/home/workshop$i/.workshop_env" 2>/dev/null || nokey=$((nokey+1))
done
[ $nokey -eq 0 ] && ok "all seats have the provider key" || bad "$nokey seats lack ANTHROPIC_API_KEY (re-run makeuser.sh)"

echo "== Port collisions (nothing should hold seat ports before students start)"
busy=$(ss -ltn 2>/dev/null | awk 'NR>1{print $4}' | sed 's/.*://' | grep -E "^(1[0-9]|2[0-9]|3[0-9]|4[0-9])[0-9]{2,3}$" | sort -un | tr '\n' ' ')
[ -z "$busy" ] && ok "no seat-range ports in use" || meh "seat-range ports already listening: $busy (running seats are fine)"

echo; echo "Summary: $pass ok, $warn warnings, $fail failures"
[ $fail -eq 0 ]
