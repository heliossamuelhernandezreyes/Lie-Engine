"""Float64 scatter oracle for area budgets, angular sectors and moving blockers.

The accepted v1 oracle supplies only direct injection. This solver scatters
each source/sector separately, independently of the GPU receiver gather.
"""
import copy
import math
import struct
import numpy as np
from lie_light_field import decode_csr, hit_box, solve as direct_oracle, unit

DEFAULTS = {'angular_sectors': 6, 'area_budget': True, 'reference_area': 1.,
            'roughness_split': .5, 'dynamic_occluders': [], 'visibility_revision': 0}


def options(model):
    raw = model.get('field_quality', {})
    if not isinstance(raw, dict) or set(raw)-set(DEFAULTS):
        raise ValueError('Unknown field quality option')
    q = copy.deepcopy(DEFAULTS); q.update(raw)
    if type(q['angular_sectors']) not in (int,float) or q['angular_sectors'] not in (1, 6):
        raise ValueError('Angular capacity must be 1 or 6')
    q['angular_sectors']=int(q['angular_sectors'])
    if type(q['area_budget']) is not bool:
        raise ValueError('Area budget must be boolean')
    for k in ('reference_area', 'roughness_split'):
        if type(q[k]) not in (int, float) or not math.isfinite(q[k]):
            raise ValueError('Finite quality parameter required')
    if not 1.17549435e-38 <= q['reference_area'] <= 3.402823466e38 or not 0 <= q['roughness_split'] <= 1:
        raise ValueError('Invalid quality parameter range')
    revision=q['visibility_revision']
    if type(revision) not in (int,float) or not math.isfinite(revision) or int(revision)!=revision or not 0 <= revision <= 0xffffffff:
        raise ValueError('Invalid visibility revision')
    q['visibility_revision']=int(revision)
    if not isinstance(q['dynamic_occluders'],list):raise ValueError('Occluders must be an array')
    for box in q['dynamic_occluders']:
        if not isinstance(box,list) or len(box)!=2:raise ValueError('Box must have two corners')
        for p in box:
            if not isinstance(p,list) or len(p)!=3 or any(type(v) not in (int,float) for v in p):raise ValueError('Box coordinates must be numeric')
    boxes = np.asarray(q['dynamic_occluders'], dtype=float)
    if boxes.size == 0: boxes = boxes.reshape(0, 2, 3)
    if boxes.shape != (len(boxes), 2, 3) or len(boxes) > 16 or not np.isfinite(boxes).all() or not (boxes[:, 0] < boxes[:, 1]).all():
        raise ValueError('Invalid dynamic occluder bounds')
    return q


def packet(model):
    q = options(model); n = len(model['patches'])
    rows = np.zeros((n+32, 4), dtype='<f4')
    rows[:n, 0] = [p['area']/q['reference_area'] for p in model['patches']]
    for i, box in enumerate(q['dynamic_occluders']):
        rows[n+i*2, :3] = box[0]; rows[n+i*2+1, :3] = box[1]
    if not np.isfinite(rows).all() or not (rows[:n, 0] > 0).all():
        raise ValueError('Field policy not representable in float32')
    for i in range(len(q['dynamic_occluders'])):
        if not (rows[n+i*2,:3]<rows[n+i*2+1,:3]).all():raise ValueError('Occluder collapses in float32')
    return struct.pack('<4I4f', q['angular_sectors'], q['area_budget'], len(q['dynamic_occluders']),
                       q['visibility_revision'], q['reference_area'], q['roughness_split'], 0, 0)+rows.tobytes()


def sectors(directions, normals, roughness, q):
    axis = np.tile([0., 0., 1.], (len(normals), 1))
    axis[np.abs(normals[:, 2]) >= .9] = [0., 1., 0.]
    tangent = unit(np.cross(axis, normals)); bitangent = np.cross(normals, tangent)
    local = np.stack([np.sum(directions*tangent, 1), np.sum(directions*bitangent, 1), np.sum(directions*normals, 1)], 1)
    dominant = np.argmax(np.abs(local), axis=1)
    result = dominant*2+(local[np.arange(len(local)), dominant] < 0)
    return np.where((q['angular_sectors'] == 1) | (roughness >= q['roughness_split']), 0, result)


