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

## Validation update 2026-11-09

292 Python tests passed (one skip) with the pinned dependency environment.
Godot 4.7.2 import and native visibility/physics/hardware/rig/agent headless
suites passed. Actual llvmpipe Vulkan real-bank surface suite: 27 checks passed,
including full 480,000-sample brick, atomic budget rejection, production/probe
byte equality, all eight A/B/B/A blocks, restoration and a ~16.3 kB clipboard.
The headless metrics/report suite now passes 12 checks including sixty blocks,
exact declared dense statistics and nested-history removal without mutation.

The first full-bank continuous prototype was slower than frozen 6.4 on this
CPU Vulkan implementation, especially close up; no mobile speedup is claimed.
It exposed 119,239,716 candidate footprint pixels with only 13,788,358 supported.
Conservative pre-clipping to the ALREADY authoritative source bounds, support
rectangle and instance cut reduces candidates to 33,126,272 (72.2% less), while
the supported and material counts stay identical. A single lane computes a
shared conservative workgroup bound. No source data, clipping predicate or
visible disk coverage is removed. Before/after real-bank color, depth and
shadow snapshot buffers are byte-identical; both surface suites pass 27 checks.
All 29 independent-oracle Vulkan cases also pass after this work reduction,
with zero coverage or owner mismatches and exact color. Five instrumented
cases remain byte-exact. All 105 immutable source files match.

Local negative runs retained: launching the full scene with SwiftShader lacks
VK_KHR_xlib_surface and falls back to OpenGL; this is not GPU acceptance. The
full compositor passes instead use actual Mesa llvmpipe Vulkan. A Python run
from the base runtime lacked optional capture dependencies; the pinned venv
passes all 292 tests. The first sixty-block summary exceeded the copy bound;
a declared column layout now retains every block and exact statistics.

Final CI, frozen-6.4 image comparison and verified ARM64 APK are still pending.

## Read-only diagnostic refinement

All seven local real-bank GPU suites passed 256 checks. CI also passed the
real-bank suites on LLVM 21, but the first frozen-image comparison stopped at
a missing `surface_probe` state key in the baseline. Both controls now
explicitly set that diagnostic flag false; state/sample/float comparisons
remain strict. The next CI run rejected the `opaque_close` instrumented
fixture. The original combined assertion did not preserve whether pixels or
counters differed, so no specific floating-point or driver cause is claimed.
Detailed per-buffer mismatches are now preserved. A later diagnostic run
passed all fixtures, all real-bank suites and the frozen float comparison.

The diagnostic path is now isolated structurally: production SPIR-V renders
first; four extra GPU traversals then read the production projections, depth,
winners and source data. Their image/visibility buffers are declared read-only
and only queue statistics are written. Counters run after production GPU end
timestamps and outside benchmark blocks. All seven exported production
SPIR-V binaries are byte-identical before/after this isolation. A separate
Vulkan replay synchronization defect was found and fixed: shader writes to
the queue now become visible to DRAW_INDIRECT/INDIRECT_COMMAND_READ. Godot
4.7.2 already tracks RESOURCE_USAGE_INDIRECT_BUFFER_READ in its public dispatch
implementation; its path was not replaced.

The revised diagnostic passes all 29 oracle fixtures on both SwiftShader and
Mesa 26/LLVM 19 locally; the complete 292-test Python suite still passes with
one skip. Current compositor/control and final Android checks remain pending.
