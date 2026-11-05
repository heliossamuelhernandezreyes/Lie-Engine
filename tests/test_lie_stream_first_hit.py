"""Staged GPU first-hit audit contracts: no production G-buffer overwrite."""
from __future__ import annotations
import importlib.util
from pathlib import Path
import tempfile
import unittest
import numpy as np

BASE=Path(__file__).resolve().parents[1]/'tools'
def module(name):
    spec=importlib.util.spec_from_file_location(name,BASE/(name+'.py'))
    m=importlib.util.module_from_spec(spec)
    assert spec.loader
    spec.loader.exec_module(m)
    return m

stage=module('lie_stream_first_hit_stage')

class StagedGPUResolverTests(unittest.TestCase):
    def test_compute_shader_signature_and_winning_record(self):
        src=(BASE/'shaders/lie_stream_first_hit.comp.glsl').read_text()
        self.assertIn('layout(local_size_x=64',src)
        self.assertIn('binding=6,std430',src)
        self.assertIn('binding=7,std430',src)
        self.assertIn('for(int instance=0;instance<97;instance++)',src)
        self.assertIn('if(!is_flagged(pixel,side))return;',src)
        self.assertIn('output_hit.h[pixel].info=vec4(best_revz,1.',src)
        self.assertIn('vec4(0.,3.,float(traversed),0.)',src)
        self.assertNotIn('imageStore(',src)

    def test_staged_injection_preserves_original_draw(self):
        # Minimal but exact Godot markers; staging tool must reject surprises.
        base="""const NativeShadowShader = preload("res://shaders/lie_direct_native_shadow.glsl")
var _lie_risk_zero := PackedByteArray()
    _lie_risk = _buffer(_lie_risk_zero)
var files: Dictionary = {"light":LightShader}
        if key == "light": pipeline = _rd.compute_pipeline_create(shader)
    var group_buffer: RID = light_groups
        _draw(backend,_primary_frame,0); primary_builds += 1; _camera_key = camera_key
"lie_candidate_risk":_rd.buffer_get_data(_lie_risk) if _backend == "native" else PackedByteArray()}
"""
        with tempfile.TemporaryDirectory() as td:
            root=Path(td)
            (root/'shaders').mkdir()
            (root/'lie_direct_renderer.gd').write_text(base)
            (root/'test_lie_native_depth.gd').write_text(
                '    var image := Image.create_from_data(data["output_size"]')
            report=stage.apply(root)
            self.assertEqual(report['output_record_bytes'],64)
            render=(root/'lie_direct_renderer.gd').read_text()
            self.assertEqual(render.count('_draw(backend,_primary_frame,0)'),1)
            self.assertIn('_rd.compute_list_dispatch',render)
            self.assertIn('_lie_resolve_set',render)
            self.assertIn('lie_first_hit',render)
            self.assertTrue((root/'shaders/lie_stream_first_hit.glsl').exists())
            with self.assertRaises(ValueError):stage.apply(root)

    def test_shader_missing_source_is_failure(self):
        with tempfile.TemporaryDirectory() as td:
            with self.assertRaises(FileNotFoundError):stage.apply(Path(td))

if __name__=='__main__':unittest.main()
