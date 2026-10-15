"""Stage dedicated GPU kernels and a paired three-binary phone diagnostic."""
import argparse,json,re,shutil
from pathlib import Path
import lie_wall16_android_build as previous
ROOT=Path(__file__).resolve().parents[1]
def stage_project(destination):
    report=previous.stage_project(destination)
    source=ROOT/'gpu_compute';pending=['lie_wall17_android_lab.tscn','test_lie_wall17_commands.gd','test_lie_wall17_mobile.gd'];copied=set()
    pattern=re.compile(r'(?:\bextends\s+|\b(?:preload|load)\s*\(\s*|\bpath\s*=\s*)"res://([^"]+)"')
    while pending:
        name=pending.pop()
        if name in copied:continue
        path=source/name;out=destination/name;out.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,out);copied.add(name)
        if path.suffix in ('.gd','.tscn','.tres'):pending.extend(pattern.findall(path.read_text()))
    project=destination/'project.godot';project.write_text(project.read_text().replace('LIE Consultas 1.3','LIE Kernels 1.4').replace('1.3.0','1.4.0').replace('lie_wall16_android_lab.tscn','lie_wall17_android_lab.tscn'))
    preset=destination/'export_presets.cfg';preset.write_text(preset.read_text().replace('version/code=13','version/code=14').replace('1.3.0-surface-queries','1.4.0-stage-kernels').replace('v130','v140').replace('LIE Consultas 1.3','LIE Kernels 1.4'))
    return report
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--stage',type=Path,required=True);p.add_argument('--godot',type=Path);p.add_argument('--sdk',type=Path);p.add_argument('--keystore',type=Path);p.add_argument('--output',type=Path);args=p.parse_args();report=stage_project(args.stage.resolve())
    if args.output:
        import lie_runtime_android_build as base
        report.update(base.export(args.stage.resolve(),args.godot.resolve(),args.sdk.resolve(),args.keystore.resolve(),args.output.resolve()));report.update(package='org.lieengine.wallruntime.v140',version='1.4.0-stage-kernels');(args.output.parent/'android-build.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
