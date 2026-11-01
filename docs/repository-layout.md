# Repository boundaries

- `web/` contains product source, tests, schema, and migrations.
- Provider-neutral module contracts, including OpenAuto's read-only vehicle and
  energy models, live in `web/lib/`; provider wire mappings remain in adapters.
- `deploy/cloudflare/` and `deploy/docker/` are optional deployment adapters.
- Generated builds, local databases, deployment configuration, binaries, captures, logs, credentials, provider endpoints, and investigation evidence are ignored.

A public release is built from a clean checkout. It must pass tests, lint, both Node.js and Workers builds, and a privacy scan before publication. Research materials are outside the public product repository. Source, deployment configuration, runtime state, and build artifacts remain separate.
