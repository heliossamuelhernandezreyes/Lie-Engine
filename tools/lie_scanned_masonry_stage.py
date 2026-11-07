"""Small isolated native project; large source/captures stay outside Git."""
import argparse,re,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def stage(bank,out,test='test_lie_scanned_masonry.gd'):
    if out.exists():raise ValueError('Use new stage')
    out.mkdir(parents=True);pending=['lie_scanned_masonry_lab.tscn',test,'test_lie26_rig.gd','workshop/test_lie_agent_session.gd'];done=set()
    pattern=re.compile(r'(?:\bextends\s+|\b(?:preload|load)\s*\(\s*|\bpath\s*=\s*)"res://([^"]+)"')
    while pending:
        name=pending.pop()
        if name in done:continue
        src=ROOT/'gpu_compute'/name;dst=out/name;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst);done.add(name)
        if src.suffix in ('.gd','.tscn','.tres'):pending.extend(pattern.findall(src.read_text()))
    target=out/'captures/scanned_masonry';shutil.copytree(bank,target);(target/'.gdignore').write_text('')
    (out/'fixtures').mkdir(exist_ok=True);shutil.copyfile(ROOT/'gpu_compute/fixtures/lie26-rig.json',out/'fixtures/lie26-rig.json')
    (out/'project.godot').write_text('config_version=5\n[application]\nrun/main_scene="res://lie_scanned_masonry_lab.tscn"\n[rendering]\nrenderer/rendering_method="mobile"\n[display]\nwindow/size/viewport_width=1080\nwindow/size/viewport_height=740\n[editor]\nimport/use_multiple_threads=false\n')
    print('STAGED',out,len(done))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--bank',type=Path,required=True);p.add_argument('--stage',type=Path,required=True);p.add_argument('--test',default='test_lie_scanned_masonry.gd');a=p.parse_args();stage(a.bank,a.stage,a.test)
