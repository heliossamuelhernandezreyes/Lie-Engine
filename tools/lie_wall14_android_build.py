"""Stage verified WALL13 rendering with selectable reports and touch inspection."""
import argparse,json,re,shutil
from pathlib import Path
import lie_wall13_android_build as previous
ROOT=Path(__file__).resolve().parents[1]
def stage_project(destination):
    report=previous.stage_project(destination)
    source=ROOT/'gpu_compute';pending=['lie_wall14_android_lab.tscn','test_lie_wall14_commands.gd','test_lie_mobile_diagnostics.gd','test_lie_wall14_mobile.gd'];copied=set()
    pattern=re.compile(r'(?:\bextends\s+|\b(?:preload|load)\s*\(\s*|\bpath\s*=\s*)"res://([^"]+)"')
    while pending:
        name=pending.pop()
        if name in copied:continue
        path=source/name;out=destination/name;out.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,out);copied.add(name)
        if path.suffix in ('.gd','.tscn','.tres'):pending.extend(pattern.findall(path.read_text()))
    project=destination/'project.godot';project.write_text(project.read_text().replace('LIE Área 1.0','LIE Diagnóstico 1.1').replace('1.0.0','1.1.0').replace('lie_wall13_android_lab.tscn','lie_wall14_android_lab.tscn'))
    preset=destination/'export_presets.cfg';preset.write_text(preset.read_text().replace('version/code=10','version/code=11').replace('1.0.0-area-continuity','1.1.0-diagnostics-touch').replace('v100','v110').replace('LIE Área 1.0','LIE Diagnóstico 1.1'))
    return report
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--stage',type=Path,required=True);p.add_argument('--godot',type=Path);p.add_argument('--sdk',type=Path);p.add_argument('--keystore',type=Path);p.add_argument('--output',type=Path);args=p.parse_args();report=stage_project(args.stage.resolve())
    if args.output:
        import lie_runtime_android_build as base
        report.update(base.export(args.stage.resolve(),args.godot.resolve(),args.sdk.resolve(),args.keystore.resolve(),args.output.resolve()));report.update(package='org.lieengine.wallruntime.v110',version='1.1.0-diagnostics-touch');(args.output.parent/'android-build.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
