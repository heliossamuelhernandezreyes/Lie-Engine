# R2 Android touch prototype

`lie_robot_mobile.tscn` runs the existing world lab with `touch_mode=true`.
The same validated `command()` controls the same collision actor, FK/IK rig,
assembly and custom LIE compute compositor. This is a playable test, not a
production game. Source meshes remain collision-only and are not displayed.

The APK is an offline ARM64 Android application, package
`org.lieengine.robotdemo`, label **LIE R2 Robot**, version `0.1.0-r2-test`.
Godot's 4.7.2 prebuilt template declares minimum API 24 and target API 36.
Actual use needs a working Vulkan Mobile renderer; the Poco X7 Pro must still
be tested by its owner. There is no physical Android/FPS claim.

## Controls

Use the phone horizontally. Hold the bottom-left joystick: vertical motion
walks forward/backward and horizontal motion turns the robot. Drag elsewhere
below the header to orbit the camera. Finger IDs remain independent, so walking
and looking work simultaneously. Releasing movement clears its input; losing
application focus clears every finger and pauses. The top buttons reset the
entrance, toggle overview/roof/shadows/grip, adjust camera distance and pause.
The roof adds/removes the same source collision surfaces as the desktop.

The HUD keeps the original square reconstruction centered in a responsive
landscape viewport. Output is 512 square / internal reconstruction 1024 square,
instead of desktop 768 / 1536. The bank, geometry, work budget, shader and
motion remain unchanged. The verified software-Vulkan allocation is 260,979,520
bytes (about 249 MiB), excluding the rest of Godot/Android. Lower output does
not establish a phone frame rate. The Shadows button can reduce compute work.

This dedicated export omits the desktop file agent autoload, unrelated labs,
source Blender/GLB files and other capture banks. Desktop agent control is
unchanged. Raw JSON/bin filters include the combined bank and collision data;
both are verified byte-for-byte inside the final APK.

## Build

Restore `captures/robot_world` from the exact R2 asset package/checkpoint.
Install official Godot **4.7.2** and its matching Android export templates,
OpenJDK 17 and the official Android SDK. This build used command-line tools
15859902, platform-tools, Android platform 35 and build-tools 35.0.1. Prebuilt
APK export does not require a Gradle/NDK source compilation.

Set the Godot Editor Settings Android Java SDK path to the JDK directory.
The builder sets its Android SDK path, stages only declared dependencies in
a fresh directory, imports shaders using a real Vulkan display, and exports
the debug APK. The general `gpu_compute/project.godot` remains unchanged.

```sh
python tools/lie_robot_android_build.py \
  --godot /absolute/path/godot \
  --sdk /absolute/path/android-sdk \
  --keystore /absolute/path/android-debug.keystore \
  --stage /absolute/path/new-empty-stage \
  --output /absolute/path/LIE-R2-Robot-Prueba.apk
```

The keystore is an Android debug key, alias `androiddebugkey`, password
`android`. Its private bytes are saved separately with the APK checkpoint and
are not committed to Git. Reuse that exact key for installable updates; a
different certificate requires uninstalling the previous test application.
The APK has no Internet/storage/location/camera/microphone permission.

`lie_android_manifest.py` repairs the prebuilt exporter metadata before final
alignment/signing: Vulkan feature `required` and `version` need native binary
XML Boolean/integer types and the `android:version` resource ID; AndroidX
Startup must have its own authority instead of reusing FileProvider's.
These problems are visible in Godot 4.7.2's `platform/android/export/export_plugin.cpp`.
The normalizer preserves values, uses SDK attr/version `0x01010519`, is
idempotent, and does not change any scene/bank/native-library payload.
`zipalign -P 16`, `apksigner verify` and `aapt dump badging` validate the result.
The engine ELF load segments are aligned to 16 KiB.

Official setup: https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html
Exporter source: https://github.com/godotengine/godot/blob/4.7.2-stable/platform/android/export/export_plugin.cpp
Compositor support: https://docs.godotengine.org/en/stable/tutorials/rendering/compositor.html

## Verification and limits

```sh
godot --headless --path gpu_compute --script res://test_robot_touch.gd
godot --path gpu_compute --script res://test_robot_touch.gd \
  --rendering-method mobile --audio-driver Dummy -- --gpu
```

The touch test sends actual screen-touch/drag events through the native
Viewport. It exercises simultaneous movement/camera, a third-finger GUI
button, release order, turning, collision movement, focus loss, reset, roof
colliders and grip. Buttons receive native touch without mouse emulation.
GPU mode checks real Mobile-compositor pixels and bank residency and saves an
actual native HUD screenshot. Latest result: **262,165 checks pass** on
llvmpipe software Vulkan, with one immutable bank upload. Existing motion
3,019 checks, rig 3,734 checks, agent 20 checks and Python 72 tests (one skip)
also pass. No Android device/emulator has run the packaged application yet.

The first visual check found joystick drawing covered by the background;
controls now draw in a separate top overlay. Export attempts also retained the
missing ETC2 import flag, invalid prebuilt SDK overrides and untyped feature
metadata failures. The corrected pipeline enables ETC2/ASTC imports and uses
the template's SDK levels. These are development failures, not successful phone
tests. Future art, contact physics and physical-device performance remain work.
