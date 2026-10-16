import math,random,sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from lie_wall22_shader import outputs,functions
from lie_wall17_shader import generate

class ScreenTileContracts(unittest.TestCase):
    def test_footprint_reference_capacity_and_clip(self):
        rng=random.Random(22)
        for width,height in [(1,1),(7,9),(1080,1080),(1440,1440)]:
            for _ in range(1500):
                x=rng.randrange(-10,width+10);y=rng.randrange(-10,height+10);bound=rng.randrange(1,9)
                pixels={(px,py) for py in range(max(0,y-bound),min(height-1,y+bound)+1) for px in range(max(0,x-bound),min(width-1,x+bound)+1)}
                tiles={(px//8,py//8) for px,py in pixels}
                self.assertLessEqual(len(tiles),9)
                if pixels:
                    expected={(tx,ty) for ty in range(max(0,y-bound)//8,min(height-1,y+bound)//8+1) for tx in range(max(0,x-bound)//8,min(width-1,x+bound)//8+1)}
                    self.assertEqual(tiles,expected)

    def test_original_helpers_and_single_pixel_writer(self):
        original={f[0]:f[3] for f in functions(generate(3)[0])}
        source=outputs()['gpu_compute/shaders/lie_wall22_resolve.glsl']
        candidate={f[0]:f[3] for f in functions(source)}
        for name in ['covered','pixel_depth','footprint_distance','lie_splat_row']:
            self.assertEqual(original[name],candidate[name],name)
        self.assertNotIn('atomicAdd(accumulated',source)
        self.assertNotIn('atomicMin(depths',source)
        self.assertNotIn('atomicMin(winners',source)
        self.assertIn('bits==nearest',source)
        self.assertIn('owner=min(owner,id)',source)
        self.assertIn('source_visibility.values[id].y,0x80000000u',source)

    def test_integer_reduction_independent_of_list_order(self):
        # Adversarial equal-depth ownership, tolerance boundary and uint wrap.
        rng=random.Random(23)
        records=[(i,3 if i%5==0 else 4 if i%7==0 else 8,[rng.randrange(2**32) for _ in range(8)]) for i in range(1301)]
        expected_owner=min(i for i,d,_ in records if d==3)
        expected=[sum(v[k] for _,d,v in records if abs(d-3)<=1)%(2**32) for k in range(8)]
        for _ in range(12):
            rng.shuffle(records)
            self.assertEqual(min(i for i,d,_ in records if d==min(r[1] for r in records)),expected_owner)
            self.assertEqual([sum(v[k] for _,d,v in records if abs(d-3)<=1)%(2**32) for k in range(8)],expected)

    def test_generated_sources_current(self):
        root=Path(__file__).resolve().parents[1]
        for name,source in outputs().items():self.assertEqual((root/name).read_text(),source,name)

if __name__=='__main__':unittest.main()
