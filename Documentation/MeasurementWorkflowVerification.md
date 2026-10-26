# Measurement and detection verification

Verified on October 6, 2026 using the active scanner's production geometry helpers, analytic fixtures, prompt tests, and an Xcode simulator build. This is software verification, not a measurement-accuracy or clinical-validation study.

## Reproduced defects and corrections

| Finding | Correction |
| --- | --- |
| Manual loft volume depended on the wound's location relative to the AR origin. A 2 × 2 × 0.5 cm box gave 3.206478 cm³ at offset (3, −2, 4) m and 310.24334 cm³ at (10, 10, 10) m, instead of 2 cm³. | Recenter both contours before resampling and calculate signed volumes using Double accumulation. The same examples now give 2.000042 and 2.000137 cm³. |
| Near-collinear outlines passed a check that measured the length of a normalized normal instead of actual area. | Validate finite coordinates and unnormalized area relative to perimeter; reject collapsed contours. Require cap triangulation to cover the whole cap before accepting a loft volume. |
| Independent majorities for area and volume could report consensus even when only one observation supported both values. | Require a majority of the same observations to support both area and volume, while retaining existing quality and dispersion limits. |
| Detection freshness used inference completion time, and repeated sensor frames could be counted again. | Use the ARFrame sensor timestamp, reject stale/duplicate/out-of-order frames, recheck freshness and tracking at completion, and prevent repeated depth-frame accumulation. Existing scan-generation checks still discard results from earlier scans. |
| A legacy metrics callback averaged rim and bottom areas/perimeters, disagreeing with preview and final measurements. | Keep rim area and perimeter as the definitions in all active callbacks. Bottom geometry affects volume. |
| Finalization cleared the estimator's preliminary flag, and UI depth looked like a direct depth measurement. | Preserve the estimator's preliminary status and label volume/area as estimated mean depth. Missing depth is unavailable rather than zero. |

The geometric math and temporal consistency logic now live in `WoundGeometry.swift` and `WoundMeasurementConsistency.swift`, used by the actual scanner and the regression fixtures. The unused LiDARVolumeCalculator has now been archived outside the app target; no active scanner references it.

## Automated checks

294 checks cover:

- Metric conversions for a square prism, a tapered square frustum, and a concave L-shaped prism.
- Translation and rotation, clockwise/counterclockwise winding, different trace starting points, and different sample densities.
- Invalid, nonfinite, repeated, and nearly collinear contour points.
- Agreement, single-frame rejection, low-quality samples, outliers, area-only samples, and conflicting area/volume majorities.
- Fresh, stale, duplicate, future, and out-of-order sensor timestamps, including results that became stale during inference.

The translated/rotated prism fixtures use a 0.1% numerical tolerance. This tolerance concerns arithmetic applied to synthetic coordinates, not LiDAR sensor accuracy.

Run the regression checks from the repository root:

```sh
swiftc 'LiDARDepth/Model/Code/Codes/WoundGeometry.swift' \
  'LiDARDepth/Model/Code/Codes/WoundMeasurementConsistency.swift' \
  'LiDARDepth/Model/Code/Codes/WoundDetectionFrameGate.swift' \
  Tests/WoundMeasurementRegressionTests.swift -o /tmp/woundcorder-regression-tests
/tmp/woundcorder-regression-tests
```

The measurement-to-AI prompt tests also pass. The simulator Debug build includes both arm64 and x86_64; the existing device-only MNN linker flag is omitted for this simulator check.

## Detection limitation and remaining device checks

The bundled `WoundSegmentation` asset is identified by the existing loader as an all-zero placeholder. Automatic boundary detection therefore uses the RGB/depth heuristic fallback. The newly added `WoundSemantic` CNN classifies photos and does not supply a segmentation mask. No labeled segmentation dataset or recorded ARFrame fixtures are present here, so boundary accuracy, false detection rate, and clinical classification accuracy are not established by these tests.

On a LiDAR iPhone/iPad, the next verification should use known-dimension wound phantoms and record:

