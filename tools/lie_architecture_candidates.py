"""Research candidates; never modify accepted capture bytes or source files.

Cached material uses four previously unconsumed scalar projection fields. Both
projection and accumulation kernels must change together. Depth/owner/material
buffers must remain exact before this can be accepted as a runtime change.
"""


def cached_material(stage, source):
    if stage not in (2, 3):
        return source
    rough = '''float rough=clamp(s.attributes.z+inst.tint.w,.2,.95);
                if(int(s.attributes.x)==3 || int(s.attributes.x)==6) {uint id=uint(max(inst.meta.x,0));if(inst.meta.y>.5)id+=uint(int(s.attributes.y)%2+6*(int(s.attributes.y)/2));rough=clamp(rough+(variation(id)-.5)*parameters.wall.w*.3,.2,.95);}'''
    signature = 'bool covered(Projection p,vec2 xy,Sample s,Instance inst,mat3 inverse_basis,SourceBounds bounds)'
    if source.count(signature) != 1 or source.count(rough) != 1:
        raise ValueError('candidate_source_contract')
    source = source.replace(signature, signature[:-1] + ',uint sid)')
    source = source.replace('in_source(bounds,uint(p.gradient.w),local)', 'in_source(bounds,sid,local)')
    source = source.replace('covered(p,vec2(q)+.5,s,inst,inverse_basis,bounds)',
                            'covered(p,vec2(q)+.5,s,inst,inverse_basis,bounds,sid)')
    source = source.replace('projected.v[i]=p;', '''if(p.screen.z>0.) {
                vec3 cached_color=material_color(s,inst);
                ''' + rough + '''
                p.normal.w=cached_color.x;p.gradient.w=cached_color.y;p.ellipse.w=cached_color.z;p.geometry.w=rough;
            }
            projected.v[i]=p;''')
    source = source.replace('round(material_color(s,inst)*float(w))',
                            'round(vec3(p.normal.w,p.gradient.w,p.ellipse.w)*float(w))')
    # Remove only the second occurrence: the first is now in projection.
    at = source.rindex(rough)
    source = source[:at] + source[at:].replace(rough, 'float rough=p.geometry.w;', 1)
    return source


def hoisted_material(stage, source):
    if stage != 3:
        return source
    rough = '''float rough=clamp(s.attributes.z+inst.tint.w,.2,.95);
                if(int(s.attributes.x)==3 || int(s.attributes.x)==6) {uint id=uint(max(inst.meta.x,0));if(inst.meta.y>.5)id+=uint(int(s.attributes.y)%2+6*(int(s.attributes.y)/2));rough=clamp(rough+(variation(id)-.5)*parameters.wall.w*.3,.2,.95);}'''
    anchor = '        int bound=int(ceil(p.screen.w));'
    if source.count(rough) != 1 or source.count(anchor) != 1:
        raise ValueError('candidate_source_contract')
    source = source.replace(anchor, '        vec3 base_color=material_color(s,inst);\n        vec3 encoded_normal=p.normal.xyz*.5+.5;\n        ' + rough + '\n' + anchor)
    source = source.replace('round(material_color(s,inst)*float(w))', 'round(base_color*float(w))')
    source = source.replace('round((p.normal.xyz*.5+.5)*float(w))', 'round(encoded_normal*float(w))')
    at = source.rindex(rough)
    return source[:at] + source[at:].replace(rough, '', 1)


if __name__ == '__main__':
    import argparse
    from pathlib import Path
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--stage', type=Path, required=True)
    args = p.parse_args()
    for name, transform in [('hoist', hoisted_material), ('cache', cached_material)]:
        for stage in (2, 3):
            original = args.stage / 'shaders' / f'lie_construction_scene_stage_{stage}.glsl'
            target = args.stage / 'shaders' / f'audit-{name}-{stage}.glsl'
            target.write_text(transform(stage, original.read_text()))
