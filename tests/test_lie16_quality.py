import math
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from lie16_quality import merge_cell, lod_weights


class ConservativeQuality(unittest.TestCase):
    def points(self):
        return [[x, y, .5, .7, 0, 0, 1, 5] for y in [-.005, .005] for x in [-.005, .005]]

    def test_complete_planar_cell_preserves_plane_and_mean(self):
        self.assertEqual(merge_cell(self.points(), 2), [0, 0, .5, .7, 0, 0, 1, 5])

    def test_boundary_and_thin_detail_never_merge(self):
        self.assertIsNone(merge_cell(self.points()[:3], 2))

    def test_material_crease_and_discontinuous_depth_remain_fine(self):
        for index, value in [(3, .2), (4, 1.), (2, .55), (7, 4)]:
            points = self.points()
            points[0][index] = value
            self.assertIsNone(merge_cell(points, 2))

    def test_lod_weights_are_continuous_and_conserve_contribution(self):
        for spacing in [.01, .3, .575, .8, 1.15, 2, 20]:
            weights = lod_weights(spacing)
            self.assertAlmostEqual(sum(w for _, w in weights), 1)
            self.assertTrue(all(0 <= w <= 1 for _, w in weights))
        for boundary in [.30, .35, .60, .70]:
            a = dict(lod_weights(boundary - 1e-7))
            b = dict(lod_weights(boundary + 1e-7))
            self.assertLess(max(abs(a.get(k, 0) - b.get(k, 0)) for k in range(3)), 1e-5)

    def test_invalid_screen_footprint_rejected(self):
        for spacing in [0, -1, math.nan, math.inf]:
            with self.assertRaises(ValueError):
                lod_weights(spacing)
