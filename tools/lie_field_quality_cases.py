"""Acceptance scenes: exact area subdivision, same-source paths and blockers."""
import copy
import json
import math
from pathlib import Path
import numpy as np
from lie_light_field import fixture_cases, sources, unit
from lie_light_transport import form_factors
from lie_field_quality import solve
ROOT = Path(__file__).resolve().parents[1]


def partition_model(split):
    area = .004**2
    points = [[x, 0, z] for x in (-.001, .001) for z in (-.001, .001)] if split else [[0, 0, 0]]
    mats = {'white': {'absorption_code': 0, 'tint_linear': [1, 1, 1], 'albedo': [1, 1, 1], 'roughness': 1, 'ior': 1},
            'black': {'absorption_code': 1000, 'tint_linear': [1, 1, 1], 'albedo': [0, 0, 0], 'roughness': 1, 'ior': 1}}
    return {'schema': 1, 'materials': mats, 'lights': [{'position': [0, 1, 0], 'radius': 100, 'power_rgb': [4*math.pi*.1/area]*3}],
            'patches': [{'position': p, 'normal': [0, 1, 0], 'area': area/len(points), 'gray_mean': 1, 'material': 'white'} for p in points]+
                       [{'position': [0, 4, 0], 'normal': [0, -1, 0], 'area': .1, 'gray_mean': 1, 'material': 'black'}],
            'blockers': [], 'bounces': 1, 'secondary_radii': {'mode': 'irradiance', 'radius_max': 6, 'radius_decay': 1, 'irradiance_cutoff': .1/(math.pi*36)},
            'field_quality': {'angular_sectors': 6, 'area_budget': True, 'reference_area': area}}


def paths_model():
    positions = [[-1, 0, 1], [1, 0, 1], [0, 0, 0], [-2, 0, 2], [2, 0, 2], [0, 0, 2]]
    normals = [[1, 0, 0], [-1, 0, 0], [0, 0, 1], unit([1, 0, -1]).tolist(), unit([-1, 0, -1]).tolist(), [0, 0, -1]]
    mats = {k: {'absorption_code': 1000 if k == 'receiver' else 0, 'tint_linear': [1, 1, 1], 'albedo': [1, 1, 1],
                'roughness': .1 if k == 'mirror' else 1, 'ior': 1 if k != 'mirror' else 1.5, 'metallic': 1 if k == 'mirror' else 0}
            for k in ('diffuse', 'mirror', 'receiver')}
    model = {'schema': 1, 'materials': mats, 'lights': [{'position': [0, 0, 3], 'radius': 10, 'power_rgb': [20, 10, 5]}],
             'patches': [{'position': p, 'normal': n, 'area': .1, 'gray_mean': 1, 'material': 'mirror' if i == 2 else 'diffuse' if i < 2 else 'receiver'}
                         for i, (p, n) in enumerate(zip(positions, normals))], 'blockers': [], 'bounces': 2}
    F = np.zeros((6, 6)); F[0, 2] = F[1, 2] = .1
    F[2, 3] = F[2, 4] = .1*math.sqrt(.5); F[2, 5] = .1
    return model, F


def cases():
    result = {}
    def add(name, model, packets=None):
        m = copy.deepcopy(model)
        if packets is None: packets = sources(m, form_factors(m)[0])
        result[name] = {'model': m, 'sources_hex': {k: v.hex() for k, v in packets.items()},
                        'separate': True, 'output': solve(m, packets)}
    for name, c in fixture_cases().items():
        if not c['separate']: continue
        m = copy.deepcopy(c['model']); m['field_quality'] = {'angular_sectors': 1, 'area_budget': False}
        add('legacy_'+name, m, {k: bytes.fromhex(v) for k, v in c['sources_hex'].items()})
    for split in (False, True):
        m = partition_model(split); add('partition_'+('four' if split else 'one'), m)
        m['field_quality']['area_budget'] = False; add('old_cutoff_'+('four' if split else 'one'), m)
    m, F = paths_model(); packets = sources(m, F)
    add('paths_six', m, packets)
    m['field_quality'] = {'angular_sectors': 1}; add('paths_one', m, packets)
    m['field_quality'] = {'angular_sectors': 6, 'dynamic_occluders': [[[.35, -.1, .35], [.65, .1, .65]]], 'visibility_revision': 1}
    add('paths_blocked', m, packets)
    m['field_quality'] = {'angular_sectors': 6, 'visibility_revision': 2}; add('paths_restored', m, packets)
    return result


def prepare():
    data = {'schema': 'lie-field-quality-reference/1', 'reference': 'float64 source/sector scatter', 'cases': cases()}
    path = ROOT/'gpu_compute/fixtures/field-quality-reference.json'; path.parent.mkdir(exist_ok=True)
    path.write_text(json.dumps(data, indent=2)+'\n')
    return data


if __name__ == '__main__': print(json.dumps({'cases': len(prepare()['cases'])}))
