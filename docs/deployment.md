# Deployment

## Node.js and SQLite

Node.js is the portable default and requires no Cloudflare services. Configure `.env.local`, run `npm run build:node`, then `npm run start:node`. Persist the directory containing `OPENHOME_DATABASE_PATH` and terminate TLS at a reverse proxy.

## Docker

Build from `deploy/docker/Dockerfile`, mount `/app/web/data`, and pass configuration as environment variables or secrets. The image runs the standard Next.js server and local SQLite.

## Cloudflare Workers and D1

The Cloudflare adapter is optional. Set `OPENHOME_CF_DATABASE_ID` and optionally `OPENHOME_CF_DATABASE_NAME`, `OPENHOME_CF_CUSTOM_DOMAIN`, and `OPENHOME_ACCESS_ENABLED=1` in the private deployment environment, configure Worker secrets, then run `npm run cf:deploy` from `web`. The generated `web/wrangler.production.jsonc` is ignored. No account ID, database UUID, custom domain, or secret belongs in this repository.

For a private Web deployment, an identity proxy may protect the Web hostname and
set the header named by `OPENHOME_BROWSER_IDENTITY_HEADER`. Native clients use a
second, non-interactive API hostname routed to the same application and database;
its application routes validate revocable OpenHome device bearer tokens. Create
a ten-minute single-use activation package with `npm run activation:create`.
The command derives its administrator proof from the recoverable session key,
so no additional long-lived secret is required or printed.

Live Activity state is refreshed through the authenticated, platform-neutral
`POST /api/v1/live-activities/refresh` contract. Run `npm run
live-activities:refresh` from any trusted scheduler with the deployment's
existing API URL and session key; APNs variables remain on the application
runtime. The scheduler may be a Node
cron job, a CI schedule, or a platform timer; the product core does not depend
on Cloudflare scheduling. Unchanged state is not sent again, and a terminal
dryer state closes its registered activity.

To sync an ignored private environment file through a deployment host without retaining a remote plaintext copy, run `deploy/cloudflare/sync-via-ssh.sh <ssh-target> <remote-repo-root> [private-env-file]`. The remote temporary file is removed automatically after Wrangler updates the Worker secrets.

`OPENHOME_SESSION_ENCRYPTION_KEY` is deployment-owned key material. Generate or rotate it with `node deploy/cloudflare/rotate-session-key.mjs .env.deploy.local --yes`, then sync the secrets. The tool uses 32 cryptographically random bytes encoded as 64 hexadecimal characters. Rotation deliberately makes existing stored sessions unreadable, so every account must log in again.

Provider compatibility is installed as a schema-versioned bundle. Configure `OPENHOME_PROVIDER_BUNDLE_URL` and `OPENHOME_PROVIDER_BUNDLE_TOKEN` in the ignored private deployment environment, then run `node deploy/cloudflare/sync-secrets.mjs .env.deploy.local` from the repository root. The deployment command fetches the bundle over HTTPS and streams bounded parts directly into the Worker secret store; it does not save or print the bundle. Each deployer is responsible for an authorized compatible configuration source.

Cloudflare Secrets are write-only and are not a backup. Keep the session key,
bundle-service token, and the source values used to rebuild the provider bundle
in encrypted private machine configuration owned by the deployer. The ignored
deployment file may reference those inputs, but neither it nor generated bundle
JSON belongs in Git.
