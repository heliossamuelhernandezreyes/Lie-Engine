"""Compare source, captured representation and consumer geometry, per pixel.

This is a diagnostic contract, not a renderer or an implementation of LIE GPU.
Inputs must represent the same camera, pose, resolution and depth convention.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

SCHEMA = 'lie-geometric-triplet/1'


def _percentile(sorted_values, pct):
    if not sorted_values:
        return None
    idx = (len(sorted_values)-1)*pct/100
    lo = int(math.floor(idx))
    hi = int(math.ceil(idx))
    f = idx-lo
    return sorted_values[lo]*(1-f)+sorted_values[hi]*f


def validate(payload):
    if payload.get('schema') != SCHEMA:
        raise ValueError('schema must be '+SCHEMA)
    w,h = payload.get('width'),payload.get('height')
    if type(w) is not int or type(h) is not int or w <= 0 or h <= 0:
        raise ValueError('width and height must be positive integers')
    n = w*h
    tol = payload.get('depth_tolerance_m',0.005)
    if isinstance(tol,bool) or not isinstance(tol,(int,float)) or not math.isfinite(tol) or tol < 0:
        raise ValueError('depth_tolerance_m must be finite and non-negative')
    layers = payload.get('layers')
    if not isinstance(layers,dict):
        raise ValueError('layers object required')
    for name in ('source','representation','consumer'):
        if name not in layers or not isinstance(layers[name],dict):
            raise ValueError('missing layer '+name)
        layer = layers[name]
        hit,depth = layer.get('hit'),layer.get('depth_m')
        if not isinstance(hit,list) or not isinstance(depth,list) or len(hit)!=n or len(depth)!=n:
            raise ValueError(name+' hit/depth_m must be flat arrays of width*height')
        if 'owner_id' in layer and (not isinstance(layer['owner_id'],list) or len(layer['owner_id'])!=n):
            raise ValueError(name+' owner_id must be flat array of width*height')
        for i,(m,d) in enumerate(zip(hit,depth)):
            if m not in (0,1,False,True):
                raise ValueError(name+' invalid hit at '+str(i))
            if m and (isinstance(d,bool) or not isinstance(d,(float,int)) or not math.isfinite(d)):
                raise ValueError(name+' missing/invalid depth at hit '+str(i))
            if not m and d is not None:
                raise ValueError(name+' non-null depth at miss '+str(i))
    return n,float(tol)


def _is_different(a,b,i,tol):
    ah = bool(a['hit'][i]); bh = bool(b['hit'][i])
    if ah != bh: return True
    if not ah: return False
    if abs(a['depth_m'][i]-b['depth_m'][i]) > tol: return True
    if 'owner_id' in a and 'owner_id' in b:
        return a['owner_id'][i]!=b['owner_id'][i]
    return False


def _compare(a,b,n,tol):
    missing=extra=common=union=owner_wrong=0
    diffs=[]
    owners_both = 'owner_id' in a and 'owner_id' in b
    for i in range(n):
        ah,bh = bool(a['hit'][i]),bool(b['hit'][i])
        if ah or bh: union+=1
        if ah and not bh: missing+=1
        elif bh and not ah: extra+=1
        elif ah and bh:
            common+=1
            diffs.append(abs(a['depth_m'][i]-b['depth_m'][i]))
            if owners_both and a['owner_id'][i]!=b['owner_id'][i]:owner_wrong+=1
    diffs.sort()
    return {
        'missing':missing, 'extra':extra, 'overlap_hits':common,
        'iou': (common/union if union else 1.0),
        'depth_over_tolerance':sum(d>tol for d in diffs),
        'depth_p50_m':_percentile(diffs,50),
        'depth_p95_m':_percentile(diffs,95),
        'depth_p99_m':_percentile(diffs,99),
        'depth_max_m':diffs[-1] if diffs else None,
        'owner_mismatches':owner_wrong if owners_both else None,
    }


def assess(payload,include_pixel_causes=False):
    n,tol=validate(payload)
    src,rep,con=(payload['layers'][key] for key in ('source','representation','consumer'))
    first=_compare(src,rep,n,tol)
    second=_compare(rep,con,n,tol)
    counts={k:0 for k in ('data_only','consumer_only','both','neither')}
    pixels=[]
    for i in range(n):
        d=_is_different(src,rep,i,tol)
        c=_is_different(rep,con,i,tol)
        tag='both' if d and c else 'data_only' if d else 'consumer_only' if c else 'neither'
        counts[tag]+=1
        if include_pixel_causes:pixels.append(tag)
    result={'schema':'lie-geometric-triplet-report/1',
      'width':payload['width'],'height':payload['height'],
      'depth_tolerance_m':tol,
      'source_to_representation':first,
      'representation_to_consumer':second,
      'attribution_pixel_counts':counts,
      'limitations':'Both means mismatches at both stages; it is not a unique causal attribution. This does not test appearance/lighting or guarantee correspondence to original assets.'}
    if 'provenance' in payload: result['provenance']=payload['provenance']
    if include_pixel_causes: result['pixel_causes']=pixels
    return result


def demo_payload(kind):
    import numpy as np
    from lie_geometric_sufficiency_probe import grid,source,samples,representation_rays,projected_consumer,SIDE
    x,y=grid()
    sm,sz=source(kind,x,y)
    rm,rz,rid=representation_rays(samples(kind),x,y)
    cm,cz,cid=projected_consumer(samples(kind))
    def layer(hit,depth,owner=None):
        obj={'hit':hit.ravel().astype(int).tolist(),
             'depth_m':[float(v) if h else None for h,v in zip(hit.ravel(),depth.ravel())]}
        if owner is not None:obj['owner_id']=[int(v) if h else None for h,v in zip(hit.ravel(),owner.ravel())]
        return obj
    return {'schema':SCHEMA,'width':SIDE,'height':SIDE,'depth_tolerance_m':0.005,
         'provenance':{'fixture':kind,'source':'analytic CPU','representation':'finite tangent patches CPU','consumer':'CPU push emulator, NOT Vulkan'},
         'layers':{'source':layer(sm,sz),'representation':layer(rm,rz,rid),'consumer':layer(cm,cz,cid)}}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    src=parser.add_mutually_exclusive_group(required=True)
    src.add_argument('--input',type=Path,help='Triplet JSON with source, representation and consumer layers')
    src.add_argument('--demo',choices=('flat','wall_hole','cylinder','hidden_bump'),help='Use existing CPU fixture; NOT a GPU result')
    parser.add_argument('--output',type=Path)
    parser.add_argument('--pixel-causes',action='store_true',help='Emit flat per-pixel classification labels (larger output)')
    args=parser.parse_args()
    payload=json.loads(args.input.read_text()) if args.input else demo_payload(args.demo)
    report=assess(payload,args.pixel_causes)
    result=json.dumps(report,indent=2,sort_keys=True,allow_nan=False)+'\n'
    if args.output:
        args.output.parent.mkdir(parents=True,exist_ok=True)
        args.output.write_text(result)
    print(result)


if __name__=='__main__':main()
