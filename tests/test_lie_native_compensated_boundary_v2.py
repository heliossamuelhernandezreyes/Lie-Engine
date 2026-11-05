"""V2 injection tests: original depth must remain unrounded in fallback."""
from __future__ import annotations
import importlib.util
from pathlib import Path
import tempfile
import unittest
P=Path(__file__).resolve().parents[1]/'tools'/'lie_native_compensated_boundary_v2.py'
spec=importlib.util.spec_from_file_location('lie_compensated_v2',P)
tool=importlib.util.module_from_spec(spec);spec.loader.exec_module(tool)

class CompensatedV2(unittest.TestCase):
    def test_exact_depth_varying_is_passed_between_stages(self):
        original='''#[vertex]
#version 450
layout(location=3) flat out float plane_coord;
void main(){plane_coord=(q.meta.x%2u==0u)?p.hi[axis]-q.depth.x:p.lo[axis]+q.depth.x;}
#[fragment]
#version 450
layout(location=2) out vec4 out_color;
void main(){if(any(lessThan(capture_cell,patch_cells.xy))||any(greaterThanEqual(capture_cell,patch_cells.zw)))discard;}
'''
        with tempfile.TemporaryDirectory() as td:
            file=Path(td)/'shader.glsl';file.write_text(original)
            tool.apply(file);x=file.read_text()
            self.assertIn('layout(location=4) flat out float lie_native_source_depth;',x)
            self.assertIn('layout(location=4) flat in float lie_native_source_depth;',x)
            self.assertIn('lie_native_source_depth=q.depth.x;',x)
            self.assertIn('lie_dd_sub(vec2(p.hi[axis],0.),vec2(lie_native_source_depth,0.))',x)
            self.assertIn('precise vec2 value_low',x)
            self.assertNotIn(tool.ORIGINAL,x)
            with self.assertRaises(ValueError):tool.apply(file)

if __name__=='__main__': unittest.main()
