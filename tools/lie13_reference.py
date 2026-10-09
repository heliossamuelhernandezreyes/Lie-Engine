"""LIE-13 CPU acceptance data for finite secondary radii and thin sheets."""
import argparse
import copy
import json
import math
from pathlib import Path
from lie_light_transport import solve
from lie_optics import refraction_probe


def scenario(base,name):
    m=copy.deepcopy(base)
    m['bounces']=3
    m['secondary_radii']={'radius_max':4.0,'radius_decay':.82,'power_reference':.015}
    if name=='direct': m['bounces']=0
    elif name=='short': m['secondary_radii']['radius_max']=.3
    elif name=='legacy': del m['secondary_radii']
    elif name=='absorbing':
        for key in m['materials']:
            if 'bounce red' in key: m['materials'][key]['absorption_code']=980
    elif name=='dark': m['lights'][0]['power_rgb']=[0,0,0]
    elif name=='filtered':
        m['optical_sheets']=[{'center':[0,0,.4],'right':[1,0,0],'up':[0,1,0],
            'half_width':1.5,'half_height':1.5,'ior':1.5,'thickness':.1,'sigma':[5,.4,.1]}]
    elif name in ('coupled','coupled_clear'):
        m['lights'][0]['position']=[.1,.65,2.25]
        a=math.radians(20)
        m['optical_sheets']=[]
        for x,ior,thickness,sigma in ([(-.48,1.5,.025,[3,.5,.2]),(.5,1.333,.12,[1.8,.3,.08])] if name=='coupled' else []):
            m['optical_sheets'].append({'center':[x,1.3*math.sin(a),1.3*math.cos(a)],'right':[1,0,0],'up':[0,math.cos(a),-math.sin(a)],
                'half_width':.44,'half_height':.68,'ior':ior,'thickness':thickness,'sigma':sigma})
    elif name!='bounce': raise ValueError(name)
    return m


def write(root):
    root=Path(root)
    base=json.loads((root/'light-model.json').read_text())
    result={'schema':1,'reference':'Python float64; same patch graph, independent Fresnel/Beer equations and radius transport', 'scenarios':{}}
    for name in ['direct','bounce','short','legacy','absorbing','dark','filtered','coupled','coupled_clear']:
        m=scenario(base,name)
        result['scenarios'][name]=solve(m,m['bounces'])
        print('LIE-13 ORACLE',name,flush=True)
    metadata=json.loads((root/'code-manifest.json').read_text())
    result['refraction_probe']=refraction_probe(metadata['capture_radius']*3.5)
    (root/'lie13-reference.json').write_text(json.dumps(result,separators=(',',':'))+'\n')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('root');write(p.parse_args().root)
