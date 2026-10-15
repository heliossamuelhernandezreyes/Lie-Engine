import hashlib,json,sys,unittest,zlib
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from lie_asset_contract import inspect_bank,planar_frame,proper_rotation,optical_profile
from lie_light_interpolation import weights
from lie_wall07_prepare import compile_groups
class Contract(unittest.TestCase):
    def test_real_scan_and_other_existing_asset(self):
        from lie_brick02_restore import restore
        restore();p=ROOT/'gpu_compute/captures/liebrick02';b=inspect_bank((p/'library.bin').read_bytes(),json.loads((p/'catalog.json').read_text()))
        p=ROOT/'gpu_compute/assets/lie31';cat=json.loads((p/'catalog.json').read_text());raw=zlib.decompress((p/'hd_bank.zlib').read_bytes());other=inspect_bank(raw,cat)
        self.assertIn('concrete_panel',other['assets']);self.assertNotEqual(b['bank_sha256'],other['bank_sha256']);self.assertEqual(other['assets']['concrete_panel']['levels'][0],other['assets']['concrete_panel']['levels'][1])
    def test_failed_bank_rejected_before_render(self):
        p=ROOT/'gpu_compute/assets/lie31';c=json.loads((p/'catalog.json').read_text());raw=zlib.decompress((p/'hd_bank.zlib').read_bytes())
        for field,value,label in [(3,0,'radius'),(4,8,'normal'),(10,-1,'material'),(9,16777216,'patch_id')]:
            a=np.frombuffer(raw,dtype='<f4').copy().reshape(-1,20);a[0,field]=value;mutated=a.tobytes();cat=dict(c,sha256=hashlib.sha256(mutated).hexdigest())
            with self.subTest(label=label),self.assertRaises(ValueError):inspect_bank(mutated,cat)
    def test_semantic_rotation_not_axis_size_guess(self):
        rng=np.random.default_rng(17);xy=rng.uniform(-1,1,(1000,2));a=np.zeros((1000,7));a[:,:3]=np.c_[xy,xy[:,0]*.4-xy[:,1]*.2]
        result=planar_frame(a,np.arange(1000));R=result['rotation'];proper_rotation(R)
        np.testing.assert_allclose(R@result['source_normal'],[0,0,1],atol=1e-12)
        np.testing.assert_allclose(np.linalg.norm((a[1:,:3]-a[:-1,:3])@R.T,axis=1),np.linalg.norm(a[1:,:3]-a[:-1,:3],axis=1),atol=1e-12)
    def test_ambiguous_or_curved_assets_need_authored_frame(self):
        rng=np.random.default_rng(6);a=np.zeros((4000,7));a[:,:3]=rng.normal(size=(4000,3));a[:,:3]/=np.linalg.norm(a[:,:3],axis=1)[:,None]
        with self.assertRaisesRegex(ValueError,'reliable_plane'):planar_frame(a,np.arange(4000))
        with self.assertRaises(ValueError):proper_rotation(np.diag([1,2,1]))
    def test_materials_are_declared_not_guessed(self):
        with self.assertRaises(ValueError):optical_profile({'roughness_origin':'photograph_guess'})
        self.assertEqual(optical_profile({'metallic':0,'transmission':0,'ior':1.5,'roughness_origin':'authored'})['roughness_origin'],'authored')
    def test_groups_partition_and_limit(self):
        self.assertEqual(len(compile_groups([(0,4),(4,3)],7)),16+7*16)
        for groups in [[(0,10)],[(0,4),(3,4)],[(0,4)]]:
            with self.assertRaises(ValueError):compile_groups(groups,7)
class Interpolation(unittest.TestCase):
    def test_constant_and_convex_no_added_radiance(self):
        p=np.array([[-1,-1,0],[1,-1,0],[-1,1,0],[1,1,0]],float);n=np.tile([0,0,1],(4,1));g=np.tile([0,4],(4,1))
        for x in np.linspace(-1,1,21):
            w=weights([x,.2,0],0,p,n,g);self.assertTrue((w>=0).all());self.assertAlmostEqual(w.sum(),1)
            self.assertAlmostEqual(w@np.full(4,3.2),3.2);v=w@np.array([0,1,4,3]);self.assertGreaterEqual(v,0);self.assertLessEqual(v,4)
    def test_no_cross_owner_or_opposite_surface(self):
        p=np.zeros((4,3));n=np.array([[0,0,1],[0,0,-1],[0,0,1],[0,0,1]]);g=np.array([[0,2],[0,2],[2,2],[2,2]])
        np.testing.assert_equal(weights([0,0,0],0,p,n,g),[1,0,0,0])
    def test_continuity_independent_of_reference_node(self):
        p=np.array([[-1,0,0],[1,0,0]]);n=np.array([[0,0,1],[0,0,1]]);g=np.array([[0,2],[0,2]])
        np.testing.assert_allclose(weights([-.000001,0,0],0,p,n,g),weights([.000001,0,0],1,p,n,g),atol=2e-6)
    def test_disabled_is_exact_legacy_selection(self):
        p=np.zeros((4,3));n=np.tile([0,0,1],(4,1));g=np.tile([0,4],(4,1));np.testing.assert_equal(weights([1,2,3],2,p,n,g,False),[0,0,1,0])
if __name__=='__main__':unittest.main()
