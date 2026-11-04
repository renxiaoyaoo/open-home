# OpenHome client roadmap

This document records product direction, not current implementation status.
OpenHome should have one client whose modules share navigation, security, and
platform integrations. OpenGate is the access-control module inside that client,
not a separate client product.

OpenLock live video belongs in the native OpenHome app, where the provider's
native media SDK can own playback and lifecycle. The Web module covers device
status, capture albums, security and operation records, and temporary passwords;
it must not add an Android runtime or video gateway to obtain live playback.

OpenAuto is the read-only vehicle module. Its stable client model covers vehicle
identity, ignition state, estimated range, traction-battery and fuel levels,
recent and cumulative energy consumption, cost, mileage, load distribution, and
trend data. Provider endpoints, raw response fields, sessions, signatures, and
client compatibility values remain behind its adapter. Remote controls are not
part of the initial module.

## Module operating modes

The same module UI supports two mutually exclusive modes per upstream account.
Users choose how the account is hosted without learning two different products.

### Connect to OpenHome

The client connects to a self-hosted OpenHome service and uses the module API.
The upstream account signs in once on the service. iPhone, Web, Control Center,
widgets, and shortcuts share that server-held upstream session. The client stores
only its own per-device OpenHome credential, never the upstream credential.

This mode supports multiple clients and centralized management of multiple
accounts and all their access resources. Each activated client receives an
independently revocable device token; finer module permissions remain future work.

### Use only on this device

The client talks directly to the configured provider and stores account
sessions in local secure storage. It requires no OpenHome service and offers the
same focused, advertisement-free OpenGate experience.

Some upstream providers allow only one active session. Local mode may therefore
invalidate the provider's official app or another device. An upstream account
must not be enabled in both modes at the same time.

## Shared client contract

Each module defines one interface for both modes and returns the same account,
resource, and operation-result models. OpenGate starts with:

```text
Native OpenHome client
        |
        v
Unified GateProvider
        |
        +-- RemoteOpenGateProvider -> OpenHome OpenGate API
        |
        +-- LocalGateProvider      -> on-device provider adapter
```

The UI must not depend directly on either the OpenHome API or provider protocol.
Both modes support authentication challenges, multiple accounts, common and all
resources, common-resource selection and ordering, one-tap access with an
explicit result, temporary-code display/copy with remaining validity, and
account management.

OpenAuto follows the same split through `OpenAutoProvider`: center mode calls the
OpenHome API, while local mode keeps the provider session in device secure
storage. Both return the models in `web/lib/openauto.ts`; neither UI path may
consume provider response maps directly.

## Native iPhone direction

The first native client should target iOS because the primary journeys include
locked-screen access, Control Center, in-app temporary codes, widgets, and
Shortcuts. The main app owns authentication, resource selection, and settings.
App Intents expose only user-selected resources to Control Center, Lock Screen,
widgets, and shortcuts. Credentials stay in Keychain.

## Delivery order

1. Stabilize and document the OpenGate API.
2. Define shared client models and `GateProvider`.
3. Build the native iOS client using `RemoteOpenGateProvider`.
4. Add App Intents, Control Center, Lock Screen, widgets, and shortcuts.
5. Add per-device credentials, revocation, and permissions to OpenHome.
6. Add `LocalGateProvider` using the existing compatible protocol adapter.
7. Consider Android and distribution only after the core journeys are stable.

The first usable release is: connect to OpenHome, show common access resources,
perform one-tap access, display temporary codes, and expose selected resources
through Control Center.
