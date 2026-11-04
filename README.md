# RepDuo

Native UIKit iPhone app for camera-based squat and push-up counting. The MVP keeps camera frames on-device and stores only workout summaries.

## Requirements

- Xcode 26 or newer, with an iOS Simulator Runtime matching the active SDK
- iOS 15 or newer
- XcodeGen (`brew install xcodegen`)

## Generate and build

```sh
xcodegen generate
xcodebuild -project RepDuo.xcodeproj -scheme RepDuo -sdk iphonesimulator build
```

The platform-independent pose geometry, repetition state machines, and workout-session tests can also run without Simulator:

```sh
swift test
```

The iOS Simulator has no camera. In Debug Simulator builds, RepDuo presents a bundled exercise reference image and an explicit demo-count control. Those controls are excluded from Release builds. Camera, Vision, thermal behavior, and pose accuracy require a physical iPhone.

## Current verification

- 38 portable core/persistence tests pass.
- Debug unit/UI-test bundles and the Release app compile and link against the iOS Simulator SDK.
- Xcode static analysis succeeds without app-source diagnostics.

See [implementation status](Docs/IMPLEMENTATION_STATUS.md) and the [P0 acceptance matrix](Docs/ACCEPTANCE_MATRIX.md) for the exact remaining Simulator, device, performance, visual, and App Store gates.
