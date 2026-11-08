"""Lossless 64-byte projection layout. Captured samples remain 80 bytes.

Drop four unused projection scalars; pass source SID explicitly to support
tests. All retained values are still float32 and sample/owner addresses are
unchanged. std430 packs each vec3 together with its following scalar.
"""

OLD = 'struct Projection { vec4 normal; vec4 screen; vec4 gradient; vec4 geometry; vec4 ellipse; };'
NEW = '''// 64-byte std430 record: offsets 0/12, 16/24, 32/44, 48/60.
struct Projection {
    vec3 normal; float depth;
    vec2 center; vec2 gradient;
    vec3 geometry; float owner;
    vec3 ellipse; float radius;
};'''


def compact(stage, shader):
    if shader.count(OLD) != 1:
        raise ValueError('projection_layout_contract')
    shader = shader.replace(OLD, NEW)
    if stage in (2, 3, 8):
        signature = 'bool covered(Projection p,vec2 xy,Sample s,Instance inst,mat3 inverse_basis,SourceBounds bounds)'
        if shader.count(signature) != 1:
            raise ValueError('projection_support_contract')
        shader = shader.replace(signature, signature[:-1] + ',uint sid)')
        shader = shader.replace('in_source(bounds,uint(p.gradient.w),local)', 'in_source(bounds,sid,local)')
        shader = shader.replace('covered(p,vec2(q)+.5,s,inst,inverse_basis,bounds)',
                                'covered(p,vec2(q)+.5,s,inst,inverse_basis,bounds,sid)')
        shader = shader.replace(
            'p.normal=vec4(shading,front);p.screen=vec4(0);p.gradient=vec4(0,0,float(job.z),float(sid));p.geometry=vec4(n,s.attributes.x);p.ellipse=vec4(0);',
            'p.normal=shading;p.depth=0.;p.center=vec2(0);p.gradient=vec2(0);p.geometry=n;p.owner=float(job.z);p.ellipse=vec3(0);p.radius=0.;')
        shader = shader.replace('p.ellipse=vec4(yy/det,-off/det,xx/det,0);p.screen=vec4(xy,depth,clamp(sqrt(max(xx,yy)),.5,64));',
                                'p.ellipse=vec3(yy/det,-off/det,xx/det);p.center=xy;p.depth=depth;p.radius=clamp(sqrt(max(xx,yy)),.5,64);')
    for name in ('p', 'point'):
        for old, new in [('screen.xy','center'),('screen.x','center.x'),('screen.y','center.y'),('screen.z','depth'),('screen.w','radius'),
                         ('gradient.xy','gradient'),('gradient.z','owner'),
                         ('normal.xyz','normal'),('geometry.xyz','geometry')]:
            shader = shader.replace(name + '.' + old, name + '.' + new)
    # These would indicate a reader/writer that was not migrated together.
    for obsolete in ('p.screen','point.screen','p.gradient.w','point.gradient.w',
                     'p.gradient.z','point.gradient.z','p.normal=vec4','p.ellipse=vec4'):
        if obsolete in shader:
            raise ValueError('unmigrated_projection_field:' + obsolete)
    return shader
