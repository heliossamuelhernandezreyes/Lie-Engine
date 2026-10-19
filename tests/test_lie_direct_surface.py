import sys,unittest
from pathlib import Path
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from lie_direct_surface import bake_face

def sample(z,node=0,color=(.2,.4,.7),rough=.6):
    s=np.zeros(20,np.float32);s[:4]=[0,0,z,.22];s[4:7]=[0,0,1];s[9]=node;s[10]=rough;s[12:15]=color;return s

class DirectField(unittest.TestCase):
    def test_holes_are_not_proxy_faces(self):
        d,n,c,p=bake_face(np.array([sample(.1)]),np.array([-1.,-1.,-1.]),np.array([1.,1.,1.]),2,1,24)
        self.assertEqual(float(d[0,0,0]),-1)
        self.assertGreater(float(d[12,12,0]),0)
        self.assertTrue(np.all(c[d[...,0]<0,0,:]==0))
    def test_front_layers_and_owner_identity(self):
        records=np.array([sample(.1,2),sample(.4,3),sample(-.3,4)])
        d,n,c,p=bake_face(records,np.array([-.5,-.5,-1.]),np.array([.5,.5,1.]),2,1,16)
        np.testing.assert_allclose(d[4,4,:3],[.6,.9,1.3],atol=1e-6)
        np.testing.assert_equal(n[4,4,:3,3],[3,2,4])
    def test_finite_layers_report_truncation(self):
        records=np.array([sample(z,node) for node,z in enumerate([.5,.4,.3,.2,.1])])
        d,n,c,p=bake_face(records,np.array([-.5,-.5,-1.]),np.array([.5,.5,1.]),2,1,16)
        self.assertGreater(p['farther_insertions_dropped'],0)
        np.testing.assert_allclose(d[4,4],[.5,.6,.7,.8],atol=1e-6)
    def test_linear_color_roughness_and_backface(self):
        a=sample(.1,color=(.1,.2,.3),rough=.4);b=sample(.1,color=(.3,.4,.5),rough=.8)
        d,n,c,p=bake_face(np.array([a,b]),np.array([-.5,-.5,-1.]),np.array([.5,.5,1.]),2,1,16)
        np.testing.assert_allclose(c[4,4,0],[.2,.3,.4,.6],atol=1e-6)
        back=bake_face(np.array([a,b]),np.array([-.5,-.5,-1.]),np.array([.5,.5,1.]),2,-1,16)
        self.assertTrue(np.all(back[0]==-1))

if __name__=='__main__':unittest.main()
