import sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from lie_wall23_shader import outputs,generate,functions
from lie_wall17_shader import generate as original

class PowerResponseContracts(unittest.TestCase):
    def test_generated_sources_current(self):
        root=Path(__file__).resolve().parents[1]
        for name,source in outputs().items():self.assertEqual((root/name).read_text(),source,name)

    def test_capture_preserves_original_surface_helpers(self):
        old={f[0]:f[3] for f in functions(original(10)[0])}
        new={f[0]:f[3] for f in functions(generate('capture')[0])}
        for name in old.keys() & new.keys()-{'lie_resolve_surface','main'}:
            self.assertEqual(old[name],new[name],name)
        self.assertIn('vec4(old_direct,1)',new['lie_resolve_surface'])
        self.assertIn('vec4(contribution,1)',new['lie_resolve_surface'])

    def test_reuse_has_no_surface_queries_or_brdf(self):
        source,bindings=generate('reuse')
        self.assertEqual(bindings,[6,9,23,42])
        self.assertEqual({f[0] for f in functions(source)},{'lie_resolve_surface','main'})
        for token in ('lie_opaque_brdf(', 'lie_contact_visibility(', 'lie_cached_source_visibility('):self.assertNotIn(token,source)
        self.assertIn('max(base.rgb-old_total,vec3(0))+new_total',source)

if __name__=='__main__':unittest.main()
