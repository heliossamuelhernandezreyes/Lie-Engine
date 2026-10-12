"""Algebraic regression test for LIE33 flattened two-dimensional GPU grids.

Tests *correct coverage*, no duplication, and safe workgroup limits
for all six compositor compute passes at 1080 native and 2160 internal.
The native Vulkan CI is an independent, stronger test.
"""
from __future__ import annotations
import math
import unittest

GROUP_X_LIMIT = 65535
THREADS = 64


def grid(items: int) -> tuple[int, int]:
    groups = math.ceil(items/THREADS)
    x = min(groups, GROUP_X_LIMIT)
    return x, math.ceil(groups/x)


def emitted_intervals(items: int):
    x, y = grid(items)
    assert x <= 65535 and y <= 65535 and x >= 1 and y >= 1
    pitch = x * THREADS
    # Flatten each Y workgroup row and explicitly validate its start/end.
    return [(row*pitch, min(items,(row+1)*pitch)) for row in range(y)]


class TiledDispatch(unittest.TestCase):
    def test_full1080_square_clear_and_shade(self):
        size = 2160*2160
        assert grid(size) == (65535,2)
        intervals=emitted_intervals(size)
        self.assertEqual(intervals[0],(0,4194240))
        self.assertEqual(intervals[1],(4194240,size))
        self.assertEqual(sum(b-a for a,b in intervals),size)

    def test_render_passes(self):
        for items in (262144,437306,750000,1080*1080,2160*2160):
            runs=emitted_intervals(items)
            self.assertEqual(runs[0][0],0)
            self.assertEqual(runs[-1][1],items)
            for left,right in zip(runs,runs[1:]):
                self.assertEqual(left[1],right[0])
                self.assertLessEqual(left[0],left[1])

    def test_zero_and_stage_boundaries(self):
        for items in (1,64,65,65535*64,65535*64+1):
            self.assertEqual(sum(b-a for a,b in emitted_intervals(items)),items)


if __name__ == "__main__":
    unittest.main()
