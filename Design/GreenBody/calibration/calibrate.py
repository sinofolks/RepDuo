#!/usr/bin/env python3
"""Versioned, local single-view calibration. Never writes to a source .blend.

Input PNGs are measurement evidence. Derived overlays/masks are diagnostic
visualizations, not retouched model renders. Only uniform scale and translation
are allowed in normalization, and the transform is retained in every report.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, PngImagePlugin
from scipy import ndimage

ROOT = Path(__file__).resolve().parent


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def json_digest(data):
    return hashlib.sha256(json.dumps(data, sort_keys=True, ensure_ascii=False,
                                     allow_nan=False).encode()).hexdigest()


def read_json(path):
    return json.loads(Path(path).read_text())


def write_json(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2,
                                     allow_nan=False) + "\n")


def save_png(path, array, origin):
    meta = PngImagePlugin.PngInfo()
    meta.add_text("Source", origin)
    meta.add_text("Purpose", "Calibration evidence; measured transform, no image generation or repainting")
    Image.fromarray(np.asarray(array).astype(np.uint8)).save(path, pnginfo=meta)


def largest_component(mask):
    labels, count = ndimage.label(mask)  # Explicit 4-connectivity, no row wrap.
    if not count:
        raise ValueError("未找到人物前景，不能评分")
    areas = np.bincount(labels.ravel())
    areas[0] = 0
    return labels == int(areas.argmax())


def bounds(mask):
    ys, xs = np.where(mask)
    if not len(xs):
        raise ValueError("前景为空，不能评分")
    return [int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1]


def mask_check(mask, *, minimum_area=1000):
    if mask.ndim != 2 or int(mask.sum()) < minimum_area:
        raise ValueError("前景过少或遮罩格式错误，不能评分")
    if mask[0].any() or mask[-1].any() or mask[:, 0].any() or mask[:, -1].any():
        raise ValueError("人物碰到图像边界，疑似裁切；请重新采集完整身体")
    return bounds(mask)


def normalize(rgb, mask, landmarks, settings):
    """Deterministic framing normalization, never search/warp to inflate score."""
    x0, y0, x1, y1 = mask_check(mask)
    width, height = settings["width"], settings["height"]
    scale = settings["body_height"] / (y1 - y0)
    tx = width / 2 - scale * (x0 + x1) / 2
    ty = settings["top"] - scale * y0
    inverse = (1 / scale, 0, -tx / scale, 0, 1 / scale, -ty / scale)
    # Premasking prevents a concept-board label/floor from entering appearance.
    masked = np.where(mask[..., None], rgb, 0).astype(np.uint8)
    image = Image.fromarray(masked).transform((width, height), Image.Transform.AFFINE,
                                             inverse, Image.Resampling.BICUBIC)
    mask_image = Image.fromarray(mask.astype(np.uint8) * 255).transform(
        (width, height), Image.Transform.AFFINE, inverse, Image.Resampling.NEAREST)
    output_mask = np.asarray(mask_image) > 127
    mask_check(output_mask)
    output = np.asarray(image).copy()
    output[~output_mask] = 0
    output_landmarks = {}
    for name, item in landmarks.items():
        if item.get("in_frame") is False or item.get("in_front") is False:
            continue  # Missing points are penalized by metrics, not renormalized.
        point = item.get("xy", [item.get("pixel_x"), item.get("pixel_y")])
        if len(point) != 2 or not all(isinstance(v, (int, float)) and np.isfinite(v) for v in point):
            continue
        output_landmarks[name] = {**item, "xy": [point[0] * scale + tx, point[1] * scale + ty],
                                  "uncertainty_px": float(item.get("uncertainty_px", 0)) * scale}
    return output, output_mask, output_landmarks, {
        "method": "foreground height + bbox horizontal center; uniform scale and translation only",
        "source_bounds_xyxy": [x0, y0, x1, y1], "scale": scale, "translate": [tx, ty],
        "source_size": [rgb.shape[1], rgb.shape[0]], "canonical_size": [width, height],
        "rotation": 0, "mirror": False, "nonuniform_warp": False,
        "note": "全局画面占比与平移被消除，不计入形体分；相机角度和姿态差异仍会影响评分。"}


def diagnostic_images(out, ref, cand, rm, cm, rpoints, cpoints):
    assets = {}
    for name, arr in (("reference", ref), ("candidate", cand),
                      ("reference_mask", rm.astype(np.uint8) * 255),
                      ("candidate_mask", cm.astype(np.uint8) * 255),
                      ("overlay", np.rint(ref.astype(float) * .5 + cand.astype(float) * .5))):
        path = out / (name + ".png")
        save_png(path, arr, "Source images and uniform transforms in this run's result.json")
        assets[name] = str(path)
    diff = np.full_like(ref, (10, 13, 15))
    diff[rm & cm] = (64, 72, 76)
    diff[rm & ~cm] = (51, 200, 224)
    diff[cm & ~rm] = (250, 150, 75)
    for mask, color in ((rm, (89, 220, 242)), (cm, (255, 170, 96))):
        edge = mask & ~ndimage.binary_erosion(mask)
        diff[edge] = color
    save_png(out / "difference.png", diff, "Boolean reference minus candidate/candidate minus reference mask; cyan=reference, orange=candidate")
    assets["difference"] = str(out / "difference.png")
    canvas = Image.fromarray(np.rint(ref.astype(float) * .35 + cand.astype(float) * .65).astype(np.uint8))
    draw = ImageDraw.Draw(canvas)
    for idx, (name, rp) in enumerate(rpoints.items(), 1):
        x, y = rp["xy"]
        radius = rp.get("uncertainty_px", 0)
        draw.ellipse((x-radius, y-radius, x+radius, y+radius), outline=(89, 220, 242), width=1)
        draw.ellipse((x-3, y-3, x+3, y+3), fill=(89, 220, 242))
        cp = cpoints.get(name)
        if cp:
            xx, yy = cp["xy"]
            draw.line((x, y, xx, yy), fill=(238, 239, 232), width=1)
            draw.rectangle((xx-3, yy-3, xx+3, yy+3), fill=(255, 170, 96))
        draw.text((x+5, y-12), str(idx), fill=(230, 240, 240))
    save_png(out / "landmarks.png", canvas, "Estimated reference joints (cyan circles with uncertainty) versus projected Blender rig anchors (orange squares)")
    assets["landmarks"] = str(out / "landmarks.png")
    return assets


def init_reference(config_path, out):
    config_path = Path(config_path).resolve()
    cfg = read_json(config_path)
    source = (config_path.parent / cfg["image"]).resolve()
    if digest(source) != cfg["image_sha256"]:
        raise ValueError("参考原图校验失败；不要在原评分协议中替换图片")
    if out.exists():
        raise ValueError(f"参考版本已存在，不能覆盖：{out}。修改标注时另建新版本。")
    rgb = np.asarray(Image.open(source).convert("RGB"))
    r, g, b = [rgb[..., i].astype(float) for i in range(3)]
    seg = cfg["segmentation"]
    mask = (g >= seg["min_green"]) & (g > r * seg["green_red_ratio"]) & (g > b * seg["green_blue_ratio"])
    x0, y0, x1, y1 = cfg["roi"]
    region = np.zeros(mask.shape, dtype=bool)
    region[y0:y1, x0:x1] = True
    mask = largest_component(mask & region)
    normalized, nm, points, alignment = normalize(rgb, mask, cfg["landmarks"], cfg["canonical"])
    out.mkdir(parents=True)
    save_png(out / "source.png", rgb, str(source) + " sha256:" + digest(source))
    save_png(out / "mask.png", mask.astype(np.uint8)*255, "Frozen reference segmentation from reference-v1.json; provisional, requires visual review")
    assets = diagnostic_images(out, normalized, normalized, nm, nm, points, points)
    manifest = {"schema": "greenbody-reference-lock-v1", "config": cfg,
                "original_source": str(source), "original_sha256": digest(source),
                "config_sha256": json_digest(cfg), "source_sha256": digest(out / "source.png"),
                "mask_sha256": digest(out / "mask.png"), "landmarks": points,
                "alignment": alignment, "assets": assets}
    write_json(out / "reference.json", manifest)
    print(f"Reference locked: {out / 'reference.json'}")


def load_reference(path):
    path = Path(path).resolve()
    if path.is_dir():
        path = path / "reference.json"
    m = read_json(path)
    for key, file in (("source_sha256", "source.png"), ("mask_sha256", "mask.png")):
        if digest(path.parent / file) != m[key]:
            raise ValueError(f"锁定参考被更改：{file}。请创建新的参考版本。")
    if json_digest(m["config"]) != m["config_sha256"]:
        raise ValueError("参考配置锁不匹配")
    rgb = np.asarray(Image.open(path.parent / "source.png").convert("RGB"))
    mask = np.asarray(Image.open(path.parent / "mask.png").convert("L")) > 127
    return m, normalize(rgb, mask, m["config"]["landmarks"], m["config"]["canonical"])


def verify_capture(directory, cap):
    if cap.get("status") != "complete" or cap.get("source_unchanged") is not True:
        raise ValueError("采集未完成或源模型在采集时发生变化，请重新采集")
    if cap.get("source_blend_sha256_before") != cap.get("source_blend_sha256_after"):
        raise ValueError("源模型校验不一致")
    for key in ("effective_profile_sha256", "collector_sha256", "lighting_hash", "material_hash", "track"):
        if not cap.get(key):
            raise ValueError(f"采集缺少校验字段 {key}")
    for name in ("beauty.png", "mask.png"):
        expected = cap.get("outputs", {}).get(name, {}).get("sha256")
        if not expected or digest(directory / name) != expected:
            raise ValueError(f"采集证据被改动或缺失：{name}，请重新采集")


def incomplete_status(value):
    return str(value).startswith(("invalid", "incomplete"))


def group_index(result, keys):
    total = sum(result["metrics"][k]["weight"] for k in keys)
    return sum(result["metrics"][k]["weight"] * result["metrics"][k]["score"]
               for k in keys) / total if total else None


def recommendations(result):
    items = []
    regions = result.get("regional_results", [])
    if isinstance(regions, dict):
        regions = [{"region": k, **v} for k, v in regions.items()]
    for row in sorted(regions, key=lambda v: v.get("score", 100))[:3]:
        region = row.get("region", row.get("name", "局部"))
        items.append(f"优先检查 {region}：区域匹配分 {row.get('score', 0):.1f}。结合叠图区分相机/姿态偏移与局部厚度，单次只改一个因素。")
    items += ["固定相机协议下比较形体；调相机或摄影棚请开新协议并重新渲染基线。",
              "总分上升不等于全部改善：先检查各区域退步、侧背面和动作变形，再决定是否保留模型。"]
    return items


def evaluate_capture(reference_path, capture_dir, label, out_root):
    from metrics import evaluate
    capture_dir = Path(capture_dir).resolve()
    cap = read_json(capture_dir / "capture.json")
    verify_capture(capture_dir, cap)
    refmeta, (ref, rm, rpoints, ralign) = load_reference(reference_path)
    rgb = np.asarray(Image.open(capture_dir / "beauty.png").convert("RGB"))
    cm = np.asarray(Image.open(capture_dir / "mask.png").convert("L")) > 127
    if rgb.shape[:2] != cm.shape:
        raise ValueError("采集图像和遮罩尺寸不一致")
    mask_check(cm)
    cand, cm, cpoints, calign = normalize(rgb, cm, cap["landmarks"], refmeta["config"]["canonical"])
    scoring = {**refmeta["config"].get("scoring", {}),
               "required_landmark_names": list(refmeta["config"]["landmarks"])}
    result = evaluate(ref, cand, rm, cm, rpoints, cpoints, scoring)
    result["metrics_score_status"] = result["score_status"]
    result["geometry_index"] = group_index(result, ("silhouette_iou", "boundary_f1", "width_profile", "landmarks"))
    result["appearance_index"] = group_index(result, ("color", "shading"))
    # Profile/source keys are versioned by render_candidate.py; never compare
    # captures with arbitrary missing provenance as if they were equivalent.
    profile_key = cap.get("effective_profile_sha256")
    if not profile_key:
        raise ValueError("采集记录缺少 profile_sha256，无法建立可比评分协议")
    protocol = {"reference_config": refmeta["config_sha256"], "reference_mask": refmeta["mask_sha256"],
                "reference_source": refmeta["source_sha256"], "capture_profile": profile_key,
                "appearance_mode": cap["track"], "collector": cap["collector_sha256"],
                "lighting": cap["lighting_hash"],
                "fixed_material": None if cap.get("native_appearance") else cap["material_hash"],
                "blender_build": [cap.get("blender_version"), cap.get("blender_build_hash")],
                "metrics_code": digest(ROOT / "metrics.py"), "pipeline_code": digest(__file__)}
    created = datetime.now(timezone.utc).isoformat()
    slug = re.sub(r"[^a-zA-Z0-9_-]+", "-", label).strip("-") or "candidate"
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ") + "-" + slug
    out = Path(out_root).resolve() / run_id
    out.mkdir(parents=True, exist_ok=False)
    assets = diagnostic_images(out, ref, cand, rm, cm, rpoints, cpoints)
    result.update({"schema": "greenbody-calibration-run-v1", "run_id": run_id, "label": label,
                   "created_at": created, "protocol_id": json_digest(protocol), "protocol": protocol,
                   "reference_landmarks": rpoints, "candidate_landmarks": cpoints,
                   "alignment": {"reference": ralign, "candidate": calign}, "assets": assets,
                   "provenance": {"capture": cap, "capture_manifest_sha256": digest(capture_dir / "capture.json"),
                                  "beauty_sha256": digest(capture_dir / "beauty.png"),
                                  "mask_sha256": digest(capture_dir / "mask.png"),
                                  "reference": refmeta, "numpy_version": np.__version__},
                   "annotation_status": refmeta["config"]["annotation_status"],
                   "interpretation": "单视角匹配指数，非3D还原百分比；未验证背面、内部结构、动画或生物力学。"})
    result["warnings"].append(refmeta["config"]["annotation_note"])
    result["recommendations"] = recommendations(result)
    # A deterministic boundary-perturbation check, NOT a confidence interval.
    # Keep the same transforms/points; vary only reference edge by one pixel.
    sensitivity = [evaluate(ref, cand, changed, cm, rpoints, cpoints, scoring)["composite_score"]
                   for changed in (ndimage.binary_erosion(rm), ndimage.binary_dilation(rm))]
    result["mask_sensitivity"] = {"min_score": min(sensitivity + [result["composite_score"]]),
                                   "max_score": max(sensitivity + [result["composite_score"]]),
                                   "canonical_edge_perturbation_px": 1,
                                   "note": "参考遮罩边缘±1像素的敏感性范围，非统计置信区间；新边缘的黑像素也可能影响外观项。"}
    if not incomplete_status(result.get("score_status")):
        result["score_status"] = "provisional" if result["annotation_status"] != "reviewed" else "measured"
    write_json(out / "result.json", result)
    print(json.dumps({"run": str(out / "result.json"), "score": result["composite_score"],
                      "status": result["score_status"], "protocol": result["protocol_id"][:12]}, ensure_ascii=False))
    return result


def compare_runs(base_path, candidate_path):
    base, candidate = read_json(base_path), read_json(candidate_path)
    if base["protocol_id"] != candidate["protocol_id"]:
        raise ValueError("不同协议不可直接相减。请用相同参考、规则和采集设置重新评分两版。")
    if any(incomplete_status(r.get("score_status")) or r.get("metrics_score_status") != "complete"
           for r in (base, candidate)):
        raise ValueError("输入不完整或无效，不能判断改善")
    changes = {k: candidate["metrics"][k]["score"] - v["score"] for k, v in base["metrics"].items()}
    def regions(r):
        rows = r.get("regional_results", [])
        return rows if isinstance(rows, dict) else {x.get("region", x.get("name")): x for x in rows}
    br, cr = regions(base), regions(candidate)
    regional = {k: cr[k]["score"] - v["score"] for k, v in br.items() if k in cr}
    delta = candidate["composite_score"] - base["composite_score"]
    veto = [k for k, v in regional.items() if v < -3]
    sensitivity_margin = max((r.get("mask_sensitivity", {}).get("max_score", r["composite_score"])
                              - r.get("mask_sensitivity", {}).get("min_score", r["composite_score"]))
                             for r in (base, candidate))
    return {"baseline": base["label"], "candidate": candidate["label"], "delta": delta,
            "metric_deltas": changes, "region_deltas": regional, "regression_guard_points": 3,
            "regressions": veto, "sensitivity_margin": sensitivity_margin,
            "decision": "review_candidate" if delta > max(.25, sensitivity_margin) and not veto else "hold_for_review",
            "note": "仅建议人工复核；不自动覆盖模型，不代表全3D质量通过。"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    init = sub.add_parser("init-reference")
    init.add_argument("--config", type=Path, default=ROOT / "reference-v3.json")
    init.add_argument("--out", type=Path, default=ROOT / "references" / "v3")
    ev = sub.add_parser("evaluate")
    ev.add_argument("--reference", type=Path, default=ROOT / "references" / "v3")
    ev.add_argument("--capture", type=Path, required=True)
    ev.add_argument("--label", required=True)
    ev.add_argument("--out", type=Path, default=ROOT / "runs")
    report = sub.add_parser("report")
    report.add_argument("--runs", type=Path, default=ROOT / "runs")
    report.add_argument("--out", type=Path, default=ROOT / "report.html")
    compare = sub.add_parser("compare")
    compare.add_argument("baseline", type=Path)
    compare.add_argument("candidate", type=Path)
    run = sub.add_parser("run", help="One command: real Blender capture, evaluation, refreshed local report")
    run.add_argument("--blend", required=True, type=Path)
    run.add_argument("--label", required=True)
    run.add_argument("--reference", type=Path, default=ROOT / "references" / "v3")
    run.add_argument("--profile", type=Path, default=ROOT / "capture-profile-v1.json")
    run.add_argument("--blender", default="/Applications/Blender.app/Contents/MacOS/Blender")
    run.add_argument("--native-appearance", action="store_true")
    args = parser.parse_args()
    try:
        if args.command == "init-reference":
            init_reference(args.config, args.out.resolve())
        elif args.command == "evaluate":
            evaluate_capture(args.reference, args.capture, args.label, args.out)
        elif args.command == "report":
            from report import build_report
            runs = [read_json(p) for p in sorted(args.runs.glob("*/result.json"))]
            build_report(runs, args.out.resolve())
            print(f"Report: {args.out.resolve()}")
        elif args.command == "run":
            slug = re.sub(r"[^a-zA-Z0-9_-]+", "-", args.label).strip("-") or "candidate"
            capture = ROOT / "captures" / (datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ-") + slug)
            command = [args.blender, "--background", "--factory-startup", "--python-exit-code", "1",
                       "--python", str(ROOT / "render_candidate.py"), "--", "--blend", str(args.blend.resolve()),
                       "--out", str(capture), "--profile", str(args.profile.resolve())]
            if args.native_appearance:
                command.append("--native-appearance")
            subprocess.run(command, check=True)
            evaluate_capture(args.reference, capture, args.label, ROOT / "runs")
            from report import build_report
            build_report([read_json(p) for p in sorted((ROOT / "runs").glob("*/result.json"))], ROOT / "report.html")
            print(f"Report: {ROOT / 'report.html'}")
        else:
            print(json.dumps(compare_runs(args.baseline, args.candidate), ensure_ascii=False, indent=2))
    except (ValueError, KeyError, FileNotFoundError, subprocess.CalledProcessError) as exc:
        parser.exit(2, f"Calibration error: {exc}\n")


if __name__ == "__main__":
    main()
