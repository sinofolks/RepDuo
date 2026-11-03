# RepDuo implementation status

RepDuo now contains a buildable iPhone P0 implementation of `REPDUO-IOS-DEVELOPMENT-PLAN.md`. The app is UIKit-only, has no third-party runtime dependency, and keeps camera processing on the device.

## Implemented

- Coordinator-based app lifecycle, dependency container, design tokens, reusable UIKit controls, Dynamic Type, VoiceOver metadata, Reduce Motion, and Reduce Transparency handling.
- Onboarding, camera rationale and denied-permission recovery, non-blocking gear check, exercise selection, pose-aware camera setup, pose-gated countdown, live workout, pause/resume/finish, completion summary, history, settings, and clear-history flow.
- 720p front-camera capture at a requested 30 FPS, Center Stage front ultra-wide detection with a persistent static `WIDE` framing mode and standard-camera fallback, consistent portrait/mirror transform, capture interruption recovery, bounded backpressure, and thermal-aware Vision sampling.
- Vision human-pose and person-segmentation requests, EMA landmark smoothing, left/right-side support, required-joint confidence gates, multi-person rejection, stale-mask expiry, and setup framing guidance.
- Independent squat and push-up state machines with hysteresis, stable-frame gates, duration and cooldown checks, missing-body recovery, and push-up body-line validation.
- Metal-backed `MTKView` rendering with Core Image plus Metal Performance Shaders blur, crisp edge and glow layers, short mask transition, stale-mask clearing, and thermal quality degradation.
- Audio phase cues, completion cue, haptics, visible equivalents, system audio-route classification, and optional Watch pairing/install/reachability status. No unsupported device scan or battery claim is made.
- Programmatic Core Data store with migration options, id-based upsert, summary-only persistence, and clear-history support. Frames, masks, and pose sequences are not persisted.
- Privacy manifest, App Store privacy preparation notes, and a deployable privacy-policy HTML draft.
- GitHub Actions CI baseline for portable tests plus Simulator unit/UI tests on an eligible hosted runtime.
- Debug-only telemetry for camera FPS, Vision latency, Metal GPU time, thermal state, pose phase/quality, joint angle, renderer quality, and a bounded rep-event timeline. Simulator demo controls and telemetry are absent from a Release device build.
- Structured OSLog categories for lifecycle, camera, pose, segmentation, rep engine, Metal, Watch, audio route, and persistence. Logs avoid frames, keypoints, user-named audio devices, and plaintext local-store errors.

## Automated evidence

- `swift test`: 39 tests executed, 0 failures. Coverage includes pose geometry and transforms, confidence/framing/centering rules, smoothing, thermal degradation and mask-freshness policies, both rep engines, invalid/fast/partial/missing/multiple-person paths, nine normalized pose fixtures, session pause/summary behavior, Core Data round trips/upserts/reopen, and persistent Wide-camera preference behavior.
- `RepDuoTests` Debug test bundle: compiled and linked successfully for the iOS Simulator SDK, including four iOS-only Watch/audio-route mapping tests.
- `RepDuoUITests`: seven flows compile and link, including both exercise routes, pause/finish-cancel behavior, denied-camera Settings recovery, accessibility text-size navigation, landscape Gear Check layout, and Wide-camera control switching.
- App target: Debug builds compile and link for the generic iOS Simulator destination with asset-catalog compilation enabled; the complete Debug test products also build successfully.
- Xcode static analysis: succeeded with no application-source diagnostic.
- `PrivacyInfo.xcprivacy` and `Info.plist`: plist validation succeeded.

## Validation still requiring an external environment

- Boot an installed iPhone Simulator and execute the newly expanded unit/UI suite. The iOS 26.5 runtime is installed, but no Simulator was booted during the Wide-camera implementation pass.
- On physical iPhones, verify camera orientation and mirroring, Vision/Metal alignment, setup framing, MPS glow appearance, mask latency, and interruption/background/audio-route recovery.
- On an iPhone 17, iPhone Air, or iPhone 17 Pro, verify that `WIDE` selects the front `.builtInUltraWideCamera`, logs the expected field of view, keeps the full body visible, and remains aligned with Vision and Metal overlays; verify `1×` switching and fallback on a device without that camera.
- Establish the release accuracy threshold and run the agreed recorded/video test corpus across body types, camera placements, lighting, occlusion, and motion speeds. The bundled normalized-keypoint corpus is a regression baseline, not a release accuracy certification.
- Measure a 10-minute workout with Instruments on minimum, mainstream, and high-end target devices: preview FPS, P95 render time, end-to-end outline latency, CPU/GPU, memory/leaks, energy, and thermal degradation.
- Compare device screenshots with the approved Penpot boards and complete VoiceOver/high-contrast QA.
- Resolve the currently blocked `design-qa.md` by capturing matching app states and iterating until it records `final result: passed`.
- Replace the privacy-policy placeholders with the publisher's legal name, jurisdiction, support contact, and public HTTPS URL; then complete App Store Connect App Privacy answers.

## Deferred P1

- watchOS companion target, live heart rate, Watch battery transport, HealthKit workout save/mirroring, and Watch-enriched summaries.
- Individual calibration, manual rep correction, and richer coaching/trends.

See `ACCEPTANCE_MATRIX.md` for requirement-by-requirement status and evidence.
