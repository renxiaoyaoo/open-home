# OpenHome for iOS

The native client shares OpenHome's provider-neutral domain and API boundary.
It supports a remote center selected with an activation code and installable
on-device provider adapters. Credentials belong in Keychain; provider-specific
protocol values do not belong in this public target.

The app target owns navigation and account setup. The Live Activity extension
renders normalized dryer and vehicle state on the Lock Screen and Dynamic
Island. A center deployment may update activities through ActivityKit push;
direct mode refreshes state while the app has permitted execution time.
