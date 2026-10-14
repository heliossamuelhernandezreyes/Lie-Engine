"""LIE-35 opt-in directional optical transport: independent float64 reference.

Small-N source -> receiver demonstrator. Not a photon tracer, GGX solver,
production light cache, or replacement for existing LIE-11 node transport.
A finite-radius weighted angular redistribution with per-channel passive
energy budgets. All scene units are metres; RGB powers are relative.
"""
import json
import math
from pathlib import Path

PI = math.pi
EPS = 1e-10


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def normal(a):
    d = math.sqrt(dot(a, a))
    if d < EPS or not math.isfinite(d):
        raise ValueError("Invalid direction")
    return [x / d for x in a]


def sub(a, b):
    return [a[i] - b[i] for i in range(3)]


def reflect(direction, normal_vector):
    t = 2.0 * dot(direction, normal_vector)
    return [direction[i] - t * normal_vector[i] for i in range(3)]


def refract(direction, n, ior):
    eta = 1.0 / ior
    cosi = max(0.0, -dot(direction, n))
    k = 1.0 - eta * eta * (1.0 - cosi * cosi)
    if k < 0.0:
        return None
    return normal([eta * direction[i] + (eta * cosi - math.sqrt(k)) * n[i] for i in range(3)])


def effective_radius(power, irradiance_cutoff=0.001, radius_max=6.0,
                     parent_radius=6.0, radius_decay=0.82, scale=1.0):
    if min(irradiance_cutoff, radius_max, parent_radius) <= 0 or not 0 <= radius_decay <= 1 or not 0 <= scale <= 1:
        raise ValueError("Invalid energy-radius policy")
    if len(power) != 3 or any(not math.isfinite(x) or x < 0 for x in power):
        raise ValueError("Invalid power")
    return min(parent_radius * radius_decay,
               math.sqrt(max(power) / (PI * irradiance_cutoff)),
               radius_max) * scale


def budgets(emitter):
    n = normal(emitter["normal"])
    incoming = normal(emitter["incident"])
    if dot(n, incoming) >= -EPS:
        return [[0.0] * 3 for _ in range(3)], n, incoming, None
    tint = emitter["albedo"]
    metallic, trans, ior = emitter["metallic"], emitter["transmission"], emitter["ior"]
    rough = emitter["roughness"]
    if not 0.025 <= rough <= 1.0 or not 0 <= metallic <= 1 or not 0 <= trans <= 1 or not 1 <= ior <= 3:
        raise ValueError("Invalid optical material")
    if len(tint) != 3 or any(not math.isfinite(x) or not 0 <= x <= 1 for x in tint):
        raise ValueError("Invalid albedo")
    sigma = emitter["sigma"]
    thickness = emitter["thickness"]
    if not 0 <= thickness or not math.isfinite(thickness) or len(sigma) != 3 or any(not math.isfinite(x) or x < 0 for x in sigma):
        raise ValueError("Invalid extinction")
    transmitted_dir = refract(incoming, n, ior)
    cosi = min(1, -dot(incoming, n))
    f_dielectric = ((ior - 1) / (ior + 1)) ** 2
    f0 = [metallic * tint[k] + (1 - metallic) * f_dielectric for k in range(3)]
    fresnel = [f0[k] + (1 - f0[k]) * (1 - cosi) ** 5 for k in range(3)]
    if transmitted_dir is None:
        fresnel = [1.0] * 3
    cost = 1.0 if transmitted_dir is None else max(-dot(transmitted_dir, n), 0.001)
    diffuse = [(1 - metallic) * (1 - trans) * (1 - fresnel[k]) * tint[k] for k in range(3)]
    specular = fresnel
    transmitted = [(1 - metallic) * trans * (1 - fresnel[k]) *
                   math.exp(-sigma[k] * thickness / cost) if transmitted_dir is not None else 0.
                   for k in range(3)]
    # A fail-safe against accidental nonpassive parameter combinations.
    for k in range(3):
        cap = max(1.0, diffuse[k] + specular[k] + transmitted[k])
        diffuse[k] /= cap
        specular[k] /= cap
        transmitted[k] /= cap
    return [diffuse, specular, transmitted], n, incoming, transmitted_dir


