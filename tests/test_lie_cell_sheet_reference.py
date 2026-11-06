"""Independent geometry cases for the no-DDA sheet reference."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from lie_cell_sheet_reference import CellSheetReference, rational_support


class AnalyticSheetTests(unittest.TestCase):
    def bank(self, root, depth):
        root = Path(root)/'direct'
        root.mkdir()
        depth = np.asarray(depth, dtype='<f4')
        h, w, layers = depth.shape
        normal = np.zeros((layers, h, w, 4), dtype='<f2')
        for y in range(h):
            for x in range(w):
                normal[:, y, x, 3] = y*w+x
        packets = {}
        for name, arr in [('depth.bin', depth), ('normal.bin', normal)]:
            data = arr.tobytes()
            (root/name).write_bytes(data)
            packets[name] = dict(bytes=len(data), sha256=hashlib.sha256(data).hexdigest())
        proof = dict(width=w, height=h, layers=layers, packets=packets,
                     faces=[dict(width=w, height=h, x=0, y=0) for _ in range(6)])
        (root/'surface.json').write_text(json.dumps(proof))
        packet = np.zeros(48, dtype='<f4')
        packet[:16] = np.eye(4).T.reshape(-1)
        packet[16:32] = np.eye(4).T.reshape(-1)
        packet[32:35] = [0, 0, 0]
        packet[36:39] = [1, 1, 1]
        return CellSheetReference(root.parent), packet

    def test_half_open_edge_assigns_exactly_one_cell(self):
        with tempfile.TemporaryDirectory() as td:
            ref, p = self.bank(td, [[[.5], [.5]]])
            for x, expected in [(.5-1e-12, 1), (.5, 2), (.5+1e-12, 2)]:
                d, o, _ = ref.trace([x, .5, 2], [[0, 0, -1]], [p])
                self.assertEqual(o[0], expected)
                self.assertAlmostEqual(d[0], 1.5)

    def test_nearest_hit_is_not_first_cell_in_rectangle_or_first_layer(self):
        # A slanted ray can reach an earlier plane in a later X cell. The
        # reference must compare ray time, rather than array enumeration order.
        with tempfile.TemporaryDirectory() as td:
            ref, p = self.bank(td, [[[.8, .9], [.3, .1]]])
            d, o, _ = ref.trace([.1, .5, 2], [[.4, 0, -1]], [p], details=True)
            self.assertEqual(o[0], 2)
            self.assertAlmostEqual(d[0], 1.1, places=6)

    def test_parallel_ray_outside_box_is_empty(self):
        with tempfile.TemporaryDirectory() as td:
            ref, p = self.bank(td, [[[.5]]])
            d, o, _ = ref.trace([2, .5, 2], [[0, 0, -1]], [p])
            self.assertTrue(np.isinf(d[0]))
            self.assertEqual(o[0], 0)

    def test_zero_measure_corner_keeps_half_open_owner(self):
        with tempfile.TemporaryDirectory() as td:
            ref, p = self.bank(td, np.full((2, 2, 1), .5))
            d, o, _ = ref.trace([.5, .5, 2], [[0, 0, -1]], [p])
            self.assertEqual(o[0], 4)
            self.assertAlmostEqual(d[0], 1.5)

    def test_packet_tampering_is_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            self.bank(td, [[[.5]]])
            (Path(td)/'direct/depth.bin').write_bytes(b'bad')
            with self.assertRaisesRegex(ValueError, 'identity'):
                CellSheetReference(Path(td))

    def test_rational_witness_distinguishes_half_open_edge_without_epsilon(self):
        with tempfile.TemporaryDirectory() as td:
            _, p = self.bank(td, [[[.5], [.5]]])
            view = np.zeros(20, dtype='<f4')
            view[:3] = [.5, .5, 2]
            view[12:15] = [0, 0, -1]
            # At screen centre, the ray lies exactly on X=.5. Its sheet
            # belongs to cell 1; accepting cell 0 would invent an occluder.
            self.assertFalse(rational_support(view, p, [0, 0], 1, 4, [0, 0], .5, [2, 1])['inside'])
            self.assertTrue(rational_support(view, p, [0, 0], 1, 4, [1, 0], .5, [2, 1])['inside'])


if __name__ == '__main__':
    unittest.main()
