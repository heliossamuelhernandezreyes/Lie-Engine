import sys,unittest
from pathlib import Path
try:
    import numpy as np
except ModuleNotFoundError as error:
    if error.name != 'numpy':
        raise
    # Legacy reference suites use only the standard library. LIE-26 CI installs
    # NumPy explicitly and runs the entire suite, including every test below.
    raise unittest.SkipTest('LIE-26 offline bindings require NumPy; covered by LIE-26 CI')
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from lie26_motion import rig,bindings

class AnatomicalBindings(unittest.TestCase):
    def test_connected_weights_and_finite_gradients(self):
        rng=np.random.default_rng(26);p=rng.uniform([-.34,.01,-.06],[.34,1.64,.24],(20000,3));b=rig();a,c,w,g=bindings(p,b)
        self.assertTrue(np.isfinite(g).all());self.assertTrue(np.all((w>=0)&(w<=1)))
        self.assertTrue(all(a[i]==c[i] or b[c[i]]['parent']==a[i] for i in range(len(p))))

    def test_torso_cannot_follow_elbow(self):
        # The original nearest-line field incorrectly assigned these side
        # patches to forearms and tore the torso when an elbow bent.
        a,c,w,g=bindings([[.14,1.07,.13],[-.14,1.07,.13],[.13,1.13,.13]],rig())
        self.assertFalse(any(i in [4,7] for i in np.r_[a,c]))

    def test_elbow_weight_gradient(self):
        p=np.array([[-.230,1.04,.115]]);bones=rig();a,c,w,g=bindings(p,bones)
        for axis in range(3):
            d=np.eye(3)[axis]*1e-5;aa,cc,plus,_=bindings(p+d,bones);ab,cb,minus,_=bindings(p-d,bones)
            np.testing.assert_array_equal(a,aa);np.testing.assert_array_equal(a,ab);np.testing.assert_array_equal(c,cc);np.testing.assert_array_equal(c,cb)
            np.testing.assert_allclose(g[:,axis],(plus-minus)/2e-5,rtol=2e-4,atol=1e-4)

    def test_bone_binding_is_rigid(self):
        a,c,w,g=bindings([[.24,1.0,.10]],rig(),True)
        np.testing.assert_array_equal(a,c);self.assertEqual(w[0],0);self.assertTrue((g==0).all())

    def test_cranium_and_eyes_follow_head(self):
        a,c,w,g=bindings([[.03,1.505,.16],[0,1.55,.18],[.06,1.46,.14]],rig())
        self.assertTrue((a==1).all());self.assertTrue((c==2).all());self.assertTrue((w==1).all());self.assertTrue((g==0).all())

if __name__=='__main__':unittest.main()
