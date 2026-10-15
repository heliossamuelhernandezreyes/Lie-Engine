import sys,unittest
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from lie_filter_reference import cases
from lie_wall13_shader import generate_filter_test
class FilterReference(unittest.TestCase):
    def test_shader_fresh(self):self.assertEqual(generate_filter_test(),(ROOT/'gpu_compute/shaders/lie_filter_test.glsl').read_text())
    def test_boundaries_and_hole(self):
        c=cases();self.assertTrue(np.array(c['open_hole']['expected'])[12*8:13*8].sum()==0)
        # Rejected right neighbors are identical regardless of their depth,
        # group, instance, or geometric normal reason for rejection.
        expected=np.array(c['instance_edge']['expected'])[12*8:13*8]
        for name in ['group_edge','normal_edge','depth_edge']:np.testing.assert_array_equal(expected,np.array(c[name]['expected'])[12*8:13*8])
    def test_checker_reduction(self):
        c=cases()['checker'];delta=np.linalg.norm(np.array(c['expected'])[12*8:12*8+3]-np.array(c['center_raw'])[:3]);self.assertGreater(delta,.001);self.assertLess(delta,.05)
