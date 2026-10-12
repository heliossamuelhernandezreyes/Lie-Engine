import math
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/"tools"))
from lie_rigid_master import (cylinder_blocked, cylinder_patches, inverse, patch_id,
                             rotation_z, skeleton, transform)


class RigidMasterTests(unittest.TestCase):
    def test_shared_joint_endpoints_and_rigid_lengths(self):
        instances = skeleton([-.8, 1.5, -.4])
        for i, instance in enumerate(instances):
            a = transform([0, -.6, 0], instance["basis"], instance["origin"])
            b = transform([0, .6, 0], instance["basis"], instance["origin"])
            self.assertAlmostEqual(sum((a[k]-b[k])**2 for k in range(3)), 1.44)
            if i:
                previous = instances[i-1]
                end = transform([0, .6, 0], previous["basis"], previous["origin"])
                for x, y in zip(a, end):
                    self.assertAlmostEqual(x, y)

    def test_invalid_angles(self):
        for angles in [[0], [0, math.nan, 0], [0, 3, 0]]:
            with self.assertRaises(ValueError):
                skeleton(angles)

    def test_inverse_and_normals(self):
        basis = rotation_z(.7)
        p = [.18, .1, -.05]
        for x, y in zip(p, inverse(transform(p, basis, [1, 2, 3]), basis, [1, 2, 3])):
            self.assertAlmostEqual(x, y)
        normal = transform([1, 0, 0], basis)
        self.assertAlmostEqual(sum(n*n for n in normal), 1)

    def test_cylinder_is_not_perception_box(self):
        instance = {"basis": rotation_z(0), "origin": [0, 0, 0], "radius": .18, "half_height": .6}
        self.assertFalse(cylinder_blocked([.17, -.8, .17], [.17, .8, .17], [instance]))
        self.assertTrue(cylinder_blocked([.05, -.8, .05], [.05, .8, .05], [instance]))
        self.assertTrue(cylinder_blocked([-.3, 0, 0], [.3, 0, 0], [instance]))
        self.assertFalse(cylinder_blocked([.183, 0, 0], [1, 0, 0], [instance]))

    def test_rotated_proxy(self):
        instance = {"basis": rotation_z(math.pi/2), "origin": [2, 1, 0], "radius": .18, "half_height": .6}
        self.assertTrue(cylinder_blocked([2, .5, 0], [2, 1.5, 0], [instance]))
        self.assertFalse(cylinder_blocked([2, .5, .3], [2, 1.5, .3], [instance]))

    def test_area_and_cap_mapping(self):
        patches = cylinder_patches()
        self.assertEqual(len(patches), 18)
        self.assertAlmostEqual(sum(p["area"] for p in patches), 2*math.pi*.18*(1.2+.18))
        self.assertEqual(patch_id([0, .6, 0], [0, 1, 0]), 17)
        self.assertEqual(patch_id([.18, -.1, 0], [1, 0, 0]), 0)
        self.assertEqual(patch_id([.18, .1, 0], [1, 0, 0]), 8)
