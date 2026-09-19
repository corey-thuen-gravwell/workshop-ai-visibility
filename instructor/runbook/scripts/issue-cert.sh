#!/bin/bash
# Issue the Let's Encrypt cert for the lab hostname via acme.sh manual DNS-01, which works with any
# DNS provider and needs no registrar API. Two-step: (1) print the TXT challenge, (2) after you add it, finish issuance and
# deploy to /opt/workshop/certs (root-owned; docker mounts it into every seat's Gravwell).
# One cert covers every per-seat port. No auto-renew: the host is disposable (90-day cert).
#
# Usage:  HOST=lab.example.com EMAIL=you@example.com ./issue-cert.sh step1   (HOST defaults to LAB_HOST)
#         (add the TXT record printed)      ./issue-cert.sh step2
set -euo pipefail
HOST="${HOST:-${LAB_HOST:-$(sed -n 's/^LAB_HOST="\(.*\)"$/\1/p' /opt/workshop/.env 2>/dev/null)}}"
: "${HOST:?set HOST= (or LAB_HOST in /opt/workshop/.env) to the lab host DNS name}"
EMAIL="${EMAIL:?Set EMAIL for the ACME account}"
CERT_DIR="${CERT_DIR:-/opt/workshop/certs}"
ACME=/root/.acme.sh/acme.sh
step="${1:-}"

if [ ! -x "$ACME" ]; then
    git clone --depth 1 https://github.com/acmesh-official/acme.sh.git /root/acme.sh-src
    (cd /root/acme.sh-src && ./acme.sh --install -m "$EMAIL" --home /root/.acme.sh --nocron)
    "$ACME" --server letsencrypt --register-account -m "$EMAIL"
fi
case "$step" in
  step1)
    "$ACME" --server letsencrypt --issue --dns -d "$HOST" \
        --yes-I-know-dns-manual-mode-enough-go-ahead-please || true
    echo; echo ">> Add the TXT record above at your DNS provider, wait ~2 min, then run: $0 step2" ;;
  step2)
    "$ACME" --server letsencrypt --renew -d "$HOST" --yes-I-know-dns-manual-mode-enough-go-ahead-please
    install -d -m 0755 "$CERT_DIR"
    "$ACME" --install-cert -d "$HOST" --fullchain-file "$CERT_DIR/cert.pem" --key-file "$CERT_DIR/key.pem"
    chmod 644 "$CERT_DIR/cert.pem"; chmod 600 "$CERT_DIR/key.pem"
    openssl x509 -in "$CERT_DIR/cert.pem" -noout -subject -issuer -enddate
    echo ">> Deployed to $CERT_DIR. Running Gravwell containers pick it up on restart." ;;
  *) echo "usage: $0 step1|step2"; exit 1 ;;
esac
