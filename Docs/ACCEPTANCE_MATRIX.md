# P0 acceptance matrix

Status meanings:

- **Verified**: implemented and exercised by an available automated check.
- **Implemented / execution pending**: code and automated test exist, but the required eligible Simulator or device is unavailable locally.
- **Device QA required**: the plan explicitly requires physical-device or visual/performance evidence.
- **Release input required**: completion depends on a product/legal value not present in the development plan.

| Plan area | Status | Evidence / remaining gate |
|---|---|---|
| Camera rationale, denial, and Settings recovery | Implemented / execution pending | Coordinator and dedicated denial screen implemented; UI test compiles. Execute on eligible Simulator/device. |
| Squat and push-up end-to-end routes | Implemented / execution pending | Both routes and seven UI-test flows compile. The expanded suite awaits a booted Simulator for its next complete run. |
| No-device core workout | Verified | Gear Check never blocks Continue; Watch and audio mappings compile in the iOS test bundle. |
| Camera setup and 3-second countdown | Device QA required | Required-joint, framing, centering, size, and 0.8-second stability gates implemented. Validate placement guidance with real camera input. |
| Camera/Vision processing | Device QA required | 720p capture, nominal 30 FPS, latest-frame backpressure, pose/segmentation, stale result protection, and thermal stride are implemented. Camera behavior must be measured on device. |
| Front-camera Wide framing | Device QA required | Camera setup exposes persistent `WIDE`/standard switching. Supported devices select the front `.builtInUltraWideCamera`; unsupported devices fall back to standard. Static capability/UI tests are present; field of view and overlay alignment require iPhone 17-family hardware. |
| Squat and push-up counting | Verified for normalized fixtures; release corpus pending | 38 core tests pass, including nine specified fixture scenarios. Set a release threshold and validate the agreed real-user/video corpus. |
| Missing, occluded, low-confidence, and multiple-person handling | Verified for logic; device QA required | Logic/fixtures freeze or reset partial cycles without incrementing. Validate camera-derived classifications in the device matrix. |
| Neon segmentation rendering | Device QA required | Metal/Core Image/MPS renderer compiles with crisp edge, layered glow, short temporal transition, stale-mask expiry, and thermal degradation. Alignment, trailing, and visual parity require device screenshots/traces. |
| Pause/resume/finish and interruptions | Verified for domain logic; UI/device execution pending | Session unit tests pass; UI pause/finish-cancel test compiles; background, camera, and audio interruptions pause without auto-resume. Execute on device. |
| Audio cues, haptics, and visible equivalents | Device QA required | Phase/completion feedback and on-screen phase text implemented; route changes are shown. Validate Bluetooth/AirPods and accessibility behavior on device. |
| Local workout records | Verified | Core Data round-trip, duplicate upsert, deletion, and SQLite reopen tests pass; only summary fields are persisted. |
| Accessibility | Implemented / execution pending | Dynamic Type, VoiceOver labels/hints, visible status text, Reduce Motion, and Reduce Transparency paths implemented. Automated large-text route compiles; manual VoiceOver/high-contrast QA remains. |
| Privacy manifest and local-only media handling | Verified in source/build | Manifest plist validates and is copied into the app bundle; no network/analytics dependency exists; camera buffers are not persisted. |
| Privacy policy and App Privacy form | Release input required | Policy HTML draft and answer worksheet exist. Publisher identity/contact/hosting and App Store Connect submission remain. |
| Debug controls excluded from Release | Verified | Telemetry and simulated-rep UI are compile-time Debug-only; Release target builds successfully. |
| Static engineering checks | Verified | Debug app and complete test products build with assets; Release app and Xcode Analyze passed previously; 39 portable tests execute successfully. |
| Performance and leak budgets | Device QA required | Metrics and thermal quality hooks exist. Instruments evidence for 30 FPS, P95 < 33 ms, outline latency, stable memory, energy, and 10-minute thermal behavior remains mandatory. |
| Penpot visual parity | Device QA required | Supplied production assets are integrated and the code-drawn wordmark approximation was replaced. `design-qa.md` correctly remains blocked until matching implementation screenshots can be compared side by side. |

## Non-blocking P1 boundary

The iPhone app reports real Watch pairing/install/reachability only. Live heart rate, Watch battery, HealthKit save/mirroring, and enriched Watch summaries require the deferred watchOS companion/HealthKit scope and are not represented as active P0 capabilities.
