import importlib.util
from pathlib import Path
import struct
import unittest
import numpy as np

path=Path(__file__).resolve().parents[1]/'tools/lie_direct_access.py'
spec=importlib.util.spec_from_file_location('access',path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

class AccessTests(unittest.TestCase):
    def test_regions_enclose_every_layer_and_partial_edge(self):
        d=np.full((11,19,4),-1,np.float32);d[1,1,0]=.2;d[2,3,3]=.7;d[-1,-1,2]=.4
        b=m.region_bounds(d)
        self.assertEqual(b.shape,(2,3,4));self.assertEqual(b[0,0,2],2)
        for y,x,k in np.argwhere(d>=0):
            lo,hi,count,_=b[y//8,x//8];self.assertLessEqual(lo,d[y,x,k]);self.assertGreaterEqual(hi,d[y,x,k]);self.assertGreater(count,0)
        self.assertTrue((b[0,1,:2]==-1).all())

    def test_plane_is_compiled_once_with_native_corner_depth(self):
        y,x=np.mgrid[:8,:8];d=(.1+x*.001+y*.002).astype(np.float32)
        mesh,error=m.envelope_quads(d,np.zeros((8,8)),3,2,.000001)
        self.assertEqual(len(mesh),48);self.assertLess(error,.000001)
        q=struct.unpack('<8f4I',mesh);self.assertEqual(q[:4],(0.,0.,8.,8.));self.assertEqual(q[8:10],(3,2))
        self.assertAlmostEqual(q[4],.0985,places=6)

    def test_holes_and_owner_changes_never_become_quad_coverage(self):
        d=np.ones((9,13),np.float32)*.1;d[3:6,5:8]=-1
        owner=np.zeros_like(d);owner[:,9:]=4
        mesh,_=m.envelope_quads(d,owner,0,0)
        cover=np.zeros_like(d,dtype=int)
        for off in range(0,len(mesh),48):
            q=struct.unpack_from('<8f4I',mesh,off);x0,y0,x1,y1=map(int,q[:4]);cover[y0:y1,x0:x1]+=1
            self.assertTrue(np.all(owner[y0:y1,x0:x1]==owner[y0,x0]))
        np.testing.assert_array_equal(cover,(d>=0).astype(int))

    def test_depth_discontinuities_split_and_empty_layers_have_no_geometry(self):
        d=np.ones((8,8),np.float32)*.1;d[4:,4:]=.2
        mesh,error=m.envelope_quads(d,np.zeros_like(d),0,0,.0001)
        self.assertGreater(len(mesh),48);self.assertLessEqual(error,.0001)
        self.assertEqual(m.envelope_quads(np.full((3,5),-1),np.zeros((3,5)),0,1)[0],b'')

    def test_native_envelope_refines_large_depth_jumps(self):
        d=np.ones((8,8),np.float32)*.01;d[3:,3:]=1.4;d[0,0]=-1
        mesh,error=m.coarse_envelope(d,6)
        self.assertGreater(len(mesh),4*48);self.assertLessEqual(error,.003001)
        for off in range(0,len(mesh),48):
            q=struct.unpack_from('<8f4I',mesh,off)
            self.assertEqual(q[8:10],(6,0));self.assertTrue(np.isfinite(q[:8]).all())

if __name__=='__main__':unittest.main()
