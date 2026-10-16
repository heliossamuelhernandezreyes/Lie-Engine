"""Stage refitted source bounds with unchanged original primitive kernels."""
import argparse,json,re,shutil
from pathlib import Path
import lie_wall19_android_build as previous
from lie_tangent_bounds import prepare,prepare_reference
ROOT=Path(__file__).resolve().parents[1]
def stage_project(destination):
    report=previous.stage_project(destination);order=prepare();source=ROOT/'gpu_compute'
    shutil.copy2(prepare_reference(),destination/'fixtures/tangent-visibility-reference.json')
    for name in ['tangent-bounds.bin','tangent-bounds.json']:shutil.copy2(source/'captures/liewall06'/name,destination/'captures/liewall06'/name)
    pending=['lie_wall20_android_lab.tscn','test_lie_wall20_commands.gd','test_lie_wall20_mobile.gd','test_lie_tangent_reference_gpu.gd'];copied=set()
    pattern=re.compile(r'(?:\bextends\s+|\b(?:preload|load)\s*\(\s*|\bpath\s*=\s*)"res://([^"]+)"')
    while pending:
        name=pending.pop()
        if name in copied:continue
        path=source/name;out=destination/name;out.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,out);copied.add(name)
        if path.suffix in ('.gd','.tscn','.tres'):pending.extend(pattern.findall(path.read_text()))
    project=destination/'project.godot';project.write_text(project.read_text().replace('LIE Visibilidad 1.6','LIE Límites 1.7').replace('1.6.0','1.7.0').replace('lie_wall19_android_lab.tscn','lie_wall20_android_lab.tscn'))
    preset=destination/'export_presets.cfg';preset.write_text(preset.read_text().replace('version/code=16','version/code=17').replace('1.6.0-visibility-stream','1.7.0-tangent-bounds').replace('v160','v170').replace('LIE Visibilidad 1.6','LIE Límites 1.7'))
    report['tangent_bounds_bytes']=order['bytes'];report['tangent_bounds_sha256']=order['sha256'];return report
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--stage',type=Path,required=True);p.add_argument('--godot',type=Path);p.add_argument('--sdk',type=Path);p.add_argument('--keystore',type=Path);p.add_argument('--output',type=Path);args=p.parse_args();report=stage_project(args.stage.resolve())
    if args.output:
        import lie_runtime_android_build as base
        report.update(base.export(args.stage.resolve(),args.godot.resolve(),args.sdk.resolve(),args.keystore.resolve(),args.output.resolve()));report.update(package='org.lieengine.wallruntime.v170',version='1.7.0-tangent-bounds');(args.output.parent/'android-build.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
