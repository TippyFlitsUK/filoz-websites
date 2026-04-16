#!/usr/bin/env bash
# Update the KV entry for a site with a new CID.
# The shared Worker (foc-gateway-proxy) reads CIDS[hostname] on every request.
#
# Usage: infra/workers/proxy/deploy-site.sh <site-name> <cid>
#
# Required env: CLOUDFLARE_API_TOKEN (Account > Workers KV Storage Edit)

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <site-name> <cid>" >&2
  exit 1
fi

SITE="$1"
CID="$2"
: "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN env var required}"

# Validate CID: bafy... (v1, base32) or Qm... (v0, base58). Minimum ~46 chars.
if [[ ! "$CID" =~ ^(bafy[a-z2-7]{55,}|Qm[1-9A-HJ-NP-Za-km-z]{44})$ ]]; then
  echo "invalid CID format: '$CID' (expected bafy... or Qm...)" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CONFIG="$SCRIPT_DIR/config.json"
DEPLOY_JSON="$REPO_ROOT/sites/$SITE/deploy.json"
[[ -f "$CONFIG" ]] || { echo "missing $CONFIG" >&2; exit 1; }
[[ -f "$DEPLOY_JSON" ]] || { echo "missing $DEPLOY_JSON" >&2; exit 1; }

CF_ACCOUNT_ID=$(jq -er .cf_account_id "$CONFIG")
KV_ID=$(jq -er .kv_namespace_id "$CONFIG")
HOSTNAME=$(jq -er .hostname "$DEPLOY_JSON")

echo "KV PUT $HOSTNAME = $CID ..."
RESP=$(curl -sS -X PUT \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/storage/kv/namespaces/$KV_ID/values/$HOSTNAME" \
  --data "$CID")

if [[ $(echo "$RESP" | jq -r .success) != "true" ]]; then
  echo "$RESP" | jq . >&2; exit 1
fi
echo "done."
