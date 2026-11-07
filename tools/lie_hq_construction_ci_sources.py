"""Acquire the same two original v4 materials and pinned mortar for reproduction."""
import argparse,json,shutil
from pathlib import Path
from lie_hq_materials import acquire,LOCK
from lie_hq_construction_sources import acquire_mortar,write
def prepare(root):
    root.mkdir(parents=True,exist_ok=True);lock=json.loads(LOCK.read_text());wanted=('wood_table_worn','concrete_layers')
    acquire(root,{'materials':{k:lock['materials'][k] for k in wanted}})
    for name,key in [('wood_table_worn','wood'),('concrete_layers','concrete')]:
        target=root/key
        if target.exists():shutil.rmtree(target)
        (root/name).rename(target);write(target/'material-source.json',lock['materials'][name])
    acquire_mortar(root/'mortar')
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args();prepare(a.output)
