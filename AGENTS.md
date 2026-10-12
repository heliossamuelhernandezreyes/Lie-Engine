# Working on Lie Engine

Use `gpu_compute/project.godot` with Godot 4.7.2. The top-level Godot project
is a historical LIE-06 example. The current desktop entry is LIE-27; the
editor's Lie dock also opens the piece workshop and anatomical laboratory.

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
