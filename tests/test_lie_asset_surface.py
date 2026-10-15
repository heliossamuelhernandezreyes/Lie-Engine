import unittest,sys,struct
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from lie_asset_surface import partition_selection,compile_blas,compile_scene
from lie_source_visibility_fixture import cases
class SurfaceCompiler(unittest.TestCase):
    def test_selection_source_ids_and_determinism(self):
        rng=np.random.default_rng(37);a=np.zeros((500,20),dtype='<f4');a[:,:3]=rng.random((500,3));a[:,3]=.001;a[:,6]=1
        selected=partition_selection(a,40)
        np.testing.assert_array_equal(selected,partition_selection(a,40))
        for ids in selected:self.assertEqual(len(set(ids)),40);self.assertLess(int(ids.max()),len(a))
    def test_bvh_bounds_are_outward_and_references_preserved(self):
        a=np.zeros((23,20),dtype='<f4');a[:,0]=np.arange(23)*.01;a[:,3]=.00085;a[:,6]=1
        nodes,refs,roots=compile_blas(a,[(0,23)]);r=np.frombuffer(refs,dtype='<u4');leaves=[]
        for at in range(0,len(nodes),32):
            values=struct.unpack_from('<3fI3fI',nodes,at);self.assertGreater(values[3],at//32)
            if values[7]!=0xffffffff:
                first=values[7];leaves.extend(r[first+1:first+1+r[first]])
        self.assertEqual(sorted(leaves),list(range(23)))
        lo=np.frombuffer(nodes[:12],dtype='<f4');self.assertTrue(np.all(lo<=np.min(a[:,:3].astype(float)-a[:,3,None],axis=0)))
    def test_camera_free_visibility_cases(self):
        result={c['name']:c['expected'] for c in cases()}
        for name in ['flat','slope','opening','reverse','range']:self.assertTrue(all(v==1. for v in result[name]),name)
        for name in ['hidden_step','rotation','nonuniform_scale','same_master_other_instance']:self.assertTrue(all(v==0. for v in result[name]),name)
        for v in result.values():self.assertTrue(all(x==v[0] for x in v))
    def test_singular_transform_rejected(self):
        a=np.zeros((1,20),dtype='<f4');a[:,3]=.001;a[:,6]=1;_,_,roots=compile_blas(a,[(0,1)])
        with self.assertRaises(ValueError):compile_scene([{'root':0,'matrix':np.zeros((4,4)).tolist()}],roots)
    def test_generated_kernel_is_current(self):
        from lie_wall10_shader import generate
        self.assertEqual((ROOT/'gpu_compute/shaders/lie_wall10_source.glsl').read_text(),generate())
if __name__=='__main__':unittest.main()
