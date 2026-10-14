"""Build the isolated WALL05 phone laboratory; offline, one shared brick master."""
import argparse,json,re,shutil,hashlib
from pathlib import Path
import lie_runtime_android_build as base
from lie_wall05_shared import build
from lie_wall05_reference import write as write_reference
ROOT=Path(__file__).resolve().parents[1]

def stage_project(destination):
    build()
    write_reference()
    base.PROJECT=base.PROJECT.replace('config/name="LIE Pared"','config/name="LIE Pared 0.2"').replace('config/version="0.1.0"','config/version="0.2.0"').replace('lie_runtime_android_lab.tscn','lie_wall05_android_lab.tscn')
    # Godot 4.7.2's ShaderFile editor preview checks scene visibility from an
    # import worker. Serial import avoids that editor-only thread violation.
    base.PROJECT+='\n[editor]\nimport/use_multiple_threads=false\n'
    base.PRESET=base.PRESET.replace('version/code=1','version/code=2').replace('0.1.0-runtime-lighting','0.2.0-shared-optical').replace('org.lieengine.wallruntime','org.lieengine.wallruntime.v020').replace('package/name="LIE Pared"','package/name="LIE Pared 0.2"').replace('include_filter="','include_filter="captures/liewall05/*.bin,captures/liewall05/*.json,').replace('exclude_filter="','exclude_filter="captures/liewall04/library.bin,')
    report=base.stage_project(destination)
    pattern=re.compile(r'(?:\bextends\s+|\b(?:preload|load)\s*\(\s*|\bpath\s*=\s*)"res://([^"]+)"')
    pending=['lie_wall05_android_lab.tscn','test_lie_wall05_mobile.gd'];copied=set()
    while pending:
        name=pending.pop()
        if name in copied:continue
        p=ROOT/'gpu_compute'/name
        if not p.is_file():raise ValueError('Missing WALL05 dependency '+name)
        out=destination/name;out.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,out);copied.add(name)
        if p.suffix in ('.gd','.tscn','.tres'):pending.extend(pattern.findall(p.read_text()))
    shutil.copytree(ROOT/'gpu_compute/captures/liewall05',destination/'captures/liewall05')
    (destination/'fixtures').mkdir(exist_ok=True)
    shutil.copy2(ROOT/'gpu_compute/fixtures/wall05-neutral-reference.json',destination/'fixtures/wall05-neutral-reference.json')
    (destination/'ATTRIBUTION.txt').write_text((destination/'ATTRIBUTION.txt').read_text()+'\nWALL05: same original neutral brick records and photographic mortar; source-ID indirection, geometry/light caches and experimental opaque directional transport.\n')
    cat=json.loads((destination/'captures/liewall05/catalog.json').read_text())
    report.update(shared_bank_bytes=cat['bytes'],shared_bank_sha256=cat['sha256'],source_reference_bytes=cat['wall05']['reference_bytes'],brick_master_count=1,brick_instances=96)
    return report
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--stage',type=Path,required=True);p.add_argument('--godot',type=Path);p.add_argument('--sdk',type=Path);p.add_argument('--keystore',type=Path);p.add_argument('--output',type=Path)
    args=p.parse_args();report=stage_project(args.stage.resolve())
    if args.output:
        if not all((args.godot,args.sdk,args.keystore)):raise ValueError('Export requires Godot, SDK and debug key')
        report.update(base.export(args.stage.resolve(),args.godot.resolve(),args.sdk.resolve(),args.keystore.resolve(),args.output.resolve()))
        report.update(package='org.lieengine.wallruntime.v020',version='0.2.0-shared-optical')
        (args.output.parent/'android-build.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
