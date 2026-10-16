"""Addressed source pages, retained visibility and separate cold/warm evidence."""
import argparse,json,re,shutil
from pathlib import Path
import lie_wall17_android_build as previous
from lie_spatial_pages import prepare
from lie_spatial_pages_fixture import prepare as prepare_fixture
ROOT=Path(__file__).resolve().parents[1]
def stage_project(destination):
    report=previous.stage_project(destination);pages=prepare();prepare_fixture()
    source=ROOT/'gpu_compute'
    for name in ['spatial-pages.bin','spatial-pages.json']:shutil.copy2(source/'captures/liewall06'/name,destination/'captures/liewall06'/name)
    shutil.copy2(source/'fixtures/spatial-pages-reference.json',destination/'fixtures/spatial-pages-reference.json')
    pending=['lie_wall18_android_lab.tscn','test_lie_wall18_commands.gd','test_lie_wall18_mobile.gd','test_lie_pages_gpu.gd'];copied=set()
    pattern=re.compile(r'(?:\bextends\s+|\b(?:preload|load)\s*\(\s*|\bpath\s*=\s*)"res://([^"]+)"')
    while pending:
        name=pending.pop()
        if name in copied:continue
        path=source/name;out=destination/name;out.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,out);copied.add(name)
        if path.suffix in ('.gd','.tscn','.tres'):pending.extend(pattern.findall(path.read_text()))
    project=destination/'project.godot';project.write_text(project.read_text().replace('LIE Kernels 1.4','LIE Paginas 1.5').replace('1.4.0','1.5.0').replace('lie_wall17_android_lab.tscn','lie_wall18_android_lab.tscn'))
    preset=destination/'export_presets.cfg';preset.write_text(preset.read_text().replace('version/code=14','version/code=15').replace('1.4.0-stage-kernels','1.5.0-spatial-pages').replace('v140','v150').replace('LIE Kernels 1.4','LIE Paginas 1.5'))
    report['spatial_page_bytes']=pages['bytes'];report['spatial_page_sha256']=pages['sha256'];return report
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--stage',type=Path,required=True);p.add_argument('--godot',type=Path);p.add_argument('--sdk',type=Path);p.add_argument('--keystore',type=Path);p.add_argument('--output',type=Path);args=p.parse_args();report=stage_project(args.stage.resolve())
    if args.output:
        import lie_runtime_android_build as base
        report.update(base.export(args.stage.resolve(),args.godot.resolve(),args.sdk.resolve(),args.keystore.resolve(),args.output.resolve()));report.update(package='org.lieengine.wallruntime.v150',version='1.5.0-spatial-pages');(args.output.parent/'android-build.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
