# filoz-websites

Mono-repo for FilOz web properties. Same architecture as [foc-websites](https://github.com/TippyFlitsUK/foc-websites) — each site is an [Astro](https://astro.build) project under `sites/`, deployed to Filecoin Onchain Cloud via [Nova](https://github.com/FilOzone/filecoin-nova), and served through a shared Cloudflare Worker proxy with an ENS fallback.

Plan + rollout tracker: [FilOzone/tpm-utils#2](https://github.com/FilOzone/tpm-utils/issues/2)

## Architecture

Identical to foc-websites. Both repos deploy against the same Cloudflare Worker (`foc-gateway-proxy`) and the same KV namespace — the Worker resolves `CIDS[hostname]` per request, so each site's deploys update only its own KV key.

```
Browser -> *.filoz.org (prod) / *.filecoincloud.io (staging)
        -> Cloudflare edge -> Worker -> KV[hostname]
        -> fallback IPFS gateways: dweb.link -> ipfs.io -> 4everland.io
        -> FOC-pinned content
```

ENS fallback: `*.filnova.eth` (staging) / `*.filoz.eth` (prod), resolvable via `eth.limo`.

## Repo layout

```
filoz-websites/
  infra/workers/proxy/            copy of foc-websites worker infra
  sites/<name>/                   one Astro project per site
    deploy.json                   per-site zone / hostname / ENS name
```

See [`infra/workers/proxy/README.md`](infra/workers/proxy/README.md) for the Worker + deploy scripts.

## Sites

| Site | Production | Staging | Status |
|---|---|---|---|
| FilOz Home | filoz.org | filoz.filecoincloud.io | Pending (source: Hugo Webflow clone at `filoz-home-desite`) |
| DealBot | dealbot.filoz.org | dealbot.filecoincloud.io | Pending |
| DealBot Staging | staging.dealbot.filoz.org | dealbot-staging.filecoincloud.io | Pending |

## Deploy

Same flow as foc-websites:

```bash
export CLOUDFLARE_API_TOKEN=...
cd sites/<name>
npm run build
CID=$(nova deploy dist --json | jq -r .cid)              # never use --clean
../../infra/workers/proxy/deploy-site.sh <name> "$CID"
../../infra/workers/proxy/dnslink.sh <name> "$CID"
NOVA_RPC_URL=https://ethereum-rpc.publicnode.com \
  nova ens "$CID" --ens $(jq -r .ens_name deploy.json)
```

Required GitHub secrets: `NOVA_PIN_KEY`, `NOVA_WALLET_ADDRESS`, `NOVA_ENS_KEY`, `NOVA_RPC_URL`, `CLOUDFLARE_API_TOKEN`.

## Special considerations

- **DealBot** frontend is a React SPA calling a backend API. `API_BASE_URL` must be set to an absolute backend URL at build time — same-origin won't work from IPFS. Backend stays on current infrastructure (`77.42.75.71`).
- **FilOz Home** rebuilds a Webflow site; Webflow IX2 animations depend on `data-wf-page` attributes — preserve them per page during the Hugo → Astro port.
