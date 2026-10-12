"""Small, deterministic geometry invariants for physically chipped LIE samples."""
import sys,unittest
from pathlib import Path
import numpy as np

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
from lie_brick01_capture import bake_face, DIMS, PROFILES, clustered_grid


class HeroCaptureGeometry(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        h,w=128,256
        yy,xx=np.mgrid[0:h,0:w]
        red=np.stack([np.full((h,w),.65),np.full((h,w),.30),
                      np.full((h,w),.19)],axis=-1).astype(np.float32)
        colors=np.dstack((red[...,0]+.04*np.sin(xx*.43),red[...,1],red[...,2]))
        height=(.5+.20*np.sin(xx*.20)*np.sin(yy*.3)).astype(np.float32)
        rough=np.full((h,w,3),.72,dtype=np.float32)
        normal=np.full((h,w,3),.5,dtype=np.float32)
        normal[...,2]=1.
        cls.maps={"color":colors,"normal":normal,
                  "height":np.repeat(height[...,None],3,axis=-1),
                  "roughness":rough}
        cls.rect=(0.05,0.05,.95,.95)

    def test_edge_weighted_grid(self):
        s=clustered_grid(100)
        self.assertLess(s[1]-s[0],s[50]-s[49])
        self.assertLess(s[-1]-s[-2],s[50]-s[49])

    def test_front_has_geometric_relief_and_chipped_corner(self):
        length,height,depth=DIMS["brick_full"]
        samples,stats=bake_face(self.maps,self.rect,DIMS["brick_full"],
                                "front",150,80,True)
        self.assertEqual(len(samples),12000)
        self.assertGreater(stats["max_corner_cut_mm"],2.0)
        self.assertGreater(stats["max_edge_cut_mm"],.8)
        self.assertGreater(np.ptp(samples[:,2]),.003)
        self.assertGreater(np.std(samples[:,4:7]),.01)
        self.assertTrue(np.isfinite(samples).all())
        self.assertEqual(samples.dtype,np.dtype("<f4"))

    def test_all_sides_and_half_are_valid(self):
        for master in DIMS:
            for face in ("front","back","top","bottom","left","right"):
                pts,_=bake_face(self.maps,self.rect,DIMS[master],face,60,28,True)
                self.assertEqual(pts.shape,(1680,20))
                self.assertTrue(np.all(pts[:,3]>0))
                self.assertTrue(np.all(pts[:,10]>=.2))
                self.assertTrue(np.all(pts[:,16]<=pts[:,18]))
                self.assertTrue(np.all(pts[:,17]<=pts[:,19]))
                self.assertTrue(np.isfinite(pts).all())

    def test_source_levels_are_in_order(self):
        self.assertEqual(list(PROFILES),["hero","mid","wall"])
        self.assertLess(PROFILES["wall"]["front"][0],PROFILES["hero"]["front"][0])


if __name__=="__main__":unittest.main()
