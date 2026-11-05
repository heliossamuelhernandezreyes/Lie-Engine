"""Regression checks for the controlled CPU geometric sufficiency experiment."""
import importlib.util
from pathlib import Path
import unittest
import numpy as np

module_path = Path(__file__).resolve().parents[1] / 'tools' / 'lie_geometric_sufficiency_probe.py'
spec = importlib.util.spec_from_file_location('lie_geometric_sufficiency_probe', module_path)
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)

class GeometricSufficiency(unittest.TestCase):
    def test_flat_is_represented_and_projected_without_error(self):
        case = probe.assess('flat')
        for stage in ('source_to_representation', 'representation_to_cpu_consumer'):
            for metric in ('missing', 'extra', 'depth_gt_5mm'):
                self.assertEqual(case[stage][metric], 0)

    def test_finite_samples_cannot_reveal_hidden_bump(self):
        flat = probe.samples('flat')
        bump = probe.samples('hidden_bump')
        np.testing.assert_array_equal(flat, bump)
        case = probe.assess('hidden_bump')
        self.assertGreater(case['source_to_representation']['depth_gt_5mm'], 0)
        self.assertGreater(case['source_to_representation']['depth_max_m'], .25)
        self.assertEqual(case['representation_to_cpu_consumer']['depth_gt_5mm'], 0)

    def test_hole_requires_boundary_support(self):
        case = probe.assess('wall_hole')
        self.assertGreater(case['source_to_representation']['extra'], 0)
        self.assertEqual(case['source_to_representation']['missing'], 0)

    def test_curved_surface_is_not_equal_to_tangent_patches(self):
        case = probe.assess('cylinder')
        self.assertGreater(case['source_to_representation']['depth_gt_5mm'], 0)
        self.assertGreater(case['source_to_representation']['missing'], 0)

    def test_pull_vs_push_are_identical_for_same_representation(self):
        for kind in ('flat', 'wall_hole', 'cylinder', 'hidden_bump'):
            with self.subTest(kind=kind):
                x, y = probe.grid()
                rep = probe.representation_rays(probe.samples(kind), x, y)
                consumer = probe.projected_consumer(probe.samples(kind))
                for left, right in zip(rep, consumer):
                    np.testing.assert_array_equal(left, right)

    def test_repeatable_digests(self):
        for kind in ('flat', 'wall_hole', 'cylinder', 'hidden_bump'):
            self.assertEqual(probe.assess(kind)['sample_sha256'], probe.assess(kind)['sample_sha256'])

if __name__ == '__main__':
    unittest.main()
