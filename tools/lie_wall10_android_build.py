"""Stage source-continuity and camera-independent visibility on Android."""
import argparse,json,re,shutil
from pathlib import Path
import lie_wall09_android_build as previous
from lie_wall10_prepare import prepare
from lie_source_visibility_fixture import prepare as prepare_fixture
ROOT=Path(__file__).resolve().parents[1]
def stage_project(destination):
    report=previous.stage_project(destination);prepare();prepare_fixture()
    source=ROOT/'gpu_compute';root=source/'captures/liewall06'
    for name in ['surface-source.json','surface-refs.bin','surface-bvh.bin','surface-leaves.bin','surface-scene.bin']:shutil.copy2(root/name,destination/'captures/liewall06'/name)
    shutil.copy2(source/'fixtures/source-visibility-reference.json',destination/'fixtures/source-visibility-reference.json')
    pattern=re.compile(r'(?:\bextends\s+|\b(?:preload|load)\s*\(\s*|\bpath\s*=\s*)"res://([^"]+)"')
    pending=['lie_wall10_android_lab.tscn','test_lie_source_visibility_gpu.gd','test_lie_source_reference_gpu.gd','test_lie_wall10_mobile.gd','test_lie_wall10_commands.gd'];copied=set()
    while pending:
        name=pending.pop()
        if name in copied:continue
        path=source/name;out=destination/name;out.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,out);copied.add(name)
        if path.suffix in ('.gd','.tscn','.tres'):pending.extend(pattern.findall(path.read_text()))
    project=destination/'project.godot';project.write_text(project.read_text().replace('LIE Relieve 0.6','LIE Superficie 0.7').replace('0.6.0','0.7.0').replace('lie_wall09_android_lab.tscn','lie_wall10_android_lab.tscn'))
    preset=destination/'export_presets.cfg';preset.write_text(preset.read_text().replace('version/code=6','version/code=7').replace('0.6.0-surface-light','0.7.0-source-continuity').replace('v060','v070').replace('LIE Relieve 0.6','LIE Superficie 0.7'))
    return report
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--stage',type=Path,required=True);p.add_argument('--godot',type=Path);p.add_argument('--sdk',type=Path);p.add_argument('--keystore',type=Path);p.add_argument('--output',type=Path);args=p.parse_args();report=stage_project(args.stage.resolve())
    if args.output:
        report.update(previous.previous.previous.previous.base.export(args.stage.resolve(),args.godot.resolve(),args.sdk.resolve(),args.keystore.resolve(),args.output.resolve()));report.update(package='org.lieengine.wallruntime.v070',version='0.7.0-source-continuity');(args.output.parent/'android-build.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
