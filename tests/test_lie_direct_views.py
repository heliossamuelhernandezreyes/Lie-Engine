import sys
import unittest
from pathlib import Path
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import lie_direct_views as v

class CapturedViewsTests(unittest.TestCase):
    def test_angular_index_covers_sphere_with_bounded_three_references(self):
        rng = np.random.default_rng(147)
        for direction in rng.normal(size=(1000, 3)):
            selected = v.oct_select(direction)
            self.assertEqual(len(selected), 3)
            self.assertAlmostEqual(sum(w for _, w in selected), 1)
            self.assertTrue(all(0 <= i < 64 and w >= -1e-12 for i, w in selected))
            reconstructed = sum(v.oct_decode([i % 8 / 7, i // 8 / 7]) * w for i, w in selected)
            cosine = reconstructed @ direction / np.linalg.norm(reconstructed) / np.linalg.norm(direction)
            self.assertGreater(cosine, .97)

    def test_provenance_bits_keep_full_atlas_layer_and_face_without_float_rounding(self):
        for face in range(12):
            for layer in range(4):
                code = v.pack_code(np.array([0,1023]), np.array([0,2047]), face, layer)
                x, y, f, k = v.unpack_code(code)
                np.testing.assert_array_equal(x, [0,1023]); np.testing.assert_array_equal(y, [0,2047])
                self.assertTrue((f == face).all() and (k == layer).all() and (code != 0).all())

    def test_offline_visibility_selects_nearer_cell_and_preserves_real_hole(self):
        # Two parallel, attributed captured squares. The reference camera sees
        # the nearer square at z=.2, while a deliberately empty right half stays empty.
        xyz = np.array([[-.5,0.,0.],[-.5,0.,.2]])
        cells = [(4,2,[0,1],np.array([1.,2.]),xyz,v.pack_code([3,5],[7,7],4,[0,1]))]
        image, _ = v.bake_view(cells,np.array([-1.,-1.,-.5]),np.array([1.,1.,.5]),np.array([0.,0.,1.]),32)
        occupied = image[...,1] != 0
        self.assertTrue(occupied.any()); self.assertTrue((~occupied[:,20:]).all())
        self.assertTrue(np.allclose(image[...,0].view(np.float32)[occupied],.2))
        x,y,face,layer = v.unpack_code(image[...,1][occupied])
        self.assertTrue((x==5).all() and (layer==1).all())

    def test_orthographic_frame_preserves_original_bounds_without_axis_guessing(self):
        lo=np.array([-.1,-.03,-.05]); hi=-lo
        corners=np.array([[x,y,z] for x in [lo[0],hi[0]] for y in [lo[1],hi[1]] for z in [lo[2],hi[2]]])
        for index in range(64):
            direction=v.oct_decode([index%8/7,index//8/7])
            center,right,up,extent,wh=v.camera(lo,hi,direction,192)
            self.assertAlmostEqual(right@up,0)
            self.assertTrue((np.abs(np.column_stack([(corners-center)@right,(corners-center)@up])) < extent).all())
            self.assertTrue((wh<=192).all())

if __name__=='__main__': unittest.main()
