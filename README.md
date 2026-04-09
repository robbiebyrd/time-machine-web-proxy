# Time Machine Web Proxy

A proxy server that fetches archived web content from the [Wayback Machine](https://web.archive.org) and serves it with the Wayback toolbar stripped, URLs rewritten to route through the proxy, and aggressive disk caching to minimize upstream requests.

Supports both HTTP and WebSocket interfaces.

> Adapted from [timeprox](https://github.com/remino/timeprox) by [Rémi](https://remino.net).

---

## Features

- Fetches pages from `web.archive.org` at a configurable point in time
- Strips the Wayback Machine toolbar and injected JS
- Rewrites HTML/CSS links to route through the local proxy
- Disk-based response cache (keyed by URL + timestamp)
- Background prefetching of images and stylesheets
- Token-bucket rate limiting with concurrency control
- Exponential backoff retry on transient network errors
- WebSocket API for programmatic access
- SSRF protection: blocks private/internal IPs and non-HTTP protocols
- Optional host whitelist
- Bearer token protection on the cache management API
- Docker support with Google Cloud Run deployment

---

## Quick Start (Docker)

```bash
cp .env .env.local   # adjust values as needed
docker compose up --build -d
```

The proxy listens on port `8765` by default.

---

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `TIMEMACHINE_PORT` | `8765` | Port the server listens on |
| `LISTENER` | `0.0.0.0` | Bind address |
| `PROXY_BASE_URL` | _(derived from `LISTENER:PORT`)_ | Public base URL used when rewriting proxied links. Required when running behind a reverse proxy or on Cloud Run (e.g. `https://your-service.run.app`) |
| `ARCHIVE_TIME` | `19980101000000` | Default Wayback timestamp (`YYYYMMDDHHmmss`) |
| `URL_PREFIX` | `https://web.archive.org/web` | Archive base URL |
| `PROXY_PREFIX` | _(empty)_ | Optional path prefix appended between timestamp and URL |
| `CACHE_DIR` | `/app/cache` | Directory for cached responses |
| `CACHE_ENABLED` | `true` | Set to `false` to disable disk caching |
| `CACHE_CLEAR_TOKEN` | _(empty)_ | Bearer token required to call `DELETE /cache`. If empty, the endpoint is unprotected. |
| `CORS_ORIGIN` | `http://localhost:5173` | Allowed CORS origin (`*` for open) |
| `WHITELIST_HOSTS` | `*` | Comma-separated list of allowed target hostnames (supports `*.example.com` wildcards). `*` allows all. |
| `ARCHIVE_RATE_PER_SEC` | `2` | Archive fetch rate limit (requests/sec) |
| `ARCHIVE_BURST` | `5` | Token bucket burst capacity |
| `ARCHIVE_MAX_RETRIES` | `3` | Max retries on transient errors |
| `BACKOFF_INTERVAL_SEC` | `10` | Base backoff interval (seconds); uses exponential backoff |
| `ARCHIVE_MAX_CONCURRENT` | `10` | Max concurrent in-flight archive requests |

---

## HTTP API

### `GET /?url=<url>&time=<timestamp>`

Fetches a URL from the archive at the given timestamp and returns the response with URLs rewritten.

| Parameter | Required | Description |
|---|---|---|
| `url` | Yes | Full URL to fetch (e.g. `https://example.com`) |
| `time` | No | 14-digit Wayback timestamp. Defaults to `ARCHIVE_TIME`. |

**Response headers:**

| Header | Description |
|---|---|
| `X-Archive-Url` | The resolved Wayback Machine URL |
| `X-Original-Url` | The original requested URL |
| `X-Archive-Time` | The actual timestamp of the archived snapshot |
| `X-Cache` | `HIT` or `MISS` |

**Errors:**

| Status | Reason |
|---|---|
| `400` | Missing or invalid `url`/`time` parameter |
| `403` | Private/internal host, disallowed protocol, or host not whitelisted |
| `404` | No snapshot found in archive |
| `500` | Upstream fetch failed |

---

### `DELETE /cache`

Clears cached entries. Supports optional filters.

If `CACHE_CLEAR_TOKEN` is set, requests must include:

```
Authorization: Bearer <token>
```

Returns `401` if the token is missing or incorrect.

| Query param | Description |
|---|---|
| `type` | Filter by type: `html`, `css`, or `image` |
| `domain` | Filter by domain (supports `*.example.com` wildcards) |

**Response:**

```json
{ "deleted": 12, "errors": 0 }
```

---

## WebSocket API

Connect to `ws://<host>:<port>/ws` (or `wss://` when behind TLS).

### Request

```json
{
  "type": "fetch",
  "id": "optional-correlation-id",
  "url": "https://example.com",
  "time": "19980101000000"
}
```

`time` is optional and defaults to `ARCHIVE_TIME`.

### Success response

```json
{
  "type": "result",
  "id": "optional-correlation-id",
  "html": "<body>...</body>",
  "contentType": "text/html; charset=utf-8",
  "archiveUrl": "https://web.archive.org/web/19980101000000/https://example.com",
  "originalUrl": "https://example.com",
  "archiveTime": "19980101120000",
  "cache": "MISS"
}
```

For non-HTML responses, `html` contains a base64-encoded body.

### Error response

```json
{
  "type": "error",
  "id": "optional-correlation-id",
  "status": 403,
  "message": "Host not whitelisted"
}
```

---

## Development

**Requirements:** Node.js 22+, npm

```bash
npm install
npx tsx timemachine.ts
```

The source is a single TypeScript file (`timemachine.ts`). esbuild bundles it into `dist/timemachine.js`, which the Docker image runs.

**npm scripts:**

| Script | Description |
|---|---|
| `npm run build` | Bundle `timemachine.ts` with esbuild |
| `npm run typecheck` | Type-check without emitting |

---

## Deployment (Google Cloud Run)

TLS and WSS termination are handled by Cloud Run — the container receives plain HTTP.

**One-time setup:**

```bash
./setup2.sh   # creates GCP service account and IAM bindings for GitHub Actions
```

**Deploy:**

```bash
./deploy.sh         # deploys using .env
./deploy.sh prod    # deploys using .env.prod
```

Or push to `main` — the GitHub Actions workflow triggers automatically.

**GitHub secrets required:**

| Secret | Description |
|---|---|
| `GCP_SA_KEY` | Service account JSON key |
| `GCP_PROJECT_ID` | GCP project ID |
| `GCP_CACHE_BUCKET` | GCS bucket name for shared cache |
| `ENV_PROD` | Full contents of `.env.prod` |

The shared cache is a GCS bucket mounted at `/app/cache` via GCS FUSE, so all Cloud Run instances share cached responses across restarts and scale-out events.

---

## Security

- Only `http:` and `https:` protocols are allowed as targets
- Private and loopback addresses are blocked (`localhost`, `127.x`, `10.x`, `192.168.x`, etc.)
- All archive fetches are constrained to `URL_PREFIX` — arbitrary upstream fetches are not possible
- CORS is restricted to `CORS_ORIGIN`
- `WHITELIST_HOSTS` can restrict which domains can be proxied
- `DELETE /cache` can be protected with a Bearer token via `CACHE_CLEAR_TOKEN`

---

## Credits

Based on [timeprox](https://github.com/remino/timeprox) by [Rémi](https://remino.net).