1. Ground-truth area/volume and repeated automatic/manual results, including bias and variation across repeats.
2. Results after moving the target or restarting the AR session; vary camera angle, distance, lighting, and boundary contrast while keeping phantom dimensions fixed.
3. Boundary mapping → confirmation → multi-view capture → finalization. Confirm that insufficient coverage or tracking loss prevents an accepted result.
4. Interruptions, rapid re-scan, manual correction/undo, and return from AI analysis. Confirm no old outline or measurement replaces the current scan.
5. The exact area/perimeter/volume, units, location, source, and preliminary flag at finalization, in the AI prompt, and when saved. Test the library-photo choice both with and without attached measurements.

No hardware-specific accuracy, latency, or end-to-end camera claim is made until those checks are run.

## October 12 refinement pass

- Migrated patient and measurement indexes into separate protected, versioned files with atomic writes, verified legacy migration, optimistic stale-writer rejection, and explicit prior-copy recovery. Save success follows disk success. Unlinked legacy measurements remain in history and are never associated by name.
- Added per-capture notification scope to commands and status events. The compatibility measurement route is history-only; photo capture uses AVCaptureSession rather than a second AR mesh session. It no longer automatically writes wound images into Photos.
- Removed the unreachable, duplicate Vision segmentation route. Hidden/shut-down scans reject late inference and manual/automatic active scans stop on interruption. Same-frame sceneDepth is requested and preferred over smoothed depth.
- Corrected ARKit confidence semantics: 0 is low, 1 medium, 2 high. All-low/missing/invalid confidence no longer becomes perfect confidence or geometry support. Low-confidence pixels are excluded from measurement samples.
- Segmentation mask decoding honors strides, rejects nonfinite/ambiguous outputs, and applies a consistent explicitly named logits/probability interpretation.
- Saved measurements retain their source, quality, and preliminary flag. Missing depth still is not interpreted as proof of a shallow wound.
- Direct 224-pixel sRGB preprocessing removes a full-resolution image copy and preserves orientation, mirroring, aspect ratio, and neutral letterboxing. Numeric postprocessing rejects invalid data and avoids overflow.

Run Tests/run-review-checks.sh for the Foundation/CoreML regression suites. Debug Simulator launch argument --review-results runs actual store migrations, failure/recovery checks, pixel-level orientation/letterbox assertions, privacy checks, and production CNN inference on nine bundled reference images. These tests verify software behavior and output validity, not diagnostic or sensor accuracy.


## Compact capture flow

- In both modes, Home → Check a wound collects intake and then opens LiDAR on supported devices. Devices without scene depth use photo analysis after intake.
- Device is informational; the default scan entry point is Home. The separate Check photo shortcut remains available.
- The scanner shows a compact instruction, scan controls, and Skip to AI. Finalized measurements open under Results & save instead of covering the live preview.
- Camera options includes Restart camera. AR rendering is explicitly enabled, backgrounding pauses the session, foregrounding restarts it, and a first-frame timeout explains recovery options.
- Device verification still required: first camera permission, live LiDAR preview, background/foreground, restart, manual tracing, results/save, and LiDAR → AI → back. A build cannot verify physical camera output.

## Wound boundary visibility and acquisition tolerance

- Mapping confirmation now permits 5–10 mm boundary variation (scaled to wound radius), versus 3–7 mm for post-confirmation tracking. Center, normal, area, and boundary-distance checks remain active; acquisition still requires multiple accepted observations and explicit user confirmation.
- Stability compares the prior world-space contour reprojected into the current view, avoiding false instability from phone movement alone. Normal depth confidence, stale-frame rejection, capture coverage, and final measurement consensus are unchanged.
- The live outline has a dark 7-point halo, a 3.5-point colored edge, and 20% fill. Amber dashed means candidate; green solid means associated wound. Candidate highlights expire with the existing frame freshness window.
- On-device verification: compare slight hand movement against abrupt jumps or a neighboring wound, inspect outline visibility against different skin tones, confirm/remap the highlighted boundary, and complete the scan. These tolerance changes are not a validation of measurement accuracy.

## Boundary review after a matched pair

The green matched contour now reaches review after two associated observations, without the extra four-observation/screen-stability gate. Review still requires fresh evidence from this scan, normal AR tracking, visible geometry, and a valid 3D contour. The user must confirm the boundary before point capture. Mapping allows up to 20 seconds; missing usable geometry still fails rather than producing measurements. Final depth, coverage, and consensus requirements are unchanged. WoundBoundaryReviewPolicyTests covers review eligibility and rejects single, stale, previous-scan, future, and invalid evidence. Physical-device verification remains required.

## AI camera orientation

