import copy
import sys
import unittest
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from lie_field_quality import options,packet,solve
from lie_field_quality_cases import cases,partition_model,paths_model
from lie_field_quality_shader import outputs
from lie_light_field import sources,fixture_cases

class FieldQuality(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.cases=cases()
    def result(self,name,key='flux'):return np.array(self.cases[name]['output'][key])
    def test_subdivision_preserves_reach_and_reproduces_old_failure(self):
        a=self.result('partition_one','frontier')[-1];b=self.result('partition_four','frontier')[-1]
        # Center quadrature + smooth radial window have a measured 6.32e-6
        # refinement error in this fixture. The previous cutoff lost 100%.
        np.testing.assert_allclose(a,b,rtol=1e-5,atol=1e-12)
        self.assertGreater(a.max(),.0001)
        self.assertEqual(self.result('old_cutoff_four','frontier')[-1].max(),0)
    def test_same_source_paths_keep_lateral_reflections(self):
        six=self.result('paths_six','frontier');one=self.result('paths_one','frontier')
        self.assertGreater(six[3,0],1e-5);self.assertGreater(six[4,0],1e-5)
        self.assertLess(six[5,0],1e-20);self.assertGreater(one[5,0],1e-5)
        self.assertLess(one[3,0],1e-20)
    def test_moving_occluder_and_restoration(self):
        a=self.result('paths_six','frontier');b=self.result('paths_blocked','frontier')
        self.assertGreater(abs(a-b).max(),1e-5)
        np.testing.assert_array_equal(self.result('paths_six'),self.result('paths_restored'))
    def test_passive_per_source_generation_and_finite_lobes(self):
        for name,c in self.cases.items():
            g=np.array(c['output']['channel_totals_by_generation'])
            self.assertTrue(np.isfinite(g).all(),name);self.assertTrue((g>=0).all(),name)
            self.assertTrue((g[1:]<=g[:-1]+1e-8).all(),name)
    def test_legacy_and_source_superposition(self):
        original=fixture_cases()
        for name,c in original.items():
            if c['separate']:np.testing.assert_allclose(self.result('legacy_'+name),c['output']['flux'],atol=1e-14)
        m,F=paths_model();m['lights'].append({'position':[.4,.1,3.],'radius':10.,'power_rgb':[2.,7.,12.]});packets=sources(m,F)
        both=np.array(solve(m,packets)['flux']);single=[]
        for l in m['lights']:
            one=copy.deepcopy(m);one['lights']=[l];single.append(np.array(solve(one,packets)['flux']))
        np.testing.assert_allclose(both,sum(single),atol=1e-14)
    def test_invalid_policies_fail_and_input_not_mutated(self):
        for bad in ({'angular_sectors':2},{'area_budget':1},{'reference_area':0},{'unknown':1},{'visibility_revision':-1},
                    {'dynamic_occluders':[[[0,0,0],[0,1,1]]]},{'roughness_split':float('nan')}):
            m=partition_model(False);m['field_quality']=bad
            with self.assertRaises(ValueError):packet(m)
        m=partition_model(False);saved=copy.deepcopy(m);packet(m);self.assertEqual(m,saved)
    def test_generated_sources_are_current(self):
        for name,s in outputs().items():self.assertEqual((ROOT/'gpu_compute/shaders'/name).read_text(),s)

if __name__=='__main__':unittest.main()
