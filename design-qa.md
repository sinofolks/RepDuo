# RepDuo AI Coach — Design QA

- Source visual truth: `/Users/aaronphy/.codex/generated_images/01a021e8-56a2-7980-96aa-a1993ad2cfa1/exec-ecd339c8-6935-4dd5-9ab8-a92d1673956d.png`
- Final implementation capture: `/var/folders/83/qkqt7zgs28x11vrzrl7fg5v00000gn/T/screenshot_optimized_a5616c8c-c5e3-4efe-92fa-da7f3151aa0d.jpg`
- Full-view normalized comparison: `/Users/aaronphy/Documents/ChatGPT/RepDuo/design-qa-comparison.png`
- Focused count/coach comparison: `/Users/aaronphy/Documents/ChatGPT/RepDuo/design-qa-focused.png`
- Viewport: iPhone 17 Pro simulator, portrait, 368 × 800 pt capture
- Pixels and normalization: source 852 × 1846 px; implementation 368 × 800 px. Source was downsampled to 368 × 800 px for equal-size comparison. This is a native UIKit capture, so CSS size and browser device scale factor do not apply.
- State: Simplified Chinese, push-up workout, three reliable repetitions learned, AI score visible, tracking locked, active set.

## Findings

No actionable P0, P1, or P2 mismatch remains.

- Fonts and typography: Native system black/bold weights preserve the source hierarchy. The rep count, narrow score rail, metric labels, advice, and actions remain legible at the target viewport. Dynamic workout copy may wrap to two lines, which is intentional.
- Spacing and layout rhythm: The count remains left-aligned, the narrow coach rail docks to the right edge, the subject stays visually central, and advice/actions anchor to the bottom. Persistent controls remain accessible in portrait and landscape.
- Colors and visual tokens: The implementation uses the selected deep black stage (`#101317`), warm white, muted gray, neon lime, amber warning, and subtle dark surfaces from the existing RepDuo token set.
- Image quality and asset fidelity: The simulator demo retains a high-resolution photographic subject and neon edge. The real camera renderer uses Vision person segmentation to replace the room with black; if the mask is lost, the person fades into black instead of revealing the room. The simulator demo can retain faint staged floor texture, an expected fallback-image difference rather than live-camera behavior.
- Copy and content: The source's count, form score, range, tempo, symmetry, primary advice, pause, and finish-set content are all represented. The implementation additionally shows tracking state and learning/personalization status because those are functional product states.

## Comparison history

### Iteration 1 — blocked

- P1: The always-on debug metrics panel covered the AI score header and made the coach rail unreadable.
- P2: A visible navigation/status-bar gap shifted all above-the-fold content downward.
- P2: The coach rail floated too far from the right edge and was materially wider than the selected design.
- P2: Negative stack spacing caused the rep caption and phase to overlap.
- Evidence: `/var/folders/83/qkqt7zgs28x11vrzrl7fg5v00000gn/T/screenshot_optimized_e22d2ff9-e633-4ba5-8021-c1772c8f49a2.jpg`

Fixes made:

- Debug metrics now appear only with the explicit `-showDebugMetrics` launch argument.
- Workout mode hides navigation and status chrome for an immersive stage.
- The rail was narrowed and docked partially beyond the right safe edge.
- Rep caption/phase spacing and portrait count sizing were corrected.
- Advice was centered and secondary actions received subtle filled surfaces; finish remains neon-accented.

### Iteration 2 — passed

- Post-fix evidence: `/var/folders/83/qkqt7zgs28x11vrzrl7fg5v00000gn/T/screenshot_optimized_a5616c8c-c5e3-4efe-92fa-da7f3151aa0d.jpg`
- Full and focused normalized comparisons show no remaining actionable P0/P1/P2 drift.

## Interaction and responsive checks

- Push-up route reaches workout, produces a scored rep, finishes the set, and exposes the AI summary card.
- Landscape UI test verifies the coach rail, pause action, and finish action remain present and hittable.
- Unit coverage verifies baseline learning, low-confidence no-score behavior, repeated-error voice gating, fatigue detection, persistence, and workout summary integration.

## Follow-up polish

- P3: Validate the live segmentation boundary on a range of hair, loose clothing, and low-light backgrounds on physical devices; simulator evidence cannot fully represent camera-mask quality.

final result: passed
