# OpenHome

OpenHome is a self-hosted home-control hub and the foundation for one unified native client. Its shared Web and API foundation hosts focused modules.

The public project is provider-neutral: upstream endpoints, credentials, signing material, deployment domains, user data, and captured artifacts are never committed.

## Modules

- **OpenGate**: multiple access-provider accounts, aggregated doors, remote opening, and temporary access codes
- **OpenDevice**: authorized smart-appliance accounts and device controls; dryer status, programs, operation, and appointments are currently implemented
- **OpenLock**: smart-lock status, capture albums, security and operation records, and temporary passwords
- **OpenAuto**: read-only vehicle status, range, battery/fuel levels, mileage, charging data, tire pressure, and energy analysis

## Shared foundation

- Server-held OpenGate sessions that can be shared across clients
- Aggregated doors without exposing account-to-door relationships
- Opaque public identifiers and idempotent open requests
- Large, mobile-first door controls
- Cloudflare Workers + D1 deployment
- Standard Node.js + local SQLite deployment
- Compatible with an external access boundary such as Cloudflare Zero Trust

The existing Web UI remains a first-class client. Future native clients use the
same domain models and let each upstream account choose either a self-hosted
OpenHome center or an on-device provider adapter. Center mode uses the database;
direct mode stores its session in the device's secure storage and needs no
OpenHome database.

## Run with Node.js

```sh
cd web
cp .env.example .env.local
npm ci
npm run build:node
npm run start:node
```

Node.js 22.13 or newer is required. Local state is stored in `web/data/open-home.sqlite` by default.

## Cloudflare

Cloudflare is an optional adapter, not a core requirement. See [`deploy/cloudflare`](deploy/cloudflare) for the D1/Workers template. Deployment domains and Cloudflare account identifiers belong in private, ignored configuration.

See [architecture](web/docs/central-architecture.md), [client roadmap](docs/client-roadmap.md), [OpenAPI](web/docs/openapi.yaml), [deployment guide](docs/deployment.md), and [repository boundaries](docs/repository-layout.md).
