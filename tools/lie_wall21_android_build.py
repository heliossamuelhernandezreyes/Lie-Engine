"""Stage exact compact shadow view and native GPU diagnostics."""
import argparse,json,re,shutil
from pathlib import Path
import lie_wall20_android_build as previous
from lie_shadow_view import prepare,prepare_reference
ROOT=Path(__file__).resolve().parents[1]
def stage_project(destination):
    if not (ROOT/'gpu_compute/addons/lie_gpu_probe/lie_gpu_probe.gdextension').is_file():raise ValueError('Build the native diagnostics before staging LIE 1.8')
    report=previous.stage_project(destination);order=prepare();source=ROOT/'gpu_compute'
    shutil.copy2(prepare_reference(),destination/'fixtures/compact-shadow-reference.json')
    for name in ['shadow-view.bin','shadow-view.json']:shutil.copy2(source/'captures/liewall06'/name,destination/'captures/liewall06'/name)
    pending=['lie_wall21_android_lab.tscn','test_lie_wall21_commands.gd','test_lie_wall21_mobile.gd','test_lie_compact_reference_gpu.gd','test_lie_hardware_probe.gd'];copied=set()
    pattern=re.compile(r'(?:\bextends\s+|\b(?:preload|load)\s*\(\s*|\bpath\s*=\s*)"res://([^"]+)"')
    while pending:
        name=pending.pop()
        if name in copied:continue
        path=source/name;out=destination/name;out.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,out);copied.add(name)
        if path.suffix in ('.gd','.tscn','.tres'):pending.extend(pattern.findall(path.read_text()))
    project=destination/'project.godot';project.write_text(project.read_text().replace('LIE Límites 1.7','LIE GPU 1.8').replace('1.7.0','1.8.0').replace('lie_wall20_android_lab.tscn','lie_wall21_android_lab.tscn'))
    preset=destination/'export_presets.cfg';preset.write_text(preset.read_text().replace('version/code=17','version/code=18').replace('1.7.0-tangent-bounds','1.8.0-gpu-diagnostics').replace('v170','v180').replace('LIE Límites 1.7','LIE GPU 1.8'))
    shutil.copytree(source/'addons/lie_gpu_probe',destination/'addons/lie_gpu_probe',dirs_exist_ok=True)
    preset.write_text(preset.read_text().replace('ATTRIBUTION.txt','ATTRIBUTION.txt,addons/lie_gpu_probe/licenses/*.txt,addons/lie_gpu_probe/bin/*/build.json'))
    report['shadow_view_bytes']=order['bytes'];report['shadow_view_sha256']=order['sha256'];return report
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--stage',type=Path,required=True);p.add_argument('--godot',type=Path);p.add_argument('--sdk',type=Path);p.add_argument('--keystore',type=Path);p.add_argument('--output',type=Path);args=p.parse_args();report=stage_project(args.stage.resolve())
    if args.output:
        import lie_runtime_android_build as base
        report.update(base.export(args.stage.resolve(),args.godot.resolve(),args.sdk.resolve(),args.keystore.resolve(),args.output.resolve()));report.update(package='org.lieengine.wallruntime.v180',version='1.8.0-gpu-diagnostics');(args.output.parent/'android-build.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
