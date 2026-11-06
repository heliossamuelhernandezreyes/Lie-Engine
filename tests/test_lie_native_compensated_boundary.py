"""Static regression guards for STAGED compensated-FP32 GLSL rewriting."""
from __future__ import annotations
import importlib.util
from pathlib import Path
import tempfile
import unittest

P=Path(__file__).resolve().parents[1]/'tools'/'lie_native_compensated_boundary.py'
spec=importlib.util.spec_from_file_location('lie_native_compensated_boundary',P)
tool=importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

class CompensatedShaderExperiment(unittest.TestCase):
    def test_injects_only_ambiguous_predicate(self):
        original='#[fragment]\n#version 450\n'+tool.INSERT_AFTER+'\nvoid main(){'+tool.ORIGINAL+'}'
        with tempfile.TemporaryDirectory() as tmp:
            shader=Path(tmp)/'native.glsl'
            shader.write_text(original)
            result=tool.apply(shader)
            changed=shader.read_text()
            self.assertEqual(result['sensitive_threshold_in_capture_cells'],.002)
            self.assertIn('lie_precise_patch_contains(p,v,rect,patch_cells,plane_coord)',changed)
            self.assertIn('lie_dd_local_eye',changed)
            self.assertIn('lie_dd_local_dir',changed)
            self.assertIn('lie_edge_function',changed)
            self.assertIn('fma(a,b,-hi)',changed)
            self.assertIn('if(lie_ambiguous)',changed)
            self.assertIn('} else if(!lie_rough_inside)discard;',changed)
            self.assertNotIn(tool.ORIGINAL,changed)
            with self.assertRaises(ValueError):tool.apply(shader)

    def test_refuses_unknown_generated_shader(self):
        with tempfile.TemporaryDirectory() as tmp:
            shader=Path(tmp)/'native.glsl'
            shader.write_text('#version 450\nvoid main(){}')
            with self.assertRaises(ValueError):tool.apply(shader)

    def test_rewrite_is_not_a_global_border_discard(self):
        self.assertNotIn('lie_edge_guard',tool.REPLACEMENT)
        self.assertIn('if(!lie_precise_patch_contains',tool.REPLACEMENT)
        self.assertIn('vec2(0.002)',tool.REPLACEMENT)

if __name__=='__main__':unittest.main()