def link_weights(emitter, receiver):
    energy, n, incidence, transmitted = budgets(emitter)
    direction = sub(receiver["position"], emitter["position"])
    d2 = dot(direction, direction)
    radius = emitter["radius"]
    if d2 <= EPS or radius <= 0 or d2 >= radius * radius:
        return [0., 0., 0.]
    distance = math.sqrt(d2)
    out = [v / distance for v in direction]
    face = max(dot(normal(receiver["normal"]), [-v for v in out]), 0)
    if face <= 0 or receiver["area"] <= 0 or not receiver.get("visible", True):
        return [0., 0., 0.]
    decay = (max(0., 1. - (distance / radius) ** 4)) ** 2
    geometry = receiver["area"] * face * decay / (4 * PI * max(d2, 0.0025))
    mirrored = normal(reflect(incidence, n))
    expo = min(2048., max(1., 2 / (emitter["roughness"] ** 2) - 2))
    diff = max(dot(n, out), 0)
    glossy = max(dot(mirrored, out), 0) ** expo if diff > 0 else 0
    travel = max(dot(transmitted, out), 0) ** max(1., expo * 0.5) if transmitted is not None and dot(n, out) < 0 else 0
    return [geometry * diff, geometry * glossy, geometry * travel]


def propagate(emitters, receivers):
    if not (1 <= len(emitters) <= 128 and 1 <= len(receivers) <= 128):
        raise ValueError("Prototype supports at most 128 sources/receivers")
    output = [[0.0, 0.0, 0.0] for _ in receivers]
    for emitter in emitters:
        power = emitter["power"]
        if len(power) != 3 or any(not math.isfinite(x) or x < 0 for x in power):
            raise ValueError("Invalid source power")
        parts, _, _, _ = budgets(emitter)
        weights = [link_weights(emitter, dst) for dst in receivers]
        caps = [max(1., sum(w[k] for w in weights)) for k in range(3)]
        for j, w in enumerate(weights):
            for color in range(3):
                output[j][color] += power[color] * sum(
                    parts[k][color] * w[k] / caps[k] for k in range(3))
    for color in range(3):
        received = sum(row[color] for row in output)
        incoming = sum(src["power"][color] for src in emitters)
        if received > incoming + 1e-7:
            raise AssertionError("Energy creation")
    return output


def receiver(position, area=3.0):
    return {"position":position,"normal":normal([-x for x in position]),"area":area,"visible":True}


def source(material, **changes):
    base = {
        "position":[0.,0.,0.], "normal":[0.,0.,1.],
        "incident":[0.6,0.,-0.8], "albedo":[0.7,0.45,0.3],
        "roughness":0.65, "metallic":0., "transmission":0.,
        "ior":1.5, "sigma":[0.,0.,0.], "thickness":0.02,
        "power":[2.,2.,2.], "radius":3.0
    }
    if material == "metal":
        base.update(albedo=[0.92,0.75,0.3],roughness=0.16,metallic=1.)
    if material == "glass":
        base.update(albedo=[1.,1.,1.],roughness=0.18,metallic=0.,transmission=1.,
                    sigma=[8.,1.5,0.2],thickness=0.07)
    base.update(changes)
    return base


def fixtures():
    receivers = [receiver([.75,0.,1.]),receiver([-.75,0.,1.]),receiver([0.,0.,-1.2])]
    return {
        "brick":{"emitters":[source("brick")],"receivers":receivers},
        "metal":{"emitters":[source("metal")],"receivers":receivers},
        "glass":{"emitters":[source("glass")],"receivers":receivers},
        "absorbing":{"emitters":[source("brick",albedo=[0.06]*3)],"receivers":receivers},
        "near_cutoff":{"emitters":[source("metal",radius=.9)],"receivers":receivers},
        "mixed":{"emitters":[source("brick"),source("glass",power=[.2,.4,.6])],"receivers":receivers},
    }


def write_reference(path):
    cases = fixtures()
    report = {}
    for name, c in cases.items():
        output = propagate(c["emitters"], c["receivers"])
        report[name] = {
            **c, "output":output,
            "incoming_total":[sum(s["power"][k] for s in c["emitters"]) for k in range(3)],
            "received_total":[sum(row[k] for row in output) for k in range(3)]
        }
    target = Path(path)
    target.parent.mkdir(parents=True,exist_ok=True)
    target.write_text(json.dumps({"schema":"lie35-angular/1","cases":report},
                                 indent=2,sort_keys=True) + "\n")
    return report


if __name__=="__main__":
    target=Path(__file__).resolve().parents[1]/"gpu_compute/fixtures/lie35-directional-reference.json"
    report=write_reference(target)
    for name, r in report.items():
        print(name, "power",r["received_total"],"incoming",r["incoming_total"])
