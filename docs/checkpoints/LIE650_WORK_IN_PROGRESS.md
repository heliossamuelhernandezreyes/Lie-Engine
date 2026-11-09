# LIE 6.5 surface reconstruction — work checkpoint

Base: 412ba1ffd2cee31906c24bb603d52cbd587fc083, runtime 6.4
94ac4f1ee225da96155f7e60433f9eaf11408f71. Original capture bytes remain intact.

Implemented so far: perspective disk conics; conservative clipped disk path;
cooperative 64-lane large-footprint queue in the existing jobs binding; distinct
depth/owner/material passes; material restricted to the winning instance;
separate compile-time instrumentation; reusable work arenas; frozen 6.4 camera
reference; A/B/B/A phone action; full original brick inspection; bounded report
copy with clipboard roundtrip; atomic sample-budget rejection.

First actual Vulkan execution of the new kernels on SwiftShader CPU recovered
65532/16228/15616/1476 visible pixels in the four audit fixtures. The original
path gave 16641/0/0/0. The red/blue 0.1 mm case now returns [1,0,0]; the 0.5 mm
control stays [1,0,0]. These are analytic test inputs, not replacement assets.

The existing Python suite passed 287 tests with one skip during implementation.
The new independent oracle/fixture tests and expanded actual-Vulkan cases are
being integrated. First staging found a formatted `load()` path unsupported by
the dependency crawler; the shader exporter now preloads the kernel catalog.
This negative is retained as a packaging issue, not rendering acceptance.

Pending before delivery: complete current parse/CPU and expanded Vulkan checks;
real attributed-bank compositor suites and probe equality; independent frozen
6.4 legacy-image comparison; mobile benchmark/report/restoration; reviewed
resource counts; signed/aligned/verified ARM64 APK and persistent deliverables.
No physical Android speedup or 60 FPS target is established by this checkpoint.
