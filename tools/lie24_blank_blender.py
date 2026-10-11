"""A smooth skin cap replaces nasal folds in the featureless base.

The cap meets the outer scanned contour. Hidden
nostril geometry remains behind it; no original nostril color is baked in.
"""
from collections import Counter, defaultdict
from mathutils import Vector
from mathutils.geometry import delaunay_2d_cdt
from mathutils.bvhtree import BVHTree
from lie20_prepare_blender import srgb


class BlankColor:
    def __init__(self, points, triangles, colors):
        self.points=[Vector((p.x,p.y,0)) for p in points]
        self.triangles=triangles;self.colors=[Vector(c) for c in colors]
        self.bvh=BVHTree.FromPolygons(self.points,triangles,all_triangles=True)
    def at(self, uv):
        hit,_,ti,_=self.bvh.find_nearest(Vector((uv.x,uv.y,0)))
        ids=self.triangles[ti];a,b,c=(self.points[k] for k in ids)
        # Use a float64 signed-area formula for the tiny constrained border
        # triangles; the general capture helper has an absolute area cutoff.
        ax,ay=map(float,a[:2]);bx,by=map(float,b[:2]);cx,cy=map(float,c[:2]);x,y=map(float,hit[:2])
        determinant=(bx-ax)*(cy-ay)-(by-ay)*(cx-ax)
        if abs(determinant)<1e-22:raise ValueError('Degenerate blank color triangle')
        u=((x-ax)*(cy-ay)-(y-ay)*(cx-ax))/determinant
        v=((bx-ax)*(y-ay)-(by-ay)*(x-ax))/determinant
        weights=[max(1-u-v,0),max(u,0),max(v,0)];total=sum(weights);weights=[w/total for w in weights]
        linear=sum((self.colors[k]*w for k,w in zip(ids,weights)),Vector())
        return Vector(tuple(12.92*v if v<=.0031308 else 1.055*max(v,0)**(1/2.4)-.055 for v in linear))


class BlankSpec:
    def at(self, _uv):return Vector((.35,.35,.35))


def blank_nose(rest, triangles, selected, uvs, color):
    edges=Counter(tuple(sorted((triangles[i][j],triangles[i][(j+1)%3]))) for i in selected for j in range(3))
    graph=defaultdict(list)
    for (a,b),count in edges.items():
        if count==1:graph[a].append(b);graph[b].append(a)
    unused=set(graph);loops=[]
    while unused:
        first=min(unused);loop=[first];previous=None;current=first
        while True:
            following=next(k for k in graph[current] if k!=previous)
            if following==first:break
            loop.append(following);previous,current=current,following
        unused.difference_update(loop);loops.append(loop)
    def area(loop):return sum(rest[loop[i]].x*rest[loop[(i+1)%len(loop)]].y-rest[loop[i]].y*rest[loop[(i+1)%len(loop)]].x for i in range(len(loop)))
    boundary=max(loops,key=lambda loop:abs(area(loop)))
    if area(boundary)<0:boundary=boundary[::-1]
    border_colors=[Vector(tuple(srgb(v) for v in color.at(Vector(uvs[k])))) for k in boundary]
    mean_color=sum(border_colors,Vector())/len(border_colors)
    # A radial fan folds over the small concavities of a scanned contour.
    # Constrained triangulation retains every boundary edge and creates a
    # non-overlapping skin patch, including those concave portions.
    planar=[Vector((rest[k].x,rest[k].y)) for k in boundary]
    low=[min(p[a] for p in planar) for a in range(2)];high=[max(p[a] for p in planar) for a in range(2)]
    step=.002
    for ix in range(int((high[0]-low[0])/step)+1):
        for iy in range(int((high[1]-low[1])/step)+1):
            planar.append(Vector((low[0]+(ix+.5)*step,low[1]+(iy+.5)*step)))
    out,_,raw_faces,orig,_,_=delaunay_2d_cdt(planar,[],[list(range(len(boundary)))],1,1e-9)
    used=sorted({k for tri in raw_faces for k in tri});remap={k:i for i,k in enumerate(used)}
    faces=[tuple(remap[k] for k in tri) for tri in raw_faces]
    if any(len(tri)!=3 for tri in faces):raise ValueError('Blank cap must be triangulated')
    points=[];colors=[];source_ids=[];extras=[];fixed=set()
    mean_depth=sum(rest[k].z for k in boundary)/len(boundary)
    for local,k in enumerate(used):
        candidates=[j for j in orig[k] if j<len(boundary)]
        if len(candidates)>1:raise ValueError('Blank cap merged distinct mounting vertices')
        if candidates:
            j=candidates[0];source_ids.append(boundary[j]);points.append(rest[boundary[j]].copy());colors.append(border_colors[j]);fixed.add(local)
        else:
            source_ids.append(len(rest)+len(extras));p=Vector((out[k].x,out[k].y,mean_depth));points.append(p);extras.append(p);colors.append(mean_color.copy())
    if set(source_ids)&set(boundary)!=set(boundary):raise ValueError('Blank cap lost a mounting vertex')
    graph=defaultdict(set)
    for tri in faces:
        for k in tri:graph[k].update(set(tri)-{k})
    interior=[k for k in range(len(points)) if k not in fixed]
    for _ in range(900):
        values={k:(sum(points[q].z for q in graph[k])/len(graph[k]),sum((colors[q] for q in graph[k]),Vector())/len(graph[k])) for k in interior}
        delta=max((abs(points[k].z-z) for k,(z,c) in values.items()),default=0)
        for k,(z,c) in values.items():points[k].z=z;colors[k]=c
        if delta<1e-9:break
    full_points=[p.copy() for p in rest]+extras
    source_faces=[tuple(source_ids[k] for k in tri) for tri in faces]
    full_faces=[tri for i,tri in enumerate(triangles) if i not in selected]+source_faces
    return {'boundary':boundary,'source_ids':source_ids,'points':points,'triangles':faces,'colors':colors,
        'full_points':full_points,'full_triangles':full_faces,'source_triangles':source_faces,
        'base_triangle_ids':[i for i in range(len(triangles)) if i not in selected],
        'color':BlankColor(points,faces,colors),'spec':BlankSpec()}
