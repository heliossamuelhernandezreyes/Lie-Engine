"""Independent scene geometry, radiometric comparison and shared shader wiring."""
import unittest
import numpy as np
from lie_brick_reference_math import split_triangle, triangle_area, camera_frame, metrics
from lie_brick_reference_shader import generate


class BrickReferenceTests(unittest.TestCase):
    def test_subdivision_preserves_source_area_and_orientation(self):
        t=np.array([[0,0,0],[.24,0,0],[0,.07,0.]])
        children=split_triangle(t,.04)
        self.assertGreater(len(children),1)
        self.assertAlmostEqual(sum(triangle_area(c) for c in children),triangle_area(t),places=13)
        self.assertTrue(all(np.cross(c[1]-c[0],c[2]-c[0])[2]>0 for c in children))

    def test_thin_surface_quadrature_budget_keeps_area(self):
        t=np.array([[0,0,0],[.6,0,0],[0,.008,0]])
        children=split_triangle(t,.075,.0025)
        self.assertEqual(len(children),1)
        self.assertAlmostEqual(sum(triangle_area(c) for c in children),.0024)

    def test_camera_frame_is_orthonormal(self):
        right,up,forward=camera_frame([.48,.34,.57],[0,.075,-.035])
        basis=np.array([right,up,-forward]);np.testing.assert_allclose(basis@basis.T,np.eye(3),atol=1e-14)
        self.assertAlmostEqual(np.linalg.det(basis),1.)

    def test_errors_do_not_fit_exposure(self):
        reference=np.ones((3,3,3));actual=reference*2
        self.assertEqual(metrics(actual,reference)['relative_l1'],1.)

    def test_invalid_or_empty_comparison_rejected(self):
        image=np.zeros((3,3,3))
        with self.assertRaises(ValueError):metrics(image,image,np.zeros((3,3),bool))
        with self.assertRaises(ValueError):metrics(image+np.nan,image)

    def test_consumer_keeps_capture_reconstruction_and_common_stencil(self):
        shader=generate()
        for name in ['bool covered(', 'float pixel_depth(', 'lie_stencil_weight(', 'bench_indirect(', 'lie_surface_unoccluded(', 'lie_emitter_gain(']:self.assertIn(name,shader)
        self.assertIn('imageStore(final_image,xy,vec4(linear,',shader)
        self.assertNotIn('parameters.ambient.rgb*.12',shader)
        self.assertIn('light*uint(SHADOW_SIZE*SHADOW_SIZE)',shader)
        self.assertIn('bool face_support=',shader)
        self.assertIn('y=-shadow_bound',shader)
        self.assertNotIn('y=-shadow_bound',generate(False))


if __name__=='__main__':unittest.main()
