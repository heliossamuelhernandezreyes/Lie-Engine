# Captured-cell native rasterization and reverse-Z recovery

This branch resumes the stalled native visibility experiment from
`work/lie-captured-views` at `6ee27c4`. The previous session's native changes
were absent from that saved head. Its initial screenshot and statements were
not treated as proof of a completed implementation.

The recovered original bank is 41,700,560 bytes, SHA-256
`ca667dfc0e5f5de19190ef12c24395a99b2be66a418420bf30e61ba9ef253340`.
Its layered depth, normal and material packet hashes match the recorded 2.5
packet identities. Capture bytes and provenance were not edited.

## Implementation

`lie_native_surface.py` compiles all four captured layers into disjoint finite
constant-depth cell rectangles. It merges only bit-identical adjacent depths.
Normals, material and ownership still come from the original cell and layer.
No original source mesh, depth-plane fitting, hole filling or angular-view
blending is introduced. These **are auxiliary raster triangles**, additional
to the invisible boxes and the existing single wall collider.

The first direct triangle rasterization lost subpixel coverage and selected
farther surfaces at some cell edges. The final shader rasterizes conservative
screen rectangles, then analytically intersects the original finite cell
plane and rejects samples outside its original half-open bounds. Each patch
fragment has a fixed query budget, with no cell walk. Conservative coverage
does not change the accepted surface bounds or fill a real opening.

The native primary uses directly evaluated reverse-Z projection, a D32 depth
attachment, GREATER comparison and zero clear. Native shadows keep the
accepted regions traversal over the same captured field, with reverse-Z
projection, comparison and bias. The older comparison modes keep their
forward-depth convention. Subtracting an already rounded forward depth from
one would not repair its lost precision; reverse depth is computed directly.

The native option is available through the existing validated commands and
selector. The visible picture heading now identifies the effective backend
and internal/output resolution, including an explicit simple-control warning.
The default backend and the six-mode 2.5 benchmark are unchanged. Selecting
native does **not** add it to that old benchmark's timing groups.

## Actual execution and remaining failures

Godot 4.7.2, native Vulkan 1.4, llvmpipe LLVM 20.1.2. These are untimed
software rendering results, not Mali measurements or physical FPS.

The exact phone camera uses yaw -72.90939846038818, elevation
2.0563994513617607 and distance .6, at 720 internal and output resolution.
The light state matches the preserved phone-pose diagnosis. Geometry/owner
comparisons disable shadows; separate captures enable them.

| Camera yaw | Missing vs regions | Extra vs regions | Missing inside covered 5x5 neighborhood | Different overlapping owner IDs |
| --- | ---: | ---: | ---: | ---: |
| -72.90939846 | 1 | 0 | 1 | 59 |
| -73.00939846 | 8 | 0 | 3 | 75 |
| -72.80939846 | 3 | 0 | 1 | 71 |

The earlier adjusted-view result missed 6,531 region hits at the exact phone
pose. Regions is a comparison baseline, **not source ground truth**.

An independent float64 finite-cell ray oracle checks every differing owner or
coverage pixel at the exact pose, plus seeded unchanged hit and empty rays.
It uses the actual uploaded camera/proxy packets, rather than rebuilding
their float32 transforms from authored dimensions. Among 2,460 selected rays
and 1,259 oracle hits, native has zero missing/extra sampled hits but **seven
owner mismatches and seven distance errors above 20 micrometres**. The largest
distance error is 4.413 mm. This targeted sample is not a population error-rate
estimate. Strict owner/depth equivalence remains open.

The first direct-triangle attempt is preserved as a negative result. Against
the corrected oracle inputs, its selected sample has 564 owner mismatches and
577 distance errors above 20 micrometres. An earlier temporary oracle used an
incorrect transform reconstruction and is superseded by the packet-based
oracle; its output is not evidence against either renderer.

The black grain remains. At the exact pose, native has 42,347 dark valid
pixels with shadows and 22,286 without them, using max RGB < .025. The regions
counts are 42,345 and 22,287. Thus reverse-Z and improved visibility have not
solved the lighting/material appearance failure. No denoising or exposure
change is presented as a geometric correction.

The exact representation submits **48,958,966 primary triangles** for this
96-brick wall and mortar, before vertex rejection. Its mesh packet occupies
14,823,504 bytes. This is an expensive correctness experiment, not an accepted
mobile replacement or speed optimization. No APK was produced from this
branch, and no Android or whole-frame performance claim is made.

## Validation and reproduction

* 238 Python tests discovered: no failures; one existing locked-source test skipped.
* Four native compiler/depth tests cover holes, cliffs, adjacent float depths,
  exact occupied-cell recovery and a 30-micrometre D32 precision example.
* GDScript import succeeds; 247 rig, 25 agent-session and 22 command checks pass.
* 25 actual Vulkan execution/cache/light checks pass, including light
  superposition/removal, camera/power reuse, per-light shadow invalidation,
  cached/fresh equality and idle behavior. These checks do not override the
  seven independent precision failures above.

After restoring the attributed bank and the existing direct access/view
packets, use:

```sh
python tools/lie_direct_access_shaders.py
python tools/lie_direct_views_shaders.py
python tools/lie_native_shaders.py
python tools/lie_native_surface.py
python tools/lie_native_stage.py --stage /tmp/lie-native-qa
godot --headless --path /tmp/lie-native-qa --editor --import --quit
godot --path /tmp/lie-native-qa --rendering-driver vulkan --rendering-method mobile \
  --audio-driver Dummy --script res://test_lie_native_depth.gd
python tools/lie_native_oracle.py --captures /tmp/lie-native-qa/native-depth \
  --output /tmp/lie-native-oracle.json
```

The graphics run requires a working display and Vulkan driver. For an
independent staged build from the repository's attributed reconstruction
pipeline, `lie_direct_views_build.py` also compiles the new native packet.
The native QA stage deliberately does not produce an Android release.

Machine-readable execution, residual precision failures, packet identities,
negative results and image hashes are in
`checkpoints/LIE_NATIVE_DEPTH_RECOVERY.json`. Actual native PNGs and logs are
in `evidence/native-depth/`. Remaining work is numerical edge precision,
lighting/material grain and a representation with acceptable mobile geometry
cost. The current evidence does not establish whole-camera-range acceptance.
