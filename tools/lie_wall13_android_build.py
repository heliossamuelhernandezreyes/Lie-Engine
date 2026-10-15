"""Stage opaque per-source material response and bounded raster work on Android."""
import argparse,json,re,shutil
from pathlib import Path
import lie_wall12_android_build as previous
from lie_opaque_reference import prepare
from lie_area_reference import prepare as prepare_area
ROOT=Path(__file__).resolve().parents[1]
def stage_project(destination):
    prepare();prepare_area();report=previous.stage_project(destination)
    source=ROOT/'gpu_compute';pending=['lie_wall13_android_lab.tscn','test_lie_wall13_mobile.gd','test_lie_wall13_commands.gd','test_lie_area_emitters.gd','test_lie_area_field_gpu.gd'];copied=set()
    pattern=re.compile(r'(?:\bextends\s+|\b(?:preload|load)\s*\(\s*|\bpath\s*=\s*)"res://([^"]+)"')
    while pending:
        name=pending.pop()
        if name in copied:continue
        path=source/name;out=destination/name;out.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,out);copied.add(name)
        if path.suffix in ('.gd','.tscn','.tres'):pending.extend(pattern.findall(path.read_text()))
    shutil.copy2(source/'fixtures/area-field-reference.json',destination/'fixtures/area-field-reference.json')
    project=destination/'project.godot';project.write_text(project.read_text().replace('LIE Material 0.9','LIE Área 1.0').replace('0.9.0','1.0.0').replace('lie_wall12_android_lab.tscn','lie_wall13_android_lab.tscn'))
    preset=destination/'export_presets.cfg';preset.write_text(preset.read_text().replace('version/code=9','version/code=10').replace('0.9.0-material-light','1.0.0-area-continuity').replace('v090','v100').replace('LIE Material 0.9','LIE Área 1.0'))
    return report
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--stage',type=Path,required=True);p.add_argument('--godot',type=Path);p.add_argument('--sdk',type=Path);p.add_argument('--keystore',type=Path);p.add_argument('--output',type=Path);args=p.parse_args();report=stage_project(args.stage.resolve())
    if args.output:
        report.update(previous.previous.previous.previous.previous.previous.previous.base.export(args.stage.resolve(),args.godot.resolve(),args.sdk.resolve(),args.keystore.resolve(),args.output.resolve()));report.update(package='org.lieengine.wallruntime.v100',version='1.0.0-area-continuity');(args.output.parent/'android-build.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
