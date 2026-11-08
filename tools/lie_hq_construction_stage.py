"""Stage code dependencies separately from immutable asset data."""
import argparse,re,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def stage(data,out):
    for name in ['light-field-reference.json','field-quality-reference.json']:
        if not (ROOT/'gpu_compute/fixtures'/name).is_file():raise ValueError('Generate common field fixtures first: tools/lie_light_field.py and tools/lie_field_quality_cases.py')
    if out.exists():raise ValueError('Use a fresh stage')
    out.mkdir(parents=True);pending=['test_lie_construction_reconstruction.gd','test_lie_construction_field.gd','test_lie_light_field_gpu.gd','test_lie_surface_field_gpu.gd','test_lie_field_quality_gpu.gd','test_lie_field_quality_commands.gd','test_lie_hq_component_quality.gd','lie_hq_construction_lab.tscn','test_lie_hq_construction.gd','test_lie26_rig.gd','workshop/test_lie_agent_session.gd'];done=set();pattern=re.compile(r'(?:\bextends\s+|\b(?:preload|load)\s*\(\s*|\bpath\s*=\s*)"res://([^"]+)"')
    while pending:
        name=pending.pop()
        if name in done:continue
        src=ROOT/'gpu_compute'/name;dst=out/name;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst);done.add(name)
        if src.suffix in ('.gd','.tscn','.tres'):pending.extend(pattern.findall(src.read_text()))
    target=out/'captures/hq_construction';shutil.copytree(data,target,ignore=shutil.ignore_patterns('individual'));(target/'.gdignore').write_text('')
    (out/'fixtures').mkdir(exist_ok=True);shutil.copy2(ROOT/'gpu_compute/fixtures/lie26-rig.json',out/'fixtures/lie26-rig.json')
    for name in ['light-field-reference.json','field-quality-reference.json']:shutil.copy2(ROOT/'gpu_compute/fixtures'/name,out/'fixtures'/name)
    (out/'project.godot').write_text('config_version=5\n[application]\nrun/main_scene="res://lie_hq_construction_lab.tscn"\n[rendering]\nrenderer/rendering_method="mobile"\n[display]\nwindow/size/viewport_width=1150\nwindow/size/viewport_height=820\n[editor]\nimport/use_multiple_threads=false\n');print('STAGED',out,len(done))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--data',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();stage(a.data,a.output)
