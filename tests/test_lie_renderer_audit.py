"""Independent known-domain and generated instrumented-kernel acceptance."""
import importlib.util
from pathlib import Path
import sys, unittest
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import lie_renderer_census as census

class AuditTests(unittest.TestCase):
    def test_final_entrypoint_and_package_independent_of_previous_stage(self):
        import tempfile
        import lie_renderer_audit_build as build
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)
            (path / 'project.godot').write_text('config/name="LIE Límites 1.7"\nconfig/version="1.7.0"\nrun/main_scene="res://lie_wall20_android_lab.tscn"\n')
            (path / 'export_presets.cfg').write_text('version/code=17\nversion/name="1.7.0-tangent-bounds"\npackage/unique_name="org.lieengine.wallruntime.v170"\npackage/name="LIE Límites 1.7"\ninclude_filter="captures/liewall06/*.bin"\n')
            build.configure_project(path)
            self.assertIn('run/main_scene="res://lie_renderer_audit_lab.tscn"', (path / 'project.godot').read_text())
            preset = (path / 'export_presets.cfg').read_text()
            self.assertIn('package/unique_name="org.lieengine.wallruntime.v220"', preset)
            self.assertIn('version/code=23', preset)
            self.assertIn('addons/lie_gpu_probe/licenses/*.txt', preset)
            build.configure_project(path)
            self.assertEqual(preset, (path / 'export_presets.cfg').read_text())

    def test_generated_sources_current(self):
        for name, data in census.outputs().items():
            self.assertEqual((ROOT / name).read_text(), data, name)

    def test_counter_additions_leave_rendering_equations(self):
        # Every changed line must differ only by counting statements and the
        # local accepted counter; validate the final image independently in Vulkan.
        import re
        for stage in census.STAGES:
            original = (ROOT / f'gpu_compute/shaders/lie_wall17_stage_{stage:02d}.glsl').read_text()
            changed = census.generate(stage)
            changed = re.sub(r'\n// GENERATED diagnostic census; excludes performance results\.', '', changed)
            changed = re.sub(r'\nlayout\(set=0,binding=49,std430\)[^\n]+\nvoid lie_count[^\n]+\n', '', changed)
            changed = re.sub(r'lie_count\(\d+u,(?:1u|group.y|candidates|accepted)\);', '', changed)
            changed = changed.replace('uint candidates=0u,accepted=0u;', 'uint candidates=0u;').replace('accepted++;', '')
            self.assertEqual(''.join(original.split()), ''.join(changed.split()), stage)

    def test_clear_domain_includes_all_lod0_references(self):
        # The preexisting 720-pixel dispatch demonstrably missed the tail.
        work = 535670
        old = max(720**2, 512**2)
        self.assertEqual(work - old, 17270)
        for size in [720, 810, 900, 1080, 1440]:
            count = max(work, size**2, 512**2)
            self.assertGreaterEqual(((count + 63) // 64) * 64, work)
        source = (ROOT / 'gpu_compute/lie_wall05_shared_effect.gd').read_text()
        self.assertIn('maxi(work,maxi(render_size*render_size,512*512))', source)

if __name__ == '__main__': unittest.main()
