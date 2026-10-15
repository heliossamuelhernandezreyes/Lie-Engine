# Working on Lie Engine

Use `gpu_compute/project.godot` with Godot 4.7.2. The top-level Godot project
is a historical LIE-06 example. The current desktop entry is LIE-27; the
editor's Lie dock also opens the piece workshop and anatomical laboratory.
The construction laboratory is LIE-28 (`lie28_building_lab.tscn`). Read
`docs/LIE_28_MODULAR_BUILDING.md` for its native masters, CC0 material maps,
capture bank and independent geometry/material checks.

Read `docs/AGENT_WORKFLOW.md` before controlling a live desktop. External
agents and desktop widgets must use the existing validated `command()`
methods. The persistent `LieAgent` session routes those commands, exposes
control ranges, saves/restores states and captures actual compositor/window
images. Do not implement a second deformation/control path or evaluate
arbitrary code through the inbox.

Code, shaders, scenes, generators and durable research notes belong in Git.
Large attributed capture banks remain outside Git. The LIE-27 bank and
evidence are distributed as `LIE27-Experimento.zip`; verify the exact sizes
and hashes in `docs/checkpoints/LIE27_CHECKPOINT.json` before use. A Git
checkout alone does not contain that bank or the separately acquired source.

Preserve experimental failures. Passing material/depth ownership tests does
not establish realistic motion, continuous shading, whole-body coverage,
physical GPU speed, Android performance or sharing between enemies.
Read `docs/checkpoints/LIE27_CONTINUATION.md` before the next face correction.

For relevant changes run Python regressions, compile changed GDScripts and
run the CPU rig/agent tests. Changes to reconstruction need the real Vulkan
checks with the attributed bank; do not replace those with mocked rendering.
The live desktop agent smoke test changes controls and navigates scenes:
use a fresh disposable application session, not an unsaved user session.

User instructions determine publication/merge authorization. Preserve
reviewable history and inspect current branch heads before updating refs.
Do not edit generated capture bytes without updating provenance and hashes.

## New 80-byte assets

Use `tools/lie_asset_capture.py` with an authored unit/pivot/rotation profile,
or an explicit source-surface frame recipe through `lie_asset_contract.py`.
Do not silently infer semantic orientation from bounding-box aspect ratios.
Keep source SHA/provenance, linear albedo, geometric normals and optical
material declarations separate; the current capture backend supports opaque
nonmetal base color/roughness and source geometry normals. Unsupported glTF
features must be reported or explicitly declared as an authored override.

Run the common preflight and keep `asset-contract.json` alongside the bank.
Runtime IDs bind the bank SHA, master name and LOD ranges; residency uses the
existing RenderingDevice bank leases. Native depth/coverage/material/cache
acceptance is still required. Preflight alone does not establish photo fidelity.
Use source-authored owner/material groups for shared irradiance interpolation;
never interpolate appearance across an unrelated master or real opening.
Read `docs/LIE_ASSET_PIPELINE.md` for the compiler, common kernel and limits.
