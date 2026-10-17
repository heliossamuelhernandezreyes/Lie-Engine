"""Stage the isolated scalar-power response and GPU submission experiment."""
import argparse,json,re,shutil
from pathlib import Path
import lie_wall22_android_build as previous
ROOT=Path(__file__).resolve().parents[1]
def stage_project(destination):
    report=previous.stage_project(destination);source=ROOT/'gpu_compute'
    pending=['lie_wall23_android_lab.tscn','test_lie_wall23_commands.gd','test_lie_wall23_mobile.gd','test_lie_light_field_gpu.gd'];copied=set()
    pattern=re.compile(r'(?:\bextends\s+|\b(?:preload|load)\s*\(\s*|\bpath\s*=\s*)"res://([^"]+)"')
    while pending:
        name=pending.pop()
        if name in copied:continue
        path=source/name;out=destination/name;out.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,out);copied.add(name)
        if path.suffix in ('.gd','.tscn','.tres'):pending.extend(pattern.findall(path.read_text()))
    project=destination/'project.godot';project.write_text(project.read_text().replace('LIE Bloques 1.9','LIE Respuesta 2.0').replace('1.9.0','2.0.0').replace('lie_wall22_android_lab.tscn','lie_wall23_android_lab.tscn'))
    preset=destination/'export_presets.cfg';preset.write_text(preset.read_text().replace('version/code=20','version/code=21').replace('1.9.0-screen-tiles','2.0.0-power-response').replace('v190','v200').replace('LIE Bloques 1.9','LIE Respuesta 2.0'))
    report['power_response']='lazy direct response cache; unchanged indirect field; isolated whole GPU intervals';return report
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--stage',type=Path,required=True);p.add_argument('--godot',type=Path);p.add_argument('--sdk',type=Path);p.add_argument('--keystore',type=Path);p.add_argument('--output',type=Path);args=p.parse_args();report=stage_project(args.stage.resolve())
    if args.output:
        import lie_runtime_android_build as base
        report.update(base.export(args.stage.resolve(),args.godot.resolve(),args.sdk.resolve(),args.keystore.resolve(),args.output.resolve()));report.update(package='org.lieengine.wallruntime.v200',version='2.0.0-power-response');(args.output.parent/'android-build.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
