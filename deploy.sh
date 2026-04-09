#!/usr/bin/env bash
set -euo pipefail

ENV="${1:-}"
if [[ "$ENV" == "prod" ]]; then
  source .env.prod
else
  source .env
fi

gcloud builds submit \
  --config cloudbuild.yaml . \
  --project="$PROJECT_ID" \
  --substitutions="_CACHE_BUCKET=$CACHE_BUCKET,COMMIT_SHA=$(git rev-parse --short HEAD)"
