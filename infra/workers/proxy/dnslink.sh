#!/usr/bin/env bash
# Create or update a DNSLink TXT record for a site so IPFS-native clients
# (Brave, IPFS Desktop, ipfs:// URIs) can resolve the hostname to a CID.
#
# Usage: infra/workers/proxy/dnslink.sh <site-name> <cid>
#
# Optional: the Worker proxy path does NOT need this. Only add it if you want
# ipfs://<hostname> and /ipns/<hostname>/... on public gateways to work.

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <site-name> <cid>" >&2
  exit 1
fi

SITE="$1"
CID="$2"
: "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN env var required}"

if [[ ! "$CID" =~ ^(bafy[a-z2-7]{55,}|Qm[1-9A-HJ-NP-Za-km-z]{44})$ ]]; then
  echo "invalid CID format: '$CID'" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DEPLOY_JSON="$REPO_ROOT/sites/$SITE/deploy.json"
[[ -f "$DEPLOY_JSON" ]] || { echo "missing $DEPLOY_JSON" >&2; exit 1; }

CF_ZONE_ID=$(jq -er .cf_zone_id "$DEPLOY_JSON")
HOSTNAME=$(jq -er .hostname "$DEPLOY_JSON")
RECORD_NAME="_dnslink.$HOSTNAME"
TXT_CONTENT="dnslink=/ipfs/$CID"

echo "Looking up existing $RECORD_NAME ..."
EXISTING=$(curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records?type=TXT&name=$RECORD_NAME")

RECORD_ID=$(echo "$EXISTING" | jq -r '.result[0].id // empty')

if [[ -n "$RECORD_ID" ]]; then
  echo "Updating TXT $RECORD_NAME -> $TXT_CONTENT"
  RESP=$(curl -sS -X PATCH \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type: application/json" \
    "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records/$RECORD_ID" \
    --data "$(jq -n --arg c "$TXT_CONTENT" '{content: $c}')")
else
  echo "Creating TXT $RECORD_NAME -> $TXT_CONTENT"
  RESP=$(curl -sS -X POST \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type: application/json" \
    "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
    --data "$(jq -n --arg n "$RECORD_NAME" --arg c "$TXT_CONTENT" '{type: "TXT", name: $n, content: $c, ttl: 300}')")
fi

if [[ $(echo "$RESP" | jq -r .success) != "true" ]]; then
  echo "$RESP" | jq . >&2; exit 1
fi
echo "done: $(echo "$RESP" | jq -r '.result.name') = $(echo "$RESP" | jq -r '.result.content')"
