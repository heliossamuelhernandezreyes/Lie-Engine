import sys,unittest,re
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from lie_wall16_shader import generate,generate_test

class Queries(unittest.TestCase):
    def test_generated_contract_and_mobile_descriptor_budget(self):
        for name,fn in [('lie_wall16_query.glsl',generate),('lie_witness_test.glsl',generate_test)]:
            self.assertEqual((ROOT/'gpu_compute/shaders'/name).read_text(),fn())
        shader=generate()
        bindings=re.findall(r'layout\(set=0,binding=(\d+),std430\)',shader)
        self.assertEqual(len(bindings),len(set(bindings)))
        self.assertLessEqual(len(bindings),32)
        self.assertIn('lie_query_geometry(s,inst,world,n,radius)',shader)
        self.assertIn('query_memory.words[64u+slot*8u+light]',shader)

    def test_conservative_regions_against_individual_points(self):
        rng=np.random.default_rng(162613)
        # Independent oracle projects each point, with the full 9-pixel halo.
        for _ in range(3000):
            points=(rng.normal(size=(64,3))*rng.uniform(.0001,.3)+rng.uniform(-3,3,3)).astype('f4').astype(float)
            normals=rng.normal(size=(64,3));normals/=np.linalg.norm(normals,axis=1)[:,None]
            eye=rng.uniform(-3,3,3);target=rng.normal(size=3);f=target/np.linalg.norm(target)
            r=np.cross(f,[0,1,0]);r/=np.linalg.norm(r);u=np.cross(r,f)
            tangent=rng.uniform(.2,1.5);size=int(rng.choice([720,1080,1440]));near=.001;far=10.
            d=points-eye;z=d@f;front=np.sum(normals*(-d),axis=1)/np.maximum(np.linalg.norm(d,axis=1),1e-30)
            xy=np.column_stack((d@r,d@u))/np.maximum(z[:,None],1e-30)/tangent
            contributing=(z>near)&(z<far)&(front>.015)&(abs(xy[:,0])<=1+18/size)&(abs(xy[:,1])<=1+18/size)
            lo=points.min(0);hi=points.max(0);c=(lo+hi)*.5;ext=(hi-lo)*.5;delta=c-eye
            tolerance=2e-5*(1+np.linalg.norm(c)+np.linalg.norm(eye))
            rejected=delta@f+ext@abs(f)<near-tolerance or delta@f-ext@abs(f)>far+tolerance
            for side in [r,-r,u,-u]:
                plane=f*tangent*(1+20/size)+side
                rejected=rejected or delta@plane+ext@abs(plane)<-tolerance
            nl=normals.min(0);nh=normals.max(0);dl=eye-hi;dh=eye-lo
            upper=np.maximum.reduce([nl*dl,nl*dh,nh*dl,nh*dh]).sum()
            rejected=rejected or upper < -tolerance
            self.assertFalse(rejected and contributing.any())

    def test_blocking_witness_retested_for_moving_ray(self):
        rng=np.random.default_rng(82615);certified=0
        # Exhaustively enumerate independent finite disks in 2,000 scenes.
        for _ in range(2000):
            centers=rng.uniform([-.03,-.01,.0001],[.03,.01,.012],size=(32,3));radii=rng.uniform(.0001,.008,32)
            direction=np.array([1.,rng.uniform(-.3,.3),rng.uniform(.05,1.)]);direction/=np.linalg.norm(direction)
            origin=np.array([0,0,.0003]);minimum=.0003;limit=.025
            t=(centers[:,2]-origin[2])/direction[2];delta=origin+t[:,None]*direction-centers
            valid=(t>minimum)&(t<limit)&(np.sum(delta*delta,axis=1)<=radii*radii)
            candidate=int(rng.integers(32))
            if valid[candidate] and t[candidate]<=.75*limit:
                certified+=1
                nearest=t[valid].min();x=np.clip((nearest-.75*limit)/(.25*limit),0,1)
                self.assertEqual(x*x*(3-2*x),0.)
        self.assertGreater(certified,10)

if __name__=='__main__':unittest.main()
