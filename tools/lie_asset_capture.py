"""Common 80-byte opaque master compiler with an authored semantic frame.

Source meshes are OFFLINE capture inputs. This backend preserves source
geometry normals, base color and roughness; it does not implement metal,
alpha/transmission paths or tangent-space normal-map capture.
"""
import argparse,json
from pathlib import Path
from lie_brick02_capture_scan import capture
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--provenance',type=Path,required=True);p.add_argument('--profile',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--counts',type=int,nargs=3,default=(220000,52000,9000));p.add_argument('--seed',type=int,default=2102);a=p.parse_args()
    capture(a.source,a.provenance,a.output,counts=tuple(a.counts),seed=a.seed,asset_profile=json.loads(a.profile.read_text()))
