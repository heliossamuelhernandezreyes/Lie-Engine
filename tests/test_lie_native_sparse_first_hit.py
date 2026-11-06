"""Native-only sparse first-hit detection regression fixtures; NOT GPU execution."""
import importlib.util
import sys
from pathlib import Path
import unittest
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
spec=importlib.util.spec_from_file_location('lie_native_sparse_first_hit',ROOT/'tools'/'lie_native_sparse_first_hit.py')
sparse=importlib.util.module_from_spec(spec)
spec.loader.exec_module(sparse)


def packets():
    world=np.zeros((sparse.N,4),dtype='<f4')
    view=np.zeros(20,dtype='<f4')
    view[:3]=[.5,.5,2.]
    view[14]=-1.
    view[4]=1.
    view[9]=1.
    view[18]=1.
    proxies=np.zeros((97,48),dtype='<f4')
    proxies[0,16:32]=np.eye(4,dtype='<f4').T.flatten()
    proxies[0,32:35]=[0,0,0]
    proxies[0,36:39]=[1,1,1]
    surface={'boxes':[{'first_face':0}], 'faces':[{'width':2,'height':2} for i in range(6)]}
    return world,view,proxies,surface


class SparseFirstHitTests(unittest.TestCase):
    def test_neighbor_cardinal_count_not_wraparound(self):
        hit=np.zeros(sparse.N,bool)
        at=360*sparse.WIDTH+360
        for offset in (-1,1,-sparse.WIDTH,sparse.WIDTH):
            hit[at+offset]=True
        n=sparse.neighbor_counts(hit)
        self.assertEqual(int(n[at]),4)
        self.assertEqual(int(n[0]),0)
        self.assertEqual(int(n[-1]),0)

    def test_native_winner_near_capture_cell_boundary(self):
        w,v,p,meta=packets()
        k=359*sparse.WIDTH+359
        w[k]=[.5,.5,1.,1.]
        flag,signals=sparse.flag_native(w,v,p,meta,threshold_cells=.002)
        self.assertTrue(bool(flag[k]))
        self.assertTrue(bool(signals['edge'][k]))
        self.assertFalse(bool(signals['small_gap'][k]))
        self.assertAlmostEqual(float(signals['nearest_cell_boundary'][k]),0.,places=5)

    def test_interior_winner_not_flagged(self):
        w,v,p,meta=packets()
        k=360*sparse.WIDTH+360
        w[k]=[.6,.6,1.,1.]
        flag,signals=sparse.flag_native(w,v,p,meta,threshold_cells=.002)
        self.assertFalse(bool(flag[k]))
        self.assertGreater(signals['nearest_cell_boundary'][k],.1)

    def test_small_background_gap_detected_without_owners(self):
        w,v,p,meta=packets()
        k=360*sparse.WIDTH+360
        w[k-1,3]=1;w[k+1,3]=1;w[k-sparse.WIDTH,3]=1
        flags,signals=sparse.flag_native(w,v,p,meta,threshold_cells=0.,gap_neighbors=3)
        self.assertTrue(bool(flags[k]))
        self.assertTrue(bool(signals['small_gap'][k]))
        self.assertFalse(bool(signals['edge'][k]))

    def test_missing_errors_not_silently_marked_solved(self):
        flag=np.zeros(sparse.N,bool)
        flag[2]=True
        diagnosis={'disagreement_pixels':[{'pixel_id':1},{'pixel_id':2}]}
        result=sparse.evaluate_known_errors(flag,diagnosis)
        self.assertEqual(result['caught'],1)
        self.assertEqual(result['missed'],1)
        self.assertEqual(result['missed_pixel_ids'],[1])

    def test_invalid_owner_or_settings_rejected(self):
        w,v,p,meta=packets()
        k=360*sparse.WIDTH+360
        w[k]=[.5,.5,1.,900.]
        flags,signals=sparse.flag_native(w,v,p,meta)
        self.assertFalse(bool(flags[k]))  # Mortar / unknown owner excluded, NOT guessed.
        with self.assertRaises(ValueError):sparse.flag_native(w,v,p,meta,-.1)
        with self.assertRaises(ValueError):sparse.flag_native(w,v,p,meta,.002,1)

if __name__=='__main__':unittest.main()
