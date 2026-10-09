import math
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "tools"))
from lie_angles import capture_direction, lie_to_blender, select_view, view_code


class AngularKeyTests(unittest.TestCase):
    def test_cardinal_directions(self):
        cases = [
            ((0, 0, 8), (0, 1, "az_00_el_01")),
            ((8, 0, 0), (4, 1, "az_04_el_01")),
            ((0, 0, -8), (8, 1, "az_08_el_01")),
            ((-8, 0, 0), (12, 1, "az_12_el_01")),
            ((0, 8, 8), (0, 2, "az_00_el_02")),
            ((0, -8, 8), (0, 0, "az_00_el_00")),
        ]
        for pos, expected in cases:
            with self.subTest(pos=pos):
                self.assertEqual(select_view(pos, (0, 0, 0), 0, 16, (-30, 0, 30)), expected)

    def test_local_rotation_and_translation(self):
        self.assertEqual(
            select_view((33, 0, -7), (25, 0, -7), 90, 16, (-30, 0, 30)),
            (0, 1, "az_00_el_01"),
        )

    def test_all_view_directions_roundtrip(self):
        for ai in range(16):
            for ei, e in enumerate((-30, 0, 30)):
                d = capture_direction(ai, 16, e)
                self.assertEqual(
                    select_view(tuple(v * 10 for v in d), (0, 0, 0), 0, 16, (-30, 0, 30))[2],
                    view_code(ai, ei),
                )

    def test_gltf_to_blender_axes(self):
        self.assertEqual(lie_to_blender((0, 0, 1)), (0.0, -1.0, 0.0))
        self.assertEqual(lie_to_blender((0, 1, 0)), (0.0, 0.0, 1.0))
        self.assertEqual(lie_to_blender((1, 0, 0)), (1.0, 0.0, 0.0))

    def test_boundary_wrap_and_invalid(self):
        self.assertEqual(select_view((-0.01, 0, 10), (0, 0, 0), 0, 16, (0,))[2],
                         "az_00_el_00")
        with self.assertRaises(ValueError):
            select_view((1, 0, 0), (0, 0, 0), 0, 2, (0,))
        with self.assertRaises(ValueError):
            view_code(-1, 0)


if __name__ == "__main__":
    unittest.main()
