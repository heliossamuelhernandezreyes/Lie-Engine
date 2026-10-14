"""WALL04 native frame audit: distinguish transparent joint gaps from true shadows.

This is a SCREEN-SPACE diagnostic, not a claim that source PBR masks were
reviewed. The pixels come only from actual Godot Vulkan compositor PNGs.
Column-bounded alpha voids include intended/real holes and must be visually
inspected; background outside the brick-wall silhouette is excluded.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image

PREVIOUS_MEASURED_NEUTRAL_IN_WALL_GAPS = 38564  # 2026-10-14, source SHA locked


def audit_frame(path: Path) -> dict:
    with Image.open(path) as img:
        rgba = np.asarray(img.convert("RGBA"), dtype=np.uint8)
    if rgba.shape != (1080, 1080, 4):
        raise ValueError("Compare exact 1080x1080 native Vulkan frames only")
    observed = rgba[:, :, 3] >= 128
    interior_empty = 0
    interior_pixels = 0
    hist = [0] * 33
    columns = 0
    for col in range(observed.shape[1]):
        y = np.flatnonzero(observed[:, col])
        if len(y) < 8:
            continue
        inside = observed[y[0]:y[-1] + 1, col]
        if len(inside) < 10:
            continue
        columns += 1
        interior_pixels += len(inside)
        holes = ~inside
        interior_empty += int(np.count_nonzero(holes))
        edge = np.diff(np.r_[0, holes, 0].astype(np.int8))
        start, stop = np.flatnonzero(edge == 1), np.flatnonzero(edge == -1)
        for span in stop - start:
            hist[min(int(span), 32)] += 1
    if not (columns >= 800 and 250000 <= interior_pixels <= 600000):
        raise ValueError("Frame does not contain the expected source wall")
    dark_opaque = observed & (np.max(rgba[:, :, :3], axis=2) <= 10)
    return {
        "filename": path.name,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "pixels_alpha_ge_128": int(np.count_nonzero(observed)),
        "wall_columns": columns,
        "column_bounded_wall_pixels": interior_pixels,
        "in_wall_alpha_empty_pixels": interior_empty,
        "in_wall_alpha_gap_fraction": float(interior_empty / interior_pixels),
        "visible_dark_opaque_pixels_max_rgb_le_10": int(np.count_nonzero(dark_opaque)),
        "vertical_gap_runs_by_length": {
            "1_to_2": sum(hist[1:3]),
            "3_to_5": sum(hist[3:6]),
            "6_to_9": sum(hist[6:10]),
            "10_to_31": sum(hist[10:32]),
            "32_or_more": hist[32],
        },
    }


def main(directory: Path) -> dict:
    neutral = audit_frame(directory / "LIE-WALL04-CapturedMortar-Neutral.png")
    unoccluded = audit_frame(directory / "LIE-WALL04-CapturedMortar-NoOccluders-DIAGNOSTIC.png")
    report = {
        "experimental_screen_space_diagnostic": True,
        "real_native_vulkan_png_only": True,
        "source_photo_masks_G1_reviewed": False,
        "never_treat_transparent_background_as_missing_mortar": True,
        "reference_baseline_in_wall_gaps": PREVIOUS_MEASURED_NEUTRAL_IN_WALL_GAPS,
        "delta_in_wall_gaps": neutral["in_wall_alpha_empty_pixels"] - PREVIOUS_MEASURED_NEUTRAL_IN_WALL_GAPS,
        "neutral": neutral,
        "without_shadow_occluders": unoccluded,
        "alpha_equal_between_lighting_variants": (
            neutral["pixels_alpha_ge_128"] == unoccluded["pixels_alpha_ge_128"]
            and neutral["in_wall_alpha_empty_pixels"] == unoccluded["in_wall_alpha_empty_pixels"]
        ),
    }
    (directory / "LIE-WALL04-gap-audit.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    if report["alpha_equal_between_lighting_variants"] is False:
        raise AssertionError("Geometry alpha depends on shadow toggles unexpectedly")
    return report


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--directory", required=True, type=Path)
    main(ap.parse_args().directory)
