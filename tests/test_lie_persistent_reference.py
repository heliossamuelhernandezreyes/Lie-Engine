import sys,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from lie_wall11_shader import generate,generate_test
from lie_persistent_reference import prepare
class PersistentReference(unittest.TestCase):
    def test_actual_kernels_are_current(self):
        self.assertEqual(generate(),(ROOT/'gpu_compute/shaders/lie_wall11_persistent.glsl').read_text())
        self.assertEqual(generate_test(),(ROOT/'gpu_compute/shaders/lie_persistent_visibility_test.glsl').read_text())
    def test_fractional_and_zero_visibility_oracles(self):
        cases={c['name']:c for c in prepare()}
        self.assertEqual(cases['hidden_step']['expected'][0],0.)
        self.assertEqual(cases['opening']['expected'][0],1.)
        self.assertGreater(cases['metric_fade']['expected'][0],.05)
        self.assertLess(cases['metric_fade']['expected'][0],.95)
        self.assertEqual(cases['same_master_other_instance']['expected'][0],0.)
        self.assertEqual(cases['hidden_step']['moved_expected'],1.)
if __name__=='__main__':unittest.main()
