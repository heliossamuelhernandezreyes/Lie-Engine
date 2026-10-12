"""Shared-boundary facial slots, independent of Blender and capture cameras.

Every variant keeps the same boundary IDs and an unchanged collar. Ownership
is exclusive per slot; extra capture angles cannot repair a mismatched seam.
"""
from collections import Counter, defaultdict
import math


def nose_slot(points, triangles, regions):
    selected = []
    for i, tri in enumerate(triangles):
        center = [sum(points[k][a] for k in tri)/3 for a in range(3)]
        t=min(max((center[1]-.278)/.017,0),1);width=.027-.017*t*t*(3-2*t)
        # Narrow the upper bridge before reaching either inner eye corner.
        # A nasal slot must not cut through the orbital attachment collar.
        if ((center[0]/width)**2+((center[1]-.273)/.035)**2 < 1
                and center[2] > .062 and not any(regions[k] for k in tri)):
            selected.append(i)
    # Include complete incident fans at pinched vertices. The resulting slot
    # must have closed boundaries before any module is captured. The scanned
    # nostril interior can add a second attachment loop.
    for _ in range(30):
        edges = Counter(tuple(sorted((triangles[i][j], triangles[i][(j+1)%3])))
                        for i in selected for j in range(3))
        boundary = [edge for edge, count in edges.items() if count == 1]
        neighbors = defaultdict(list)
        for a, b in boundary:
            neighbors[a].append(b); neighbors[b].append(a)
        pinched = {k for k, n in neighbors.items() if len(n) != 2}
        if not pinched:
            break
        selected = sorted(set(selected) | {i for i, tri in enumerate(triangles) if any(k in pinched for k in tri)})
    if not selected or pinched:
        raise ValueError('Nose slot has a pinched or empty boundary')
    if any(regions[k] for i in selected for k in triangles[i]):
        raise ValueError('Nose slot intrudes into a moving eyelid')
    unused=set(neighbors);boundary=[]
    while unused:
        start=min(unused);loop=[start];previous=None;current=start
        while True:
            following=next(k for k in neighbors[current] if k!=previous)
            if following==start:break
            if following in loop:raise ValueError('Nose slot boundary self-intersects')
            loop.append(following);previous,current=current,following
        unused.difference_update(loop);boundary.extend(loop)
    vertices = sorted({k for i in selected for k in triangles[i]})
    return selected, boundary, vertices


def nose_variants(points, triangles, selected, boundary, indices):
    """Flatten only the nose slot and derive three compatible closed surfaces.

    Harmonic depth supplies a featureless filler that meets the scanned face.
    A collar of source vertices also preserves boundary tangents and normals.
    """
    graph = defaultdict(set)
    for i in selected:
        for k in triangles[i]:
            graph[k].update(set(triangles[i])-{k})
    distance = {k: 0 for k in boundary}; frontier = set(boundary)
    for step in range(1, 1000):
        frontier = {q for k in frontier for q in graph[k] if q not in distance}
        if not frontier:
            break
        distance.update({k: step for k in frontier})
    if set(distance) != set(indices):
        raise ValueError('Disconnected nose slot')
    collar = {k for k in indices if distance[k] <= 2}
    depth = {k: points[k][2] for k in indices}
    interior = [k for k in indices if k not in collar]
    for _ in range(900):
        next_depth = {k: sum(depth[q] for q in graph[k])/len(graph[k]) for k in interior}
        delta = max((abs(depth[k]-v) for k, v in next_depth.items()), default=0)
        depth.update(next_depth)
        if delta < 1e-9:
            break
    result = []
    for variant in range(4):
        coordinates = {}
        for k in indices:
            x, y, z = points[k]
            t = min(max((distance[k]-2)/7, 0), 1); blend = t*t*(3-2*t)
            relief = z-depth[k]
            if variant == 0:
                z -= blend*relief
            elif variant == 2:  # Shorter projection, softly lifted tip.
                z -= blend*max(relief, 0)*.36
                y += blend*.003*math.exp(-((y-.261)/.015)**2)
            elif variant == 3:  # Wider wings, retained bridge and collar.
                x += blend*x*.24*math.exp(-((y-.259)/.020)**2)
                z += blend*.0025*math.exp(-(x/.017)**2-((y-.260)/.012)**2)
            coordinates[k] = (x, y, z)
        result.append(coordinates)
    return result, sorted(collar)
