"""Stage/export the common surface-light experiment with the accepted sources."""
import argparse,json,re,shutil
from pathlib import Path
import lie_wall08_android_build as previous
from lie_surface_reference import prepare as prepare_surface
ROOT=Path(__file__).resolve().parents[1]
def stage_project(destination):
    prepare_surface()
    report=previous.stage_project(destination)
    source=ROOT/'gpu_compute'
    pattern=re.compile(r'(?:\bextends\s+|\b(?:preload|load)\s*\(\s*|\bpath\s*=\s*)"res://([^"]+)"')
    pending=['lie_wall09_android_lab.tscn','test_lie_wall09_mobile.gd','test_lie_surface_gpu.gd','test_lie_surface_field_gpu.gd','test_lie_wall09_commands.gd'];copied=set()
    while pending:
        name=pending.pop()
        if name in copied:continue
        path=source/name;out=destination/name;out.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,out);copied.add(name)
        if path.suffix in ('.gd','.tscn','.tres'):pending.extend(pattern.findall(path.read_text()))
    shutil.copy2(source/'fixtures/surface-reference.json',destination/'fixtures/surface-reference.json')
    project=destination/'project.godot';project.write_text(project.read_text().replace('LIE Luz 0.5','LIE Relieve 0.6').replace('0.5.0','0.6.0').replace('lie_wall08_android_lab.tscn','lie_wall09_android_lab.tscn'))
    preset=destination/'export_presets.cfg';preset.write_text(preset.read_text().replace('version/code=5','version/code=6').replace('0.5.0-source-light-field','0.6.0-surface-light').replace('v050','v060').replace('LIE Luz 0.5','LIE Relieve 0.6'))
    return report
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--stage',type=Path,required=True);p.add_argument('--godot',type=Path);p.add_argument('--sdk',type=Path);p.add_argument('--keystore',type=Path);p.add_argument('--output',type=Path);args=p.parse_args();report=stage_project(args.stage.resolve())
    if args.output:
        report.update(previous.previous.previous.base.export(args.stage.resolve(),args.godot.resolve(),args.sdk.resolve(),args.keystore.resolve(),args.output.resolve()));report.update(package='org.lieengine.wallruntime.v060',version='0.6.0-surface-light');(args.output.parent/'android-build.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
