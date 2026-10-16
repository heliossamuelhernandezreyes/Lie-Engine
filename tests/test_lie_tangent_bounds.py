import sys, struct, unittest
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from lie_asset_surface import compile_blas
from lie_tangent_bounds import disk_bounds, refit

class TangentBounds(unittest.TestCase):
    def bank(self,n=73):
        rng=np.random.default_rng(17);a=np.zeros((n,20),dtype='<f4');a[:,:3]=rng.uniform(-.2,.2,(n,3));a[:,3]=rng.uniform(.0005,.003,n)
        normal=rng.normal(size=(n,3));a[:,4:7]=normal/np.linalg.norm(normal,axis=1)[:,None];return a
    def test_circle_boundary_inside_outward_bounds(self):
        a=self.bank();low,high=disk_bounds(a)
        for i in range(len(a)):
            n=a[i,4:7].astype(float);n/=np.linalg.norm(n);u=np.cross(n,[1,0,0] if abs(n[0])<.8 else [0,1,0]);u/=np.linalg.norm(u);v=np.cross(n,u)
            angles=np.linspace(0,2*np.pi,1001);points=a[i,:3]+a[i,3]*(np.cos(angles)[:,None]*u+np.sin(angles)[:,None]*v)
            self.assertTrue((points>=low[i]).all() and (points<=high[i]).all())
    def test_axis_aligned_disks_and_reversed_normal(self):
        a=self.bank(6);a[:,4:7]=np.r_[np.eye(3),-np.eye(3)];low,high=disk_bounds(a)
        self.assertLess(float((high-low)[np.arange(6),np.arange(6)%3].max()),.00002)
    def test_refit_preserves_forest_and_every_source_id(self):
        a=self.bank();nodes,leaves,roots=compile_blas(a,[(0,37),(37,36)])
        candidate=refit(a,nodes,leaves);self.assertEqual(candidate,refit(a,nodes,leaves));self.assertEqual(len(nodes),len(candidate))
        before=np.frombuffer(nodes,dtype='<u4').reshape(-1,8);after=np.frombuffer(candidate,dtype='<u4').reshape(-1,8)
        np.testing.assert_array_equal(before[:,[3,7]],after[:,[3,7]])
        b=before.view('<f4');c=after.view('<f4');self.assertTrue((c[:,:3]>=b[:,:3]).all() and (c[:,4:7]<=b[:,4:7]).all())
    def test_invalid_packets_rejected(self):
        a=self.bank();nodes,leaves,_=compile_blas(a,[(0,len(a))])
        for bad in [b'',nodes[:-1],b'\0'*len(nodes)]:
            with self.assertRaises(ValueError):refit(a,bad,leaves)
        bad=bytearray(nodes);struct.pack_into('<I',bad,28,0xfffffffe)
        with self.assertRaises(ValueError):refit(a,bad,leaves)

if __name__=='__main__':unittest.main()
