# Agent and desktop workflow

Lie's native Godot desktop and external agents use the same validated control
methods. GitHub stores source, shaders, scenes, generators and research notes;
the desktop reconstructs the attributed capture banks and exposes live state.
No browser session or arbitrary code-evaluation endpoint is required.

## Restore the checkpoint

1. Clone `heliossamuelhernandezreyes/Lie-Engine` and use `main` after integration.
2. Obtain `LIE27-Experimento.zip` from the saved project deliverables. Verify
   its SHA-256 against `checkpoints/LIE27_CHECKPOINT.json`, then extract it
   over the parent of the checkout. This supplies `gpu_compute/captures/anatomy27`.
3. Verify each bank buffer's exact bytes/SHA-256 from `master.json`. The bank
   uses the unchanged source identified in the checkpoint manifest.
4. Use Godot 4.7.2 and `gpu_compute/project.godot`. The root project is the
   historical LIE-06 example. The current default desktop scene is LIE-27.

The old piece workshop and other laboratories need their own attributed
banks. Missing assets are reported in snapshots; opening their scene is not
proof that their renderer is ready. Their existing CI workflows regenerate
and exercise their corresponding assets.

## Launch and discover a native session

```sh
python tools/lie_agent_launch.py --godot /path/to/godot \
  --lab lie27 --directory /absolute/path/new-lie-session
python tools/lie_workshop_client.py \
  --directory /absolute/path/new-lie-session --command '{"op":"describe"}'
```

Use a fresh directory for a new process. The launcher returns process ID,
directory, protocol, scene and log path. It never reports a render as ready
solely because a process started. Check `snapshot.runtime.capture_loaded`,
`gpu_ready` and `failure` before requesting images. A timeout can leave the
application running: inspect it before launching a duplicate.

For a disposable Linux runner, close it before
tearing down its display with `python tools/lie_agent_stop.py --directory DIR`.
The `shutdown` protocol operation requires the exact `expected_session` and
allows scene/render-thread resources to release before quitting; it never
defaults to closing an unspecified session. The helper waits for that PID to
stop and does not send process signals. Other platforms can use the same
protocol and wait for their process through platform-specific supervision.

Without launcher arguments the desktop publishes a separate session under
Godot's user-data directory at `agent/sessions/<pid>/session.json`. The editor
Lie dock provides direct buttons for both the piece workshop and LIE-27.
The LIE-27 desktop has **Guardar estado / Abrir estado** buttons using the
same persistence endpoint as an agent.

## Commands

`LieAgent` is a persistent autoload. Scene navigation keeps the same inbox
directory and creates a new session token. Requests are correlated by ID,
published atomically by the existing Python client, and executed serially.
No socket, remote credentials or third-party Python package is required.

| Operation | Behavior |
|---|---|
| `snapshot`, `describe` | Current state, revision, renderer readiness, control fields, ranges and laboratory catalog |
| `set_values`, `set_pose` | Forwarded to the actual laboratory's validated `command()`; update both UI and renderer |
| `save_state`, `load_state` | Complete state for LIE-25/26/27; optional basename ending `.lie.json`; atomic storage and validated restore |
| `capture` | Actual `compositor` (default) or native `window`; optional PNG basename inside the session directory |
| `open_lab` | Navigate to a declared workshop/LIE-20…28 scene without replacing the endpoint |
| Other native commands | Forwarded unchanged; older document laboratories retain save/load/history/material/assembly APIs |

LIE-27 discovery includes every state field, seven facial channels, pose
limits, IK chains, booleans, palette/eye shapes and ranges, layer mask and
focus/playback enums. `face` and `eyes` must be complete dictionaries.
The main facial channels are `blink_left`, `blink_right`, `smile`, `frown`,
`brow_up`, `brow_down`, `jaw_open`. The standalone eyelash feature is absent.

```json
{"op":"set_values","values":{"focus":"face","distance":0.35,"brows":true}}
```

```json
{"op":"set_pose","values":{"head_yaw":15,"right_index":30}}
```

```json
{"op":"save_state","filename":"working-face.lie.json"}
```

```json
{"op":"capture","kind":"window","filename":"desktop.png"}
```

For edits based on a snapshot, include its `expected_revision`,
`expected_session` and `expected_lab`. A stale revision/process/scene rejects
the operation before mutation. Save before navigating if a pose should survive
scene destruction, then restore it after returning. Capture waits for rendered
frames; pause playback first when an exact reproducible state is needed.

This controls existing laboratory features. It does not add a general Godot
scene-editor API, import arbitrary masters, or automate an external operating
system mouse. An agent with desktop automation can also use native widgets;
the verified route here is programmatic control of the real native window.

## GitHub and verification

Use a branch for further changes. Inspect current `main` and PR heads, preserve
the bank/source hashes and record both passing and failing visual results.
GitHub-connected agents can publish trees/commits, update a branch with an
expected head, inspect workflow runs and merge an authorized PR. Local git
credentials are environment-specific; never infer them from connector access.

```sh
python -m unittest discover -s tests -p 'test_*.py' -v
godot --headless --path gpu_compute --editor --import --quit
godot --headless --path gpu_compute --script res://test_lie27_regions.gd
godot --headless --path gpu_compute --script res://workshop/test_lie_agent_session.gd
```

For a **fresh disposable desktop** with the bank restored:

```sh
python tools/lie_agent_smoke.py --directory /absolute/path/new-lie-session
```

The smoke test exercises discovery, all current control fields, IK/playback,
atomic rejection, revision/session conflicts, state persistence, compositor
and desktop-window capture, actual blink image changes, exact restored-image
hashes and navigation away/back. It writes `agent-verification.json` and real
PNG evidence into the session. Software Vulkan is supported but its timings
do not establish physical GPU or Android performance.

Continue from the diagnosis in `checkpoints/LIE27_CONTINUATION.md`. This saved
research checkpoint intentionally retains provisional anatomy, shading and
whole-body visual failures for the next iteration.
