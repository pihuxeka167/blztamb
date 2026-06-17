# BLZTamburelloSignalKit

Reusable SwiftUI package for server-driven WebView launches with:

- camera upload support for web file inputs
- photo library upload support
- files picker fallback
- WebKit media capture permission handling for trusted hosts
- reactive language forwarding through `@AppStorage("settings.language")`
- audio keepalive workarounds for game-like web runtimes

Requires `iOS 16+`.

## Add To An App

```swift
dependencies: [
    .package(path: "../BLZTamburelloSignalKit")
]
```

```swift
import BLZTamburelloSignalKit
```

## Configure

```swift
let webConfiguration = BLZSignalConfiguration(
    serverDomain: "bwfit.site",
    webToken: "90e87d28cae0314e8a251e9521cdbe953ae88e42a3d4f861ba0838b57dd3ef60",
    bundleID: "com.blz.tamburellohub"
)
```

Preset example:

```swift
BLZSignalConfiguration.standardPreset
```

## Launch Panel

```swift
BLZSignalLaunchPanel(
    configuration: .standardPreset
)
```

## Root Flow

```swift
BLZSignalRootGate(
    configuration: .standardPreset,
    requestReviewBeforeCheck: false
) {
    RootView()
}
```

## Required Info.plist Keys

- `NSCameraUsageDescription`
- `NSMicrophoneUsageDescription`
- `NSPhotoLibraryUsageDescription`
