# WoundCorder analysis workflow

All home photo entry points use named patient intake and the body map before analysis. Patient details are optional except name. Health answers start as unknown. Patient language is plain; professional mode uses clinical terms.

Photo Check / Image-Only Analysis runs the bundled CNN. Photo + Health Context / Image + Clinical Context runs the CNN and a local vision-language model. The latter always receives CNN observations, optional age and BMI (height in cm, weight in kg), duration, health answers, and wound location. Names and record IDs are not included in inference prompts.

CNN results show one type when the top probability is at least 50%, otherwise two. Combined results show two. Tissue and wound education are shared by both modes, with role-specific descriptions adapted from the supplied documents. Source documents are preserved in WoundEducation. Normal-control and surgical-wound fallback descriptions are explicitly authored additions because the references omit these model labels.

Photos are only sent through an explicit email composer addressed to info@woundcorder.ai. The user chooses one of four disclosure levels and reviews the body and attachment. Image metadata is stripped during attachment creation. This does not automatically send email.

The supplied WoundCorder_iOS_Integration_v1.zip contains 994 reference images, including 360 classification records. All 1030 package checksums were verified. ReferenceData contains two source-labeled examples for each of the nine classes, with source attribution and checksums. The owner confirmed on October 12, 2026 that the ZIP images are cleared for the final product. All configurations now bundle the 18 selected examples with attribution intact; see ReferenceData/DistributionApproval.txt. Examples are matched by source label, not relabeled by the CNN. Clinical review of example representativeness remains separate from the owner’s distribution permission.

Photo checks save the actual image, role-specific results, model comments, intake, demographics, and optional real measurements in protected, backup-excluded files. They do not create zero-valued LiDAR measurements. The result screen and saved result screen share the same education and explicit email controls. Model comments must pass a constrained JSON schema; malformed output falls back to CNN results.

Size-index groups describe the existing measurement heuristic and must not be interpreted as medical urgency.

Physical-device camera, LiDAR, memory pressure, model generation, and email sending require device verification. A simulator build is not a clinical validation.

Patient and measurement indexes now migrate from legacy preferences to separate versioned, atomic, protected files, excluded from device backups. Migration removes a legacy key only after the replacement is verified. Unreadable data is kept, writes are blocked, and recovery is explicit. The older measurement calculator is archived outside the app target. All active scan commands/status updates have per-session scopes; photo capture uses a separate AVCaptureSession and never automatically writes to Photos.
