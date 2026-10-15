"""Build WALL07 with reusable asset preflight and irradiance reconstruction."""
import argparse,json,re,shutil
from pathlib import Path
import lie_wall06_android_build as previous
from lie_wall07_prepare import prepare
from lie_light_fixture import prepare as prepare_fixture
ROOT=Path(__file__).resolve().parents[1]
def stage_project(destination):
    report=previous.stage_project(destination);prepare();prepare_fixture()
    source=ROOT/'gpu_compute'
    for name in ['asset-contract.json','light-groups.json','light-groups.bin']:shutil.copy2(source/'captures/liewall06'/name,destination/'captures/liewall06'/name)
    pattern=re.compile(r'(?:\bextends\s+|\b(?:preload|load)\s*\(\s*|\bpath\s*=\s*)"res://([^"]+)"')
    pending=['lie_wall07_android_lab.tscn','test_lie_wall07_mobile.gd','test_lie_asset_stencil_gpu.gd'];copied=set()
    while pending:
        name=pending.pop()
        if name in copied:continue
        path=source/name;out=destination/name;out.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,out);copied.add(name)
        if path.suffix in ('.gd','.tscn','.tres'):pending.extend(pattern.findall(path.read_text()))
    shutil.copy2(source/'fixtures/asset-light-reference.json',destination/'fixtures/asset-light-reference.json')
    project=destination/'project.godot';project.write_text(project.read_text().replace('LIE Pared 0.3','LIE Pared 0.4').replace('0.3.0','0.4.0').replace('lie_wall06_android_lab.tscn','lie_wall07_android_lab.tscn'))
    preset=destination/'export_presets.cfg';preset.write_text(preset.read_text().replace('version/code=3','version/code=4').replace('0.3.0-aligned-optical','0.4.0-common-assets').replace('v030','v040').replace('LIE Pared 0.3','LIE Pared 0.4'))
    attribution=destination/'ATTRIBUTION.txt';attribution.write_text(attribution.read_text()+'\nWALL07: source-preserving asset contract and convex irradiance reconstruction; same captured geometry/colors as WALL06.\n')
    return report
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--stage',type=Path,required=True);p.add_argument('--godot',type=Path);p.add_argument('--sdk',type=Path);p.add_argument('--keystore',type=Path);p.add_argument('--output',type=Path);args=p.parse_args();report=stage_project(args.stage.resolve())
    if args.output:
        report.update(previous.base.export(args.stage.resolve(),args.godot.resolve(),args.sdk.resolve(),args.keystore.resolve(),args.output.resolve()));report.update(package='org.lieengine.wallruntime.v040',version='0.4.0-common-assets');(args.output.parent/'android-build.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
