"""Stage and export an isolated offline WALL04 ARM64 phone laboratory."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from lie_android_manifest import normalize_apk

ROOT=Path(__file__).resolve().parents[1]
PROJECT='''config_version=5
[application]
config/name="LIE Pared"
config/version="0.1.0"
config/icon="res://icon.svg"
run/main_scene="res://lie_runtime_android_lab.tscn"
boot_splash/bg_color=Color(0.025,0.034,0.045,1)
[display]
window/size/viewport_width=1280
window/size/viewport_height=800
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"
window/handheld/orientation=0
[input_devices]
pointing/emulate_mouse_from_touch=true
pointing/emulate_touch_from_mouse=false
[rendering]
renderer/rendering_method="mobile"
renderer/rendering_method.mobile="mobile"
rendering_device/driver.android="vulkan"
textures/vram_compression/import_etc2_astc=true
'''
PRESET='''[preset.0]
name="LIE Wall Android"
platform="Android"
runnable=true
advanced_options=false
export_filter="all_resources"
include_filter="captures/liewall04/*.bin,captures/liewall04/*.json,ATTRIBUTION.txt"
exclude_filter="test_*,*.log,*.apk"
script_export_mode=2
[preset.0.options]
gradle_build/use_gradle_build=false
architectures/armeabi-v7a=false
architectures/arm64-v8a=true
architectures/x86=false
architectures/x86_64=false
version/code=1
version/name="0.1.0-runtime-lighting"
package/unique_name="org.lieengine.wallruntime"
package/name="LIE Pared"
package/signed=true
screen/immersive_mode=true
screen/edge_to_edge=false
shader_baker/enabled=false
permissions/internet=false
permissions/access_network_state=false
permissions/vibrate=false
permissions/read_external_storage=false
permissions/write_external_storage=false
user_data_backup/allow=false
'''
ICON='''<svg xmlns="http://www.w3.org/2000/svg" width="432" height="432" viewBox="0 0 432 432"><rect width="432" height="432" rx="90" fill="#101924"/><g fill="#c19171"><path d="M70 95h133v69H70zM221 95h141v69H221zM70 180h61v69H70zM149 180h135v69H149zM302 180h60v69H302zM70 265h133v69H70zM221 265h141v69H221z"/></g></svg>'''

def stage_project(destination: Path) -> dict:
    if destination.exists() and any(destination.iterdir()):raise ValueError('Use an empty Android staging directory')
    destination.mkdir(parents=True,exist_ok=True)
    source=ROOT/'gpu_compute'
    pending=['lie_runtime_android_lab.tscn','test_lie_runtime_android.gd'];copied=set()
    # Only compile-time dependencies; dynamic bank roots are intentionally
    # resolved to the one verified WALL04 source below, not other laboratories.
    pattern=re.compile(r'(?:\bextends\s+|\b(?:preload|load)\s*\(\s*|\bpath\s*=\s*)"res://([^"]+)"')
    while pending:
        name=pending.pop()
        if name in copied:continue
        path=source/name
        if not path.is_file():raise ValueError('Missing runtime dependency '+name)
        out=destination/name;out.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,out);copied.add(name)
        if path.suffix in ('.gd','.tscn','.tres'):pending.extend(pattern.findall(path.read_text()))
    bank=source/'captures/liewall04'
    catalog=json.loads((bank/'catalog.json').read_text())
    raw=bank/'library.bin'
    if raw.stat().st_size!=catalog['bytes'] or hashlib.sha256(raw.read_bytes()).hexdigest()!=catalog['sha256']:
        raise ValueError('Real photographed wall bank integrity failed')
    if catalog['sha256']!='f6f7d9f726e909c7bfba2aff5e416d1b12d2162b07e50844f351ac273682e4da':
        raise ValueError('Unexpected WALL04 source revision')
    for name in ('catalog.json','library.bin','light-model.json','indirect_factors.bin','indirect_factors.json','indirect_sparse.bin','indirect_sparse.json'):
        out=destination/'captures/liewall04'/name;out.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(bank/name,out)
    (destination/'project.godot').write_text(PROJECT)
    (destination/'export_presets.cfg').write_text(PRESET)
    (destination/'icon.svg').write_text(ICON)
    # Include the actual published author, source, license and modifications.
    (destination/'ATTRIBUTION.txt').write_text(
        'LIE Pared 0.1.0 experimental WALL04 reconstruction.\n'
        'Stratford New Place Brick Ver 2 by Centre-of-Archaeology, CC BY 4.0.\n'
        'https://sketchfab.com/3d-models/stratford-new-place-brick-ver-2-6077f6801089403993f6a6612ff5739a\n'
        'License: https://creativecommons.org/licenses/by/4.0/\n'
        'Modifications: source vertex-color/XYZ sampling, transforms, deterministic wall layout, LOD and coded lighting.\n'
        'Mortar source: Poly Haven photographic PBR, CC0; see the source catalog below.\n'
        'Joint masks and metric relief remain unreviewed; not certified photorealism.\n'
        'Godot 4.7.2, MIT: https://godotengine.org/license/\n\n'
        +(ROOT/'tools/licenses/GODOT_LICENSE.txt').read_text()+'\n\n'
        +(ROOT/'assets/material_masters/mortar/hero/real_masonry_joint/material_manifest.json').read_text())
    return {'files':sorted(copied),'wall_sha256':catalog['sha256'],'wall_bytes':catalog['bytes']}

def export(stage: Path,godot: Path,sdk: Path,keystore: Path,output: Path) -> dict:
    output.parent.mkdir(parents=True,exist_ok=True)
    env=os.environ.copy()
    env.update(GODOT_ANDROID_KEYSTORE_DEBUG_PATH=str(keystore.resolve()),GODOT_ANDROID_KEYSTORE_DEBUG_USER='androiddebugkey',GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD='android')
    settings=Path.home()/'.config/godot/editor_settings-4.7.tres'
    settings.parent.mkdir(parents=True,exist_ok=True)
    text=settings.read_text() if settings.exists() else '[gd_resource type="EditorSettings" format=3]\n[resource]\n'
    keys={'export/android/android_sdk_path':str(sdk.resolve()),'export/android/java_sdk_path':str(Path(os.environ.get('JAVA_HOME','/usr/lib/jvm/java-17-openjdk-amd64')))}
    lines=[line for line in text.splitlines() if not any(line.startswith(key+' ') for key in keys)]
    settings.write_text('\n'.join(lines)+'\n'+''.join(f'{key} = {json.dumps(value)}\n' for key,value in keys.items()))
    private=Path(tempfile.mkdtemp(prefix='lie-wall-android-'))
    raw=private/'export.apk';normalized=private/'normalized.apk';aligned=private/'aligned.apk'
    bt=sdk/'build-tools/36.0.0'
    with (output.parent/'android-build.log').open('w') as log:
        subprocess.run([str(godot),'--headless','--path',str(stage),'--editor','--import','--quit'],env=env,stdout=log,stderr=subprocess.STDOUT,check=True)
        subprocess.run([str(godot),'--headless','--path',str(stage),'--export-debug','LIE Wall Android',str(raw)],env=env,stdout=log,stderr=subprocess.STDOUT,check=True)
        modified=normalize_apk(raw,normalized)
        subprocess.run([str(bt/'zipalign'),'-f','-P','16','4',str(normalized),str(aligned)],stdout=log,stderr=subprocess.STDOUT,check=True)
        subprocess.run([str(bt/'apksigner'),'sign','--ks',str(keystore),'--ks-pass','pass:android','--ks-key-alias','androiddebugkey',str(aligned)],stdout=log,stderr=subprocess.STDOUT,check=True)
        subprocess.run([str(bt/'apksigner'),'verify','--verbose',str(aligned)],stdout=log,stderr=subprocess.STDOUT,check=True)
        subprocess.run([str(bt/'zipalign'),'-c','-P','16','4',str(aligned)],stdout=log,stderr=subprocess.STDOUT,check=True)
        subprocess.run([str(bt/'aapt'),'dump','badging',str(aligned)],stdout=log,stderr=subprocess.STDOUT,check=True)
        log.write(f'\nNormalized manifest attributes: {modified}\n')
    temporary=output.with_suffix('.apk.tmp');shutil.copyfile(aligned,temporary);temporary.replace(output)
    report={'apk':str(output),'bytes':output.stat().st_size,'sha256':hashlib.sha256(output.read_bytes()).hexdigest(),'package':'org.lieengine.wallruntime','version':'0.1.0-runtime-lighting','physical_android_tested':False}
    (output.parent/'android-build.json').write_text(json.dumps(report,indent=2)+'\n')
    return report

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--stage',type=Path,required=True)
    p.add_argument('--godot',type=Path);p.add_argument('--sdk',type=Path);p.add_argument('--keystore',type=Path);p.add_argument('--output',type=Path)
    args=p.parse_args();stage=args.stage.resolve();report=stage_project(stage)
    if args.output:
        if not all((args.godot,args.sdk,args.keystore)):raise ValueError('Export requires Godot, Android SDK and a debug keystore')
        report.update(export(stage,args.godot.resolve(),args.sdk.resolve(),args.keystore.resolve(),args.output.resolve()))
    print(json.dumps(report,indent=2))
