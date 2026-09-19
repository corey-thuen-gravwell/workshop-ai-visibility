#!/bin/bash
# Bootstrap a FRESH cloud host (Ubuntu 24.04/26.04 or Debian 12/13) as the workshop lab host. Run as root.
# Idempotent: safe to re-run. Installs docker, tooling, opencode; stages /opt/workshop; pre-pulls
# images; builds the shared LLM-ingester image. Does NOT create seats (makeuser.sh) or issue the
# TLS cert (issue-cert.sh): those are separate, documented steps in the runbook.
#
# Usage (on the new host):
#   git clone <authoring repo> /opt/workshop/src && cd /opt/workshop/src
#   cp .env.example /opt/workshop/.env && $EDITOR /opt/workshop/.env      # real secrets, chmod 600
#   instructor/runbook/scripts/bootstrap-host.sh
#   instructor/runbook/scripts/issue-cert.sh        # Let's Encrypt (manual DNS-01)
#   instructor/runbook/scripts/build-student-repo.sh
#   instructor/runbook/scripts/makeuser.sh          # SEATS=2 by default; a class sets its roster size
#   instructor/runbook/scripts/preflight.sh
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "$0")/../../.." && pwd)}"
WORKSHOP_DIR="${WORKSHOP_DIR:-/opt/workshop}"
OPENCODE_VERSION="${OPENCODE_VERSION:-latest}"           # or a tag like v1.18.29
GRAVWELL_IMAGE="${GRAVWELL_IMAGE:-gravwell/gravwell:5.10.1}"
LITELLM_IMAGE="${LITELLM_IMAGE:-ghcr.io/berriai/litellm:main-latest}"
LLM_INGESTER_IMAGE="${LLM_INGESTER_IMAGE:-gravwell/llm_ingester:5.10.1}"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }
. /etc/os-release
log "Host: $PRETTY_NAME  ($(nproc) cpu, $(free -g | awk '/Mem:/{print $2}')G ram)"

log "Base packages"
apt-get update -q
apt-get install -y -q ca-certificates curl gnupg lsb-release git python3 python3-venv jq unzip make \
    netcat-openbsd tmux htop ufw fail2ban apt-transport-https openssl socat

log "Docker (official repo)"
if ! command -v docker >/dev/null; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/$ID/gpg" -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$ID $VERSION_CODENAME stable" \
        > /etc/apt/sources.list.d/docker.list
    apt-get update -q
    apt-get install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
systemctl enable --now docker
docker --version; docker compose version
# Log rotation so 20 seats of containers don't fill the disk
if [ ! -f /etc/docker/daemon.json ]; then
    cat > /etc/docker/daemon.json <<'JSON'
{ "log-driver": "json-file", "log-opts": { "max-size": "20m", "max-file": "3" } }
JSON
    systemctl restart docker
fi

log "opencode (system-wide, /usr/local/bin)"
if ! command -v opencode >/dev/null || [ "$OPENCODE_VERSION" != "latest" ]; then
    arch=$(uname -m); case "$arch" in x86_64) a=x64;; aarch64) a=arm64;; *) echo "unsupported arch $arch"; exit 1;; esac
    if [ "$OPENCODE_VERSION" = "latest" ]; then url="https://github.com/sst/opencode/releases/latest/download/opencode-linux-$a.tar.gz"
    else url="https://github.com/sst/opencode/releases/download/$OPENCODE_VERSION/opencode-linux-$a.tar.gz"; fi
    tmp=$(mktemp -d); curl -fsSL "$url" -o "$tmp/oc.tgz"; tar -xzf "$tmp/oc.tgz" -C "$tmp"
    install -m 0755 "$(find "$tmp" -type f -name opencode | head -1)" /usr/local/bin/opencode; rm -rf "$tmp"
fi
opencode --version || true

log "Claude Code (system-wide): the second client for padding module P4"
if ! command -v claude >/dev/null; then
    # Native installer; no node required (opencode is a static binary for the same reason).
    curl -fsSL https://claude.ai/install.sh -o /tmp/cc-install.sh && bash /tmp/cc-install.sh >/dev/null 2>&1 || true
    real=$(readlink -f /root/.local/bin/claude 2>/dev/null)
    [ -n "$real" ] && [ -f "$real" ] && install -m 0755 "$real" /usr/local/bin/claude
    rm -f /tmp/cc-install.sh
fi
claude --version 2>/dev/null || echo "   (claude not installed: P4 is optional, everything else is unaffected)"

log "Workshop dirs"
# /opt/workshop is root-only (750): the authoring copy, unreleased PDFs and the secrets live under
# it, and no seat needs to read any of it. Docker bind mounts (certs, share/live) are performed by
# the daemon as root and checked against the mounted path's own mode, so a 750 parent is invisible
# to the containers. Seats hold the docker group, which is root-equivalent: this stops browsing,
# not a determined student. Accepted risk; see the runbook README.
install -d -m 0750 "$WORKSHOP_DIR"
chmod 750 "$WORKSHOP_DIR"
install -d -m 0755 "$WORKSHOP_DIR/certs" /opt/gitsrv
if [ ! -f "$WORKSHOP_DIR/.env" ]; then
    cp "$REPO_DIR/.env.example" "$WORKSHOP_DIR/.env"; chmod 600 "$WORKSHOP_DIR/.env"
    echo "   !! $WORKSHOP_DIR/.env created from .env.example: FILL IN REAL VALUES before makeuser.sh"
