"""Independent footprint/blend-domain contracts for the experimental backend."""
import sys,unittest
from pathlib import Path
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from lie_wall24_shader import outputs

class HardwareFootprintContracts(unittest.TestCase):
    def test_generated_sources_current(self):
        root=Path(__file__).resolve().parents[1]
        for name,value in outputs().items():self.assertEqual((root/name).read_text(),value,name)

    def test_triangle_rectangle_covers_every_original_pixel_center(self):
        rng=np.random.default_rng(479)
        for xy in rng.uniform(-50,1100,(1000,2)):
            for radius in [.5,1.,3.4,8.]:
                bound=int(np.ceil(radius));center=np.floor(xy).astype(int)
                lo=center-bound;hi=center+bound+1
                for q in [center-bound,center+bound,center]:
                    self.assertTrue(np.all(q+.5>lo) and np.all(q+.5<hi))

    def test_nonnegative_integer_float_blending_domain(self):
        rng=np.random.default_rng(248)
        terms=rng.integers(0,257,(4096,8),dtype=np.uint32)
        expected=terms.sum(axis=0,dtype=np.uint64)
        for ids in [np.arange(len(terms)),rng.permutation(len(terms))]:
            total=np.zeros(8,dtype=np.float32)
            for row in terms[ids]:total+=row
            np.testing.assert_array_equal(total.astype(np.uint64),expected)
        # A concrete counterexample preserves the explicit precision limit.
        self.assertEqual(np.float32(2**24)+np.float32(1),np.float32(2**24))

if __name__=='__main__':unittest.main()
