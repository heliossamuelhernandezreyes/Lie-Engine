"""Stage opaque per-source material response and bounded raster work on Android."""
import argparse,json,re,shutil
from pathlib import Path
import lie_wall11_android_build as previous
from lie_opaque_reference import prepare
ROOT=Path(__file__).resolve().parents[1]
def stage_project(destination):
    prepare();report=previous.stage_project(destination)
    source=ROOT/'gpu_compute';pending=['lie_wall12_android_lab.tscn','test_lie_wall12_mobile.gd','test_lie_wall12_commands.gd','test_lie_opaque_gpu.gd'];copied=set()
    pattern=re.compile(r'(?:\bextends\s+|\b(?:preload|load)\s*\(\s*|\bpath\s*=\s*)"res://([^"]+)"')
    while pending:
        name=pending.pop()
        if name in copied:continue
        path=source/name;out=destination/name;out.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,out);copied.add(name)
        if path.suffix in ('.gd','.tscn','.tres'):pending.extend(pattern.findall(path.read_text()))
    shutil.copy2(source/'fixtures/opaque-reference.json',destination/'fixtures/opaque-reference.json')
    project=destination/'project.godot';project.write_text(project.read_text().replace('LIE Identidad 0.8','LIE Material 0.9').replace('0.8.0','0.9.0').replace('lie_wall11_android_lab.tscn','lie_wall12_android_lab.tscn'))
    preset=destination/'export_presets.cfg';preset.write_text(preset.read_text().replace('version/code=8','version/code=9').replace('0.8.0-persistent-light','0.9.0-material-light').replace('v080','v090').replace('LIE Identidad 0.8','LIE Material 0.9'))
    return report
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--stage',type=Path,required=True);p.add_argument('--godot',type=Path);p.add_argument('--sdk',type=Path);p.add_argument('--keystore',type=Path);p.add_argument('--output',type=Path);args=p.parse_args();report=stage_project(args.stage.resolve())
    if args.output:
        report.update(previous.previous.previous.previous.previous.previous.base.export(args.stage.resolve(),args.godot.resolve(),args.sdk.resolve(),args.keystore.resolve(),args.output.resolve()));report.update(package='org.lieengine.wallruntime.v090',version='0.9.0-material-light');(args.output.parent/'android-build.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
