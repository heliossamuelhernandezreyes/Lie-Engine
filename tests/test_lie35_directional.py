"""LIE35 independent optical material, direction, and energy gates."""
import math
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/"tools"))
from lie35_directional_reference import (
    budgets,effective_radius,fixtures,link_weights,propagate,source,receiver,write_reference
)


class TestDirectionalOpticalCodes(unittest.TestCase):
    def test_energy_conservation_per_color(self):
        for name, case in fixtures().items():
            output=propagate(case["emitters"],case["receivers"])
            for channel in range(3):
                self.assertLessEqual(sum(x[channel] for x in output),
                    sum(x["power"][channel] for x in case["emitters"])+1e-8,name)

    def test_rough_surface_diffuse_response(self):
        case=fixtures()["brick"]
        a,b,through=propagate(**case)
        self.assertGreater(sum(a),0)
        self.assertGreater(sum(b),0)
        self.assertLess(sum(through),sum(a)+sum(b)*0.1)
        coefficients,*_=budgets(case["emitters"][0])
        self.assertGreater(sum(coefficients[0]),sum(coefficients[1]))

    def test_metal_changes_angular_direction(self):
        case=fixtures()["metal"]
        a,b,_=propagate(**case)
        self.assertGreater(sum(a),max(sum(b),1e-10)*5)
        self.assertLess(sum(b),sum(a)*0.2)
        self.assertEqual(sum(budgets(case["emitters"][0])[0][2]),0)

    def test_glass_refracts_and_absorbs_by_channel(self):
        case=fixtures()["glass"]
        result=propagate(**case)
        self.assertGreater(sum(result[2]),sum(result[0]))
        self.assertGreater(result[2][2],result[2][0])
        thin=case["emitters"][0].copy();thin["thickness"]=0.0
        clear=propagate([thin],case["receivers"])
        for k in range(3):
            self.assertLess(result[2][k],clear[2][k])
        self.assertGreater(sum(budgets(case["emitters"][0])[0][2]),0)

    def test_radius_smooth_and_cutoff(self):
        case=fixtures()["metal"]
        near=source("metal",radius=1.251)
        cutoff=source("metal",radius=1.249)
        lhs=propagate([near],case["receivers"])
        rhs=propagate([cutoff],case["receivers"])
        self.assertLess(sum(sum(v) for v in lhs),0.0001)
        self.assertEqual(rhs,[[0.0]*3 for _ in range(3)])
        self.assertEqual(effective_radius([0,0,0]),0)
        self.assertAlmostEqual(effective_radius([1,1,1],radius_max=6),4.92)
        with self.assertRaises(ValueError):effective_radius([1,1,1],irradiance_cutoff=0)

    def test_opacity_absorption_is_real_not_added_light(self):
        cases=fixtures()
        brick=propagate(**cases["brick"])
        black=propagate(**cases["absorbing"])
        self.assertLess(sum(sum(v) for v in black),sum(sum(v) for v in brick))

    def test_invalid_inputs_fail_closed(self):
        invalid=source("glass",roughness=0)
        with self.assertRaises(ValueError):propagate([invalid],[receiver([0,0,1])])
        invalid=source("glass",ior=0)
        with self.assertRaises(ValueError):propagate([invalid],[receiver([0,0,1])])
        invalid=source("glass",sigma=[math.nan,0,0])
        with self.assertRaises(ValueError):propagate([invalid],[receiver([0,0,1])])
        invalid=source("glass",power=[-1,0,0])
        with self.assertRaises(ValueError):propagate([invalid],[receiver([0,0,1])])

    def test_reference_exports_for_native_gpu(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            report=write_reference(Path(tmp)/"reference.json")
            self.assertEqual(set(report),set(fixtures()))
            self.assertEqual(len(report["mixed"]["emitters"]),2)


if __name__=="__main__":
    unittest.main()
