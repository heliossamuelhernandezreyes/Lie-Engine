import copy
import importlib.util
import math
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("transport", Path(__file__).parents[1] / "tools/lie_light_transport.py")
t = importlib.util.module_from_spec(spec)
spec.loader.exec_module(t)


class TransportPhysics(unittest.TestCase):
    def setUp(self):
        self.room = t.room_fixture()

    def test_primary_and_each_bounce_conserve_per_channel_power(self):
        for name in ["bounce", "absorbing", "blocked", "cool"]:
            model, _ = t.scenario(self.room, name)
            history = t.solve(model, 8)["energy_by_generation"]
            primary = t.totals([l["power_rgb"] for l in model["lights"]])
            for step in history:
                for c in range(3):
                    self.assertLessEqual(step["incoming"][c], primary[c] + 1e-9)
                    self.assertLessEqual(step["outgoing"][c], step["incoming"][c] + 1e-9)
                primary = step["outgoing"]

    def test_transfer_preserves_area_reciprocity_and_cannot_duplicate_power(self):
        f, _ = t.form_factors(self.room)
        self.assertLessEqual(max(map(sum, f)), 1 + 1e-12)
        for i, p in enumerate(self.room["patches"]):
            self.assertEqual(f[i][i], 0)
            for j, q in enumerate(self.room["patches"]):
                self.assertAlmostEqual(p["area"] * f[i][j], q["area"] * f[j][i], places=12)

    def test_inverse_square_and_orientation(self):
        p = {"position": [0, 0, 0], "normal": [0, 1, 0], "area": .01}
        l = {"position": [0, 1, 0], "radius": 1e12}
        a = t.light_weight(p, l, [])
        l["position"][1] = 2
        self.assertAlmostEqual(t.light_weight(p, l, []) / a, .25, places=10)
        p["normal"] = [0, -1, 0]
        self.assertEqual(t.light_weight(p, l, []), 0)

    def test_radius_and_occluder_block_direct_light(self):
        p = {"position": [0, 0, 0], "normal": [0, 1, 0], "area": .01}
        l = {"position": [0, 2, 0], "radius": 1}
        self.assertEqual(t.light_weight(p, l, []), 0)
        l["radius"] = 10
        self.assertEqual(t.light_weight(p, l, [[[-1, .9, -1], [1, 1.1, 1]]]), 0)
        blocked, _ = t.scenario(self.room, "blocked")
        flux = t.direct_flux(blocked)
        for p, power in zip(blocked["patches"], flux):
            if p["surface"] == "red":
                self.assertEqual(power, [0, 0, 0])

    def test_red_bounce_and_absorption_change_neutral_receivers(self):
        direct = t.solve(self.room, 0)["total_flux"]
        bounce = t.solve(self.room, 2)["total_flux"]
        absorbing, _ = t.scenario(self.room, "absorbing")
        dark = t.solve(absorbing, 2)["total_flux"]
        floor = [i for i, p in enumerate(self.room["patches"]) if p["surface"] == "floor"]
        red = sum(bounce[i][0] - direct[i][0] for i in floor)
        green = sum(bounce[i][1] - direct[i][1] for i in floor)
        self.assertGreater(red, green * 1.2)
        self.assertLess(sum(dark[i][0] - direct[i][0] for i in floor), red)

    def test_iterations_converge_to_independent_linear_system(self):
        exact = t.closed_solution(self.room)
        errors = []
        for b in [0, 2, 4, 8]:
            approximation = t.solve(self.room, b)["total_flux"]
            errors.append(sum(abs(a - b) for x, y in zip(exact, approximation) for a, b in zip(x, y)))
        self.assertTrue(all(a > b for a, b in zip(errors, errors[1:])))
        self.assertLess(errors[-1] / sum(map(sum, exact)), .001)

    def test_lights_off_and_full_absorption(self):
        m = copy.deepcopy(self.room)
        for light in m["lights"]:
            light["power_rgb"] = [0, 0, 0]
        self.assertEqual(sum(map(sum, t.solve(m)["irradiance"])), 0)
        for material in self.room["materials"].values():
            material["absorption_code"] = 1000
        solved = t.solve(self.room)
        self.assertEqual(solved["total_flux"], solved["direct_flux"])
        self.assertEqual(sum(solved["energy_by_generation"][0]["outgoing"]), 0)

    def test_bad_codes_and_nonfinite_data_are_rejected(self):
        m = copy.deepcopy(self.room)
        m["materials"]["red"]["absorption_code"] = 1001
        with self.assertRaises(ValueError):
            t.solve(m)
        m = copy.deepcopy(self.room)
        m["lights"][0]["power_rgb"][0] = math.nan
        with self.assertRaises(ValueError):
            t.solve(m)
        with self.assertRaises(ValueError):
            t.solve(self.room, 9)


if __name__ == "__main__":
    unittest.main()
