# Project Memory — Time Machine Web Proxy

Running notes on decisions made, gotchas hit, and things to remember.

---

## GCP Configuration

| Resource | Value |
|---|---|
| Project ID | `civil-clarity-280121` |
| Project Number | `723408812472` |
| Region | `us-central1` |
| Artifact Registry | `us-central1-docker.pkg.dev/civil-clarity-280121/cloud-run-source-deploy` |
| Cloud Run service | `time-machine-proxy` |
| Cloud Run URL | `https://time-machine-proxy-723408812472.us-central1.run.app` |
| Cache bucket | `tm-cache-723408812472` |

**Artifact Registry uses the regional hostname** (`us-central1-docker.pkg.dev`), not the multi-region one (`us-docker.pkg.dev`). Using the wrong hostname produces a misleading "repository not found" error.

---

## IAM Grants

Cloud Build service account (`723408812472@cloudbuild.gserviceaccount.com`):
- `roles/artifactregistry.writer`
- `roles/run.admin`
- `roles/iam.serviceAccountUser`

GitHub deploy service account (`github-deploy@civil-clarity-280121.iam.gserviceaccount.com`):
- `roles/cloudbuild.builds.editor`
- `roles/storage.admin`

Default Compute service account (`723408812472-compute@developer.gserviceaccount.com`):
- `roles/storage.objectAdmin` — allows Cloud Run to read/write the GCS cache bucket

---

## Architecture Decisions

**esbuild over tsc:** Bundles `timemachine.ts` + `ws` into a single JS file. The runtime Docker image needs no `node_modules`, making it significantly smaller.

**GCS FUSE mount for cache:** All Cloud Run instances share `/app/cache` via the `tm-cache-723408812472` bucket. Cache entries are write-once (keyed by SHA256(url+time)), so concurrent writes from multiple instances are safe.

**Session affinity on Cloud Run:** Required for WebSocket connections to stay on the same instance for their full lifetime.

**Timeout 3600s on Cloud Run:** Allows long-lived WebSocket connections. Cloud Run's default of 300s would terminate them prematurely.

---

## Known Gotchas

**`LISTENER` on Cloud Run:** Must be `0.0.0.0`. The `.env.prod` file has `127.0.0.1` (correct for local use), but `cloudbuild.yaml` overrides it via `sed` during the env file conversion step.

**`--env-vars-file` format:** `gcloud run deploy --env-vars-file` expects YAML (`KEY: value`), not shell format (`KEY=value`). `cloudbuild.yaml` converts `.env.prod` on the fly using `awk`/`sed` before the deploy step.

**`--env-vars-file` and `--set-env-vars` are mutually exclusive:** Cannot use both in the same `gcloud run deploy` command. The `LISTENER` override is baked into the YAML conversion step instead.

**`COMMIT_SHA` in manual builds:** Not auto-populated when running `gcloud builds submit` manually. Must be passed explicitly: `--substitutions=COMMIT_SHA=$(git rev-parse --short HEAD)`.

**Docker Hub in `images:` block:** Cloud Build's `images:` block only accepts fully-qualified Artifact Registry / GCR URIs. Docker Hub short names (`robbiebyrd/time-machine-proxy`) cause a parse error. The push happens via an explicit step; Docker Hub images are not listed in `images:`.

**Alpine vs Debian user creation:** `addgroup/adduser -S` flags are Alpine Linux syntax. The base image (`node:22-bookworm-slim`) is Debian — use `addgroup --system` and `adduser --system --ingroup` instead.

**GCS bucket name collisions:** GCS bucket names are globally unique across all GCP customers. Project-ID-based names can still collide. The cache bucket uses the project number (`tm-cache-723408812472`) which is globally unique.

**`.env.prod` excluded from Cloud Build uploads:** `.env.prod` is listed in `.gitignore`, so `gcloud builds submit` skips it by default. `.gcloudignore` inherits `.gitignore` and then un-ignores `.env.prod` with `!.env.prod`.

---

## GitHub Secrets

| Secret | Description |
|---|---|
| `GCP_SA_KEY` | Service account JSON key for `github-deploy` SA |
| `GCP_PROJECT_ID` | `civil-clarity-280121` |
| `GCP_CACHE_BUCKET` | `tm-cache-723408812472` |
| `ENV_PROD` | Full contents of `.env.prod` |

After any change to `.env.prod`, update the `ENV_PROD` secret before the next deploy.
