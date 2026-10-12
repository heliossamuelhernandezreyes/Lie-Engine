"""Deterministic instance authoring regression tests for LIE29."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from lie29_brick_layout import make_wall


class BrickLayoutTests(unittest.TestCase):
    def test_ten_thousand_instances_only_three_masters(self):
        wall = make_wall()
        self.assertEqual(len(wall), 10_000)
        self.assertLessEqual(len({x.master_id for x in wall}), 3)
        self.assertTrue(all(-0.12 <= x.tone <= 0.12 for x in wall))
        self.assertTrue(all(-0.06 <= x.roughness_offset <= 0.06 for x in wall))

    def test_stable_seed(self):
        self.assertEqual(make_wall(12, 6, seed=123), make_wall(12, 6, seed=123))
        self.assertNotEqual(make_wall(12, 6, seed=123), make_wall(12, 6, seed=124))

    def test_single_master(self):
        self.assertEqual({x.master_id for x in make_wall(9, 9, masters=1)}, {0})

    def test_running_and_stack_bonds(self):
        running = make_wall(2, 2, bond="running")
        stack = make_wall(2, 2, bond="stack")
        self.assertAlmostEqual(running[2].position[0] - running[0].position[0], 0.125)
        self.assertEqual(stack[2].position[0], stack[0].position[0])

    def test_spacing_and_no_overlap(self):
        wall = make_wall(3, 2)
        self.assertAlmostEqual(wall[1].position[0] - wall[0].position[0], .25)
        self.assertAlmostEqual(wall[3].position[1] - wall[0].position[1], .08)

    def test_invalid_controls(self):
        for kwargs in ({"masters": 0}, {"masters": 4}, {"rows": 0},
                       {"columns": 0}, {"bond": "random"},
                       {"tone_variation": -1}, {"brick_height": 0},
                       {"mortar": -0.1}):
            with self.subTest(kwargs=kwargs):
                with self.assertRaises(ValueError):
                    make_wall(**kwargs)


if __name__ == "__main__":
    unittest.main()
