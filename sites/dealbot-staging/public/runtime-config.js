// Runtime-configurable values for the frontend. Can be overwritten at deploy time.
// API calls are same-origin: the Cloudflare Worker proxies /api/* to the NestJS
// backend at https://staging.dealbot.filoz.org (see infra/workers/proxy/worker.js).
window.__DEALBOT_CONFIG__ = {
  API_BASE_URL: "",
  PLAUSIBLE_DATA_DOMAIN: "staging.dealbot.filoz.org",
  DASHBOARD_URL: "https://telemetry.betterstack.com/dashboards/wt6QCw",
  DASHBOARD_EMBED_URL: "https://telemetry.betterstack.com/dashboards/1MnUG3",
  LOGS_URL: "https://telemetry.betterstack.com/dashboards/1eH3gR",
};
