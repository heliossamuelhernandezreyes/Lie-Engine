import sys,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from lie_surface_reference import fixture
class SurfaceLight(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.cases={c['name']:c for c in fixture()['cases']}
    def test_flat_and_sloped_do_not_self_shadow(self):
        for name in ['flat','sloped']:self.assertEqual(self.cases[name]['visibility'],1.,name)
    def test_step_occludes_only_light_facing_direction(self):
        self.assertEqual(self.cases['contact_step']['visibility'],0.)
        self.assertEqual(self.cases['light_reversed']['visibility'],1.)
    def test_holes_and_metric_range(self):
        for name in ['real_hole','outside_contact_range']:self.assertEqual(self.cases[name]['visibility'],1.,name)
    def test_rigid_frame_invariance(self):
        for name in ['rotated_step','translated_step']:self.assertEqual(self.cases[name]['visibility'],self.cases['contact_step']['visibility'],name)
    def test_generated_kernels_are_current(self):
        from lie_surface_light_shader import generate as transport
        from lie_wall09_shader import generate as appearance
        for name,generator in [('lie_surface_light.glsl',transport),('lie_wall09_surface.glsl',appearance)]:self.assertEqual((ROOT/'gpu_compute/shaders'/name).read_text(),generator())
if __name__=='__main__':unittest.main()
