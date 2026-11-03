"""Create the user-authorized, 3D-consistent v4 turnaround protocol.

V3 remains untouched.  V4 is a new, versioned protocol whose side-view
landmark *annotations* are reconciled to the front view under the already
locked equal-scale orthographic cameras.  The artwork is copied byte-for-byte:
this is not an image warp and does not borrow any candidate-model geometry.
"""
import hashlib
import json
import shutil
from pathlib import Path

from calibrate import init_reference


ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "multiview-reference-v3"
DEST = ROOT / "multiview-reference-v4"


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    if DEST.exists():
        raise FileExistsError(f"Refusing to overwrite {DEST}")
    # Profiles are protocol-locked capture settings.  References/runs/captures
    # are intentionally new so no v3 result can be mistaken for v4 evidence.
    for name in ("profiles",):
        shutil.copytree(SOURCE / name, DEST / name)
    (DEST / "configs").mkdir(parents=True)
    (DEST / "runs").mkdir()
    (DEST / "captures").mkdir()

    side_changes = {
        "screen_left_shoulder": 214,
        "screen_left_elbow": 318,
        "screen_left_wrist": 430,
        "screen_left_hip": 416,
        "screen_left_knee": 588,
        "screen_left_ankle": 772,
    }
    changes = {}
    for view in ("front", "side", "back"):
        config = json.loads((SOURCE / "configs" / f"{view}.json").read_text())
        config["revision"] = 4
        config["reference_series"] = "turnaround-v4-orthographic-landmarks"
        config["annotation_note"] = (
            "用户授权后，以固定同尺度正交相机和同一站姿为约束，校正侧视共享"
            "关节的纵向标注；原三视图像素未被改写。AI生成图仍不是实测三维几何。"
        )
        config["harmonization"] = {
            "method": "v3 artwork retained byte-for-byte; side shared-joint annotations reconciled to front under locked orthographic protocol",
            "authorization": "User explicitly authorized side reference / joint-annotation correction: 授权",
            "source_reference_series": "turnaround-v3-harmonized",
            "source_image_sha256": sha256(ROOT.parent / "reference" / "green-body-turnaround-v3b-harmonized.png"),
            "edited_pixels": 0,
            "not_a_model_render": True,
        }
        if view == "side":
            for landmark, new_y in side_changes.items():
                old = config["landmarks"][landmark]["xy"][1]
                config["landmarks"][landmark]["xy"][1] = new_y
                config["landmarks"][landmark]["source"] = (
                    "v4 user-authorized orthographic shared-joint reconciliation; "
                    "source artwork unchanged"
                )
                changes[landmark] = {"old_source_y": old, "new_source_y": new_y}
        (DEST / "configs" / f"{view}.json").write_text(
            json.dumps(config, indent=2, ensure_ascii=False) + "\n"
        )

        # Recollect from the immutable source image and v4 config.  This emits
        # a new lock rather than copying an old lock with stale annotations.
        init_reference(DEST / "configs" / f"{view}.json", DEST / "references" / view)

    audit = {
        "schema": "greenbody-reference-v4-annotation-reconciliation-v1",
        "authorization": "授权",
        "source_protocol": str(SOURCE),
        "source_image_sha256": sha256(ROOT.parent / "reference" / "green-body-turnaround-v3b-harmonized.png"),
        "v4_side_reference_source_sha256": json.loads(
            (DEST / "references" / "side" / "reference.json").read_text()
        )["original_sha256"],
        "artwork_edit": "none; the source artwork is byte-identical in all v4 view copies",
        "side_annotation_changes": changes,
        "constraint": "Shared front/side joint vertical coordinates are reconciled under the fixed same-scale orthographic camera and pose.",
        "limitation": "This restores a coherent landmark target; it does not make the current model 99% accurate or change scoring weights.",
    }
    (DEST / "reference-v4-authorization-audit.json").write_text(
        json.dumps(audit, indent=2, ensure_ascii=False) + "\n"
    )
    print(json.dumps(audit, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
