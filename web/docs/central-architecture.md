# OpenHome architecture

```text
Web shell / native OpenHome clients
          |
 deployment access boundary (for example Cloudflare Zero Trust)
          |
 module use cases (OpenGate, OpenLiving, future modules)
          |                         |
 stable domain models       shared security/error primitives
          \_________________________/
                       |
          storage ports + provider adapters
              /                       \
     Cloudflare D1 / SQLite      provider bundle
```

The Web shell owns navigation and shared presentation behavior; it does not own
provider protocol. Each module exposes stable use cases and domain types through
its adapter. Shared storage, encryption, error handling, and deployment code are
reused rather than copied. Cloudflare-specific bindings remain in the Worker and
deployment adapter; Node.js uses SQLite.

Provider endpoints and compatibility material arrive as one schema-versioned
runtime bundle. A private configuration service may supply that bundle during
deployment, but it is not in the daily request path. Account and device traffic
travels directly from the user's OpenHome deployment to the configured provider.

Every client uses the same interface and can add, list, or remove accounts. Account results expose only an opaque ID and display name. Door results never expose account ownership, upstream IDs, hardware addresses, or signing inputs.

Native clients select one provider implementation per upstream account:

```text
module UI -> unified module provider -> RemoteOpenHomeProvider -> OpenHome API
                              `------> LocalProvider -> provider from this device
```

Remote mode keeps only provider-scoped accounts and encrypted upstream sessions in D1 or SQLite
so several clients can share one center. Resource lists, provider-owned common
selection, and ordering are read from the provider on every request. Encrypted
opaque resource handles carry the target needed for an immediate operation, so
the center does not persist resource caches or upstream identifiers. Duplicate
open suppression is short-lived process memory, not an activity record. Local
mode does not call the OpenHome database and keeps its upstream session in
platform secure storage. The same upstream account must not be active in both
modes when the provider enforces single-session login. The current Web
deployment may rely on its deployment access boundary; native remote access
will require revocable per-device credentials before release.

Sessions are encrypted with AES-256-GCM. Mobile numbers are retained only as an
HMAC fingerprint and a display mask. Removing an account deletes its encrypted
session through a foreign-key cascade. OpenGate, OpenLiving, OpenLock, and OpenAuto all
read these server-held sessions, so browsers do not own upstream login state.
Provider token refresh uses a short account-scoped storage lease and re-reads the
latest encrypted session before refreshing. This works through the shared database
port on SQLite and D1, survives stateless instance replacement, and does not
serialize or cache ordinary real-time reads. It deliberately has no dependency on
Cloudflare Durable Objects or process memory.
The encryption key is deployment identity and must survive ordinary releases; access-boundary cookies
remain hostname-scoped and require an explicit migration or reauthentication
when the hostname changes.

State-changing adapter calls validate input, suppress accidental duplicates,
map upstream failures into stable errors, and read state back when the provider
supports it. UI scheduling uses a desired start time; any upstream delay or
completion-time representation is an adapter concern.
