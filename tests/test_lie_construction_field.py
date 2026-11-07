import unittest
import numpy as np
from lie_construction_field import build_scene
from lie_field_visibility import clear_segments
from lie_light_field import decode_csr

class ConstructionFieldContract(unittest.TestCase):
    @staticmethod
    def source(color):
        return {'bounds_low':[-.1,-.1,-.02],'bounds_high':[.1,.1,.02],'faces':[{'albedo':color,'roughness':.8} for _ in range(6)]}
    @staticmethod
    def entry(index,z=0,x=0):
        return {'bank':'test','master':'red' if index==0 else 'blue','origin':[x,0,z],'basis_columns':np.eye(3).tolist(),'scale':[1,1,1],'tint':[1,1,1],'roughness_delta':0,'id':str(index)}
    def test_distinct_owners_materials_and_exact_graph_transpose(self):
        model,p,mapping,proof=build_scene({'instances':[self.entry(0),self.entry(1,.3)]},{'test/red':self.source([.7,.2,.1]),'test/blue':self.source([.1,.2,.8])})
        n=len(model['patches']);owners=np.frombuffer(p['owners'],'<u4');self.assertEqual(n,12);self.assertTrue((owners[:6]==0).all() and (owners[6:]==1).all())
        optic=np.frombuffer(p['optics'],'<f4')[4:].reshape(n,16);np.testing.assert_allclose(optic[:6,:3],np.tile([.7,.2,.1],(6,1)),rtol=1e-6);np.testing.assert_allclose(optic[6:,:3],np.tile([.1,.2,.8],(6,1)),rtol=1e-6)
        rows,cols,weights=decode_csr(p['outgoing']);dst,src,reverse=decode_csr(p['factors']);self.assertGreater(len(weights),0)
        self.assertEqual({(int(a),int(b)):np.float32(w).tobytes() for a,b,w in zip(rows,cols,weights)},{(int(a),int(b)):np.float32(w).tobytes() for a,b,w in zip(src,dst,reverse)})
        sums=np.bincount(rows,weights=weights,minlength=n);self.assertLessEqual(sums.max(),1.000001)
        raw=np.frombuffer(mapping,'<u4');self.assertEqual(tuple(raw[:2]),(2,12));spans=raw[4:4+2*6*2].reshape(12,2);self.assertTrue((spans[:,0]==np.arange(12)).all());self.assertTrue((spans[:,1]==1).all())
    def test_aperture_and_owner_exclusion_are_geometric(self):
        boxes=np.array([[[-.3,-.2,-.03],[-.1,.2,.03]],[[.1,-.2,-.03],[.3,.2,.03]]]);a=np.array([[0.,0.,-1.],[.2,0.,-1.],[-.2,0.,0.]]);b=np.array([[0.,0.,1.],[.2,0.,1.],[-.2,0.,1.]])
        self.assertEqual(clear_segments(a,b,boxes).tolist(),[True,False,False]);self.assertEqual(clear_segments(a,b,boxes,np.array([-1,-1,0])).tolist(),[True,False,True])
    def test_parallel_neighbors_do_not_hide_the_only_facing_receiver(self):
        entries=[self.entry(0)]+[self.entry(i+1,0,x=.25*(i+1)) for i in range(12)]+[self.entry(13,.3)];_,p,_,_=build_scene({'instances':entries},{'test/red':self.source([.7,.2,.1]),'test/blue':self.source([.1,.2,.8])},neighbors=1)
        rows,cols,_=decode_csr(p['outgoing']);self.assertIn((4,13*6+5),set(zip(rows.tolist(),cols.tolist())))
if __name__=='__main__':unittest.main()