The photo camera uses AVCaptureDevice.RotationCoordinator with its actual rear camera and preview layer. Preview rotation follows observed preview angles; each shutter press snapshots the separate capture angle. Rotation is reapplied after camera configuration and layout. Rear-camera mirroring is explicitly disabled for both preview and output, and rotation observation is invalidated at shutdown.

Device check: on iPad, open AI capture in both landscape directions, portrait, and upside-down portrait; rotate while open; take a photo containing readable text and compare preview, result, and saved photo. Repeat after returning from background and from LiDAR. Live orientation cannot be verified by an unsigned build.

## Completed measurement handoff

Completed scans show area, volume, and estimated mean depth inline, with Details & save and Measure again. A finalized valid measurement enables Continue to AI with measurements and is copied into the existing frozen analysis context. The AI camera repeats attached area and volume; analysis results retain the attached-measurements section. During finalization, advancing to AI is disabled. A completed scan that fails readiness shows provisional values and explicitly offers AI without measurements, preserving the existing quality gate. Saving also offers Continue to AI with measurements.

## Stage-two convergence and measurement handoff (supersedes timed capture)

- Removed the 18-second forced finish and automatic timer completion. The user finishes after coverage and convergence pass; incomplete captures stay in stage two with guidance.
- Require 75% of expected wound cells to have agreeing measurements from multiple viewpoints, at least four camera viewpoints, 32 surrounding-skin samples, and ten seconds of capture.
- Each per-view cell needs repeated observations. Across views, retain a strict majority within 3.5 mm of the median; do not widen tolerance when disagreement grows. Only supported cells feed the measured cloud and its displayed points.
- After coverage passes, calculate estimates at least 1.5 seconds apart using new accepted depth frames. The last three must agree within 5% for area/perimeter and 12% for volume (0.03 cm³ absolute floor). Missing/low-quality estimates or stale frames clear convergence. These engineering thresholds require physical-device validation.
- Finish freezes the median of the accepted estimates and emits measurementReady=true from that same operation. It does not recompute from the final camera pose or mix in mapping-stage estimates. SwiftUI freezes one WoundAnalysisContext for display, saving, and AI attachment until a new scan begins.
- Tests cover coverage/view/time thresholds, value jumps, malformed input, unsupported single-view cells, conflicting surfaces, and outlier rejection. Validate on a physical LiDAR device with known geometry and repeated captures before claiming accuracy or repeatability across scans.

## Capture efficiency

The minimum stage-two duration is now six seconds (previously ten); convergence estimates are spaced at least 0.75 seconds apart (previously 1.5) and still require new accepted depth frames. The capture timer runs every 0.35 seconds and depth accumulation is limited to every 0.25 seconds. The 75% verified coverage, four viewpoints, repeated per-view observations, strict point agreement, three converged estimates, and frozen handoff remain unchanged.

Coverage, cloud rendering, and measurement reuse sorted surface-cell summaries for the same boundary/normal. The bounded cache is cleared whenever new cell observations arrive or capture resets; rim data and elapsed-time eligibility remain evaluated live. Regression tests pass, but scan duration and frame rate must be measured on a physical device; no real-device speedup is claimed from compilation alone.

## Coverage plateau correction

Coverage now uses a WoundCoverageGrid frozen when the boundary is confirmed. Cell size is chosen from wound area and the actual depth-pixel footprint (bounded to 2.5–6 mm). Its denominator is the set of cell centers inside the wound polygon; only those cells can contribute observations. Repeated samples of one cell cannot increase the percentage. Sensor-aware grouping lets slight lateral variation across views match the same patch without relaxing depth agreement or convergence.

Cell summaries now decode stored coordinates using the original confirmed boundary origin, including when called with a resampled boundary. Previously a different origin could shift the decoded points. Feedback distinguishes seen cells from multi-view verified cells and requests a brief pause at each new angle when overlap is the limiting factor.

WoundCoverageGridTests reproduces sparse samples reaching less than 40% against the old fine-grid denominator while correctly covering the frozen sensor-scale grid. It also tests small cross-view shifts, repeated-patch noninflation, fixed denominators, out-of-wound points, and invalid inputs. Physical-device verification remains necessary; the simulation does not establish clinical accuracy or guarantee the user's exact failure is reproduced.

## Preserve verified coverage through transient noise

