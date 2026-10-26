# Data rights and safety gate

The model and reference bank are packaged for internal research integration. This package is not, by itself, cleared for public redistribution or clinical deployment.

## Reference-image distribution

- SurgWound is reported as CC BY-SA 4.0.
- LUTSeg is reported as CC BY 4.0.
- DFUTissue and ComplexWoundDB did not have an explicit dataset redistribution license in the reviewed local/public repository material.
- SCIN remains governed by its source data-use terms.
- Local/expert-curated images require confirmation that the project has permission to redistribute them inside a public application.

Before an App Store build, generate a reference-image allowlist containing only records whose redistribution terms have been reviewed. The CNN model can be integrated without bundling the reference bank; retrieval/VLM functionality can remain disabled until this review is complete.

## Clinical interpretation

- Wound classification is an image-model prediction, not a diagnosis.
- The inflammation output is a high-sensitivity screening signal and is not equivalent to confirmed infection or cellulitis.
- Tissue outputs indicate predicted visual presence and do not replace wound assessment.
- `normal_control` means no open wound is visible; benign or non-open lesions may still be present.
- Top-two VLM output is candidate coverage, not probability or calibrated confidence.

No treatment recommendation should be produced from these outputs alone. The application should support uncertainty, escalation, and clinician review.

