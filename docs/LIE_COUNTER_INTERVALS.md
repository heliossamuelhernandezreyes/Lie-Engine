# LIE 1.8.1: isolate counter intervals

The supplied physical 1.8 report does not demonstrate a compact-view speed gain:
camera 52.53→52.72 ms, power 18.50→18.80 ms, moved light 44.03→44.52 ms
(nine timed events per mode/kind). Variability is insufficiently supplied to
establish significance. The compact view still costs an extra 16680224 resident
GPU bytes. It remains optional and OFF. No shading or traversal equations change.

The same report exposes an integration error in hardware sampling. Counter
access succeeds, but power/position intervals show zero active cycles despite
render callbacks. Reference camera contains 10803000 atomic issues; the later
compact camera contains zero, even though rasterization atomics are unchanged.
The submitted text ends partway through its final hardware block; the missing
scene, summaries and remainder have not been reconstructed or invented.

## Verified cause in the pinned source

Arm libGPUCounters commit `378c7b59e2dae87cbbffb0ac9cf96ed13c939823`:

- `backend/device/include/device/hwcnt/sampler/manual.hpp`, accumulation_stop:
  stopping stores a final accumulated sample in the reader's ring buffer.
- `hwcpipe/include/hwcpipe/sampler.hpp`, stop_sampling: stops accumulation but
  does not consume that final sample. sample_now requests a dump and reads the
  next FIFO entry, not necessarily the dump it just requested.

LIE 1.8 reused that reader after stop. Its next baseline could consume a stale
stop dump, and the retained end sample could consume a different interval.
This is a bug in LIE's capture lifecycle; it is not evidence that the GPU did no
work, that compact shadows removed atomics, or that the memory bus is free.
The clean timed A/B events precede hardware capture and do not use this sampler.
Their performance result remains usable within its statistical limits.

## Correction and checks

Every hardware interval now obtains its own sampler/reader, discards its own
initial baseline and destroys the stopped reader and queued final dump. Each
block reports a session ID. Pause, cancellation, failed baseline, failed sample
and failed stop release the reader. Counter access and corroborated measurement
are distinct report states.

The production `IntervalCapture` lifecycle has a CPU FIFO regression. Its
control reproduces the old six-block pattern `[1,0,0,3,0,0]`; fresh reader
ownership returns `[1,2,3,4,5,6]`. It checks nested starts, failures and lifetime.
These synthetic FIFO values test ownership only, not hardware accuracy or speed.

Separately captured Godot timestamp rows corroborate the same three event
serials in each hardware block. Positive GPU work with zero active cycles is
flagged invalid rather than displayed as an idle GPU. Missing timestamp events
remain uncorroborated. Clocks remain uncalibrated, so this is independent work
evidence, not exact clock alignment or per-dispatch hardware counters.

Copied reports use counter IDs linked to the retained names/units table and
keep telemetry metadata once; unavailable samples remain explicit. Full raw
rows, counter timestamps and sensor paths remain in the saved report. This
reduces the chance of losing the timing summary when pasting a long report.

The driver can still reject counters or produce invalid data. A physical rerun
is required to verify the corrected capture on this Mali-G720. Earlier 1.8
counter rows must not be used to rank per-stage bandwidth, divergence or
register pressure. No FPS improvement is claimed by this instrumentation fix.

Sources: [pinned manual sampler](https://github.com/ARM-software/libGPUCounters/blob/378c7b59e2dae87cbbffb0ac9cf96ed13c939823/backend/device/include/device/hwcnt/sampler/manual.hpp)
and [pinned public sampler](https://github.com/ARM-software/libGPUCounters/blob/378c7b59e2dae87cbbffb0ac9cf96ed13c939823/hwcpipe/include/hwcpipe/sampler.hpp).

Completed build and validation: [acceptance](checkpoints/LIE_COUNTER_INTERVALS_ACCEPTANCE.md).
