import re,sys,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from lie_wall17_shader import STAGES,outputs,functions,generate
class Kernels(unittest.TestCase):
    def test_generated_sources_and_minimal_resources(self):
        for name,expected in outputs().items():self.assertEqual((ROOT/name).read_text(),expected,name)
        for stage in STAGES:
            source,bindings=generate(stage)
            self.assertIn(f'const int stage={stage};',source)
            self.assertNotIn('int stage=phase.value.x;',source)
            self.assertEqual('shared vec3 query_positions[64]' in source,stage==18)
            self.assertLess(len([b for b in bindings if b not in (8,9,11,12,14)]),32)
            self.assertEqual(len(bindings),len(set(bindings)))
            names={entry[0] for entry in functions(source)}
            if stage not in (10,11):self.assertNotIn('lie_source_trace',names)
            if stage not in (2,3,18):self.assertNotIn('lie_query_geometry',names)
    def test_parent_equations_are_byte_identical(self):
        from lie_wall16_shader import generate as parent
        originals={f[0]:f[3] for f in functions(parent())}
        for stage in STAGES:
            for name,_,_,body in functions(generate(stage)[0]):
                if name!='main':self.assertEqual(body,originals[name],(stage,name))
    def test_paired_diagnostic_contract(self):
        source=(ROOT/'gpu_compute/lie_wall17_android_lab.gd').read_text()
        self.assertIn('KERNEL_MODES[(cycle+offset)%3]',source)
        self.assertIn('_diagnostic_trials(reset)',source)
        self.assertIn('selected.has(int(row["serial"]))',source)
        self.assertIn('effect.clear_visibility_cache()',source)
        self.assertIn('_benchmark_set_values(backup)',source)
        self.assertNotIn('buffer_get_data',source)
        self.assertNotIn('texture_get_data',source)
if __name__=='__main__':unittest.main()
