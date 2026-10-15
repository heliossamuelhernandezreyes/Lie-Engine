"""Build the isolated stable-identity and persistent-light Android experiment."""
import argparse,json,re,shutil
from pathlib import Path
import lie_wall10_android_build as previous
from lie_persistent_reference import prepare as prepare_reference
ROOT=Path(__file__).resolve().parents[1]
def stage_project(destination):
    prepare_reference();report=previous.stage_project(destination)
    source=ROOT/'gpu_compute';pending=['lie_wall11_android_lab.tscn','test_lie_wall11_mobile.gd','test_lie_wall11_commands.gd','test_lie_sample_identity.gd','test_lie_persistent_gpu.gd'];copied=set()
    pattern=re.compile(r'(?:\bextends\s+|\b(?:preload|load)\s*\(\s*|\bpath\s*=\s*)"res://([^"]+)"')
    while pending:
        name=pending.pop()
        if name in copied:continue
        path=source/name;out=destination/name;out.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,out);copied.add(name)
        if path.suffix in ('.gd','.tscn','.tres'):pending.extend(pattern.findall(path.read_text()))
    # This parent dependency was already copied by the previous stage; refresh
    # it explicitly because it now supplies generation-guarded sample handles.
    for name in ['lie_shared_sample_buffers.gd','lie22_modular_effect.gd']:shutil.copy2(source/name,destination/name)
    shutil.copy2(source/'fixtures/persistent-visibility-reference.json',destination/'fixtures/persistent-visibility-reference.json')
    project=destination/'project.godot';project.write_text(project.read_text().replace('LIE Superficie 0.7','LIE Identidad 0.8').replace('0.7.0','0.8.0').replace('lie_wall10_android_lab.tscn','lie_wall11_android_lab.tscn'))
    preset=destination/'export_presets.cfg';preset.write_text(preset.read_text().replace('version/code=7','version/code=8').replace('0.7.0-source-continuity','0.8.0-persistent-light').replace('v070','v080').replace('LIE Superficie 0.7','LIE Identidad 0.8'))
    return report
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--stage',type=Path,required=True);p.add_argument('--godot',type=Path);p.add_argument('--sdk',type=Path);p.add_argument('--keystore',type=Path);p.add_argument('--output',type=Path);args=p.parse_args();report=stage_project(args.stage.resolve())
    if args.output:
        report.update(previous.previous.previous.previous.previous.base.export(args.stage.resolve(),args.godot.resolve(),args.sdk.resolve(),args.keystore.resolve(),args.output.resolve()));report.update(package='org.lieengine.wallruntime.v080',version='0.8.0-persistent-light');(args.output.parent/'android-build.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
