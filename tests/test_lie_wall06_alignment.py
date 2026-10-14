"""Geometry/provenance and reciprocal energy checks on the actual source bank."""
import sys,json,unittest,hashlib
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from lie_wall06_alignment import build
class Alignment(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cat=build();cls.root=ROOT/'gpu_compute/captures/liewall06'
        cls.old=np.fromfile(ROOT/'gpu_compute/captures/liewall05/library.bin',dtype='<f4').reshape(-1,20)
        cls.new=np.fromfile(cls.root/'library.bin',dtype='<f4').reshape(-1,20)
    def test_rigid_shape_all_samples(self):
        R=np.array(self.cat['wall06']['rotation']);self.assertAlmostEqual(np.linalg.det(R),1,places=12)
        np.testing.assert_allclose(R@R.T,np.eye(3),atol=1e-14)
        # Independent pairwise distances spanning every LOD and source sides.
        ids=np.arange(0,281000,271);other=(ids*73+19)%281000
        before=np.linalg.norm(self.old[ids,:3]-self.old[other,:3],axis=1)
        after=np.linalg.norm(self.new[ids,:3]-self.new[other,:3],axis=1)
        np.testing.assert_allclose(after,before,atol=4e-8,rtol=1e-6)
        n=np.array(self.cat['wall06']['original_front_normal']);np.testing.assert_allclose(R@n,[0,0,1],atol=1e-12)
    def test_photo_colors_and_material_unchanged(self):
        # Includes every brick and every mortar record, all LODs.
        for lo,hi in [(7,16),(3,4)]:self.assertEqual(self.old[:,lo:hi].tobytes(),self.new[:,lo:hi].tobytes())
        self.assertEqual(self.new.shape,self.old.shape)
        self.assertFalse(self.cat['wall05']['geometry_precomposed'])
        self.assertEqual(self.cat['wall05']['neutral_master_count'],1)
    def test_source_is_still_locked(self):
        oldraw=(ROOT/'gpu_compute/captures/liewall05/library.bin').read_bytes()
        self.assertEqual(hashlib.sha256(oldraw).hexdigest(),'0d9a9effac67f5f86d9659c423e786b0f710712297baa7ec20840dc78655bb56')
        self.assertTrue(np.isfinite(self.new).all())
        np.testing.assert_allclose(np.linalg.norm(self.new[:,4:7],axis=1),1,atol=2e-6)
    def test_new_graph_has_new_geometry_and_passive_weights(self):
        model=json.loads((self.root/'light-model.json').read_text())
        f=np.fromfile(self.root/'indirect_factors.bin',dtype='<f4').reshape(872,872)
        area=np.array([p['area'] for p in model['patches']])
        self.assertTrue((f>=0).all());self.assertLessEqual(float(f.sum(1).max()),1.000001)
        np.testing.assert_allclose(f*area[:,None],f.T*area[None,:],atol=1e-9)
        self.assertEqual(len(model['direct_shadow_boxes']),96)
        self.assertEqual(self.cat['collision']['spatial_envelope_count'],1)
if __name__=='__main__':unittest.main()
