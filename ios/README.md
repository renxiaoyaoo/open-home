# OpenHome for iOS

The native client shares OpenHome's provider-neutral domain and API boundary.
It supports a remote center selected with its address and a human-readable,
short-lived activation code, plus installable
on-device provider adapters. The shared factory passes each adapter only its
provider-scoped Keychain session; credentials belong in Keychain and provider-specific
protocol values do not belong in this public target.

The app target owns navigation and account setup. The Live Activity extension
renders normalized dryer and vehicle state on the Lock Screen and Dynamic
Island. Center mode registers ActivityKit push tokens through the portable API;
direct mode refreshes state while the app has permitted execution time.

An activation code is short-lived and single-use. Every build supports the same
portable flow: scan a deployment-generated QR code or open its activation link;
manual recovery asks for the center address and short code. No deployment
address is embedded in the public client.
Native traffic reaches a non-interactive API origin protected by the
issued device bearer token. The Web origin may remain behind an identity proxy;
the server accepts its configured trusted identity header. These can be two
hostnames routing the same application and database, without coupling the core
protocol to a hosting vendor.

## Signing configurations

OpenHome keeps one implementation with two capability levels:

- `OpenHome Free` uses the `Debug-Free` and `Release-Free` configurations. It
  keeps local Live Activities but uses only app-local storage and does not
  request APNs tokens or register remote Live Activity updates. Its minimal
  entitlements support development signing with a Personal Team.
- `OpenHome Full` uses the `Debug-Full` and `Release-Full` configurations. It
  enables Push Notifications, shared App Group and Keychain storage, and remote
  Live Activity token registration for a paid Apple Developer team and release
  builds.

The repository never stores a Development Team. Load `IOS_DEVELOPMENT_TEAM`
from private machine configuration and pass it only to the build invocation:

```sh
xcodebuild -project OpenHome.xcodeproj \
  -scheme "OpenHome Free" \
  -configuration Debug-Free \
  -destination "generic/platform=iOS" \
  DEVELOPMENT_TEAM="$IOS_DEVELOPMENT_TEAM" \
  -allowProvisioningUpdates build
```
