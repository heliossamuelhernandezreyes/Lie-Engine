import sys,unittest
from pathlib import Path
try:
    import numpy as np
except ModuleNotFoundError as error:
    if error.name!='numpy':raise
    raise unittest.SkipTest('Offline regions require NumPy; executed by LIE-27 CI')
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from lie27_regions import region,bindings,joint_regions,facial_regions,deform_face
from lie26_motion import rig

class SphericalRegions(unittest.TestCase):
    def test_center_boundary_and_outside_are_exact(self):
        w,g=region([[0,0,0],[2,0,0],[0,3,0],[0,0,5],[10,0,0]],[0,0,0],[2,3,5])
        np.testing.assert_array_equal(w,[1,0,0,0,0]);np.testing.assert_array_equal(g,np.zeros((5,3)))

    def test_gradient_matches_independent_central_difference(self):
        p=np.array([[.2,.3,.4],[-.3,-.1,.2],[.9,0,0]])
        w,g=region(p,[0,0,0],[1,2,3])
        for axis in range(3):
            offset=np.eye(3)[axis]*1e-6
            plus,_=region(p+offset,[0,0,0],[1,2,3]);minus,_=region(p-offset,[0,0,0],[1,2,3])
            np.testing.assert_allclose(g[:,axis],(plus-minus)/2e-6,atol=1e-8)

    def test_invalid_radius_rejected(self):
        for r in [[0,1,1],[1,-1,1],[np.nan,1,1]]:
            with self.assertRaises(ValueError):region([[0,0,0]],[0,0,0],r)

    def test_joint_bindings_are_connected_bounded_and_finite(self):
        b=rig();p=np.random.default_rng(27).uniform([-.34,.01,-.06],[.34,1.64,.24],(15000,3));a,c,w,g=bindings(p,b)
        self.assertTrue(np.isfinite(g).all());self.assertTrue(np.all((w>=0)&(w<=1)))
        self.assertTrue(all(a[i]==c[i] or b[c[i]]['parent']==a[i] for i in range(len(p))))
        self.assertEqual(len(joint_regions(b)),14)

    def test_torso_and_cranium_keep_semantic_ownership(self):
        a,c,w,g=bindings([[.14,1.07,.13],[-.14,1.07,.13]],rig())
        self.assertFalse(any(i in [4,7] for i in np.r_[a,c]))
        a,c,w,g=bindings([[.03,1.505,.16],[0,1.55,.18]],rig())
        np.testing.assert_array_equal(c,[2,2]);np.testing.assert_array_equal(w,[1,1]);self.assertFalse(g.any())

    def test_facial_jacobian_and_unrelated_points(self):
        zones=facial_regions([[-.027,1.527,.159],[.027,1.527,.159]])
        p=np.array([[.02,1.485,.176],[0,.8,.1],[0,1.5,-.02]])
        values=[0,0,.7,.2,.5,.1,.4];out,jac=deform_face(p,zones,values)
        np.testing.assert_array_equal(out[1:],p[1:])
        for axis in range(3):
            d=np.eye(3)[axis]*1e-6;plus,_=deform_face(p+d,zones,values);minus,_=deform_face(p-d,zones,values)
            np.testing.assert_allclose(jac[:,:,axis],(plus-minus)/2e-6,atol=1e-8)

if __name__=='__main__':unittest.main()
