# LIE-27 checkpoint and next investigation — 2026-10-12

The preserved face/eyebrow implementation is commit
`fc5ab4b18d3efcf5d57c862cf9a2ff1cc86566f0`. Its attributed bank contains
5,996,289 samples, including 1,728 native chin captures, shared orbital rim
normals and native ocular material identity. Geometry source meshes remain
offline. The archive carries the real images, 172 passing software Vulkan
checks, 72 Python tests (one external-asset skip), 888 CPU rig checks and source
credits. The accompanying checkpoint manifest pins its buffers and archive.

## What is preserved

- Captured skin eyebrows follow facial/head controls; they are surface pigment,
  not standalone 3D hairs. Eyelashes were explicitly deferred by the user.
- The chin visibility rule and three native galleries remove measured inner
  leakage/missing pixels from five protected chin cases (122,605 pixels).
- Thirteen protected orbital cases (1,189,821 pixels) retain the intended
  skin/eye material ownership. Fully closed frontal, tilted and both ±35°
  views have zero visible native ocular pixels.
- Runtime asset buffers: 481,007,632 bytes. One compositor: 1,174,488,096
  bytes, excluding engine/driver overhead. One resident bank upload per lab.
- Source asset SHA-256:
  `a47d7ea9ae4082b793d4d45761c4c73db96707bb5f03c279b4133053c6c3e193`.
  3DAnatomyman / Always3D, BodyParts3D © DBCLS, CC BY-SA 2.1 Japan.

## Diagnosis made after this implementation

Three matched renders (neutral, closed and head turned 25°/pitched 15°) were
compared with lighting disabled. Depth winner arrays were identical in all
three comparisons. Many dark orbital marks disappear under uniform pigment.
This localizes much of their appearance to shading; it does not isolate a
single faulty normal formula or prove that the underlying shape is anatomical.

A small inspected neck rectangle in the turned 1024² image (x=306…359,
y=734…847) was independently ray-tested against native skin transported
through the neck/head weights. Of 5,262 source-covered pixels, two were
uncovered by Lie. This is a local diagnostic, not a whole-neck acceptance test.
The missing source positions were approximately x=−0.05164…−0.05147 m,
y=1.44083…1.44111 m, z=0.07227…0.07275 m.

The renderer still uses a mostly uniform skin pigment. Skin diffusion exists
in the shader but its final blend is zero in this revision. Eyelid geometry
uses seven authored rings against an ocular shell; full closure does not
guarantee natural folds. Automatic blinking is a symmetric squared pulse
every three seconds, updated at 30 Hz. `jaw_open` is a lower-face displacement
field, not a mandible joint or a completed oral cavity.

## Next work, after saving this checkpoint

1. Compare source, reconstructed and final accumulated normals at one eyelid
   boundary and the inspected neck region, with matched camera/light/pose.
2. Separately classify actual missing coverage, wrong depth and shading
   discontinuity. Broad dark regions must not automatically be labeled holes.
3. Replace provisional lid/mandible shapes and motion after identifying their
   contribution. More captures of the same provisional shape also preserve
   its defects; a detailed articulated source still needs faithful transport.
4. Expand acceptance beyond the protected masks to silhouette, continuous
   normals/depth, temporal motion and the relevant surrounding face/neck.

Earlier LIE-26 whole-body visual thresholds failed and remain documented in
`LIE_26_ANATOMICAL_MOTION.md`. Integration into main preserves a research
checkpoint; it does not convert those failures into production acceptance.
