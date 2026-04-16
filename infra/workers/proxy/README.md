# FOC Gateway Proxy Worker

Single Cloudflare Worker + KV namespace that serves every FOC/FilOz site.
Each site is one DNS record, one Worker route, and one KV key; the shared
Worker reads `CIDS[hostname]` per request and proxies to a public IPFS
gateway fallback chain: **dweb.link → ipfs.io → 4everland.io**.

Replaces Cloudflare Web3 Gateway, which is unreliable for FOC CIDs (root
served, subpaths returned 524 indefinitely, not fixable via any
control-plane action).

## Why this shape

One Worker for N sites instead of N Workers:

- Per-deploy CID update = single KV PUT (no script re-upload)
- Adding a site = DNS record + route + KV entry (no new Worker)
- One script file to maintain
- Same operational model whether it's 1 site or 20

## Files

| File | Purpose |
|---|---|
| `worker.js` | Shared Worker code — reads `CIDS[host]`, proxies to fallback gateways |
| `config.json` | Shared account/KV/script IDs and compat date |
| `deploy-worker.sh` | Uploads the Worker (run once, or on `worker.js` changes) |
| `setup-site.sh` | Creates DNS + route for a new site |
| `deploy-site.sh` | KV PUT for a site's CID (run on every deploy) |
| `dnslink.sh` | Creates/updates `_dnslink.<host>` TXT for IPFS-native clients (Brave, IPFS Desktop) |

## Per-site config — `sites/<name>/deploy.json`

```json
{
  "cf_zone_id": "ec64112d49365c91cf3c8db1424b5632",
  "hostname": "cloud.filecoincloud.io",
  "ens_name": "cloud.filnova.eth"
}
```

## One-time (entire monorepo)

```bash
export CLOUDFLARE_API_TOKEN=...
infra/workers/proxy/deploy-worker.sh    # uploads the shared Worker
```

## One-time per new site

```bash
infra/workers/proxy/setup-site.sh <name>    # DNS A + Worker route
```

## Every deploy

```bash
cd sites/<name>
npm run build
CID=$(nova deploy dist/ --json | jq -r .cid)   # never --clean
../../infra/workers/proxy/deploy-site.sh <name> "$CID"
../../infra/workers/proxy/dnslink.sh <name> "$CID"
NOVA_RPC_URL=https://ethereum-rpc.publicnode.com \
  nova ens "$CID" --ens $(jq -r .ens_name deploy.json)
```

KV propagation is ~60s globally.

## Cloudflare API token scopes

Single token, reused by all scripts and CI:

| Scope | Level |
|---|---|
| Workers Scripts Edit | Account |
| Workers KV Storage Edit | Account |
| Workers Routes Edit | Zone |
| DNS Edit | Zone |
| Cache Purge | Zone |
| Zone Read | Zone |

## Response headers

`x-foc-gateway: dweb.link|ipfs.io|4everland.io` and `x-foc-cid: <CID>` —
lets you see which upstream served each request.
