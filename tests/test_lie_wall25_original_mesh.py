"""Original triangle oracle checks that do not require downloading the 500K GLB."""
import unittest
import sys
from pathlib import Path
import numpy as np
import trimesh

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from lie_wall25_original_mesh import transform_original,hit_original_mesh


def packet():
    p=np.zeros(48,np.float32)
    p[16:32]=np.eye(4,dtype=np.float32).T.ravel()
    p[32:35]=[-2,-2,-2];p[36:39]=[2,2,2]
    return p


class OriginalGeometry(unittest.TestCase):
    def test_source_axis_alignment_is_independent_of_captures(self):
        mesh=trimesh.creation.box(extents=[.2,.11,.08])
        cat={'wall06':{'rotation':np.eye(3).tolist(),'translation_m':[0,0,0]}}
        result=transform_original([mesh],cat)
        span=result.vertices.max(0)-result.vertices.min(0)
        np.testing.assert_allclose(span,[.2032,.08*1.016,.11*1.016],atol=1e-12)

    def test_true_mesh_first_intersection(self):
        mesh=trimesh.Trimesh(vertices=[[-.5,-.5,0],[.5,-.5,0],[0,.5,0]],
                             faces=[[0,1,2]],process=False)
        depths=hit_original_mesh(mesh,np.array([0,0,1.]),
                    np.array([[0,0,-1.],[.8,0,-.6]]),packet())
        self.assertAlmostEqual(depths[0],1.,places=7)
        self.assertFalse(np.isfinite(depths[1]))

    def test_sparse_hit_indices_are_not_used_as_location_indices(self):
        mesh=trimesh.Trimesh(vertices=[[-.5,-.5,0],[.5,-.5,0],[0,.5,0]],faces=[[0,1,2]],process=False)
        dirs=np.array([[.9,0,-.1]]*7+[[0,0,-1.]],dtype=float)
        distances=hit_original_mesh(mesh,np.array([0,0,1.]),dirs,packet())
        self.assertFalse(np.isfinite(distances[:7]).any())
        self.assertAlmostEqual(distances[7],1.,places=7)

    def test_source_mesh_double_sided_and_proxy_rotation(self):
        mesh=trimesh.creation.box(extents=[.5,.5,.1])
        p=packet()
        depths=hit_original_mesh(mesh,np.array([0,0,1.]),
                                np.array([[0,0,-1.]]),p)
        self.assertAlmostEqual(depths[0],.95,places=7)

if __name__=='__main__':unittest.main()
