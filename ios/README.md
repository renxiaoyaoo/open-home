# OpenHome for iOS

The native client shares OpenHome's provider-neutral domain and API boundary.
It supports a remote center selected with an activation code and installable
on-device provider adapters. Credentials belong in Keychain; provider-specific
protocol values do not belong in this public target.

The app target owns navigation and account setup. The Live Activity extension
renders normalized dryer and vehicle state on the Lock Screen and Dynamic
Island. A center deployment may update activities through ActivityKit push;
direct mode refreshes state while the app has permitted execution time.

An activation package contains the center API URL and a short-lived, single-use
secret. Native traffic reaches a non-interactive API origin protected by the
issued device bearer token. The Web origin may remain behind an identity proxy;
the server accepts its configured trusted identity header. These can be two
hostnames routing the same application and database, without coupling the core
protocol to a hosting vendor.
