#!/usr/bin/env bash
# Upload (or re-upload) the shared foc-gateway-proxy Worker.
#
# Run this once initially, and again whenever worker.js changes.
# Per-site CID updates do NOT require re-running this - they go via KV.
#
# Required env: CLOUDFLARE_API_TOKEN (Account > Workers Scripts Edit)

set -euo pipefail

: "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN env var required}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$SCRIPT_DIR/config.json"
[[ -f "$CONFIG" ]] || { echo "missing $CONFIG" >&2; exit 1; }

CF_ACCOUNT_ID=$(jq -er .cf_account_id "$CONFIG")
WORKER_SCRIPT=$(jq -er .worker_script "$CONFIG")
KV_ID=$(jq -er .kv_namespace_id "$CONFIG")
COMPAT_DATE=$(jq -er .compatibility_date "$CONFIG")

METADATA=$(jq -n \
  --arg cd "$COMPAT_DATE" \
  --arg kv "$KV_ID" \
  '{
    main_module: "worker.js",
    compatibility_date: $cd,
    bindings: [{ type: "kv_namespace", name: "CIDS", namespace_id: $kv }]
  }')

echo "Uploading $WORKER_SCRIPT ..."
RESP=$(curl -sS -X PUT \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/workers/scripts/$WORKER_SCRIPT" \
  -F "metadata=$METADATA;type=application/json" \
  -F "worker.js=@$SCRIPT_DIR/worker.js;type=application/javascript+module")

if [[ $(echo "$RESP" | jq -r .success) != "true" ]]; then
  echo "$RESP" | jq . >&2; exit 1
fi
echo "deployed: $(echo "$RESP" | jq -r '.result.deployment_id')"