Verified cells now retain their accepted 3D point and supporting evidence across later angles. An isolated outlier or a changing rolling per-view median no longer deletes an established cell. Three consecutive conflicting depth observations spanning at least two viewpoints invalidate a verified cell; it remains excluded until a new scan/remap, rather than immediately being restored by old aggregate samples. An agreeing observation resets the conflict streak. Invalidated-cell guidance explains drops and suggests remapping if progress stalls.

Coverage and measurement consume the same retained, noninvalidated points, not a peak percentage. Capture resets clear both points and conflict evidence. Cross-view dispersion is calculated from the accepted inliers rather than including rejected observations. Tests cover isolated noise, single-view bias, sustained multi-view conflict, invalid data, and reset behavior. Physical-device testing is still needed to assess real scan behavior and repeatability.

## Zero-verified-coverage recovery

Verification now permits one coherent observation per angle before the existing cross-angle agreement check. Two different view bins still must agree; repeated frames from one angle cannot substitute. This removes the redundant two-frames-per-view barrier during a moving sweep. Rejected cells discard all of their old per-view observations and can be verified again from fresh cross-view evidence; they are no longer permanently excluded until remap. Cleanup addresses the bounded viewpoint keys directly to avoid scanning the entire cell dictionary for each rejected patch.

Guidance prioritizes the actual angle count before suggesting pauses. Regression tests include a moving-sweep pair, incoherent within-view observations, single-view rejection, and the existing conflict/coverage/convergence checks. These tests do not reproduce device AR sessions; actual iPad capture still requires verification.


## Faster capture target (2026-10-18)

The post-confirmation capture targets 5–10 seconds when depth and tracking are good. It requires three distinct views (the existing seven-degree separation), 75% verified coverage, and 32 rim points. Two-view cell consensus, outlier rejection, fresh frames, and explicit Finish remain required.

Convergence now starts once spatial evidence is sufficient, concurrently with the five-second minimum capture duration. Three estimates, spaced at least 0.5 seconds apart and based on newly accepted frames, must agree within 7.5% for area/perimeter and 10% for volume (the existing 0.03 cm³ absolute floor remains for near-zero volume). Capture polling is 0.25 seconds and depth accumulation is throttled to 0.20 seconds. No timeout forces acceptance of incomplete data.

These are within-scan engineering agreement thresholds, not a guarantee of 5–10% accuracy or repeatability between scans. Device validation must time both boundary mapping and post-confirmation capture, repeat scans of the same target, and check poor tracking/coverage still blocks completion. The 5–10 second target excludes manual boundary-review time.

## Camera startup (2026-10-18)

The AR session now starts from viewIsAppearing once the view is attached, permission is granted, and the app is active, overlapping the presentation animation. viewDidAppear remains a fallback. The first configuration enables scene depth without plane detection or room reconstruction; the full configuration is applied 0.25 seconds after a fresh camera frame without resetting tracking or anchors. Image-processing resources are lazy and the overlay display link starts after the first frame.

Deferred mapping is cancelled on dismissal, shutdown, backgrounding, restart, and full reset. First-frame callbacks require the visible, running controller and a timestamp from the current run. Debug builds log time to the first AR frame. Device checks: cold open, repeated open/close, first permission grant, background/foreground, interruption, manual restart, then complete a measured scan. Build verification cannot establish actual camera latency or confirm displayed-frame timing.

## Supplied education templates and intake/share changes (2026-10-19)

Imported the supplied patient and clinician Hostinger ZIP clinical-content.js data into separate bundled JSON resources, retaining source wording and references. Each mode uses its own guide and photo assets. All nine model wound classes and eight semantic outputs have matching template entries. Extra template categories remain data only and are not invented as model predictions. The archives contain wound photos, not tissue-specific photos. Existing reference images remain available as fallback. Clinician results also include the template's universal triage review.

Removed the optional What happened intake step and its context/duration review rows. Existing stored intake fields remain compatible. The Share with WoundCorder demographic body excludes the structured patient name; mail still comes from the user's configured email account, and photos/free text are not claimed to be anonymous.

Content verification: decode both JSON resources with the actual Swift model; run Tests/WoundTemplateEducationChecks.py for supported labels, images, and reference indices. These checks verify integration, not independent clinical review of the supplied content.

## Separate measurement choices (2026-10-21)

