# R2 Android touch prototype

`lie_robot_mobile.tscn` runs the existing world lab with `touch_mode=true`.
The same validated `command()` controls the same collision actor, FK/IK rig,
assembly and custom LIE compute compositor. This is a playable test, not a
production game. Source meshes remain collision-only and are not displayed.

The APK is an offline ARM64 Android application, package
`org.lieengine.robotdemo`, label **LIE R2 Robot**, version `0.1.1-r2-metrics`
(version code 2). It updates the first signed APK with the same certificate.
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

## On-screen performance monitor

The **Datos** button shows/hides a live panel; **Copiar informe** copies the
actual readings and their scopes as JSON for sharing from a phone. **Reiniciar**
starts a new rolling measurement window. It refreshes approximately every
0.5 seconds (later if a frame stalls) without full GPU readback, networking,
root or additional Android permissions.

- Screen FPS is Godot's once-per-second rendered-frame monitor. **Reconstr.
  LIE/s** counts actual compute reconstruction updates, which can be zero when
  an unchanged image is cached. Screen FPS alone is not reconstruction speed.
- Frame p50/p95 uses the monotonic wall clock between process callbacks, over
  at most 600 recent samples. It includes scheduling and vsync. Simulation
  `delta` can be capped/time-scaled, so it must not stand in for real frame time.
- **CPU proceso** is the change in `/proc/self/stat` utime+stime over elapsed
  clock time, normalized by the logical core count. Raw one-core percentage
  remains in the report (100% = one busy core; it can exceed 100% across
  threads). The tick frequency is read from `AT_CLKTCK` in `/proc/self/auxv`,
  the same source as Android bionic `sysconf(_SC_CLK_TCK)`; it is not assumed.
  This measures this process, not other apps, CPU frequency or thermals.
- RAM is approximate process RSS and kernel peak RSS from `/proc/self/status`.
  Shared resident pages are included; this is not Android PSS or exclusive
  private memory. Godot's allocator counter is a separate report field.
- GPU frame time comes from native viewport timestamp measurements. **GPU
  LIE última** is the last compute-marker duration and its age, converted from
  the pinned 4.7.2 Vulkan driver's nanoseconds to milliseconds. Captured marker
  and viewport values can refer to adjacent frames because profiling is
  asynchronous; do not subtract them as if they were one aligned frame.
- GPU memory distinguishes the global RenderingDevice/Vulkan allocator from
  requested LIE buffer/image bytes. On unified-memory phones these can overlap
  system RAM; do not sum them with RSS.
- Overall hardware GPU utilization is explicitly **N/D** / JSON null. It is
  not inferred from FPS or timestamp duration. Denied proc reads, unavailable
  driver counters and a first CPU sample also report unavailable/waiting.

The monitor contributes some overhead. It is a practical diagnostic tool, not
an Android system profiler or a physical-device performance guarantee.

Sources: Godot `Performance`, `RenderingServer` and `RenderingDevice` class
references; Linux procfs documentation; Android bionic sysconf implementation.
Note: the Godot RenderingDevice reference currently describes GPU timestamp
units as microseconds, while the pinned 4.7.2 Vulkan driver's
`timestamp_query_result_to_time` returns nanoseconds. The implementation was
checked directly and concurrent viewport readings confirm millisecond scale.

https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/vulkan/rendering_device_driver_vulkan.cpp
https://android.googlesource.com/platform/bionic/+/refs/heads/main/libc/bionic/sysconf.cpp
https://www.kernel.org/doc/Documentation/filesystems/proc.txt

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
GPU mode checks real Mobile-compositor pixels, bank residency, live process/
GPU counters, native touch toggling and actual clipboard JSON, and saves an
actual native HUD screenshot. Latest result: **262,172 checks pass** on
llvmpipe software Vulkan, with one immutable bank upload. Existing motion
3,019 checks, rig 3,734 checks, agent 20 checks and Python 72 tests (one skip)
also pass. No Android device/emulator has run the packaged application yet.
`test_robot_performance.gd` adds 15 checks, including actual procfs counters,
a real CPU workload, unavailable data handling, auxiliary clock units and
elapsed frame time despite a deliberately short simulation delta.

The first visual check found joystick drawing covered by the background;
controls now draw in a separate top overlay. Export attempts also retained the
missing ETC2 import flag, invalid prebuilt SDK overrides and untyped feature
metadata failures. The corrected pipeline enables ETC2/ASTC imports and uses
the template's SDK levels. These are development failures, not successful phone
tests. Future art, contact physics and physical-device performance remain work.
The first monitor screenshot used simulation delta for frame pacing and
underreported stalls; retained evidence shows it beside real GPU timings.
The corrected version uses monotonic elapsed time and explicitly labels
asynchronous GPU sample age and memory/CPU scopes.
