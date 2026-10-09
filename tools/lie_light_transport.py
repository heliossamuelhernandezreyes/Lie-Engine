"""LIE-11 float64 reference for absorption-coded, finite-patch light transport.

RGB values are linear relative power, not calibrated spectral watts. This is a
bounded diffuse approximation: no specular reflection, transmission or ray tracing.
"""
from __future__ import annotations

import argparse
import copy
import json
import math
from pathlib import Path


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def subtract(a, b):
    return [x - y for x, y in zip(a, b)]


def segment_blocked(a, b, boxes):
    """Slab intersection of the open segment, with explicit endpoint exclusion."""
    delta = subtract(b, a)
    for box in boxes:
        lo, hi = 0.001, 0.999
        for axis in range(3):
            if abs(delta[axis]) < 1e-8:
                if a[axis] < box[0][axis] or a[axis] > box[1][axis]:
                    lo, hi = 1.0, 0.0
                    break
            else:
                near = (box[0][axis] - a[axis]) / delta[axis]
                far = (box[1][axis] - a[axis]) / delta[axis]
                lo = max(lo, min(near, far))
                hi = min(hi, max(near, far))
        if lo <= hi:
            return True
    return False


def validate(model):
    if model.get("schema") != 1 or not 1 <= len(model["patches"]) <= 1024:
        raise ValueError("Unsupported schema or patch count")
    if not 1 <= len(model["lights"]) <= 16:
        raise ValueError("Expected 1..16 light codes")
    for p in model["patches"]:
        if len(p["position"]) != 3 or len(p["normal"]) != 3:
            raise ValueError("XYZ and normal must have three components")
        if not all(math.isfinite(v) for v in p["position"] + p["normal"]):
            raise ValueError("Non-finite patch")
        if abs(dot(p["normal"], p["normal"]) - 1) > 1e-5:
            raise ValueError("Normals must be unit world-space vectors")
        if not math.isfinite(p["area"]) or p["area"] <= 0:
            raise ValueError("Patch area must be positive")
        if not 0 <= p["gray_mean"] <= 1:
            raise ValueError("Grayscale reflectance must be in [0,1]")
        m = model["materials"][p["material"]]
        if not isinstance(m["absorption_code"], int) or not 0 <= m["absorption_code"] <= 1000:
            raise ValueError("Absorption code must be an integer in [0,1000]")
        if len(m["tint_linear"]) != 3 or not all(0 <= x <= 1 for x in m["tint_linear"]):
            raise ValueError("Material RGB filter must be in [0,1]")
    for light in model["lights"]:
        if len(light["position"]) != 3 or len(light["power_rgb"]) != 3:
            raise ValueError("Light XYZ and RGB must have three components")
        if not all(math.isfinite(x) for x in light["position"] + light["power_rgb"]):
            raise ValueError("Non-finite light")
        if min(light["power_rgb"]) < 0 or not math.isfinite(light["radius"]) or light["radius"] <= 0:
            raise ValueError("Invalid light power/radius")
    for lo, hi in model.get("blockers", []):
        if len(lo) != 3 or len(hi) != 3 or not all(math.isfinite(x) for x in lo + hi):
            raise ValueError("Invalid occluder bounds")
        if any(a >= b for a, b in zip(lo, hi)):
            raise ValueError("Occluder needs nonzero volume")


def reflectance(model, patch):
    material = model["materials"][patch["material"]]
    fraction = 1.0 - material["absorption_code"] / 1000.0
    return [fraction * x * patch["gray_mean"] for x in material["tint_linear"]]


def form_factors(model):
    """Center quadrature with one global cap preserving area reciprocity.

    F[i][j] is a fraction of source i's reflected power reaching receiver j.
    Missing row mass escapes. Global scaling is a documented conservative
    correction of the coarse quadrature, not an exact geometric integral.
    """
    validate(model)
    patches = model["patches"]
    n = len(patches)
    f = [[0.0] * n for _ in range(n)]
    for i, a in enumerate(patches):
        for j in range(i + 1, n):
            b = patches[j]
            delta = subtract(b["position"], a["position"])
            d2 = dot(delta, delta)
            if d2 < 1e-10 or segment_blocked(a["position"], b["position"], model.get("blockers", [])):
                continue
            direction = [x / math.sqrt(d2) for x in delta]
            ca = max(dot(a["normal"], direction), 0.0)
            cb = max(-dot(b["normal"], direction), 0.0)
            coupling = a["area"] * b["area"] * ca * cb / (math.pi * d2)
            f[i][j] = coupling / a["area"]
            f[j][i] = coupling / b["area"]
    correction = max(1.0, max(map(sum, f)))
    return [[v / correction for v in row] for row in f], 1.0 / correction


def light_weight(patch, light, blockers):
    delta = subtract(light["position"], patch["position"])
    d2 = dot(delta, delta)
    if d2 < 1e-10 or segment_blocked(patch["position"], light["position"], blockers):
        return 0.0
    distance = math.sqrt(d2)
    cosine = max(dot(patch["normal"], [x / distance for x in delta]), 0.0)
    window = max(0.0, 1.0 - (distance / light["radius"]) ** 4) ** 2
    # Finite source softening and a smooth radius cutoff are explicit approximations.
    return patch["area"] * cosine * window / (4 * math.pi * max(d2, 0.05 ** 2))


def direct_flux(model):
    n = len(model["patches"])
    result = [[0.0] * 3 for _ in range(n)]
    for light in model["lights"]:
        weights = [light_weight(p, light, model.get("blockers", [])) for p in model["patches"]]
        cap = max(1.0, sum(weights))
        for i, w in enumerate(weights):
            for c in range(3):
                result[i][c] += light["power_rgb"][c] * w / cap
    return result