The LiDAR controls expose Auto Detect and Trace Manually as separate actions. Manual tracing starts with a blank outline rather than silently accepting a detected seed; the existing guided rim/depth tracing and validation remain. Users may switch an unfinished automatic scan to manual, or switch manual tracing back to automatic. Existing reset logic cancels timers, invalidates segmentation work, and clears previous measurement state. Switching is blocked during automatic finalization.

Automatic boundary matching and post-confirmation capture policy are unchanged: three viewpoints, 75% verified coverage, fresh independent frames, five-second minimum capture, and three converged estimates. The 5–10 second capture target and engineering tolerances still require device validation; they are not an accuracy guarantee.

## Coverage stall and point-cloud display (2026-10-21)

Reduced required verified coverage from 75% to 65% and viewpoint separation from seven to five degrees to allow a smaller centered sweep. Still requires three viewpoints, two agreeing views per verified cell, 32 rim points, five seconds, fresh frames, and three converged measurement estimates. Guidance reads its target from the policy rather than hardcoded percentages. High confidence retains its stricter coverage/view criteria.

During confirmed capture, the point display now uses only anchored verified cell summaries. It no longer falls back to raw points while verification is sparse, avoiding a visible change between two different clouds. Rejected cells may still disappear and real AR tracking drift is not corrected or hidden by this display change. The frozen grid and measurement coordinates remain unchanged. Lower coverage trades spatial completeness for shorter capture; repeatability and latency must be checked on a physical LiDAR device with repeated scans, including motion and poor tracking.

## Retaining coverage and cold camera recovery (2026-10-21)

Coverage now requires 60%. Previously, three off-target samples crossing two view bins invalidated a verified cell even when the conflicting depths disagreed. Invalidation now requires three coherent samples in each of two distinct views, both supporting the same side/depth of a replacement surface. An agreeing revisit clears pending conflicts. Missing/unseen patches remain verified; sustained coherent disagreement still removes a patch and requires fresh verification. Regression tests cover noisy opposing depths, an angle-bin crossing, agreeing revisits, and true multi-view conflicts. Final convergence tolerances remain unchanged.

Camera startup returns to viewDidAppear and uses one complete configuration rather than reconfiguring immediately after its first frame. Session run/pause calls are serialized on a dedicated queue so teardown does not synchronously block the UI. A cold-start error or first-frame timeout receives one automatic retry; permission and lifecycle guards remain. Manual restart renews that retry budget. Device validation remains required for cold launch, permission grant, rapid open/close, backgrounding, and first-start failures. These changes address identified failure paths; they are not device-verified latency or repeatability claims.

## Workflow completion, wound series, appearance, and combined analysis (2026-10-25)

Closing/saving a photo result persists its photo, intake, CNN output, optional VLM comments, and the attached measurement snapshot before returning to Home. The camera X also saves available results and finalized measurements. A save failure keeps the workflow open. A stable record ID makes retries idempotent. The LiDAR parent saves its finalized measurement to the measurement log on completion. Results cannot be swipe-dismissed past saving.

Photo records carry an optional wound-series UUID for backward-compatible decoding. Users explicitly choose a new wound or an existing series matching the patient, body part, and side. The Progress tab shows overall dated check-in counts or per-wound area/volume bars with dated detail links; missing measurements are not plotted as zero. Old ungrouped records stay independent rather than being silently merged.

The existing CNN -> image/VLM + structured health-context pipeline is selected once by default on capable devices. The downloaded model remains required; the UI offers AI Options when absent, and failures explicitly show CNN-only results. User model selection remains available. No new model training or model installation is claimed.

Appearance scoring now weights color/discoloration at 76%, local contrast at 16%, supported depth at at most 4%, and centering at 4%, with a minimum appearance gate. The new pure-policy tests reject depth-only normal-skin selection and bound depth's influence. Real images across skin tones, lighting, and distances still require device validation. Volume capture can finish after four seconds, with three fresh estimates spaced at least 0.35 seconds apart and 10% area/perimeter/volume agreement (existing near-zero-volume absolute floor retained). Spatial coverage and point consensus gates remain.

Checks: review regression suite and appearance-policy tests; iOS build. Added UI-harness cases for idempotent saves, series persistence, and name-free sharing; those harness cases require running the app and are not counted as executed by the standalone suite.

## Explicit unable-to-determine result

