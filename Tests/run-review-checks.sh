#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
review_build_dir=$(mktemp -d /tmp/woundcorder-tests.XXXXXX)
trap 'rm -rf "$review_build_dir"' EXIT
compile_run() {
    local name=$1
    shift
    swiftc -module-cache-path /tmp/woundcorder-swift-cache "$@" -o "$review_build_dir/$name"
    "$review_build_dir/$name"
}
source_root=LiDARDepth/Model/Code/Codes
compile_run records "$source_root/WoundRecordFile.swift" Tests/WoundRecordFileTests.swift
compile_run sensors "$source_root/WoundDepthValidation.swift" "$source_root/WoundSemantic/WoundMaskDecoder.swift" Tests/WoundSensorPolicyTests.swift
compile_run semantic "$source_root/WoundSemantic/WoundSemanticMath.swift" Tests/WoundSemanticMathTests.swift
compile_run geometry "$source_root/WoundGeometry.swift" "$source_root/WoundMeasurementConsistency.swift" "$source_root/WoundDetectionFrameGate.swift" Tests/WoundMeasurementRegressionTests.swift
compile_run context "$source_root/WoundAnalysisContext.swift" Tests/WoundAnalysisContextTests.swift
compile_run workflow "$source_root/WoundWorkflowPolicy.swift" 'LiDARDepth/New Group/Views/Codes/ComorbidityChecklist.swift' Tests/WoundWorkflowPolicyTests.swift
compile_run comments "$source_root/WoundSemantic/WoundModelContract.swift" "$source_root/WoundContextComments.swift" Tests/WoundContextCommentsTests.swift

compile_run boundary-review "$source_root/WoundDetectionFrameGate.swift" "$source_root/WoundBoundaryReviewPolicy.swift" Tests/WoundBoundaryReviewPolicyTests.swift
compile_run capture-consistency "$source_root/WoundMeasurementConsistency.swift" "$source_root/WoundCaptureConsistencyPolicy.swift" Tests/WoundCaptureConsistencyPolicyTests.swift
compile_run coverage-grid "$source_root/WoundCoverageGrid.swift" Tests/WoundCoverageGridTests.swift
compile_run verified-cells "$source_root/WoundMeasurementConsistency.swift" "$source_root/WoundCaptureConsistencyPolicy.swift" "$source_root/WoundVerifiedCellEvidence.swift" Tests/WoundVerifiedCellEvidenceTests.swift

cp "$source_root/Localization/wound-localization.json" "$review_build_dir/"
compile_run localization "$source_root/Localization/WoundLocalization.swift" Tests/WoundLocalizationTests.swift
python3 Tests/WoundLocalizationCoverageTests.py
