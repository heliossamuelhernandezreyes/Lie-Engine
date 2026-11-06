import unittest
import numpy as np
from lie_scanned_masonry import recipe,noise,canonical_bytes,box_samples
from lie_scanned_masonry_shader import outputs
from pathlib import Path
class MasonryTests(unittest.TestCase):
    def test_seed_reproduction_and_coverage(self):
        size=[.1995196167,.0574072295,.100615652]
        for mode in ('wall','house'):
            a=recipe(size,'bank',2102,mode);b=recipe(size,'bank',7319,mode)
            self.assertEqual(canonical_bytes(a),canonical_bytes(recipe(size,'bank',2102,mode)))
            self.assertNotEqual(canonical_bytes(a),canonical_bytes(b))
            ids=[v['id'] for v in a['instances']];self.assertEqual(len(ids),len(set(ids)))
            for entry in a['instances']:
                if entry['master']=='scanned_brick':self.assertEqual(entry['scale'],[1,1,1])
            for opening in a['openings']:
                for row in range(opening['row'],opening['row']+opening['rows']):
                    for col in range(opening['column'],opening['column']+opening['columns']):
                        for prefix in ('brick','mortar'):self.assertNotIn(f'{prefix}/{opening["section"]}/{row}/{col}',ids)
    def test_invalid_seed(self):
        for seed in (True,-1,2**32,1.5):
            with self.assertRaises(ValueError):recipe([.2,.06,.1],'a',seed)
    def test_box_geometry_and_declarations(self):
        a=box_samples(8,(.2,.3,.4));self.assertEqual(a.shape,(384,20));self.assertTrue(np.isfinite(a).all());np.testing.assert_allclose(np.linalg.norm(a[:,4:7],axis=1),1)
        self.assertTrue((a[:,16:18]<=a[:,18:20]).all());self.assertEqual(len(np.unique(a[:,9])),6)
    def test_generated_shader_identity(self):
        root=Path(__file__).resolve().parents[1]
        for name,value in outputs().items():self.assertEqual((root/name).read_text(),value)
    def test_noise_domain(self):
        values=[noise(2102,1,2,c,0) for c in range(32)];self.assertEqual(len(set(values)),32);self.assertTrue(all(0<=v<=1 for v in values))
    def test_capture_host_float_roundoff_does_not_change_recipe(self):
        size=np.array([.1995196166917,.05740722949062766,.10061565197156495]);other=np.nextafter(size,np.inf)
        self.assertEqual(canonical_bytes(recipe(size,'same-bank',2102,'house')),canonical_bytes(recipe(other,'same-bank',2102,'house')))
