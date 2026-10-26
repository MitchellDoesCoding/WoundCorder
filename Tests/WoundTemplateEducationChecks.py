"""Validate bundled template content against the model's supported outputs."""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
wounds = {"abrasion", "bruise", "burn", "diabetic_foot_ulcer", "laceration_or_cut",
          "normal_control", "pressure_injury", "surgical_wound", "venous_leg_ulcer"}
tissues = {"inflammation", "normal_skin", "epithelial", "granulation",
           "slough_fibrin", "necrotic_eschar", "callus", "background_non_skin"}
for mode in ("patient", "clinician"):
    data = json.loads((root / f"LiDARDepth/Model/Code/Codes/WoundEducation/template-{mode}.json").read_text())
    assert wounds <= data["wounds"].keys()
    assert tissues <= data["tissues"].keys()
    for key in wounds:
        entry = data["wounds"][key]
        guidance = entry["nurse" if mode == "clinician" else "patient"]
        assert guidance["description"] and all(len(step) == 2 for step in guidance["steps"])
        for ref in guidance.get("references", []):
            assert 1 <= ref <= len(data["references"])
        for image in entry["images"]:
            asset = root / f"LiDARDepth/Assets.xcassets/template-{mode}-{Path(image).stem}.imageset"
            manifest = json.loads((asset / "Contents.json").read_text())
            for item in manifest["images"]:
                assert (asset / item["filename"]).read_bytes().startswith(b"\xff\xd8")
    for key in tissues:
        assert data["tissues"][key]["nurse" if mode == "clinician" else "patient"]
    print(f"PASS: {mode} model-label coverage, sample photos, guidance, and source indices")
