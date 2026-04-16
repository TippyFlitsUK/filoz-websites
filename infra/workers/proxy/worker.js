const GATEWAYS = [
  { name: 'dweb.link', url: (cid, path) => `https://${cid}.ipfs.dweb.link${path}` },
  { name: 'ipfs.io', url: (cid, path) => `https://ipfs.io/ipfs/${cid}${path}` },
  { name: '4everland.io', url: (cid, path) => `https://${cid}.ipfs.4everland.io${path}` },
]

const PER_GATEWAY_TIMEOUT_MS = 15000
const EDGE_CACHE_TTL_SECONDS = 300

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url)
    const host = url.hostname
    const path = url.pathname + url.search

    const cid = await env.CIDS.get(host)
    if (!cid) {
      return new Response(`No CID registered for ${host}`, { status: 404 })
    }

    if (request.method !== 'GET' && request.method !== 'HEAD') {
      return new Response('Method not allowed', { status: 405 })
    }

    const cache = caches.default
    const cacheKey = new Request(url.toString(), request)
    const cached = await cache.match(cacheKey)
    if (cached) {
      const res = new Response(cached.body, cached)
      res.headers.set('x-foc-cache', 'HIT')
      return res
    }

    const errors = []
    for (const gw of GATEWAYS) {
      try {
        const upstream = gw.url(cid, path)
        const controller = new AbortController()
        const timeoutId = setTimeout(() => controller.abort(), PER_GATEWAY_TIMEOUT_MS)

        const upstreamReq = new Request(upstream, {
          method: request.method,
          headers: filterRequestHeaders(request.headers),
          signal: controller.signal,
          redirect: 'follow',
        })

        const upstreamRes = await fetch(upstreamReq, { cf: { cacheTtl: EDGE_CACHE_TTL_SECONDS, cacheEverything: true } })
        clearTimeout(timeoutId)

        if (upstreamRes.status >= 500 || upstreamRes.status === 408 || upstreamRes.status === 429) {
          errors.push(`${gw.name}: ${upstreamRes.status}`)
          continue
        }

        const response = new Response(upstreamRes.body, {
          status: upstreamRes.status,
          statusText: upstreamRes.statusText,
          headers: filterResponseHeaders(upstreamRes.headers),
        })
        response.headers.set('x-foc-gateway', gw.name)
        response.headers.set('x-foc-cid', cid)
        response.headers.set('cache-control', `public, max-age=${EDGE_CACHE_TTL_SECONDS}`)

        if (upstreamRes.ok && request.method === 'GET') {
          ctx.waitUntil(cache.put(cacheKey, response.clone()))
        }

        return response
      } catch (err) {
        errors.push(`${gw.name}: ${err.name === 'AbortError' ? 'timeout' : err.message}`)
      }
    }

    return new Response(`All IPFS gateways failed for CID ${cid}\n\n${errors.join('\n')}`, {
      status: 502,
      headers: { 'content-type': 'text/plain; charset=utf-8' },
    })
  },
}

function filterRequestHeaders(headers) {
  const out = new Headers()
  const keep = ['accept', 'accept-encoding', 'accept-language', 'range', 'if-none-match', 'if-modified-since', 'user-agent']
  for (const [k, v] of headers) {
    if (keep.includes(k.toLowerCase())) out.set(k, v)
  }
  return out
}

function filterResponseHeaders(headers) {
  const out = new Headers()
  const drop = [
    'set-cookie',
    'x-ipfs-path',
    'x-ipfs-roots',
    'x-ipfs-pop',
    'server',
    'cf-ray',
    'nel',
    'report-to',
    'expect-ct',
    'alt-svc',
  ]
  for (const [k, v] of headers) {
    if (!drop.includes(k.toLowerCase())) out.set(k, v)
  }
  return out
}
