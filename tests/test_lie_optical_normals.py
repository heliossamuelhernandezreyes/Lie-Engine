import unittest
import numpy as np
import trimesh
from lie_optical_normals import sample_optical,inspect_optical
class OpticalNormalTests(unittest.TestCase):
    def mesh(self,mirror=False):
        m=trimesh.Trimesh(vertices=[[0,0,0],[1,0,0],[0,1,0]],faces=[[0,1,2]],process=False);uv=np.array([[0,0],[1,0],[0,1]],float)
        if mirror:uv[:,0]=1-uv[:,0]
        m.visual=trimesh.visual.TextureVisuals(uv=uv);m.metadata['lie_optical_normal_map']=np.full((2,2,3),[.8535533906,.5,.8535533906]);return m
    def test_tangent_frame_and_mirrored_uv(self):
        for mirrored in (False,True):
            n=sample_optical(self.mesh(mirrored),np.array([[.3,.3]]),np.array([[0,1,2]]),np.array([[0,0,1.]]));np.testing.assert_allclose(n[0],[(-1 if mirrored else 1)/np.sqrt(2),0,1/np.sqrt(2),1],atol=1e-6)
    def test_no_optical_map_is_exact_geometry_fallback(self):
        m=self.mesh();m.metadata.clear();n=sample_optical(m,None,np.array([[0,1,2]]),np.array([[0.,0.,1.]]));np.testing.assert_array_equal(n,[[0,0,1,0]])
    def test_sidecar_integrity_and_units(self):
        a=np.array([[0,0,1,1]],dtype='<f4');d=inspect_optical(a.tobytes(),'a'*64,1);self.assertEqual(d['source_bank_sha256'],'a'*64)
        with self.assertRaises(ValueError):inspect_optical(a.tobytes(),'a'*64,2)
        a[0,0]=1
        with self.assertRaises(ValueError):inspect_optical(a.tobytes(),'a'*64,1)
