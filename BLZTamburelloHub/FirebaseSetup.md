# Firebase setup

Firebase Analytics and Messaging are wired into the app target.

To activate them for release:

1. Create an iOS app in Firebase with bundle id `com.blz.tamburellohub`.
2. Download its `GoogleService-Info.plist`.
3. Add that file to `BLZ Tamburello Hub/BLZTamburelloHub/` and include it in the app target resources.
4. In Apple Developer, enable Push Notifications for the app id and upload/configure an APNs auth key in Firebase Cloud Messaging.

The app safely skips Firebase configuration when `GoogleService-Info.plist` is missing, so local builds do not crash.
