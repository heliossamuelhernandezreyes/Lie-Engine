import sys,unittest
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from lie_spatial_pages import compile_pages
from lie_asset_surface import compile_blas
class Pages(unittest.TestCase):
    def test_conservative_cell_membership_and_determinism(self):
        rng=np.random.default_rng(572018);a=np.zeros((128,20),dtype='<f4');a[:,:3]=rng.uniform(-.1,.1,(128,3));a[:,3]=rng.uniform(.0001,.03,128);a[:,4:7]=rng.normal(size=(128,3));a[:,4:7]/=np.linalg.norm(a[:,4:7],axis=1)[:,None]
        _,_,roots=compile_blas(a,[(0,64),(64,64)]);before=a.tobytes();raw,proof=compile_pages(a,roots);self.assertEqual(a.tobytes(),before);self.assertEqual(compile_pages(a,roots)[0],raw)
        w=np.frombuffer(raw,dtype='<u4');floats=w.view('<f4')
        for index,root in enumerate(roots):
            at=int(w[5])+16*index;dims=w[[at+3,at+7,at+8]].astype(int);lo=floats[at:at+3];hi=floats[at+4:at+7];width=((hi-lo)/dims.astype(np.float32))
            for sid in range(root['start'],root['start']+root['count']):
                s=a[sid];normal=s[4:7].astype(float);t=np.cross(normal,[1.,0,0] if abs(normal[0])<.9 else [0.,1,0]);t/=np.linalg.norm(t);b=np.cross(normal,t)
                for theta in np.linspace(0,2*np.pi,33):
                    point=(s[:3]+s[3]*(np.cos(theta)*t+np.sin(theta)*b)).astype(np.float32);c=np.clip(np.floor((point-lo)/width).astype(int),0,dims-1);cell=(c[2]*dims[1]+c[1])*dims[0]+c[0];off=int(w[at+9]);base=int(w[at+10]);ids=w[base+int(w[off+cell]):base+int(w[off+cell+1])]
                    self.assertIn(sid,ids,'disk circumference must remain in addressed page')
        self.assertEqual(w[6]*4,len(raw));self.assertEqual(len(proof['roots']),2)
    def test_primitive_equations_and_baseline_are_preserved(self):
        from lie_wall17_shader import generate
        from lie_wall18_shader import inject
        source=generate(11)[0];result=inject(source)
        self.assertEqual((ROOT/'gpu_compute/shaders/lie_wall18_pages_11.glsl').read_text(),result)
        primitive=source[source.index('            vec4 source=lie_visibility_position_radius(sid);'):source.index('            nearest=t;blocker=sid;if(nearest<=early)return nearest;')]
        helper=(ROOT/'gpu_compute/shaders/lib/lie_spatial_pages.glslinc').read_text()
        self.assertIn(primitive,helper);self.assertIn('if(accepted)return result;',result)
        self.assertEqual(result.count('binding=37'),1)
    def test_invalid_ranges_fail_before_gpu(self):
        a=np.zeros((1,20),dtype='<f4');a[0,3]=.001;a[0,6]=1
        for roots in [[{'root':0,'start':1,'count':1}],[{'root':0,'start':0,'count':2}],[{'root':1000001,'start':0,'count':1}]]:
            with self.assertRaises(ValueError):compile_pages(a,roots)
if __name__=='__main__':unittest.main()
