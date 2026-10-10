"""Float64 geometry oracle for LIE-14 rigid masters; no rendering dependency.

The six-face perception box is a bound, not a shadow/collision cylinder.
Only rigid transforms are accepted. Light remains the LIE-11/13 approximation.
"""
import math


def dot(a, b):
    return sum(x*y for x, y in zip(a, b))


def transform(p, columns, origin=(0, 0, 0)):
    return [origin[k]+sum(columns[j][k]*p[j] for j in range(3)) for k in range(3)]


def inverse(p, columns, origin):
    q = [p[k]-origin[k] for k in range(3)]
    return [dot(c, q) for c in columns]


def rotation_z(angle):
    c, s = math.cos(angle), math.sin(angle)
    return [[c, s, 0], [-s, c, 0], [0, 0, 1]]


def rotation_x(angle):
    c, s = math.cos(angle), math.sin(angle)
    return [[1, 0, 0], [0, c, s], [0, -s, c]]


def compose(a, b):
    return [transform(c, a) for c in b]


def skeleton(angles, length=1.2):
    if len(angles) != 3 or any(not math.isfinite(a) or abs(a) > 2.1 for a in angles):
        raise ValueError("Three finite joint angles in [-2.1,2.1] required")
    columns = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
    pivot = [-.65, -1, 0]
    output = []
    for i, angle in enumerate(angles):
        columns = compose(columns, rotation_z(angle))
        if i == 2:
            columns = compose(columns, rotation_x(.3))
        center = transform([0, length*.5, 0], columns, pivot)
        output.append({"basis": [c[:] for c in columns], "origin": center,
                       "radius": .18, "half_height": length*.5})
        pivot = transform([0, length, 0], columns, pivot)
    return output


def cylinder_blocked(a, b, instances):
    """Intersect open segment with a closed analytic cylinder in local space.

    Interval clipping differs from GPU's side/cap root enumeration, providing
    an independent visibility check. Endpoint margins prevent self hits.
    """
    for instance in instances:
        p = inverse(a, instance["basis"], instance["origin"])
        q = inverse(b, instance["basis"], instance["origin"])
        d = [q[k]-p[k] for k in range(3)]
        low, high = .001, .999
        half, radius = instance["half_height"], instance["radius"]
        if abs(d[1]) < 1e-12:
            if abs(p[1]) > half:
                continue
        else:
            u, v = (-half-p[1])/d[1], (half-p[1])/d[1]
            low, high = max(low, min(u, v)), min(high, max(u, v))
        aa = d[0]**2+d[2]**2
        bb = 2*(p[0]*d[0]+p[2]*d[2])
        cc = p[0]**2+p[2]**2-radius**2
        if aa < 1e-14:
            if cc > 0:
                continue
        else:
            disc = bb*bb-4*aa*cc
            if disc < 0:
                continue
            root = math.sqrt(disc)
            low = max(low, (-bb-root)/(2*aa))
            high = min(high, (-bb+root)/(2*aa))
        if low <= high:
            return True
    return False


def cylinder_patches(radius=.18, length=1.2):
    patches = []
    for band in range(2):
        for sector in range(8):
            a = (sector+.5)*math.tau/8
            n = [math.cos(a), 0, math.sin(a)]
            patches.append({"position": [radius*n[0], (band-.5)*length/2, radius*n[2]],
                            "normal": n, "area": math.tau*radius*length/16, "gray_mean": .8})
    for sign in [-1, 1]:
        patches.append({"position": [0, sign*length/2, 0], "normal": [0, sign, 0],
                        "area": math.pi*radius*radius, "gray_mean": .8})
    return patches


def patch_id(p, n):
    if abs(n[1]) > .8:
        return 16 if n[1] < 0 else 17
    sector = int((math.atan2(p[2], p[0]) % math.tau)*8/math.tau) % 8
    return (0 if p[1] < 0 else 1)*8+sector


POSES = {"base": [-.35, 1.1, -.85], "pose": [-.95, 1.7, -.55]}


def scene_model(master, name="bounce"):
    instances = skeleton(POSES["pose" if name == "pose" else "base"])
    patches = []
    for i, instance in enumerate(instances):
        for p in master["patches"]:
            q = dict(p)
            q["position"] = transform(p["position"], instance["basis"], instance["origin"])
            q["normal"] = transform(p["normal"], instance["basis"])
            q["material"] = "red" if i == 1 else "metal"
            patches.append(q)
    # Neutral floor and back wall: analytic planar sprites, sixteen nodes each.
    for wall in [False, True]:
        for row in range(4):
            for col in range(4):
                position = [-2+(col+.5), -1.05, -2+(row+.5)]
                if wall:
                    position = [-2+(col+.5), -1+(row+.5), -2]
                patches.append({"position": position, "normal": [0, 0, 1] if wall else [0, 1, 0],
                                "area": 1, "gray_mean": .7, "material": "room"})
    visibility = []
    for a in patches:
        for b in patches:
            aa = [a["position"][k]+a["normal"][k]*.003 for k in range(3)]
            bb = [b["position"][k]+b["normal"][k]*.003 for k in range(3)]
            visibility.append(int(not cylinder_blocked(aa, bb, instances)))
    n = len(patches)
    for i in range(n):
        visibility[i*n+i] = 0
        for j in range(i+1, n):
            visibility[j*n+i] = visibility[i*n+j]
    model = {"schema": 1, "patches": patches, "factor_normalization": "symmetric_local",
             "materials": {"metal": {"absorption_code": 220, "tint_linear": [.55, .8, 1]},
                           "red": {"absorption_code": 900 if name == "absorbing" else 180, "tint_linear": [1, .12, .08]},
                           "room": {"absorption_code": 300, "tint_linear": [1, 1, 1]}},
             "lights": [{"position": [1.4, 2.2, 1.8] if name == "light" else [-1.6, 2.1, 1.5],
                         "power_rgb": [0, 0, 0] if name == "dark" else [60, 50, 40], "radius": 7}],
             "bounces": 0 if name == "direct" else 2, "blockers": [], "mesh_visibility": visibility,
             "secondary_radii": {"radius_max": 4, "radius_decay": .82, "power_reference": .03}}
    return model, instances
