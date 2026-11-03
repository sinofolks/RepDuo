# RepDuo App Privacy declaration draft

This file records the intended P0 App Store privacy answers. Reconfirm every answer against the archive before submission.

## Data collection

- Tracking: No.
- Data linked to the user: None.
- Data used to track the user: None.
- Camera frames: processed ephemerally on the iPhone; not recorded, retained, uploaded, or shared.
- Pose points and person masks: processed ephemerally; not retained or uploaded.
- Workout summaries: stored locally in Core Data and not transmitted by P0.
- Preferences: stored locally in the app's own UserDefaults domain.
- Analytics, advertising, crash-reporting, accounts, and cloud SDKs: none in P0.

## Permissions

- Camera is required for live counting. The pre-permission screen explains why before the system prompt.
- Microphone is not requested.
- HealthKit is not linked by the P0 target and is not requested. It remains a P1 feature.

## Required-reason APIs

`PrivacyInfo.xcprivacy` declares:

- `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`, because preferences are accessible only to RepDuo itself.
- `NSPrivacyAccessedAPICategorySystemBootTime` with reason `35F9.1`, because monotonic elapsed time drives workout duration, cooldowns, mask expiry, throttling, and performance measurements.

## Submission audit

- Generate and inspect Xcode's privacy report from the Release archive.
- Confirm the built app contains `PrivacyInfo.xcprivacy`.
- Confirm no dependency or newly added endpoint changes these answers.
- Publish the privacy policy at a stable HTTPS URL and insert the publisher's legal name and support contact before App Store submission.
