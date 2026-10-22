import importlib.util
from pathlib import Path
import struct
import unittest
import numpy as np

path = Path(__file__).resolve().parents[1]/'tools/lie_native_surface.py'
spec = importlib.util.spec_from_file_location('native', path)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class NativeSurfaceTests(unittest.TestCase):
    def assert_exact(self, d):
        packet = m.cell_rectangles(d, 7, 3)
        coverage = np.zeros(d.shape, np.int32)
        recovered = np.full(d.shape, -1, np.float32)
        for offset in range(0, len(packet), 48):
            q = struct.unpack_from('<8f4I', packet, offset)
            x0, y0, x1, y1 = map(int, q[:4])
            self.assertEqual(q[8:10], (7, 3))
            self.assertEqual(len(set(q[4:8])), 1)
            coverage[y0:y1, x0:x1] += 1
            recovered[y0:y1, x0:x1] = q[4]
        np.testing.assert_array_equal(coverage, d >= 0)
        np.testing.assert_array_equal(recovered[d >= 0].view('u4'), d[d >= 0].view('u4'))
        return packet

    def test_holes_layers_cliffs_and_adjacent_depths_remain_exact(self):
        d = np.full((13, 17), .2, np.float32)
        d[2:6, 3:8] = -1
        d[8:, :5] = .9
        d[:, 12] = np.nextafter(np.float32(.2), np.float32(1))
        self.assert_exact(d)

    def test_seeded_fields_preserve_each_occupied_cell(self):
        rng = np.random.default_rng(641)
        for _ in range(10):
            d = rng.choice(np.array([-1, 0, .02, .02, .3, .4], np.float32), (9, 11))
            self.assert_exact(d)

    def test_uniform_field_merges_and_empty_field_emits_nothing(self):
        self.assertEqual(len(self.assert_exact(np.full((13, 17), .1, np.float32))), 48)
        self.assertEqual(self.assert_exact(np.full((7, 3), -1, np.float32)), b'')
        with self.assertRaises(ValueError):
            m.cell_rectangles(np.array([[np.nan]], np.float32), 0, 0)

    def test_reverse_float32_depth_distinguishes_thirty_micrometres(self):
        # Independent float64 projection followed by the D32 attachment's
        # float32 storage. Far/near are the real renderer's 40 m / 1 mm.
        n, f = .001, 40.
        z = np.array([2., 2.00003])
        forward = (f/(f-n)-f*n/((f-n)*z)).astype(np.float32)
        reverse = (n*(f-z)/((f-n)*z)).astype(np.float32)
        self.assertEqual(forward[0], forward[1])
        self.assertGreater(reverse[0], reverse[1])
        np.testing.assert_allclose((n*f/(n+reverse.astype(float)*(f-n))), z, atol=2e-7, rtol=0)


if __name__ == '__main__':
    unittest.main()
