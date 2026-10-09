"""LIE-13 CPU acceptance data for finite secondary radii and thin sheets."""
import argparse
import copy
import json
from pathlib import Path
from lie_light_transport import solve
from lie_optics import slab


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
    elif name!='bounce': raise ValueError(name)
    return m


def write(root):
    root=Path(root)
    base=json.loads((root/'light-model.json').read_text())
    result={'schema':1,'reference':'Python float64; same patch graph, independent Fresnel/Beer equations and radius transport', 'scenarios':{}}
    for name in ['direct','bounce','short','legacy','absorbing','dark','filtered']:
        m=scenario(base,name)
        result['scenarios'][name]=solve(m,m['bounces'])
        print('LIE-13 ORACLE',name,flush=True)
    (root/'lie13-reference.json').write_text(json.dumps(result,separators=(',',':'))+'\n')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('root');write(p.parse_args().root)
