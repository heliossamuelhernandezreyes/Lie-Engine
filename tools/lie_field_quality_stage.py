"""Stage isolated lighting contracts, optionally the unchanged captured wall."""
import argparse
import json
from pathlib import Path
import re
import shutil
from lie_field_quality_cases import prepare
from lie_field_quality_shader import outputs
ROOT=Path(__file__).resolve().parents[1]

def stage(destination,wall=False):
    if destination.exists():raise ValueError('Stage destination must be new')
    destination.mkdir(parents=True);source=ROOT/'gpu_compute'
    for name,text in outputs().items():(source/'shaders'/name).write_text(text)
    prepare()
    pending=['test_lie_field_quality_gpu.gd','test_lie_quality_legacy_probe.gd','test_lie_quality_direct_gpu.gd','test_lie_field_quality_commands.gd','test_lie26_rig.gd','workshop/test_lie_agent_session.gd']
    if wall:pending+=['lie_quality_lab.tscn','test_lie_quality_wall.gd']
    copied=set();pattern=re.compile(r'(?:\bextends\s+|\b(?:preload|load)\s*\(\s*|\bpath\s*=\s*)"res://([^"]+)"')
    while pending:
        name=pending.pop()
        if name in copied:continue
        p=source/name;out=destination/name;out.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,out);copied.add(name)
        if p.suffix in ('.gd','.tscn','.tres'):pending.extend(pattern.findall(p.read_text()))
    (destination/'fixtures').mkdir(exist_ok=True)
    shutil.copy2(source/'fixtures/field-quality-reference.json',destination/'fixtures/field-quality-reference.json')
    shutil.copy2(source/'fixtures/lie26-rig.json',destination/'fixtures/lie26-rig.json')
    if wall:shutil.copytree(source/'captures/liewall06',destination/'captures/liewall06')
    (destination/'project.godot').write_text('config_version=5\n[rendering]\nrenderer/rendering_method="mobile"\n[display]\nwindow/size/viewport_width=720\nwindow/size/viewport_height=720\n')
    print(json.dumps({'resources':len(copied),'wall':wall,'destination':str(destination)}))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--stage',type=Path,required=True);p.add_argument('--wall',action='store_true');a=p.parse_args();stage(a.stage,a.wall)
