import copy,sys,unittest
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from lie_light_field import fixture_cases,solve

class LightField(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.cases=fixture_cases()
    def flux(self,name):return np.array(self.cases[name]['output']['flux'])
    def test_light_superposition_and_zero(self):
        np.testing.assert_allclose(self.flux('two_colored_lights'),self.flux('left_only')+self.flux('right_only'),atol=1e-14)
        self.assertEqual(self.flux('all_off').max(),0)
    def test_merged_direction_loses_real_contribution(self):
        error=abs(self.flux('two_colored_lights')-self.flux('legacy_merged')).max();self.assertGreater(error,.0001)
    def test_passive_every_source_every_generation(self):
        for name,case in self.cases.items():
            values=np.array(case['output']['channel_totals_by_generation']);self.assertTrue(np.isfinite(values).all(),name)
            self.assertTrue((values>=0).all(),name);self.assertTrue((values[1:]<=values[:-1]+1e-10).all(),name)
    def test_world_translation_and_material_response(self):
        np.testing.assert_allclose(self.flux('two_colored_lights'),self.flux('translated_scene'),atol=2e-7)
        self.assertGreater(abs(self.flux('two_colored_lights')-self.flux('rough_surface')).max(),1e-6)
        self.assertLessEqual(self.flux('absorbing_surface').sum(),self.flux('two_colored_lights').sum())
    def test_shadow_and_explicit_ownership(self):
        self.assertLess(self.flux('occluded_direct').sum(),self.flux('two_colored_lights').sum())
        np.testing.assert_allclose(self.flux('explicit_owner_skip'),self.flux('two_colored_lights'),atol=1e-14)
    def test_radius_is_per_source_and_restorable(self):
        case=self.cases['bounded_radius'];model=case['model'];pack={k:bytes.fromhex(v) for k,v in case['sources_hex'].items()}
        singles=[]
        for i in range(2):
            m=copy.deepcopy(model);m['lights'][1-i]['power_rgb']=[0,0,0];singles.append(np.array(solve(m,pack)['flux']))
        np.testing.assert_allclose(singles[0]+singles[1],self.flux('bounded_radius'),atol=1e-14)
        m=copy.deepcopy(model);m.pop('secondary_radii');np.testing.assert_allclose(solve(m,pack)['flux'],self.flux('two_colored_lights'),atol=1e-14)

if __name__=='__main__':unittest.main()