Low-confidence CNN classifications now withhold wound/tissue cards and skip VLM inference instead of presenting weak candidate labels. An adequate photo with an uncertain classification shows an explicit Unable to determine card; inadequate photos retain the retake-photo flow. VLM JSON now requires assessment = possible_matches or unable_to_determine for new inference. Abstention requires an empty candidate list; a possible-match response still requires two distinct permitted CNN labels. Unknown or contradictory statuses fail validation and use the existing explicitly identified CNN-only fallback.

The result view and shared text check the combined outcome, and saved records preserve VLM abstention through the existing comments JSON. Older saved comments without assessment remain readable. Generic abstention text replaces VLM prose for an unsure outcome, so prose cannot reintroduce candidate labels. Existing measurement snapshots remain available.

Validation: standalone parser tests cover abstention, legacy responses, contradictory candidate lists, and invalid statuses. UI harness assertions cover withheld CNN labels and shared combined outcomes; physical-device VLM behavior and UI harness execution remain separate checks.

## User-added vision models

AI Options now exposes Add model from Files with a folder picker. Supports a single unsplit GGUF plus its matching mmproj GGUF, or a flat MNN vision-model folder with required config/tokenizer/vision/model files. Custom GGUF filenames are persisted in optional descriptor fields and used during inference; older descriptors keep their existing fallback filenames. Imported models appear in the existing selector and can be removed.

Imports run file copying and SHA-256 checks off the UI thread, retain security-scoped access until completion, exclude model storage from backup, clean up partial destinations on failure, and prevent simultaneous transfers. Folder checks reject symbolic links, nested folders, empty files, oversized imports, incomplete model pairs, bad GGUF magic, and MNN JSON referring outside local relative paths. Selection does not imply a model's architecture or vision projector is compatible: the installed runtime determines compatibility when loaded. The trained CNN and structured-response/uncertainty validation remain unchanged.

Validation: WoundModelImportValidationTests tests pairs, missing projectors, invalid headers, symlinks, MNN required files, and parent-directory references. Device runtime tests with real imported model weights remain required.

## English, Spanish and French (2026-10-25)

Settings now has a persisted in-app language picker (English / Español / Français). The app changes presentation language without recreating the root view or camera session. SwiftUI screens observe the preference; date presentation uses the selected locale. Stored enum values, record IDs, measurement values, model class keys and inference metadata remain stable. Height and weight accept decimal commas or periods and reject mixed separators.

The bundled translation catalog covers patient and professional navigation, intake, photo capture, AI model management, LiDAR instructions/status/measurement controls, saved-record labels, reference search and wound/tissue education. All 230 distinct education strings from the supplied templates and fallback library have Spanish and French translations; photographs and source references are retained. New VLM requests ask for prose in the selected language while preserving the English JSON schema and class keys. Model compliance with that instruction depends on the selected model and has not been clinically validated. User-authored notes, names, record titles and already-saved AI prose keep their original language. iOS-owned permission dialogs and external pages follow their own/system language settings; localized app permission descriptions are bundled for Spanish and French.

Validation:
- `Tests/run-review-checks.sh`: existing geometry, coverage, storage, workflow and model-response tests plus localization tests. Localization validates catalog parity, placeholder preservation, LiDAR progress templates, measurement units, names, multiline messages and English fallback.
- `Tests/WoundLocalizationCoverageTests.py`: every education paragraph and directly localized literal UI string has both translations (proper names/units explicitly exempted).
- Debug-only `--review-languages` harness: switches en → es → fr → en across settings, scan controls, health checklist, patient education and clinician education; asserts draft and view identity survive. Captures 16 screenshots including French accessibility text in Documents/LanguageReview. Executed on iPhone 17 Pro and iPad Pro 11-inch (M4), iOS 26 simulators. These are UI fixtures using production views, not a physical LiDAR capture or an end-to-end inference test.
- Visual review caught cramped side-by-side scan buttons at accessibility text sizes. Those controls now stack vertically; standard text retains the compact horizontal layout. Labels can grow vertically instead of using a fixed button height.

Manual device follow-up: change languages from Settings, run auto and manual measurement, verify the camera remains responsive, save a record, reopen it and inspect its measurements. Test the selected VLM's Spanish/French output on supported hardware. Simulators cannot verify actual LiDAR acquisition or model runtime quality.
