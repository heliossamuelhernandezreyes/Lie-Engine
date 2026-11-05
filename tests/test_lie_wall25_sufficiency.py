"""Self-contained tests for the genuine-bank LIE 2.5 three-stage diagnostic."""
import sys,unittest
from pathlib import Path
import numpy as np
from scipy.spatial import cKDTree

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from lie_wall25_sufficiency import intersect_single_master,source_trace,pixels_for_probe,classify,camera_rays


def fixture(points):
    rec=np.zeros((len(points),20),np.float64)
    for i,point in enumerate(points):
        rec[i,:3]=point
        rec[i,3]=.12
        rec[i,4:7]=[0,0,1]
    return dict(rec=rec,radii=rec[:,3],node=np.arange(len(rec)),
                tree=cKDTree(rec[:,:3]),maximum_radius=.12)


class SourceToField(unittest.TestCase):
    def test_near_disk_wins_independent_of_array_order(self):
        m=fixture([[0,0,-.1],[0,0,0]])
        hit=intersect_single_master([0,0,1],[0,0,-1],
             [-.2,-.2,-.2],[.2,.2,.2],m)
        self.assertIsNotNone(hit)
        self.assertAlmostEqual(hit[0],1.,places=8)
        self.assertEqual(hit[1],1)

    def test_hole_is_empty_and_backface_rejected(self):
        m=fixture([[0,0,0]])
        self.assertIsNone(intersect_single_master([.19,.19,1],[0,0,-1],
             [-.2,-.2,-.2],[.2,.2,.2],m))
        self.assertIsNone(intersect_single_master([0,0,-1],[0,0,1],
             [-.2,-.2,-.2],[.2,.2,.2],m))

    def test_sparse_sphere_pruning_does_not_drop_a_hit(self):
        m=fixture([[0,0,0]])
        hit=intersect_single_master([.1,0,1],[0,0,-1],
             [-.2,-.2,-.2],[.2,.2,.2],m)
        self.assertIsNotNone(hit)
        self.assertAlmostEqual(hit[0],1.)

    def test_original_proxy_packet_mapping(self):
        m=fixture([[0,0,0]])
        packet=np.zeros((48,),np.float32)
        packet[16:32]=np.eye(4,dtype=np.float32).T.ravel()
        packet[32:35]=[-.2,-.2,-.2]
        packet[36:39]=[.2,.2,.2]
        packet[42]=9.
        t,owner,_=source_trace(np.array([0,0,1.]),
            np.array([[0,0,-1.],[.8,0,-.6]]),np.array([packet]),[m])
        self.assertAlmostEqual(t[0],1.)
        self.assertEqual(owner[0],10.)
        self.assertFalse(np.isfinite(t[1]))

    def test_deterministic_camera_pixel_selection(self):
        a=np.zeros((400,4),np.float32)
        b=a.copy()
        a[:80,3]=1.
        b[:60,3]=1.
        p,n=pixels_for_probe(a,b,max_disagreements=5,stable_hits=5,empty=5)
        q,m=pixels_for_probe(a,b,max_disagreements=5,stable_hits=5,empty=5)
        np.testing.assert_array_equal(p,q)
        self.assertEqual(n,20)
        self.assertEqual(m,20)

    def test_attribution_missing_extra_and_depth_are_distinct(self):
        one=np.array([1.,np.inf,3.,4.])
        two=np.array([1.1,2.,np.inf,4.])
        d=classify((one,np.array([1,0,3,4])),
                   (two,np.array([1,2,0,7])))
        self.assertEqual(d['missing'],1)
        self.assertEqual(d['extra'],1)
        self.assertEqual(d['owner_mismatches'],1)
        self.assertEqual(d['depth_gt_tolerance'],1)

    def test_float_depth_view_packet_roundtrip(self):
        packet=np.zeros(20,np.float32)
        packet[12:15]=[0,0,-1]
        packet[4:7]=[1,0,0]
        packet[8:11]=[0,1,0]
        packet[18]=1.
        eye,dirs=camera_rays(packet,np.array([3]),2)
        self.assertEqual(dirs.shape,(1,3))
        self.assertAlmostEqual(np.linalg.norm(dirs[0]),1.)

if __name__=='__main__':unittest.main()
