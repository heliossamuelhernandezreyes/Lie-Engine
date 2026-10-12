# LIE30 — Running bond with physically recessed mortar

This iteration is a native, reproducible Godot/Vulkan LIE engine experiment. It
extends LIE29; its screenshots are from the native compositor and were NOT made
with image generation.

## Implemented / source integrity

- 126 individual bricks (six courses of 10 full bricks and six of 9 full plus
  two matching half bricks), **one shared sampled buffer**, 127 total instances
  including the mortar underlayer. The courses terminate at the same x bounds.
- Three actual LIE28 capture masters: `brick`, `half_brick`, `concrete_panel`.
  Each instance references an 80-byte/sample bank range, not a duplicate mesh.
- 1,181,280 uncompressed sample bytes: SHA-256
  `d2f72992a99ce1febe37eaba73fd48f9db42071eb5c5ad105270c976311a5c63`.
  Derived byte-for-byte from LIE28 LOD1 bank. Source license CC0 (Factory Brick
  and Concrete by Rob Tuytel, Poly Haven; original geometry LIE28).
- Reproducible palette/roughness offsets per placed brick; physically different
  0.115m half-brick collision proxy and 0.24m full-brick proxy.
- The concrete slab is scaled to the wall's footprint, 7mm behind the visible
  brick front plane; it adds mortar coverage and avoids transparent black gaps
  from the earlier wall. The slab is an approximation of mortar, not true
  mesh-matched mortar joints or structural simulation.

## Native acceptance

- Actual Godot 4.7.2 + software Vulkan (Mesa llvmpipe).
- GitHub Actions run: https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/38252419397
- Unmodified compositor output: `evidence/LIE30-Wall-Godot.png`.
- A separate inspected source-master closeup:
  `evidence/LIE30-Brick-Closeup-Godot.png`.
- Exact SHA report: `evidence/LIE30-validation.json`.
- Native shader submission: 127 instances, 688,262 sample invocations,
  3 shared masters, 1 bank upload, 0 visible source meshes.
- Alpha coverage at equal resolution rose from 77,179 to 81,108 pixels
  (+5.09%). This demonstrates added opaque coverage, *not* an established
  perceptual-quality score. Exact same seed restored the same screenshot.
- Python instance layout tests and Godot import/syntax checks succeeded.

## Reproduce

```sh
python tools/lie30_restore_bank.py
godot --headless --path gpu_compute --editor --import --quit
python tools/lie_agent_launch.py --godot /path/to/godot \
    --lab lie30 --directory /tmp/fresh-lie30
python tools/lie30_native_smoke.py --directory /tmp/fresh-lie30
```

## Open limits

- The brick source is still the original simple LIE28 Blender geometry,
  photographed CC0 materials at 1K. There is no newly acquired cinematic
  photogrammetry, 4K normal map, displacement map, or sculpted clay geometry.
- Sample density is LIE28 LOD1, 5,650 samples per full brick; closeups
  are visibly soft and do not establish physically accurate microstructure.
- The source shader is still primarily direct-lit with physically imperfect
  shadow/contact treatment. This is a stronger wall *assembly*, not
  cinematic realism.
- The current compositor enforces 128 instances/750,000 sample invocations.
  This 127-instance experiment is close to both caps; 10,000 bricks are not
  individually renderable with the current pipeline.
- Hardware GPU and Android benchmarking remain undone.
- The wall uses original captured mortar/concrete as a recessed backing;
  actual mortar geometry/extrusion and construction physics are unimplemented.

## Proposed LIE31

Next measure an independently licensed high-fidelity scanned brick against this
unchanged native capture at matched camera/pose/lighting, and compare adaptive
capture banks, normal map fidelity, VRAM, and real hardware GPU time before
any claim of superior quality/performance.