def totals(values):
    return [sum(row[c] for row in values) for c in range(3)]


def solve(model, bounces=2, threshold=0.0):
    if not isinstance(bounces, int) or not 0 <= bounces <= 8 or not math.isfinite(threshold) or threshold < 0:
        raise ValueError("Expected 0..8 bounces and a finite nonnegative threshold")
    f, correction = form_factors(model)
    direct = direct_flux(model)
    total = copy.deepcopy(direct)
    rho = [reflectance(model, p) for p in model["patches"]]
    frontier = [[row[c] * rho[i][c] for c in range(3)] for i, row in enumerate(direct)]
    history = [{"incoming": totals(direct), "outgoing": totals(frontier)}]
    for _ in range(bounces):
        incoming = [[sum(frontier[j][c] * f[j][i] for j in range(len(f))) for c in range(3)] for i in range(len(f))]
        frontier = [[row[c] * rho[i][c] for c in range(3)] for i, row in enumerate(incoming)]
        for i in range(len(f)):
            for c in range(3):
                total[i][c] += incoming[i][c]
            if max(frontier[i]) < threshold:
                frontier[i] = [0.0] * 3
        history.append({"incoming": totals(incoming), "outgoing": totals(frontier)})
    irradiance = [[v / p["area"] for v in row] for row, p in zip(total, model["patches"])]
    return {"direct_flux": direct, "total_flux": total, "irradiance": irradiance,
            "energy_by_generation": history, "form_factor_scale": correction,
            "max_row_sum": max(map(sum, f))}


def closed_solution(model):
    """Independent dense linear-system oracle for the infinite-bounce limit."""
    f, _ = form_factors(model)
    direct = direct_flux(model)
    rho = [reflectance(model, p) for p in model["patches"]]
    n = len(f)
    output = [[0.0] * 3 for _ in range(n)]
    for c in range(3):
        matrix = [[(1.0 if i == j else 0.0) - f[j][i] * rho[j][c] for j in range(n)]
                  + [direct[i][c]] for i in range(n)]
        for k in range(n):
            pivot = max(range(k, n), key=lambda i: abs(matrix[i][k]))
            matrix[k], matrix[pivot] = matrix[pivot], matrix[k]
            if abs(matrix[k][k]) < 1e-12:
                raise ValueError("Singular transport system")
            divisor = matrix[k][k]
            matrix[k] = [v / divisor for v in matrix[k]]
            for i in range(n):
                if i == k:
                    continue
                scale = matrix[i][k]
                matrix[i] = [a - scale * b for a, b in zip(matrix[i], matrix[k])]
        for i in range(n):
            output[i][c] = matrix[i][-1]
    return output


def room_fixture(grid=4):
    model = {"schema": 1, "materials": {
        "neutral": {"absorption_code": 200, "tint_linear": [1.0, 1.0, 1.0]},
        "red": {"absorption_code": 150, "tint_linear": [1.0, 0.025, 0.025]},
    }, "lights": [{"position": [-0.25, 1.2, 0.25], "radius": 6.0, "power_rgb": [40.0, 40.0, 40.0]}],
        "blockers": [], "patches": []}
    # Every visible surface is a Sprite3D quad. No source mesh is required.
    for surface in ["floor", "back", "red", "right"]:
        for v in range(grid):
            for u in range(grid):
                x = -1 + (u + 0.5) * 2 / grid
                z = -1 + (v + 0.5) * 2 / grid
                y = (v + 0.5) * 1.5 / grid
                position, normal, size = {
                    "floor": ([x, 0, z], [0, 1, 0], [2 / grid, 2 / grid]),
                    "back": ([x, y, -1], [0, 0, 1], [2 / grid, 1.5 / grid]),
                    "red": ([-1, y, x], [1, 0, 0], [2 / grid, 1.5 / grid]),
                    "right": ([1, y, x], [-1, 0, 0], [2 / grid, 1.5 / grid]),
                }[surface]
                model["patches"].append({"position": position, "normal": normal,
                    "area": size[0] * size[1], "size": size, "gray_mean": 0.8,
                    "material": "red" if surface == "red" else "neutral", "surface": surface})
    validate(model)
    return model


def scenario(base, name):
    m = copy.deepcopy(base)
    bounces = 2
    if name == "direct":
        bounces = 0
    elif name == "absorbing":
        m["materials"]["red"]["absorption_code"] = 980
    elif name == "blocked":
        m["blockers"] = [[[-0.62, -0.02, -1.02], [-0.58, 1.52, 1.02]]]
    elif name == "moved":
        m["lights"][0]["position"] = [0.65, 0.6, 0.5]
    elif name == "cool":
        m["lights"][0]["power_rgb"] = [8.0, 20.0, 40.0]
    elif name != "bounce":
        raise ValueError(name)
    return m, bounces


def write_reference(destination):
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    base = room_fixture()
    (destination / "lie11-room.json").write_text(json.dumps(base, indent=2) + "\n")
    result = {"schema": 1, "reference": "independent Python float64; finite-patch diffuse model", "scenarios": {}}
    for name in ["direct", "bounce", "absorbing", "blocked", "moved", "cool"]:
        m, b = scenario(base, name)
        result["scenarios"][name] = solve(m, b)
    closed = closed_solution(base)
    truncated = result["scenarios"]["bounce"]["total_flux"]
    result["two_bounce_relative_l1_error_vs_infinite"] = sum(abs(a - b) for x, y in zip(closed, truncated) for a, b in zip(x, y)) / sum(map(sum, closed))
    (destination / "lie11-reference.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"patches": len(base["patches"]), "two_bounce_relative_l1_error_vs_infinite": result["two_bounce_relative_l1_error_vs_infinite"]}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="gpu_compute/fixtures")
    args = parser.parse_args()
    write_reference(args.out)
