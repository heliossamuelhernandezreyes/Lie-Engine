import math,sys,unittest
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from lie_opaque_reference import evaluate,energy,filtered,prepare
from lie_wall12_shader import generate,generate_test
class OpaqueTests(unittest.TestCase):
    def test_generated_kernels(self):
        self.assertEqual((ROOT/'gpu_compute/shaders/lie_wall12_material.glsl').read_text(),generate())
        self.assertEqual((ROOT/'gpu_compute/shaders/lie_opaque_test.glsl').read_text(),generate_test())
    def test_reciprocity_and_rotation(self):
        rng=np.random.default_rng(73041)
        for _ in range(80):
            v=rng.normal(size=3);v[2]=abs(v[2]);l=rng.normal(size=3);l[2]=abs(l[2]);r=rng.uniform(.2,.98)
            a=evaluate((.4,.2,.1),r,v,l);b=evaluate((.4,.2,.1),r,l,v)
            np.testing.assert_allclose(a,b,rtol=1e-11,atol=1e-11)
            np.testing.assert_allclose(a,evaluate((.4,.2,.1),r,np.roll(v,1),np.roll(l,1),normal=(1,0,0)),rtol=1e-11,atol=1e-11)
    def test_white_furnace_grid(self):
        # A finite numerical audit, not a proof over every direction/material.
        values=[energy(r,nv) for r in [.2,.35,.6,.9,.98] for nv in [.02,.1,.3,.6,1.]]
        self.assertGreater(min(values),0.)
        self.assertLess(max(values),1.001,values)
    def test_variance_and_absorption(self):
        self.assertGreater(filtered(.3,.8),filtered(.3,1.))
        np.testing.assert_equal(evaluate((0,0,0),.3,(0,0,1),(0,0,1),survival=0.),(0,0,0))
        self.assertTrue(all(np.isfinite(c['expected']).all() for c in prepare()))
    def test_conservative_row_interval(self):
        # Exhaustive pixel audit of 1200 independent SPD footprints, including
        # near-edge, rotated subpixel ellipses and the legacy 8px cap.
        rng=np.random.default_rng(8124)
        for _ in range(1200):
            theta=rng.uniform(0,math.pi);rot=np.array([[math.cos(theta),-math.sin(theta)],[math.sin(theta),math.cos(theta)]])
            cov=rot@np.diag(rng.uniform(.2,120,size=2))@rot.T;A,B,C=np.linalg.inv(cov)[(0,0,1),(0,1,1)]
            xy=rng.uniform(-20,100,size=2);center=np.floor(xy).astype(int);bound=math.ceil(np.clip(math.sqrt(max(cov[0,0],cov[1,1])),.5,8))
            for y in range(center[1]-bound,center[1]+bound+1):
                dy=y+.5-xy[1];section=1-(C-B*B/A)*dy*dy;span=math.sqrt(max(section,0)/A);mid=xy[0]-B*dy/A-.5
                low=max(center[0]-bound,math.floor(mid-span)-1);high=min(center[0]+bound,math.ceil(mid+span)+1)
                for x in range(center[0]-bound,center[0]+bound+1):
                    dx=x+.5-xy[0]
                    if A*dx*dx+2*B*dx*dy+C*dy*dy<=1:self.assertTrue(low<=x<=high)
if __name__=='__main__':unittest.main()
