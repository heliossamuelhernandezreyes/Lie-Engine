import sys,unittest
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from lie_wall15_shader import generate,generate_trace_test
class ActiveVisibility(unittest.TestCase):
 def test_generated_kernels(self):
  self.assertEqual(generate(),(ROOT/'gpu_compute/shaders/lie_wall15_active.glsl').read_text())
  self.assertEqual(generate_trace_test(),(ROOT/'gpu_compute/shaders/lie_active_trace_test.glsl').read_text())
 def test_precomputed_broadphase_never_rejects_reference_hits(self):
  rng=np.random.default_rng(6515);n=30000
  lo=rng.uniform(-10,10,(n,3)).astype(np.float32);hi=lo+rng.uniform(.00001,2,(n,3)).astype(np.float32)
  o=rng.uniform(-10,10,(n,3)).astype(np.float32);target=rng.uniform(lo,hi).astype(np.float32)
  d=(target-o).astype(np.float32);d/=np.linalg.norm(d,axis=1)[:,None]
  d[::31,0]=0;d[::47,1]=np.float32(1e-13)
  near=np.zeros(n,dtype=np.float32);far=np.full(n,40,dtype=np.float32);ref_hit=np.ones(n,dtype=bool);fast_hit=ref_hit.copy()
  fast_near=near.copy();fast_far=far.copy()
  for k in range(3):
   parallel=np.abs(d[:,k])<np.float32(1e-12);outside=(o[:,k]<lo[:,k])|(o[:,k]>hi[:,k])
   ref_hit &= ~(parallel&outside);fast_hit &= ~(parallel&outside)
   safe=np.where(parallel,1,d[:,k]).astype(np.float32)
   a=((lo[:,k]-o[:,k])/safe).astype(np.float32);b=((hi[:,k]-o[:,k])/safe).astype(np.float32)
   near=np.maximum(near,np.where(parallel,-np.inf,np.minimum(a,b)));far=np.minimum(far,np.where(parallel,np.inf,np.maximum(a,b)))
   inv=(np.float32(1)/safe).astype(np.float32);x=((lo[:,k]-o[:,k])*inv).astype(np.float32);y=((hi[:,k]-o[:,k])*inv).astype(np.float32)
   padding=(np.float32(8)*np.finfo(np.float32).eps*np.maximum(abs(x),abs(y))+np.float32(1e-9)).astype(np.float32)
   fast_near=np.maximum(fast_near,np.where(parallel,-np.inf,np.minimum(x,y)-padding));fast_far=np.minimum(fast_far,np.where(parallel,np.inf,np.maximum(x,y)+padding))
  ref_hit &= near<=far;fast_hit &= fast_near<=fast_far
  self.assertGreater(np.count_nonzero(ref_hit),25000)
  self.assertFalse(np.any(ref_hit&~fast_hit))
if __name__=='__main__':unittest.main()
