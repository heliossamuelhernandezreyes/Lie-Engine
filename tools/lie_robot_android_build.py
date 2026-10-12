#!/usr/bin/env python3
"""Stage an isolated R2 Android project; preserve the desktop entry point."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from lie_android_manifest import normalize_apk

FILES = [
    "lie_robot_mobile.tscn", "lie_robot_world_lab.gd", "lie_robot_touch_hud.gd",
    "lie_robot_world_effect.gd", "lie_robot_effect.gd", "lie22_modular_effect.gd",
    "lie_robot_assembly.gd", "lie_robot_world_layout.gd", "lie_robot_controller.gd",
    "lie26_rig.gd", "lie28_building_assembly.gd",
    "shaders/lie_robot.glsl", "shaders/lie22_modular.glsl",
    "captures/robot_world/catalog.json", "captures/robot_world/library.bin",
    "captures/robot_world/collision.bin",
]
PROJECT = '''config_version=5
[application]
config/name="LIE R2 Robot"
config/version="0.1.0"
config/icon="res://icon.svg"
run/main_scene="res://lie_robot_mobile.tscn"
boot_splash/bg_color=Color(0.063,0.098,0.141,1)
[display]
window/size/viewport_width=1280
window/size/viewport_height=720
window/size/window_width_override=1280
window/size/window_height_override=720
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"
window/handheld/orientation=0
[input_devices]
pointing/emulate_mouse_from_touch=false
pointing/emulate_touch_from_mouse=false
[rendering]
renderer/rendering_method="mobile"
renderer/rendering_method.mobile="mobile"
rendering_device/driver.android="vulkan"
textures/vram_compression/import_etc2_astc=true
textures/default_filters/use_nearest_mipmap_filter=false
'''
PRESET = '''[preset.0]
name="R2 Android"
platform="Android"
runnable=true
advanced_options=false
export_filter="all_resources"
include_filter="captures/robot_world/*.bin,captures/robot_world/*.json,ATTRIBUTION.txt"
exclude_filter="test_*,*.log,*.apk"
script_export_mode=2
[preset.0.options]
gradle_build/use_gradle_build=false
architectures/armeabi-v7a=false
architectures/arm64-v8a=true
architectures/x86=false
architectures/x86_64=false
version/code=1
version/name="0.1.0-r2-test"
package/unique_name="org.lieengine.robotdemo"
package/name="LIE R2 Robot"
package/signed=true
package/app_category=0
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
ICON = '''<svg xmlns="http://www.w3.org/2000/svg" width="432" height="432" viewBox="0 0 432 432"><rect width="432" height="432" rx="90" fill="#101924"/><path d="M122 144h188v144H122z" fill="#355a73"/><path d="M153 176h126v48H153z" fill="#83dfeb"/><circle cx="180" cy="200" r="14" fill="#101924"/><circle cx="252" cy="200" r="14" fill="#101924"/><path d="M172 255h88" stroke="#ffad43" stroke-width="12"/><path d="M216 114v30" stroke="#83dfeb" stroke-width="12"/></svg>'''

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1] / "gpu_compute")
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--godot", type=Path)
    parser.add_argument("--sdk", type=Path)
    parser.add_argument("--keystore", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    stage = args.stage.resolve()
    if stage.exists() and any(stage.iterdir()):
        raise SystemExit("Use an empty staging directory to prevent stale exports")
    stage.mkdir(parents=True, exist_ok=True)
    catalog = json.loads((args.root / "captures/robot_world/catalog.json").read_text())
    bank = args.root / "captures/robot_world/library.bin"
    if hashlib.sha256(bank.read_bytes()).hexdigest() != catalog["sha256"]:
        raise SystemExit("Combined bank hash mismatch")
    for name in FILES:
        destination = stage / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(args.root / name, destination)
    (stage / "project.godot").write_text(PROJECT)
    (stage / "export_presets.cfg").write_text(PRESET)
    (stage / "icon.svg").write_text(ICON)
    (stage / "ATTRIBUTION.txt").write_text(
        "LIE Engine R2 experimental robot/collision scene.\n"
        "Materials: Poly Haven, Rob Tuytel, CC0: blue_metal_plate, metal_plate_02.\n"
        "https://polyhaven.com/a/blue_metal_plate\nhttps://polyhaven.com/a/metal_plate_02\n"
        "Architecture: Poly Haven / Rob Tuytel, CC0: factory_brick and concrete.\nhttps://polyhaven.com/a/factory_brick\nhttps://polyhaven.com/a/concrete\n"
        "Godot Engine 4.7.2, MIT: https://godotengine.org/license/\n"
        "Copyright (c) 2014-present Godot Engine contributors.\n"
        "Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.\n"
        "Permission is hereby granted, free of charge, to any person obtaining a copy\n"
        "of this software and associated documentation files (the Software), to deal\n"
        "in the Software without restriction, including without limitation the rights\n"
        "to use, copy, modify, merge, publish, distribute, sublicense, and/or sell\n"
        "copies of the Software, and to permit persons to whom the Software is\n"
        "furnished to do so, subject to the following conditions:\n"
        "The above copyright notice and this permission notice shall be included in\n"
        "all copies or substantial portions of the Software.\n"
        "THE SOFTWARE IS PROVIDED AS IS, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR\n"
        "IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,\n"
        "FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE\n"
        "AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER\n"
        "LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,\n"
        "OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN\n"
        "THE SOFTWARE.\n"
    )
    if not args.output:
        print(stage)
        return
    if not all([args.godot, args.sdk, args.keystore]):
        raise SystemExit("Export requires --godot --sdk --keystore")
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    private = Path(tempfile.mkdtemp(prefix="lie-r2-android-export-"))
    raw_apk = private / "godot-export.apk"
    env = os.environ.copy()
    env.update(GODOT_ANDROID_KEYSTORE_DEBUG_PATH=str(args.keystore.resolve()),
               GODOT_ANDROID_KEYSTORE_DEBUG_USER="androiddebugkey",
               GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD="android")
    # Godot's prebuilt APK path needs no Gradle, NDK or CMake source build.
    sdk = args.sdk.resolve()
    settings = Path.home() / ".config/godot/editor_settings-4.7.tres"
    if not settings.exists():
        settings.parent.mkdir(parents=True, exist_ok=True)
        settings.write_text('[gd_resource type="EditorSettings" format=3]\n[resource]\n')
    text = settings.read_text()
    key = "export/android/android_sdk_path"
    lines = [line for line in text.splitlines() if not line.startswith(key)]
    settings.write_text("\n".join(lines) + f'\n{key} = {json.dumps(str(sdk))}\n')
    cmd = [str(args.godot.resolve()), "--path", str(stage), "--editor", "--import", "--quit", "--audio-driver", "Dummy"]
    with (output.parent / "r2-android-build.log").open("w") as log:
        subprocess.run(cmd, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
        subprocess.run([str(args.godot.resolve()), "--headless", "--path", str(stage),
                        "--export-debug", "R2 Android", str(raw_apk)], env=env,
                       stdout=log, stderr=subprocess.STDOUT, check=True)
        normalized = private / "manifest-normalized.apk"
        aligned = private / "aligned.apk"
        changed = normalize_apk(raw_apk, normalized)
        build_tools = sorted((sdk / "build-tools").iterdir())[-1]
        subprocess.run([str(build_tools / "zipalign"), "-f", "-P", "16", "4",
                        str(normalized), str(aligned)], stdout=log, stderr=subprocess.STDOUT, check=True)
        subprocess.run([str(build_tools / "apksigner"), "sign", "--ks", str(args.keystore.resolve()),
                        "--ks-pass", "pass:android", "--ks-key-alias", "androiddebugkey", str(aligned)],
                       stdout=log, stderr=subprocess.STDOUT, check=True)
        subprocess.run([str(build_tools / "apksigner"), "verify", "--verbose", str(aligned)],
                       stdout=log, stderr=subprocess.STDOUT, check=True)
        subprocess.run([str(build_tools / "aapt"), "dump", "badging", str(aligned)],
                       stdout=log, stderr=subprocess.STDOUT, check=True)
        log.write(f"\nNormalized feature attributes: {changed}\n")
    # Publish only completed bytes; do not expose live signing intermediates in
    # a workspace which may be synchronized between tool processes.
    temporary_output = output.with_suffix(".apk.tmp")
    shutil.copyfile(aligned, temporary_output)
    temporary_output.replace(output)
    print(json.dumps({"apk": str(output), "bytes": output.stat().st_size,
                      "sha256": hashlib.sha256(output.read_bytes()).hexdigest()}))

if __name__ == "__main__":
    main()
