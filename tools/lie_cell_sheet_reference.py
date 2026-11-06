"""Analytic finite-cell reference independent of the legacy DDA traversal.

Enumerate every occupied sheet in a conservative transverse rectangle covering
the ray's AABB segment, then test its plane and half-open support directly.
This is a reference for captured cells, NEVER original source-mesh geometry.
"""
from __future__ import annotations

import hashlib
import json
from fractions import Fraction
from pathlib import Path

import numpy as np


def rational_support(view, packet, pixel, size, face, cell, source_depth, rect_wh):
    """Exact rational witness for one sheet, from the original FP32 packets.

    Tests support, not global nearestness. Uses an unnormalised camera ray so
    every input and operation remains rational; no epsilon or FP64 predicate.
    """
    f = lambda x: Fraction(float(x))
    x, y = pixel
    sx, sy = Fraction(2*x+1, size)-1, Fraction(2*y+1, size)-1
    inv = np.asarray(packet)[16:32].reshape(4, 4).T
    eye = [sum(f(inv[i, j])*f(view[j]) for j in range(3))+f(inv[i, 3]) for i in range(3)]
    world_ray = [f(view[12+j])+(f(view[4+j])*sx-f(view[8+j])*sy)*f(view[18]) for j in range(3)]
    ray = [sum(f(inv[i, j])*world_ray[j] for j in range(3)) for i in range(3)]
    lo, hi = list(map(f, packet[32:35])), list(map(f, packet[36:39]))
    axis = face//2
    if ray[axis] == 0:
        return {'inside': False, 'parallel': True}
    plane = hi[axis]-f(source_depth) if face % 2 == 0 else lo[axis]+f(source_depth)
    t = (plane-eye[axis])/ray[axis]
    axes = [j for j in range(3) if j != axis]
    fractions = [(eye[u]+ray[u]*t-lo[u])*dim/(hi[u]-lo[u])-c
                 for u, dim, c in zip(axes, rect_wh, cell)]
    return {'inside': bool(t > 0 and all(0 <= v < 1 for v in fractions)),
            'support_fraction': [float(v) for v in fractions],
            'scope': 'exact rational plane/support witness; not a global first-hit proof'}


