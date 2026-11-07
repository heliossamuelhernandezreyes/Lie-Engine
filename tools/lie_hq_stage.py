"""Isolated native project for the pinned photographic material bank."""
import argparse,re,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def stage(banks,out):
    if out.exists():raise ValueError('Use a fresh stage directory')
    out.mkdir(parents=True);pending=['lie_hq_material_lab.tscn','test_lie_hq_materials.gd'];done=set()
    pattern=re.compile(r'(?:\bextends\s+|\b(?:preload|load)\s*\(\s*|\bpath\s*=\s*)"res://([^"]+)"')
    while pending:
        name=pending.pop()
        if name in done:continue
        src=ROOT/'gpu_compute'/name;dst=out/name;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst);done.add(name)
        if src.suffix in ('.gd','.tscn','.tres'):pending.extend(pattern.findall(src.read_text()))
    dst=out/'captures/hq_materials';shutil.copytree(banks,dst);(dst/'.gdignore').write_text('')
    (out/'project.godot').write_text('config_version=5\n[application]\nrun/main_scene="res://lie_hq_material_lab.tscn"\n[rendering]\nrenderer/rendering_method="mobile"\n[display]\nwindow/size/viewport_width=1100\nwindow/size/viewport_height=780\n[editor]\nimport/use_multiple_threads=false\n')
    print('HQ STAGED',out,len(done))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--banks',type=Path,required=True);p.add_argument('--stage',type=Path,required=True);a=p.parse_args();stage(a.banks,a.stage)
