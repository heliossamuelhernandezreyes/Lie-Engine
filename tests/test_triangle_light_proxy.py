import copy
import importlib.util
from pathlib import Path
import unittest

spec=importlib.util.spec_from_file_location("triangle_transport",Path(__file__).parents[1]/"tools/lie_light_transport.py")
t=importlib.util.module_from_spec(spec)
spec.loader.exec_module(t)

class TriangleLightProxy(unittest.TestCase):
    def setUp(self):
        self.triangle=[[-1,0,-1],[1,0,-1],[0,0,1]]

    def test_two_sided_open_segment_and_no_false_parallel_hit(self):
        self.assertTrue(t.segment_blocked([0,-1,0],[0,1,0],[],[self.triangle]))
        self.assertTrue(t.segment_blocked([0,1,0],[0,-1,0],[],[self.triangle]))
        self.assertFalse(t.segment_blocked([2,-1,0],[2,1,0],[],[self.triangle]))
        self.assertFalse(t.segment_blocked([-1,1,0],[1,1,0],[],[self.triangle]))
        self.assertFalse(t.segment_blocked([0,0,0],[0,1,0],[],[self.triangle]))

    def test_actual_triangle_visibility_blocks_direct_power(self):
        p={"position":[0,-1,0],"normal":[0,1,0],"area":.1}
        l={"position":[0,1,0],"radius":10}
        self.assertGreater(t.light_weight(p,l,[]),0)
        self.assertEqual(t.light_weight(p,l,[],[self.triangle]),0)

    def test_static_mesh_cache_removes_both_transfer_directions(self):
        room=t.room_fixture(1)
        raw,_=t.form_factors(room)
        n=len(raw)
        room["mesh_visibility"]=[1]*(n*n)
        room["mesh_visibility"][1]=room["mesh_visibility"][n]=0
        f,_=t.form_factors(room)
        self.assertGreater(raw[0][1],0)
        self.assertEqual(f[0][1],0)
        self.assertEqual(f[1][0],0)
        for i,p in enumerate(room["patches"]):
            self.assertLessEqual(sum(f[i]),1+1e-12)
            for j,q in enumerate(room["patches"]):
                self.assertAlmostEqual(p["area"]*f[i][j],q["area"]*f[j][i])

    def test_malformed_geometry_and_asymmetric_cache_rejected(self):
        room=t.room_fixture(1)
        room["triangles"]=[[[0,0,float("nan")],[1,0,0],[0,1,0]]]
        with self.assertRaises(ValueError): t.solve(room)
        room=t.room_fixture(1)
        room["mesh_visibility"]=[1]*16
        room["mesh_visibility"][1]=0
        with self.assertRaises(ValueError): t.solve(room)

    def test_local_pair_caps_retain_reciprocity_and_energy_without_global_dimming(self):
        room=t.room_fixture()
        global_f,_=t.form_factors(room)
        room["factor_normalization"]="symmetric_local"
        local_f,_=t.form_factors(room)
        for i,p in enumerate(room["patches"]):
            self.assertLessEqual(sum(local_f[i]),1+1e-12)
            for j,q in enumerate(room["patches"]):
                self.assertGreaterEqual(local_f[i][j],global_f[i][j]-1e-12)
                self.assertAlmostEqual(p["area"]*local_f[i][j],q["area"]*local_f[j][i],places=12)
        incoming=t.totals([l["power_rgb"] for l in room["lights"]])
        for step in t.solve(room,8)["energy_by_generation"]:
            for c in range(3):
                self.assertLessEqual(step["incoming"][c],incoming[c]+1e-9)
                self.assertLessEqual(step["outgoing"][c],step["incoming"][c]+1e-9)
            incoming=step["outgoing"]
