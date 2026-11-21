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
resources, provider-authoritative common-resource selection, one-tap access with an
explicit result, temporary-code display/copy with remaining validity, and
account management.

### Current OpenGate state contract

The complete homepage selection includes the separately returned first item
and the remaining homepage items. The first item is not an immutable building
door. Classification lists overlap the homepage selection; selecting a resource
must not move it between classifications or remove it from its original list.

A save is followed by a fresh provider read. Return and display that final list,
including any replacement or normalization performed by the provider. A changed
resource other than the clicked one is not, by itself, a failed save. Feedback
must reflect whether the requested resource is actually selected afterward.
Keep the provider's returned order; arbitrary user-defined reordering is not a
verified capability. Repeating an already-satisfied selection must not write.

| Rule | Evidence and boundary |
| --- | --- |
| Homepage count is not fixed at three | Controlled save and restoration observed different valid counts. |
| A request for two can return three | Observed provider autofill in the tested account/community; do not impose an independent-toggle invariant. |
| First item can change | Observed first-slot changes and verified restoration; do not infer immutability from name or classification. |
| Maximum count | Reference-client strings mention nine; the current server maximum is not verified. Do not invent a client-side cap. |
| Replacement choice and priority | Not established; display the provider's result rather than predicting a replacement. |
| Accounts with fewer than three authorized resources | Not tested; do not enforce a universal three-resource minimum locally. |

### Resource freshness

Native modules keep only the state needed for the current mounted UI. They do
not persist resource snapshots, favorite lists, temporary handles, vehicle
positions or security feeds to disk. Real-time API requests bypass HTTP caches;
displayed temporary codes expire and cannot be copied after expiry. Connection
credentials, installation identity and user preferences remain persistent.
Request deduplication, credential refresh coordination and configuration parsing
are necessary safeguards, not independent copies of resource state.

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

## Todo: vendor choice per module

Not started. Do not build this until it is explicitly scheduled.

The four modules (access, lock, living, and vehicle) need room for more than
one upstream vendor:

- Sign-in lets the user pick a brand. Each brand uses its own adapter and interface.
- One brand can hold several accounts. The module aggregates those accounts.
- The adapter that already ships is one brand, not the module itself.
- Brand and vendor names stay out of public code, docs, and identifiers. The
  public tree must not publish another company's marks. A vendor id can be an
  opaque value supplied outside this repository.
