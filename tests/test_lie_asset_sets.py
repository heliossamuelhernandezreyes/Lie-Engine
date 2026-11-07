import copy,unittest
import numpy as np
from lie_asset_sets import compile_set
from lie_asset_contract import bound_source_support,authored_planar_support
from lie_construction_sources import SPECS,mesh_for
from lie_masonry_bond import turn

class Sets(unittest.TestCase):
    def setUp(self):
        self.catalog=dict(sha256='bank-a',masters={'scan':{},'authored':{}})
        self.doc=dict(schema='lie-asset-sets/1',bank_sha256='bank-a',assets={'brick':dict(master='scan',scale_policy='rigid',role='masonry'),'beam':dict(master='authored',scale_policy='authored_positive',role='opening')},sets={'leaf':dict(nodes=[dict(id='b',asset='brick',origin=[1,0,0])]),'group':dict(nodes=[dict(id='left',set='leaf',origin=[0,2,0],basis_columns=turn(1,np.pi/2).T.tolist()),dict(id='right',set='leaf',origin=[3,0,0])])})
    def test_hierarchy_composes_rigid_pose_and_identity(self):
        a=compile_set(self.doc,'group',self.catalog);self.assertEqual(len(a),2);np.testing.assert_allclose(a[0]['origin'],[0,2,-1],atol=1e-14);np.testing.assert_allclose(a[1]['origin'],[4,0,0]);self.assertNotEqual(a[0]['owner_id'],a[1]['owner_id']);self.assertEqual(a,compile_set(self.doc,'group',self.catalog))
    def test_bank_cycle_unknown_and_duplicate_fail(self):
        cases=[]
        d=copy.deepcopy(self.doc);d['bank_sha256']='bank-b';cases.append(d)
        d=copy.deepcopy(self.doc);d['sets']['leaf']['nodes']=[dict(id='loop',set='group')];cases.append(d)
        d=copy.deepcopy(self.doc);d['sets']['leaf']['nodes'][0]['asset']='missing';cases.append(d)
        d=copy.deepcopy(self.doc);d['sets']['group']['nodes'].append(copy.deepcopy(d['sets']['group']['nodes'][0]));cases.append(d)
        for d in cases:
            with self.assertRaises(ValueError):compile_set(d,'group',self.catalog)
    def test_mirrors_shear_and_indirect_scan_scaling_rejected(self):
        for value in (np.diag([-1,1,1]),np.diag([1,2,1]),np.array([[1,.2,0],[0,1,0],[0,0,1]])):
            d=copy.deepcopy(self.doc);d['sets']['group']['nodes'][0]['basis_columns']=value.T.tolist()
            with self.assertRaises(ValueError):compile_set(d,'group',self.catalog)
        for target in ('parent','scan'):
            d=copy.deepcopy(self.doc);node=d['sets']['group']['nodes'][0] if target=='parent' else d['sets']['leaf']['nodes'][0];node['scale']=[2,1,1]
            with self.assertRaises(ValueError):compile_set(d,'group',self.catalog)
    def test_authored_positive_scale_and_bad_materials(self):
        d=copy.deepcopy(self.doc);n=d['sets']['leaf']['nodes'][0];n.update(asset='beam',scale=[2,.5,1]);self.assertEqual(compile_set(d,'group',self.catalog)[0]['scale'],[2,.5,1])
        for field,value in [('scale',[-1,1,1]),('tint',[1,float('nan'),1]),('roughness_delta',.5)]:
            bad=copy.deepcopy(d);bad['sets']['leaf']['nodes'][0][field]=value
            with self.assertRaises(ValueError):compile_set(bad,'group',self.catalog)

class Sources(unittest.TestCase):
    def test_all_authored_sources_are_closed_outward_and_finite(self):
        for name,spec in SPECS.items():
            with self.subTest(asset=name):
                m=mesh_for(spec);self.assertTrue(m.is_watertight and m.is_winding_consistent);self.assertGreater(m.volume,0);self.assertTrue(np.isfinite(m.vertices).all());self.assertGreater(len(m.faces),12)
                support=authored_planar_support(m.vertices,m.faces,m.face_normals,m.metadata['support_groups'],np.eye(3),1.,np.zeros(3));self.assertEqual(support.shape,(len(m.faces),4))
    def test_incomplete_or_nonplanar_support_partition_rejected(self):
        m=mesh_for(SPECS['concrete_lintel']);groups=m.metadata['support_groups']
        with self.assertRaises(ValueError):authored_planar_support(m.vertices,m.faces,m.face_normals,groups[:-1],np.eye(3),1.,np.zeros(3))
        with self.assertRaises(ValueError):authored_planar_support(m.vertices,m.faces,m.face_normals,[list(range(len(m.faces)))],np.eye(3),1.,np.zeros(3))
    def test_thin_joint_support_cannot_escape_declared_axes(self):
        a=np.zeros((3,20));a[:,4:7]=np.eye(3);a[:,16:18]=-1;a[:,18:20]=1
        bound_source_support(a,[-.1,-.004,-.02],[.1,.004,.02]);np.testing.assert_allclose(a[0,16:20],[-.02-.0000002,-.004-.0000002,.02+.0000002,.004+.0000002]);self.assertTrue((a[:,16:18]<=a[:,18:20]).all())
