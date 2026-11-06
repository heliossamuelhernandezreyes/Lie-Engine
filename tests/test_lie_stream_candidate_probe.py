"""Adversarial fixtures for pre-discard Vulkan candidate masks and temporal reprojection."""
from __future__ import annotations
import importlib.util
from pathlib import Path
import tempfile
import unittest
import numpy as np

ROOT=Path(__file__).resolve().parents[1]/'tools'
def load(name):
    spec=importlib.util.spec_from_file_location(name,ROOT/f'{name}.py')
    module=importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module

probe=load('lie_stream_candidate_probe')
metrics=load('lie_stream_candidate_metrics')

class StreamCandidateTests(unittest.TestCase):
    def test_mask_endianness_three_planes(self):
        with tempfile.TemporaryDirectory() as td:
            f=Path(td)/'risk.bin'
            words=np.zeros((3,metrics.WORDS),dtype='<u4')
            for plane,pixel in [(0,0),(0,31),(0,32),(1,314),(2,434*720+416)]:
                words[plane,pixel//32] |= np.uint32(1 << (pixel%32))
            f.write_bytes(words.tobytes())
            risk=metrics.load_risk(f)
            self.assertEqual(risk.shape,(3,metrics.N))
            self.assertTrue(risk[0,0] and risk[0,31] and risk[0,32])
            self.assertTrue(risk[2,434*720+416])
            self.assertEqual(int(risk.sum()),5)

    def test_malformed_risk_file_fails(self):
        with tempfile.TemporaryDirectory() as td:
            f=Path(td)/'risk.bin'
            f.write_bytes(b'not a complete atomic packet')
            with self.assertRaises(ValueError):metrics.load_risk(f)

    def test_instrumentation_occurs_before_half_open_discard(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td)
            (root/'shaders').mkdir()
            shader=root/'shaders/lie_direct_native.glsl'
            renderer=root/'lie_direct_renderer.gd'
            runner=root/'test_lie_native_depth.gd'
            shader.write_text('layout(location=2) out vec4 out_color;\n'
                 'if(face!=int(face_layer.x-p.meta.x))discard;\n'
                 'if(any(lessThan(capture_cell,patch_cells.xy))||any(greaterThanEqual(capture_cell,patch_cells.zw)))discard;')
            renderer.write_text('\n'.join(probe.RENDERER_MARKERS))
            runner.write_text('    var image := Image.create_from_data(data["output_size"]')
            probe.instrument(shader,renderer,runner)
            result=shader.read_text()
            self.assertLess(result.index('lie_risk_mark(0u)'),result.index(
                'if(any(lessThan(capture_cell,patch_cells.xy))||'))
            self.assertIn('atomicOr(lie_risk.bits',result)
            self.assertIn('buffer_update(_lie_risk',renderer.read_text())
            self.assertIn('candidate-risk.bin',runner.read_text())
            with self.assertRaises(ValueError):probe.instrument(shader,renderer,runner)

    def test_temporal_reproject_owner_change_and_missing_blind_spot(self):
        previous=np.zeros((metrics.N,4),dtype='<f4')
        current=np.zeros_like(previous)
        v=np.zeros(20,dtype=float)
        v[4]=1.;v[9]=1.;v[14]=1.;v[18]=1.
        pixel=360*720+360
        point=[.5/360.,-.5/360.,1.,1.]
        previous[pixel]=point
        current[pixel]=point
        flags,summary=metrics.temporal_mask(current,previous,v)
        self.assertFalse(flags[pixel])
        self.assertEqual(summary['stable_reprojected'],1)
        current[pixel,3]=2.
        flags,_=metrics.temporal_mask(current,previous,v)
        self.assertTrue(flags[pixel])
        current[pixel,3]=0.
        flags,_=metrics.temporal_mask(current,previous,v)
        self.assertFalse(flags[pixel])  # Known temporal blind spot.

if __name__=='__main__':unittest.main()
