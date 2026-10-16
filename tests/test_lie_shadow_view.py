import sys, unittest
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from lie_shadow_view import compact
class ShadowView(unittest.TestCase):
    def test_exact_bits_and_source_order(self):
        rng=np.random.default_rng(18);a=rng.random((301,20)).astype('<f4');a[:,3]=.001
        n=rng.normal(size=(len(a),3));a[:,4:7]=n/np.linalg.norm(n,axis=1)[:,None];a[0,0]=-0.
        raw=compact(a.tobytes());self.assertEqual(len(raw),301*32)
        np.testing.assert_array_equal(np.frombuffer(raw,dtype='<u4').reshape(-1,8),a.view('<u4')[:,:8])
    def test_invalid_source_rejected(self):
        for raw in [b'',b'\0'*79,b'\0'*80]:
            with self.assertRaises(ValueError):compact(raw)
    def test_generated_shader_equations_and_bindings(self):
        from lie_wall21_shader import outputs
        from lie_wall17_shader import generate
        files=outputs()
        for name,text in files.items():self.assertEqual((ROOT/name).read_text(),text,name)
        baseline=generate(11)[0]
        start=baseline.index('float lie_source_trace(');end=baseline.index('// Header: 64 uints.',start)
        self.assertIn(baseline[start:end],files['gpu_compute/shaders/lie_wall21_visibility.glsl'])
if __name__=='__main__':unittest.main()
