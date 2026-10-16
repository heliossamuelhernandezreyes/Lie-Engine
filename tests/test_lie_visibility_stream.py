import sys,unittest
from pathlib import Path
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from lie_visibility_order import compile_order
from lie_wall19_shader import outputs
from lie_wall17_shader import functions,generate
ROOT=Path(__file__).resolve().parents[1]
class Stream(unittest.TestCase):
    def test_order_exact_permutation_and_locality(self):
        rng=np.random.default_rng(19);samples=np.zeros((512,20),dtype='<f4');samples[:,:3]=rng.uniform(-1,1,(512,3));before=samples.tobytes();refs=rng.permutation(512).astype('<u4');jobs=[[[0,256,0,0],[256,256,1,256]],[[0,64,0,0]]]
        data,proof=compile_order(samples,refs,jobs);again,_=compile_order(samples,refs,jobs);self.assertEqual(data,again);self.assertEqual(before,samples.tobytes())
        ids=np.frombuffer(data,dtype='<u4')[:512];self.assertEqual(sorted(ids.tolist()),list(range(512)))
        for start in [0,256]:
            ordered=ids[start:start+256];self.assertTrue(np.all((ordered>=start)&(ordered<start+256)))
            p=samples[refs[start:start+256],:3];q=samples[refs[ordered],:3];self.assertLess(np.linalg.norm(np.diff(q,axis=0),axis=1).mean(),np.linalg.norm(np.diff(p,axis=0),axis=1).mean()*.5)
        self.assertEqual(proof['levels'][1]['offset'],512)
    def test_invalid_schedule_rejected(self):
        a=np.zeros((4,20),dtype='<f4')
        for refs,jobs in [(np.array([9]),[[[0,1,0,0]]]),(np.arange(4),[[[0,4,0,1]]]),(np.arange(4),[[[0,5,0,0]]])]:
            with self.assertRaises(ValueError):compile_order(a,refs,jobs)
    def test_exact_disk_equations_and_separate_paths(self):
        out=outputs()
        for name,text in out.items():self.assertEqual((ROOT/name).read_text(),text,name)
        baseline={v[0]:v[3] for v in functions(generate(11)[0])};trace={v[0]:v[3] for v in functions(out['gpu_compute/shaders/lie_wall19_trace.glsl'])};prepare=out['gpu_compute/shaders/lie_wall19_prepare.glsl']
        self.assertNotIn('float lie_source_trace(',prepare)
        self.assertNotIn('bool lie_witness_blocks(',out['gpu_compute/shaders/lie_wall19_trace.glsl'])
        for name in ['lie_source_box','lie_source_box_precomputed','lie_ray_reciprocal','lie_write_visibility']:self.assertEqual(baseline[name],trace[name])
        disk='float denominator=dot(normal,d);if(abs(denominator)<1e-8)continue;'
        self.assertIn(disk,trace['lie_source_trace']);self.assertIn('if(dot(delta,delta)>source.w*source.w)continue;',trace['lie_source_trace'])
if __name__=='__main__':unittest.main()
