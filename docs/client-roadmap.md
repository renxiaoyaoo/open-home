# OpenHome client roadmap

This document records product direction and the prioritized remaining backlog.
The backlog states known verification limits; broader direction does not imply
that every described capability is missing from the implementation.
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
independently revocable device token.

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

## Prioritized remaining backlog

Rows are in priority order. Task IDs remain stable; task 6 (finer device/module
permissions) has been removed from this backlog. This is the single current
priority list; implementation work requires its own applicable verification.

| Priority | Task ID | Remaining work | Status and completion boundary |
| --- | --- | --- | --- |
| 1 | 2 | Verify the provider's maximum common-door count, including whether it is nine. | Unverified server policy; reference-client strings alone are insufficient. |
| 2 | 3 | Verify automatic replacement selection and ordering after a common-door removal. | Replacement is observed; its choice and priority remain unknown. |
| 3 | 4 | Verify common-door behavior for accounts with fewer than three authorized doors. | Untested; do not impose a universal minimum locally. |
| 4 | 10 | Unify iOS UI/UX across modules and unify Web UI/UX across modules. | Review navigation, hierarchy, list layout, timestamps, loading, empty/error states, accessibility and operation feedback within each platform's shared design. |
| 5 | 11 | Make door-opening feedback more prominent within the unified UX, with sound and haptics. | Assess existing feedback and complete gaps without creating a separate UX system. Give immediate tap/loading feedback, stronger confirmed-success feedback with sound and success haptics, and clear failure feedback with error haptics. Play success sound only after provider confirmation; retain duplicate-request protection. |
| 6 | 12 | Improve system loading, API latency and state-refresh speed, especially at app launch and for OpenGate. | Measure the current path and verify improvements. Prioritize quickly available door controls, fast operations and immediate feedback; preserve authoritative state and avoid unnecessary caches. |
| 7 | 8 | Complete iOS system entry points: App Intents, Control Center, Lock Screen, widgets and Shortcuts. | Some implementation exists; audit and complete missing user journeys with selected resources and secure credentials. |
| 8 | 1 | Add vendor choice per module, multiple accounts per vendor and aggregated resources. | Not started; see the scope below. |
| 9 | 5 | Validate Full signing, Push, remote Live Activities and release-signing capabilities. | Full compilation passes; paid-team signing and capability validation await a paid Apple Developer account. |
| 10 | 7 | Complete native OpenLock live video through the provider's native media SDK. | Audit existing implementation and complete missing playback/lifecycle behavior; no Web video gateway. |
| 11 | 9 | Complete on-device provider adapters for all four modules. | Shared provider interfaces and adapter installation support exist; audit and complete actual direct-mode adapters, authentication and operations per module. |

The first usable release is: connect to OpenHome, show common access resources,
perform one-tap access, display temporary codes, and expose selected resources
through Control Center.

## Task 1 scope: vendor choice per module

Not started. Follow the priority list above when scheduling implementation.

The four modules (access, lock, living, and vehicle) need room for more than
one upstream vendor:

- Sign-in lets the user pick a brand. Each brand uses its own adapter and interface.
- One brand can hold several accounts. The module aggregates those accounts.
- The adapter that already ships is one brand, not the module itself.
- Brand and vendor names stay out of public code, docs, and identifiers. The
  public tree must not publish another company's marks. A vendor id can be an
  opaque value supplied outside this repository.