fi
# Shared read-only copy of lab content for seats without the student repo yet
rsync -a --delete --exclude .git --exclude '.env' "$REPO_DIR/" "$WORKSHOP_DIR/src/" 2>/dev/null || cp -r "$REPO_DIR" "$WORKSHOP_DIR/src"

log "Pre-pull images (so 20 seats don't hammer the registries at once)"
docker pull -q "$GRAVWELL_IMAGE" && docker tag "$GRAVWELL_IMAGE" gravwell/gravwell:latest
docker pull -q hello-world
docker pull -q "$LITELLM_IMAGE" || echo "   (litellm pull failed: M8 will pull on demand)"

log "Pull the LLM-ingester image ($LLM_INGESTER_IMAGE)"
docker pull -q "$LLM_INGESTER_IMAGE" \
    && docker tag "$LLM_INGESTER_IMAGE" gravwell/llm_ingester:latest

log "SSH tuned for a classroom (keepalives, connection burst, fail2ban)"
# Stock sshd sends NOTHING on an idle connection: ClientAliveInterval defaults to 0, and while
# TCPKeepAlive is on, the kernel's first probe is at net.ipv4.tcp_keepalive_time = 7200s. Venue NAT
# and wifi APs expire a mapping in 5-30 minutes, so a student's session dies silently and they only
# find out at the next keystroke. Fixed server-side so nobody has to touch their own laptop's config.
cat > /etc/ssh/sshd_config.d/10-workshop.conf <<'CONF'
# Workshop lab host. A packet every 30s keeps NAT mappings warm; 30 x 20 tolerates ten minutes of
# silence, which covers wifi roaming and a lid closed over a break without tearing the session down.
ClientAliveInterval 30
ClientAliveCountMax 20
TCPKeepAlive yes

# 20 seats connect inside the same minute at 09:00, on a public IP that also takes thousands of bot
# connections a day. Stock 10:30:100 random-refuses real students during that rush.
MaxStartups 60:30:200
MaxSessions 20
CONF
sshd -t && systemctl reload ssh && echo "   sshd: keepalive 30s x 20, MaxStartups 60:30:200" \
    || echo "   !! sshd rejected the config: still running the old settings, fix before class"

# fail2ban: the whole room shares one NAT egress IP and password auth is on with a predictable seat
# password. At stock maxretry=5/findtime=600, five fumbled passwords ACROSS THE ROOM ban that IP for
# ten minutes. Worse, the rule it installs (`tcp dport 22 ip saddr @addr-set-sshd reject`, input
# hook, no ct-state match) rejects packets belonging to ESTABLISHED sessions too, so it does not
# merely block reconnects, it drops every student at once. Keep the jail (this is a public IP with
# real bots on it), but stop it taking out the class.
CLASS_IP="${WORKSHOP_CLASS_IP:-}"          # venue egress IP; set on class day, see below
install -d -m 0755 /etc/fail2ban/jail.d
cat > /etc/fail2ban/jail.d/workshop.local <<CONF
[sshd]
ignoreip = 127.0.0.1/8 ::1${CLASS_IP:+ $CLASS_IP}
maxretry = 20
findtime = 300
bantime  = 300
CONF
systemctl reload fail2ban 2>/dev/null || systemctl restart fail2ban 2>/dev/null || true
if [ -n "$CLASS_IP" ]; then
    echo "   fail2ban: $CLASS_IP whitelisted"
else
    echo "   !! CLASS IP NOT WHITELISTED. On the morning of class, from inside the room:"
    echo "        curl -s ifconfig.me"
    echo "      then re-run:  WORKSHOP_CLASS_IP=<that ip> $0"
    echo "      Without it, a handful of mistyped passwords bans everyone for 5 minutes at once."
fi

log "Firewall (ssh + seat port ranges), enable with: ufw enable"
ufw allow 22/tcp >/dev/null
ufw allow 10000:49999/tcp >/dev/null     # <ID>xxx per-seat ports (10-49 prefix)
ufw allow 10000:49999/udp >/dev/null     # <ID>514 syslog
ufw default deny incoming >/dev/null; ufw default allow outgoing >/dev/null
ufw status | head -3

log "Kernel/limits for many containers"
grep -q 'fs.inotify.max_user_instances' /etc/sysctl.d/99-workshop.conf 2>/dev/null || cat > /etc/sysctl.d/99-workshop.conf <<'S'
fs.inotify.max_user_instances=8192
fs.inotify.max_user_watches=1048576
vm.max_map_count=262144
S
sysctl -q --system >/dev/null

log "Done. Next: issue-cert.sh → build-student-repo.sh → start-llm-relay.sh → makeuser.sh → preflight.sh"
