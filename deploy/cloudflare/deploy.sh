#!/bin/sh
set -eu

# Node 24 requires this opt-in for fetch() to honor HTTP(S)_PROXY.
export NODE_USE_ENV_PROXY="${NODE_USE_ENV_PROXY:-1}"

deploy_root=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
web_root=$(CDPATH= cd -- "$deploy_root/../../web" && pwd)
cd "$web_root"
node "$deploy_root/prepare-config.mjs"
npm test
npm run lint
npm run build
./node_modules/.bin/wrangler d1 migrations apply "${OPENHOME_CF_DATABASE_NAME:-open-home}" --remote --config wrangler.production.jsonc
node "$deploy_root/sync-secrets.mjs" "" wrangler.production.jsonc
./node_modules/.bin/wrangler deploy --config wrangler.production.jsonc
