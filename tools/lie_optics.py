"""LIE-13 float64 thin dielectric reference. Coordinates and thickness in metres.

Exact unpolarized interface Fresnel/Snell + Beer absorption. Two-interface
slab truncates internal reflections after the first return; no caustic solver.
"""
import math


def fresnel(cosine, eta_i=1.0, eta_t=1.5):
    if not all(math.isfinite(v) and v > 0 for v in (eta_i, eta_t)):
        raise ValueError("Positive finite indices required")
    c = min(1.0, max(0.0, abs(cosine)))
    sin2 = (eta_i / eta_t)**2 * (1 - c*c)
    if sin2 >= 1: return 1.0, 0.0
    ct = math.sqrt(1 - sin2)
    rs = (eta_i*c - eta_t*ct) / (eta_i*c + eta_t*ct)
    rp = (eta_t*c - eta_i*ct) / (eta_t*c + eta_i*ct)
    return (rs*rs + rp*rp) / 2, ct


def slab(cosine, ior, thickness, sigma):
    if not math.isfinite(thickness) or thickness < 0 or len(sigma) != 3 or any(not math.isfinite(s) or s < 0 for s in sigma):
        raise ValueError("Nonnegative finite thickness and absorption required")
    f, ct = fresnel(cosine, 1, ior)
    attenuation = [math.exp(-s * thickness / max(ct, 1e-6)) for s in sigma]
    transmission = [(1-f)**2 * a for a in attenuation]
    reflection = [f + (1-f)**2 * a*a * f for a in attenuation]
    return {"interface_fresnel": f, "cos_transmitted": ct,
            "transmission": transmission, "reflection": reflection,
            "absorbed_or_untraced": [1-r-t for r, t in zip(reflection, transmission)]}


def validate_sheets(sheets):
    if len(sheets) > 16: raise ValueError("At most 16 thin transport sheets")
    for s in sheets:
        for key in ("center", "right", "up", "sigma"):
            if len(s[key]) != 3 or not all(math.isfinite(v) for v in s[key]): raise ValueError("Invalid sheet vectors")
        dot = lambda a, b: sum(x*y for x, y in zip(a, b))
        if abs(dot(s["right"], s["right"]) - 1) > 1e-5 or abs(dot(s["up"], s["up"]) - 1) > 1e-5 or abs(dot(s["right"], s["up"])) > 1e-5:
            raise ValueError("Orthonormal sheet basis required")
        if not all(math.isfinite(s[k]) and s[k] > 0 for k in ("half_width", "half_height", "ior")):
            raise ValueError("Positive finite sheet dimensions and IOR required")
        slab(1, s["ior"], s["thickness"], s["sigma"])


def sheet_transmission(a, b, sheets):
    value = [1.0]*3
    delta = [y-x for x, y in zip(a, b)]
    length = math.sqrt(sum(d*d for d in delta))
    if length < 1e-10: return value
    dot = lambda x, y: sum(i*j for i, j in zip(x, y))
    for sheet in sheets:
        r, u = sheet["right"], sheet["up"]
        n = [r[1]*u[2]-r[2]*u[1], r[2]*u[0]-r[0]*u[2], r[0]*u[1]-r[1]*u[0]]
        denom = dot(delta, n)
        if abs(denom) < 1e-8: continue
        t = dot([c-x for c, x in zip(sheet["center"], a)], n) / denom
        if not .001 < t < .999: continue
        local = [x+t*d-c for x, d, c in zip(a, delta, sheet["center"])]
        if abs(dot(local, r)) > sheet["half_width"] or abs(dot(local, u)) > sheet["half_height"]: continue
        transmission = slab(abs(denom)/length, sheet["ior"], sheet["thickness"], sheet["sigma"])["transmission"]
        value = [x*y for x, y in zip(value, transmission)]
    return value
