"""Build the standalone, offline GreenBody calibration evidence report.

``build_report(runs, output_path)`` reads supplied measurements and raster
assets. It never computes, repairs, or changes a score, pose, or alignment.
The returned HTML embeds all available images and has no network dependency.
"""

from __future__ import annotations

import base64
from collections.abc import Mapping
from datetime import date, datetime, timezone
import hashlib
import json
import math
from pathlib import Path
from typing import Any


TEMPLATE = Path(__file__).with_name("report-template.html")
ASSET_KEYS = ("reference", "candidate", "difference", "overlay", "landmarks")
MAX_ASSET_BYTES = 32 * 1024 * 1024


def _json_value(value: Any) -> Any:
    """Copy JSON-like data without mutating a caller's run or serializing NaN."""
    if value is None or isinstance(value, (str, bool, int)):
        return value
    if isinstance(value, float):
        return value if math.isfinite(value) else None
    if isinstance(value, (Path, date, datetime)):
        return value.isoformat() if isinstance(value, (date, datetime)) else str(value)
    if isinstance(value, Mapping):
        return {str(key): _json_value(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_json_value(item) for item in value]
    # Scientific pipelines may hand over NumPy scalar/array values. This does
    # not import NumPy and does not reinterpret any quantity or measurement.
    if hasattr(value, "tolist"):
        return _json_value(value.tolist())
    if hasattr(value, "item"):
        return _json_value(value.item())
    raise TypeError(f"Unsupported report value: {type(value).__name__}")


def _timestamp(run: dict, ordinal: int) -> tuple[float, int]:
    value = run.get("created_at")
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return parsed.timestamp(), ordinal
    except (ValueError, TypeError, OverflowError):
        return float("-inf"), ordinal


def _raster_mime(data: bytes) -> str | None:
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if data.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if data[:6] in (b"GIF87a", b"GIF89a"):
        return "image/gif"
    if data.startswith(b"RIFF") and data[8:12] == b"WEBP":
        return "image/webp"
    return None


def _embed_assets(run: dict, embedded: dict[str, str]) -> None:
    assets = run.get("assets") if isinstance(run.get("assets"), dict) else {}
    run["embedded_assets"] = {}
    run["asset_manifest"] = []
    run["report_warnings"] = []
    for key in ASSET_KEYS:
        value = assets.get(key)
        if isinstance(value, dict):
            value = value.get("path") or value.get("filepath")
        if not value:
            continue
        manifest: dict[str, Any] = {"key": key, "path": str(value)}
        try:
            path = Path(value)
            if not path.is_absolute():
                raise ValueError("图片路径必须为绝对本地路径")
            if not path.is_file():
                raise ValueError("图片文件不存在")
            if path.stat().st_size > MAX_ASSET_BYTES:
                raise ValueError("单张图片超过 32 MiB 嵌入上限")
            data = path.read_bytes()
            mime = _raster_mime(data)
            if mime is None:
                raise ValueError("仅嵌入 PNG、JPEG、WebP 或 GIF 栅格图片")
            digest = hashlib.sha256(data).hexdigest()
            asset_id = "sha256-" + digest
            if asset_id not in embedded:
                embedded[asset_id] = f"data:{mime};base64,{base64.b64encode(data).decode('ascii')}"
            run["embedded_assets"][key] = asset_id
            manifest.update({"sha256": digest, "mime_type": mime, "size_bytes": len(data), "embedded": True})
        except (OSError, TypeError, ValueError) as error:
            manifest.update({"embedded": False, "error": str(error)})
            run["report_warnings"].append(f"{key}：{error}。请检查原始记录的资产路径后重新生成报告。")
        run["asset_manifest"].append(manifest)


def build_report(runs: list[dict], output_path: Path) -> Path:
    """Write one self-contained HTML report and return its absolute path.

    Runs are ordered by supplied ``created_at`` (latest selected initially).
    Missing assets appear as explicit evidence warnings; report generation
    never silently changes the pipeline's ``score_status`` or metric values.
    Histories are separated by ``protocol_id`` in the browser.
    """
    if not isinstance(runs, list) or any(not isinstance(run, Mapping) for run in runs):
        raise TypeError("runs must be a list of run dictionaries")
    prepared = [_json_value(run) for run in runs]
    prepared = [run for _, run in sorted(enumerate(prepared), key=lambda pair: _timestamp(pair[1], pair[0]))]
    embedded: dict[str, str] = {}
    for run in prepared:
        _embed_assets(run, embedded)
    payload = {"report_schema": "greenbody-calibration-report/v1", "runs": prepared, "assets": embedded}
    serialized = json.dumps(payload, ensure_ascii=False, allow_nan=False, separators=(",", ":"))
    # A JSON script element is still parsed by the HTML tokenizer: escape '<'
    # so caller text such as '</script><img onerror=...>' cannot end the block.
    serialized = (serialized.replace("&", "\\u0026").replace("<", "\\u003c")
                  .replace(">", "\\u003e").replace("\u2028", "\\u2028").replace("\u2029", "\\u2029"))
    template = TEMPLATE.read_text(encoding="utf-8")
    marker = "__GREENBODY_REPORT_DATA__"
    if template.count(marker) != 1:
        raise ValueError("Report template must contain exactly one data marker")
    output_path = Path(output_path).expanduser().resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(template.replace(marker, serialized), encoding="utf-8")
    return output_path
