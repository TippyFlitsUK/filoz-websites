#!/usr/bin/env bash
# One-time setup for a new site:
#   1. Creates proxied A record for the hostname (placeholder 192.0.2.1, Cloudflare intercepts)
#   2. Creates Worker route <hostname>/* -> foc-gateway-proxy (shared Worker)
#
# The shared Worker is deployed separately via deploy-worker.sh (run once, or
# on Worker code changes). The CID for this hostname is stored in the KV
# namespace and updated per-deploy via deploy-site.sh.
#
# Usage: infra/workers/proxy/setup-site.sh <site-name>
#
# Required env: CLOUDFLARE_API_TOKEN

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <site-name>" >&2
  exit 1
fi

SITE="$1"
: "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN env var required}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CONFIG="$SCRIPT_DIR/config.json"
DEPLOY_JSON="$REPO_ROOT/sites/$SITE/deploy.json"
[[ -f "$CONFIG" ]] || { echo "missing $CONFIG" >&2; exit 1; }
[[ -f "$DEPLOY_JSON" ]] || { echo "missing $DEPLOY_JSON" >&2; exit 1; }

WORKER_SCRIPT=$(jq -er .worker_script "$CONFIG")
CF_ZONE_ID=$(jq -er .cf_zone_id "$DEPLOY_JSON")
HOSTNAME=$(jq -er .hostname "$DEPLOY_JSON")

echo "Site:     $SITE"
echo "Hostname: $HOSTNAME"
echo "Worker:   $WORKER_SCRIPT (shared)"
echo

echo "1/2 Creating proxied A record for $HOSTNAME ..."
DNS_RESP=$(curl -sS -X POST \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
  --data "$(jq -n --arg name "$HOSTNAME" --arg comment "Worker route placeholder - $WORKER_SCRIPT" '{
    type: "A", name: $name, content: "192.0.2.1", proxied: true, comment: $comment
  }')")
if [[ $(echo "$DNS_RESP" | jq -r .success) != "true" ]]; then
  CODE=$(echo "$DNS_RESP" | jq -r '.errors[0].code')
  if [[ "$CODE" == "81058" || "$CODE" == "81057" ]]; then
    echo "   (record already exists, skipping)"
  else
    echo "$DNS_RESP" | jq . >&2; exit 1
  fi
fi

echo "2/2 Creating Worker route $HOSTNAME/* -> $WORKER_SCRIPT ..."
ROUTE_RESP=$(curl -sS -X POST \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/workers/routes" \
  --data "$(jq -n --arg p "$HOSTNAME/*" --arg s "$WORKER_SCRIPT" '{pattern: $p, script: $s}')")
if [[ $(echo "$ROUTE_RESP" | jq -r .success) != "true" ]]; then
  CODE=$(echo "$ROUTE_RESP" | jq -r '.errors[0].code')
  if [[ "$CODE" == "10020" ]]; then
    echo "   (route already exists, skipping)"
  else
    echo "$ROUTE_RESP" | jq . >&2; exit 1
  fi
fi

echo
echo "Done. On every deploy run: deploy-site.sh $SITE <cid>"