class CellSheetReference:
    def __init__(self, bank: Path):
        root = Path(bank) / 'direct'
        self.proof = json.loads((root / 'surface.json').read_text())
        for name in ('depth.bin', 'normal.bin'):
            raw = (root / name).read_bytes()
            meta = self.proof['packets'][name]
            if len(raw) != meta['bytes'] or hashlib.sha256(raw).hexdigest() != meta['sha256']:
                raise ValueError('Captured packet identity: ' + name)
        h, w, layers = (self.proof[k] for k in ('height', 'width', 'layers'))
        self.depth = np.fromfile(root / 'depth.bin', '<f4').reshape(h, w, layers)
        self.normal = np.fromfile(root / 'normal.bin', '<f2').reshape(layers, h, w, 4)
        if not np.isfinite(self.depth).all() or not np.isfinite(self.normal).all():
            raise ValueError('Nonfinite captured cells')

    def candidates(self, eye, direction, packet, instance, *, details=False):
        """Return valid intersections for ONE ray/instance, with no DDA steps."""
        q = np.asarray(packet, dtype=np.float64)
        inv = q[16:32].reshape(4, 4).T
        o = inv[:3, :3] @ eye + inv[:3, 3]
        r = inv[:3, :3] @ direction
        lo, hi = q[32:35], q[36:39]
        parallel = r == 0
        if np.any(parallel & ((o < lo) | (o > hi))):
            return []
        near = np.full(3, -np.inf)
        far = np.full(3, np.inf)
        near[~parallel] = np.minimum((lo[~parallel]-o[~parallel])/r[~parallel],
                                     (hi[~parallel]-o[~parallel])/r[~parallel])
        far[~parallel] = np.maximum((lo[~parallel]-o[~parallel])/r[~parallel],
                                    (hi[~parallel]-o[~parallel])/r[~parallel])
        start, end = max(float(near.max()), 0.), float(far.min())
        if end < start:
            return []
        axis = int(near.argmax())
        if r[axis] == 0:
            return []
        fi = axis*2 + int(r[axis] > 0)
        # meta.x is the shader face-table offset stored as uint bits, not float.
        face_offset = int(np.asarray(packet, dtype='<f4')[44:45].view('<u4')[0])
        rect = self.proof['faces'][face_offset + fi]
        w, h = rect['width'], rect['height']
        axes = [k for k in range(3) if k != axis]
        cell_size = (hi[axes]-lo[axes]) / [w, h]
        ends = np.array([o+r*start, o+r*end])[:, axes]
        uv = (ends-lo[axes])/cell_size
        # Deliberately include a neighbouring cell at both ends. This broad
        # phase may overselect; exact half-open support below decides the hit.
        low = np.maximum(np.floor(uv.min(axis=0)).astype(int)-1, 0)
        high = np.minimum(np.floor(uv.max(axis=0)).astype(int)+1, [w-1, h-1])
        if np.any(high < low):
            return []
        xs, ys = np.meshgrid(np.arange(low[0], high[0]+1),
                             np.arange(low[1], high[1]+1))
        depths = self.depth[ys+rect['y'], xs+rect['x']]
        cy, cx, layer = np.nonzero(depths >= 0)
        x, y = xs[cy, cx], ys[cy, cx]
        d = depths[cy, cx, layer].astype(np.float64)
        plane = hi[axis]-d if fi % 2 == 0 else lo[axis]+d
        t = (plane-o[axis])/r[axis]
        points = o[axes] + t[:, None]*r[axes]
        delta = (points-lo[axes])/cell_size - np.c_[x, y]
        inside = (delta >= 0).all(axis=1) & (delta < 1).all(axis=1)
        valid = inside & (t >= start) & (t <= end) & (t > 0)
        selected = np.flatnonzero(valid)
        selected = selected[np.argsort(t[selected], kind='stable')]
        result = []
        for k in selected:
            owner = float(self.normal[layer[k], y[k]+rect['y'], x[k]+rect['x'], 3])+q[42]+1
            hit = {'t': float(t[k]), 'owner': int(owner), 'instance': int(instance),
                   'face': fi, 'cell': [int(x[k]), int(y[k])], 'layer': int(layer[k])}
            if details:
                hit.update(depth=float(d[k]), support_fraction=delta[k].tolist(),
                           world=(np.asarray(eye)+direction*t[k]).tolist())
            result.append(hit)
        return result

    def trace(self, eye, directions, proxies, *, details=False):
        eye = np.asarray(eye, dtype=np.float64)
        directions = np.asarray(directions, dtype=np.float64)
        proxies = np.asarray(proxies, dtype='<f4')
        n = len(directions)
        best = np.full(n, np.inf)
        owners = np.zeros(n, dtype=np.int64)
        witnesses = [[] for _ in range(n)] if details else None
        for instance, packet in enumerate(proxies):
            inv = packet[16:32].reshape(4, 4).T.astype(np.float64)
            o = inv[:3, :3] @ eye + inv[:3, 3]
            r = directions @ inv[:3, :3].T
            lo, hi = packet[32:35].astype(float), packet[36:39].astype(float)
            safe = np.where(r == 0, 1., r)
            near = np.minimum((lo-o)/safe, (hi-o)/safe)
            far = np.maximum((lo-o)/safe, (hi-o)/safe)
            near[r == 0] = -np.inf
            far[r == 0] = np.inf
            possible = ~np.any((r == 0) & ((o < lo) | (o > hi)), axis=1)
            start, end = np.maximum(near.max(axis=1), 0.), far.min(axis=1)
            ids = np.flatnonzero(possible & (end >= start) & (start <= best))
            for i in ids:
                hits = self.candidates(eye, directions[i], packet, instance, details=details)
                if details:
                    witnesses[i].extend(hits)
                if hits and hits[0]['t'] < best[i]:
                    best[i], owners[i] = hits[0]['t'], hits[0]['owner']
        if details:
            for hits in witnesses:
                hits.sort(key=lambda a: a['t'])
        return best, owners, witnesses
