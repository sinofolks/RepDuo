# Harmonization attempts — not selected

User authorized correcting inconsistent contours while preserving the approved design (2026-09-13, “确认”). Two built-in imagegen edits used the original approved turnaround as their sole visual input. No model image was supplied. Original reference and all locked scoring protocols are unchanged.

| Candidate | Front/back mirror IoU | Best read-only translation IoU | Front silhouette retained vs original |
|---|---:|---:|---:|
| Original approved | 90.8708% | 91.7602% | 100% |
| v2 harmonize | 90.5738% | 91.5665% | 97.7524% |
| v2b back-only request | 92.1779% | 93.2217% | 98.1457% |

These percentages are silhouette mask overlap, NOT overall model quality. The translation search is a sensitivity diagnostic and is not applied to a scorer or reference. Neither candidate sufficiently resolves the requested strict orthographic consistency. Both remain unselected, with no new reference locks or protocol scores. V2b improves overlap but still retains different hip/leg/foot contours and slightly changes the front despite the preservation instruction.

The two prompts are `turnaround-v2-harmonize-prompt.txt` and `turnaround-v2b-harmonize-prompt.txt`. Images are sibling `green-body-turnaround-v2-harmonize-candidate.png` and `green-body-turnaround-v2b-harmonize-candidate.png`. Full read-only audits are `../calibration/turnaround-v2-candidate-audit.json` and `../calibration/turnaround-v2b-candidate-audit.json`.

Proposed deterministic next method: preserve original front and side pixels; use original front mirrored silhouette as the explicit authoritative back boundary; remap the old back interior separately, while checking all limb gaps and toes. This is an authored contour harmonization, not measured geometry and not a reason to claim99. Requires explicit user agreement to programmatic image editing instead of imagegen before execution under the image editing tool policy. No such raster editing has been performed. Do not silently choose one generated candidate or substitute the current Blender model as reference.