def solve(model, packets, emission_normals=None):
    q = options(model); packet(model)  # Same numerical representability contract.
    p = np.array([v['position'] for v in model['patches']], '<f4').astype(float)
    normal = np.array([v['normal'] for v in model['patches']], '<f4').astype(float)
    area = np.array([v['area'] for v in model['patches']], '<f4').astype(float)
    n = len(p); L = len(model['lights']); B = 6
    optics = np.frombuffer(packets['optics'], '<f4')[4:].reshape(n, 16).astype(float)
    on = unit(optics[:, 12:15]); albedo = optics[:, :3]; rough = optics[:, 3]
    metal = optics[:, 4, None]; ior = optics[:, 6, None]
    absorb = np.array([model['materials'][v['material']]['absorption_code']/1000 for v in model['patches']], '<f4').astype(float)
    rho = np.array([model['materials'][v['material']]['tint_linear'] for v in model['patches']])*(1-absorb[:, None])*np.array([v['gray_mean'] for v in model['patches']])[:, None]
    src, dst, F = decode_csr(packets['outgoing']); delta = p[dst]-p[src]
    distance = np.linalg.norm(delta, axis=1); edge_dir = unit(delta)
    base = np.maximum(np.sum(normal[src]*edge_dir, 1), 1e-6)
    diffuse = np.maximum(np.sum(on[src]*edge_dir, 1), 0)
    edge_bin = sectors(edge_dir, on[dst], rough[dst], q)
    clear = np.ones(len(F), bool)
    for low, high in q['dynamic_occluders']:
        clear &= np.array([not hit_box(a, b, np.array(low), np.array(high)) for a, b in zip(p[src], p[dst])])
    policy = model.get('secondary_radii')

    def parts(travel):
        ci = np.clip(-np.sum(on*travel, 1), 0, 1)[:, None]
        f0 = (1-metal)*((ior-1)/(ior+1))**2+metal*albedo
        fresnel = f0+(1-f0)*(1-ci)**5
        D = (1-metal)*(1-fresnel)*albedo*(1-absorb[:, None]); R = fresnel*(1-absorb[:, None])
        cap = np.maximum(1, D+R)
        return np.where(ci > 1e-8, D/cap, 0), np.where(ci > 1e-8, R/cap, 0)

    def radii(parent, flux, travel):
        if not policy: return np.zeros(n)
        outgoing = sum(flux[:, s]*sum(parts(travel[:, s])) for s in range(B))
        power = outgoing.max(1); share = area/q['reference_area'] if q['area_budget'] else 1
        if policy['mode'] == 'irradiance':
            reach = np.minimum(parent*policy['radius_decay'], np.sqrt(power/(math.pi*policy['irradiance_cutoff']*share)))
        else:
            reach = np.minimum(parent*policy['radius_decay']*np.sqrt(rho.max(1)), policy['radius_max']*np.sqrt(power/(policy['power_reference']*share)))
        return np.minimum(reach, policy['radius_max'])*np.array([model['materials'][v['material']].get('radius_scale', 1) for v in model['patches']])

    incoming = np.zeros((L, n, B, 3)); travel = np.zeros_like(incoming); radius = np.zeros((L, n))
    for l, light in enumerate(model['lights']):
        direct = copy.deepcopy(model); direct['lights'] = [light]; direct['bounces'] = 0
        direct['blockers'] = model.get('blockers', [])+q['dynamic_occluders']
        result = direct_oracle(direct, packets, emission_normals=None if emission_normals is None else [emission_normals[l]])
        flux = np.asarray(result['flux']); direction = unit(p-np.array(light['position'], '<f4'), fallback=-normal)
        bins = sectors(direction, on, rough, q)
        incoming[l, np.arange(n), bins] = flux
        travel[l] = np.broadcast_to(direction[:, None], (n, B, 3))
        radius[l] = radii(np.where(flux.max(1) > 0, light['radius'], 0), incoming[l], travel[l])
    total = incoming.sum(2).copy(); channels = [total.sum(1).tolist()]
    for _ in range(model.get('bounces', 2)):
        next_flux = np.zeros_like(incoming); moment = np.zeros_like(incoming); parent = np.zeros((L, n))
        for l in range(L):
            for s in range(B):
                D, R = parts(travel[l, :, s]); mirror = travel[l, :, s]-2*np.sum(travel[l, :, s]*on, 1)[:, None]*on
                glossy = np.where(diffuse > 0, np.maximum(np.sum(mirror[src]*edge_dir, 1), 0)**np.clip(2/np.maximum(rough[src], .025)**2-2, 1, 2048), 0)
                fade = np.maximum(0, 1-(distance/np.maximum(radius[l, src], 1e-30))**4)**2 if policy else np.ones(len(F))
                weights = F[:, None]*np.stack([diffuse, glossy], 1)/base[:, None]*fade[:, None]*clear[:, None]
                caps = np.zeros((n, 2)); np.add.at(caps, src, weights)
                weights /= np.maximum(caps[src], 1)
                links = incoming[l, src, s]*(D[src]*weights[:, 0, None]+R[src]*weights[:, 1, None])
                np.add.at(next_flux[l], (dst, edge_bin), links)
                np.add.at(moment[l], (dst, edge_bin), edge_dir*links.max(1)[:, None])
                np.maximum.at(parent[l], dst, np.where(links.max(1) > 0, radius[l, src], 0))
        nt = unit(moment, fallback=-normal[None, :, None, :])
        for l in range(L):
            if (next_flux[l].sum((0, 1)) > incoming[l].sum((0, 1))+1e-8).any():
                raise AssertionError('Passive source generation')
            radius[l] = radii(parent[l], next_flux[l], nt[l])
        incoming = next_flux; travel = nt; total += incoming.sum(2); channels.append(incoming.sum((1, 2)).tolist())
    return {'flux': total.sum(0).tolist(), 'frontier': incoming.sum((0, 2)).tolist(),
            'channel_totals_by_generation': channels, 'generation_totals_rgb': np.array(channels).sum(1).tolist(),
            'irradiance': (total.sum(0)/area[:, None]).tolist(), 'last_lobes': incoming.tolist()}
