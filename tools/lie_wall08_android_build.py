"""Stage and export the source-separated LIE lighting laboratory."""
import argparse,json,re,shutil,math
from pathlib import Path
import numpy as np
import lie_wall07_android_build as previous
from lie_wall08_prepare import prepare
from lie_light_field import prepare_fixture,solve
ROOT=Path(__file__).resolve().parents[1]

def wall_reference(root):
    model=json.loads((root/'light-model.json').read_text());model['blockers']=[]
    cat=json.loads((root/'catalog.json').read_text());bounds=cat['masters']['real_scan_wall'];center=np.array(bounds['bounds_center']);reach=max(1.,bounds['bounds_size'][0]*.48)
    lights=[]
    for angle,height,power,rgb in [(-24.,.78,55.,[1.,.93,.86]),(55.,.34,55.*.32,[.44,.72,1.])]:
        rad=math.radians(angle);p=center+[math.sin(rad)*reach,height,math.cos(rad)*reach+.25]
        lights.append({'position':p.tolist(),'radius':6.,'power_rgb':(power*np.array(rgb)).tolist()})
    model['lights']=lights;proof=json.loads((root/'light-field.json').read_text());pack={key:(root/meta['file']).read_bytes() for key,meta in proof['sources'].items()}
    result=solve(model,pack);result.update(schema='lie-wall08-field-reference/1',lights=lights,source_bank_sha256=cat['sha256'])
    return result

def stage_project(destination):
    report=previous.stage_project(destination);prepare();prepare_fixture()
    source=ROOT/'gpu_compute';root=source/'captures/liewall06'
    for name in ['light-field.json','field-owners.bin','field-boxes.bin']:shutil.copy2(root/name,destination/'captures/liewall06'/name)
    reference=wall_reference(root);(destination/'fixtures/wall08-field-reference.json').write_text(json.dumps(reference,indent=2)+'\n')
    shutil.copy2(source/'fixtures/light-field-reference.json',destination/'fixtures/light-field-reference.json')
    pattern=re.compile(r'(?:\bextends\s+|\b(?:preload|load)\s*\(\s*|\bpath\s*=\s*)"res://([^"]+)"')
    pending=['lie_wall08_android_lab.tscn','test_lie_light_registry.gd','test_lie_light_field_gpu.gd','test_lie_wall08_mobile.gd'];copied=set()
    while pending:
        name=pending.pop()
        if name in copied:continue
        path=source/name;out=destination/name;out.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,out);copied.add(name)
        if path.suffix in ('.gd','.tscn','.tres'):pending.extend(pattern.findall(path.read_text()))
    # Loader is referenced by the adapter; source packets are verified at load.
    project=destination/'project.godot';project.write_text(project.read_text().replace('LIE Pared 0.4','LIE Luz 0.5').replace('0.4.0','0.5.0').replace('lie_wall07_android_lab.tscn','lie_wall08_android_lab.tscn'))
    preset=destination/'export_presets.cfg';preset.write_text(preset.read_text().replace('version/code=4','version/code=5').replace('0.4.0-common-assets','0.5.0-source-light-field').replace('v040','v050').replace('LIE Pared 0.4','LIE Luz 0.5'))
    attribution=destination/'ATTRIBUTION.txt';attribution.write_text(attribution.read_text()+'\nWALL08: common opaque light field, explicit source ownership and eight source-light directional frontiers. Same captured source geometry and colors.\n')
    return report

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--stage',type=Path,required=True);p.add_argument('--godot',type=Path);p.add_argument('--sdk',type=Path);p.add_argument('--keystore',type=Path);p.add_argument('--output',type=Path);args=p.parse_args();report=stage_project(args.stage.resolve())
    if args.output:
        report.update(previous.previous.base.export(args.stage.resolve(),args.godot.resolve(),args.sdk.resolve(),args.keystore.resolve(),args.output.resolve()));report.update(package='org.lieengine.wallruntime.v050',version='0.5.0-source-light-field');(args.output.parent/'android-build.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
