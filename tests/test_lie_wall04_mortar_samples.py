"""Source-contract + synthetic-only geometry tests; never pass synthetic as real source."""
import sys
import unittest
from pathlib import Path
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
from lie_wall04_bake import bank_samples, sample_line, deterministic_hash, ORIGINAL_WALL_SHA

WALL = {
    "sha256": ORIGINAL_WALL_SHA,
    "lighting": {"node_count": 872},
    "collision": {"spatial_envelope_count": 1},
    "wall_layout": {
        "mortar_gap_m": .0085,
        "mortar_shader_layout": {
            "rows": 8, "columns": 12, "brick_length_m": .2032,
            "brick_height_m": .07742225992271486,
            "pitch_x_m": .2117, "pitch_y_m": .08592225992271485,
            "first_brick_x_m": -1.1643500328063965,
            "first_brick_y_m": -.300727903842926,
            "mortar_plane_z_m": .0563086,
            "running_bond_stagger_fraction": .5
        }
    }
}


class SyntheticDonor:
    """Only unit-test fixture: never used in a real asset or published LOD."""
    shape=(128,256)
    def extract(self,along_m,across_m,phase):
        x=along_m*421. + across_m*2361. + phase
        n=len(x)
        color=np.stack((.15+.01*np.sin(x),.12+.006*np.sin(x),.09+.004*np.cos(x)),axis=1).astype(np.float32)
        normals=np.stack((.05*np.sin(x),.04*np.cos(x),np.ones(n)),axis=1).astype(np.float32)
        normals/=np.linalg.norm(normals,axis=1,keepdims=True)
        return (np.ones(n,dtype=bool),color,normals,
                np.asarray(.00032*np.sin(x),dtype=np.float32),
                np.asarray(.72+.05*np.cos(x),dtype=np.float32))


class Wall04SamplesTest(unittest.TestCase):
    def test_conservative_joint_centers_and_single_invisible_box(self):
        donor=SyntheticDonor()
        sampled=bank_samples(WALL,{"horizontal":[donor,donor],"vertical":[donor,donor]},.00135)
        self.assertGreater(len(sampled),35000)
        self.assertLess(len(sampled),250000)
        self.assertEqual(sampled.shape[1],20)
        self.assertTrue(np.isfinite(sampled).all())
        self.assertEqual(int(sampled[:,9].min()),864)
        self.assertEqual(int(sampled[:,9].max()),871)
        self.assertGreater(float(np.ptp(sampled[:,2])),.00005)
        self.assertEqual(WALL["collision"]["spatial_envelope_count"],1)
        self.assertTrue(np.all(sampled[:,16]<=sampled[:,0]))
        self.assertTrue(np.all(sampled[:,18]>=sampled[:,0]))
        self.assertTrue(np.all(sampled[:,17]<=sampled[:,1]))
        self.assertTrue(np.all(sampled[:,19]>=sampled[:,1]))
        j=WALL["wall_layout"]["mortar_shader_layout"]
        for row in range(8):
            for col in range(12):
                cx=(j["first_brick_x_m"]+col*j["pitch_x_m"]+
                    (row%2)*.5*j["pitch_x_m"])
                cy=j["first_brick_y_m"]+row*j["pitch_y_m"]
                violation=(np.abs(sampled[:,0]-cx)<j["brick_length_m"]*.5+.00145)&(
                    np.abs(sampled[:,1]-cy)<j["brick_height_m"]*.5+.00145)
                self.assertFalse(np.any(violation),f"sample overlaps source brick {row}/{col}")

    def test_unchanging_seed_and_no_flat_random_plane(self):
        donors=[SyntheticDonor(),SyntheticDonor()]
        a=sample_line("vertical",4,3,0.,.077,.2,.00135,.0085,.0563,donors)
        b=sample_line("vertical",4,3,0.,.077,.2,.00135,.0085,.0563,donors)
        np.testing.assert_array_equal(a,b)
        self.assertGreater(float(np.ptp(a[:,2])),.00002)
        self.assertTrue(np.all(a[:,3]>.0))
        self.assertTrue(np.all((a[:,10]>=.2)&(a[:,10]<=.99)))

    def test_invalid_source_layout_fails_closed(self):
        donor=SyntheticDonor()
        wall={**WALL,"collision":{"spatial_envelope_count":2}}
        with self.assertRaises(ValueError):
            bank_samples(wall,{"horizontal":[donor],"vertical":[donor]},.0027)
        with self.assertRaises(ValueError):
            sample_line("horizontal",0,0,0.,1.,0.,.0027,.0020,.0563,[donor])

if __name__=="__main__":unittest.main()
