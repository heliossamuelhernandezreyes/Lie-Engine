"""Stage the actual alternate surface renderer and attributed compiler outputs."""
import argparse,json,re,shutil
from pathlib import Path
import lie_renderer_audit_build as previous
from lie_direct_surface import compile_fields,BANK_SHA
ROOT=Path(__file__).resolve().parents[1]

def stage_project(destination):
    report=previous.stage_project(destination);source=ROOT/'gpu_compute'
    field=source/'captures/liewall06/direct'
    if not (field/'surface.json').exists():compile_fields()
    proof=json.loads((field/'surface.json').read_text())
    if proof['source_bank_sha256']!=BANK_SHA:raise ValueError('Compiled field source identity')
    shutil.copytree(field,destination/'captures/liewall06/direct',dirs_exist_ok=True)
    for pattern in ['lie_direct*.gd','lie_direct*.tscn','shaders/lie_direct*.glsl','test_lie_direct*.gd']:
        for path in source.glob(pattern):
            target=destination/path.relative_to(source);target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,target)
    project=destination/'project.godot';text=project.read_text()
    for key,value in {'config/name':'"LIE Superficie directa 2.3"','config/version':'"2.3.0"','run/main_scene':'"res://lie_direct_lab.tscn"'}.items():text=previous.config_key(text,key,value)
    project.write_text(text)
    preset=destination/'export_presets.cfg';text=preset.read_text()
    for key,value in {'version/code':'24','version/name':'"2.3.0-direct-surface"','package/unique_name':'"org.lieengine.wallruntime.v230"','package/name':'"LIE Superficie directa 2.3"'}.items():text=previous.config_key(text,key,value)
    line=re.search(r'^include_filter="([^"]*)"$',text,re.M)
    text=previous.config_key(text,'include_filter','"'+line[1]+',captures/liewall06/direct/*.bin,captures/liewall06/direct/*.json"')
    preset.write_text(text)
    attribution=destination/'ATTRIBUTION.txt'
    attribution.write_text(attribution.read_text()+'\nLIE 2.3 modification: layered opaque depth/normal/linear-material fields compiled from the same attributed bank, shared brick master, native proxy/depth rendering and light-space shadows. No source mesh rendering.\n')
    report['direct_surface']={'schema':proof['schema'],'packets':proof['packets'],'scope':proof['scope']};return report

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--stage',type=Path,required=True)
    for name in ['godot','sdk','keystore','output']:p.add_argument('--'+name,type=Path)
    args=p.parse_args();report=stage_project(args.stage.resolve())
    if args.output:
        import lie_runtime_android_build as base
        report.update(base.export(args.stage.resolve(),args.godot.resolve(),args.sdk.resolve(),args.keystore.resolve(),args.output.resolve()))
        report.update(package='org.lieengine.wallruntime.v230',version='2.3.0-direct-surface')
        (args.output.parent/'android-build.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
