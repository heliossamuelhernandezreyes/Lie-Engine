"""Reproduce lighting representation counterexamples, without rendering a scene.

Uses the repository's actual diffuse oracle. Optionally compares the actual
source-separated field oracle from another pinned Lie-Engine checkout.
These probes establish approximation limits, not image quality or GPU speed.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import subprocess

import lie_light_transport as legacy

ROOT = Path(__file__).resolve().parents[1]


def provenance(root: Path, paths: tuple[str, ...]) -> dict:
    commit = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=root, text=True
    ).strip()
    return {
        "commit": commit,
        "sha256": {
            path: hashlib.sha256((root / path).read_bytes()).hexdigest()
            for path in paths
        },
    }


def fixture(split: bool) -> dict:
    # Preserve total area, normal, material, illumination and receiving patch.
    # Tiny offsets avoid coincident nodes while keeping quadrature error small.
    points = [[0, 0, 0]]
    if split:
        points = [[x, 0, z] for x in (-0.001, 0.001) for z in (-0.001, 0.001)]
    model = {
        "schema": 1,
        "materials": {
            "white": {"absorption_code": 0, "tint_linear": [1, 1, 1],
                      "albedo": [1, 1, 1], "roughness": 1, "ior": 1},
            "black": {"absorption_code": 1000, "tint_linear": [1, 1, 1],
                      "albedo": [0, 0, 0], "roughness": 1, "ior": 1},
        },
        "lights": [{"position": [0, 1, 0], "radius": 100,
                    "power_rgb": [4 * math.pi] * 3}],
        "blockers": [],
        "patches": [
            {"position": point, "normal": [0, 1, 0], "area": 0.1 / len(points),
             "gray_mean": 1, "material": "white"}
            for point in points
        ],
        "bounces": 1,
    }
    model["patches"].append({
        "position": [0, 4, 0], "normal": [0, -1, 0], "area": 0.1,
        "gray_mean": 1, "material": "black",
    })
    legacy.validate(model)
    return model


def policy() -> dict:
    return {"mode": "irradiance", "radius_max": 6, "radius_decay": 1,
            "power_reference": 0.1, "irradiance_cutoff": 0.1 / (math.pi * 36)}


def partition_probe(field=None) -> dict:
    rows = {}
    for bounded in (False, True):
        for split in (False, True):
            model = fixture(split)
            if bounded:
                model["secondary_radii"] = policy()
            if field is None:
                result = legacy.solve(model, bounces=1)
                incoming = result["total_flux"][-1][0] - result["direct_flux"][-1][0]
                radii = result["secondary_radius_by_generation"][0][:-1]
            else:
                matrix, _ = legacy.form_factors(model)
                result = field.solve(model, field.sources(model, matrix))
                incoming = result["frontier"][-1][0]
                radii = None  # New oracle does not export the radius history.
            key = ("bounded" if bounded else "unbounded") + ("_four" if split else "_one")
            rows[key] = {"receiver_indirect_flux_red": incoming}
            if radii is not None:
                rows[key]["source_radii_m"] = radii
    coarse = rows["unbounded_one"]["receiver_indirect_flux_red"]
    fine = rows["unbounded_four"]["receiver_indirect_flux_red"]
    relative = abs(coarse - fine) / coarse
    assert relative < 1e-4, "Unbounded quadrature must remain effectively equivalent"
    assert rows["bounded_one"]["receiver_indirect_flux_red"] > 0
    assert rows["bounded_four"]["receiver_indirect_flux_red"] == 0
    return {"unbounded_relative_partition_error": relative, "rows": rows,
            "interpretation": "Per-node cutoff discards aggregate illumination after refinement; this is not an energy-creation failure."}


def direction_probe() -> dict:
    # Reproduce the shader's max-RGB weighted moment and power-cosine lobe.
    # Both packets come from ONE source via different paths at ONE generation.
    s = math.sqrt(0.5)
    travel = [[s, 0, -s], [-s, 0, -s]]
    moment = [sum(0.5 * row[c] for row in travel) for c in range(3)]
    length = math.sqrt(sum(v * v for v in moment))
    merged = [v / length for v in moment]
    reflected = [[row[0], row[1], -row[2]] for row in travel]
    reflected_merged = [merged[0], merged[1], -merged[2]]
    targets = [[s, 0, s], [-s, 0, s], [0, 0, 1]]
    roughness = 0.1
    exponent = min(2048, max(1, 2 / roughness**2 - 2))

    def lobe(a, b):
        return max(0, sum(x * y for x, y in zip(a, b))) ** exponent

    # F / geometric cosine = 0.1 for all three outgoing edges.
    resolved = [0.1 * sum(0.5 * lobe(t, d) for t in reflected) for d in targets]
    compressed = [0.1 * lobe(reflected_merged, d) for d in targets]
    assert resolved[0] > 0.049 and compressed[0] < 1e-20
    assert resolved[2] < 1e-20 and compressed[2] > 0.099
    assert sum(resolved) <= 1 and sum(compressed) <= 1
    return {
        "kind": "local analytical counterexample of the actual angular representation; not a full scene render",
        "source_channels": 1, "incoming_packets": travel,
        "merged_direction": merged, "roughness": roughness,
        "target_directions": targets, "resolved_flux": resolved,
        "moment_compressed_flux": compressed,
        "interpretation": "One moment cannot distinguish two angular lobes; both alternatives remain passive.",
    }


def power_probe() -> dict:
    model = fixture(False)
    model["secondary_radii"] = policy()

    def indirect(m):
        out = legacy.solve(m, bounces=1)
        return out["total_flux"][-1][0] - out["direct_flux"][-1][0]

    full = indirect(model)
    quarter = copy.deepcopy(model)
    quarter["lights"][0]["power_rgb"] = [p * 0.25 for p in quarter["lights"][0]["power_rgb"]]
    dim = indirect(quarter)
    assert full > 0 and dim == 0
    return {"full_power_indirect": full, "quarter_power_indirect": dim,
            "linear_prediction_at_quarter_power": full * 0.25,
            "interpretation": "Power-dependent support is nonlinear. The existing direct-detail cache does not cache this coarse bounded solve."}


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--field-root", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    result = {
        "schema": "lie-coded-lighting-audit/1",
        "scope": "CPU approximation probes; no new GPU execution or Android performance measurement",
        "legacy_source": provenance(ROOT, ("tools/lie_light_transport.py",)),
        "legacy_partition": partition_probe(),
        "same_source_angular_compression": direction_probe(),
        "bounded_power_nonlinearity": power_probe(),
    }
    if args.field_root:
        root = args.field_root.resolve()
        spec = importlib.util.spec_from_file_location("audited_light_field", root / "tools/lie_light_field.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        result["source_separated_field_source"] = provenance(root, (
            "tools/lie_light_field.py", "gpu_compute/shaders/lie_light_field.glsl",
            "gpu_compute/lie_runtime_android_lab.gd",
        ))
        result["source_separated_field_partition"] = partition_probe(module)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"output": str(args.out), "confirmed_counterexamples": 3,
                      "field_compared": bool(args.field_root)}))


if __name__ == "__main__":
    main()
