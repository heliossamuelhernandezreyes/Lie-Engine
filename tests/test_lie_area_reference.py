import sys,unittest
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from lie_area_reference import cases,quadrature,integral
from lie_wall13_shader import generate,generate_field
class AreaReference(unittest.TestCase):
    def test_shader_fresh(self):
        self.assertEqual(generate(),(ROOT/'gpu_compute/shaders/lie_wall13_area.glsl').read_text())
        self.assertEqual(generate_field(),(ROOT/'gpu_compute/shaders/lie_area_field.glsl').read_text())
    def test_power_centroid(self):
        q=quadrature([1,2,3],[.3,.225]);self.assertAlmostEqual(sum(w for p,w in q),1)
        np.testing.assert_allclose(sum(p*w for p,w in q),[1,2,3])
    def test_integral_convergence(self):
        a=integral([0,0,3],[.3,.225],[0,0,0],[0,0,1],2);b=integral([0,0,3],[.3,.225],[0,0,0],[0,0,1],64)
        self.assertLess(abs(a-b)/b,.001)
    def test_superposition_and_backface(self):
        c=cases();a=lambda name:np.array(c[name]['output']['flux'])
        np.testing.assert_allclose(a('two_panels'),a('key_only')+a('fill_only'),atol=1e-10)
        self.assertEqual(a('backwards').max(),0.);self.assertEqual(a('all_off').max(),0.)
        unoccluded=np.array(c['two_panels']['output']['channel_totals_by_generation'][0])
        occluded=np.array(c['edge_occlusion']['output']['channel_totals_by_generation'][0])
        np.testing.assert_array_equal(unoccluded[[4,6]],occluded[[4,6]])
        self.assertTrue((unoccluded[[5,7]]>occluded[[5,7]]).all())
