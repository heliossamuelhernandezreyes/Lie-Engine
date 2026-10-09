import copy
import math
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from lie_light_transport import solve, validate, room_fixture, closed_solution
from lie_optics import fresnel, slab, sheet_transmission, validate_sheets


class RadiusTests(unittest.TestCase):
    def model(self):
        m = room_fixture(2)
        m['secondary_radii'] = {'radius_max': 6, 'radius_decay': .8, 'power_reference': .01}
        return m

    def test_generation_shrinks_without_creating_power(self):
        result = solve(self.model(), 5)
        history = result['energy_by_generation']
        for a, b in zip(history, history[1:]):
            self.assertLessEqual(b['radius_max'], a['radius_max']*.8 + 1e-12)
            for c in range(3):
                self.assertLessEqual(b['incoming'][c], a['outgoing'][c]+1e-12)
                self.assertLessEqual(b['outgoing'][c], b['incoming'][c]+1e-12)

    def test_radius_cutoff_removes_all_out_of_range_bounces(self):
        m = self.model()
        m['secondary_radii']['radius_max'] = .01
        result = solve(m, 3)
        self.assertEqual(result['total_flux'], result['direct_flux'])
        self.assertEqual(result['energy_by_generation'][1]['incoming'], [0,0,0])

    def test_absorption_reduces_power_and_radius(self):
        m = self.model()
        before = solve(m, 0)
        m['materials']['red']['absorption_code'] = 990
        after = solve(m, 0)
        red = [i for i,p in enumerate(m['patches']) if p['material']=='red']
        self.assertTrue(any(before['secondary_radius_by_generation'][0][i]>0 for i in red))
        for i in red:
            self.assertLessEqual(after['secondary_radius_by_generation'][0][i], before['secondary_radius_by_generation'][0][i])

    def test_dark_source_has_no_secondary_radius(self):
        m = self.model()
        m['lights'][0]['power_rgb'] = [0,0,0]
        self.assertTrue(all(r==0 for row in solve(m, 4)['secondary_radius_by_generation'] for r in row))

    def test_invalid_policy_and_nonlinear_closed_oracle_rejected(self):
        m = self.model()
        with self.assertRaises(ValueError): closed_solution(m)
        for value in (0, 1.1, math.nan):
            m['secondary_radii']['radius_decay'] = value
            with self.assertRaises(ValueError): validate(m)


class OpticsTests(unittest.TestCase):
    def sheet(self):
        return {'center':[0,0,0], 'right':[1,0,0], 'up':[0,1,0],
                'half_width':1, 'half_height':1, 'thickness':.2,
                'sigma':[3,.5,.1], 'ior':1.5}

    def test_fresnel_known_normal_incidence_and_grazing(self):
        self.assertAlmostEqual(fresnel(1,1,1.5)[0], .04)
        self.assertAlmostEqual(fresnel(1,1,1.333)[0], ((1-1.333)/(1+1.333))**2)
        self.assertEqual(fresnel(0,1,1.5)[0], 1)
        self.assertGreater(fresnel(.1,1,1.5)[0], fresnel(.9,1,1.5)[0])

    def test_total_internal_reflection_and_snell(self):
        self.assertEqual(fresnel(.5,1.5,1)[0], 1)
        ci = math.cos(math.radians(45))
        f, ct = fresnel(ci,1,1.5)
        self.assertAlmostEqual(math.sqrt(1-ct*ct), math.sqrt(1-ci*ci)/1.5)

    def test_beer_known_value_and_energy_partition(self):
        thin = slab(1,1.5,.2,[3,.5,.1])
        self.assertAlmostEqual(thin['transmission'][0], .96**2*math.exp(-.6))
        for ci in (0,.001,.1,.5,1):
            s = slab(ci,1.5,.2,[3,.5,.1])
            self.assertTrue(all(r+t<=1+1e-12 for r,t in zip(s['reflection'],s['transmission'])))
            self.assertTrue(all(a>=-1e-12 for a in s['absorbed_or_untraced']))
        thick = slab(1,1.5,.8,[3,.5,.1])
        self.assertTrue(all(b<a for a,b in zip(thin['transmission'],thick['transmission'])))

    def test_identity_sheet_transmits_exactly(self):
        s = self.sheet(); s.update(ior=1, sigma=[0,0,0])
        self.assertEqual(sheet_transmission([0,0,-1],[0,0,1],[s]),[1,1,1])

    def test_sheet_segment_is_finite_symmetric_and_stacks(self):
        s = self.sheet()
        forward = sheet_transmission([0,0,-1],[0,0,1],[s])
        self.assertEqual(forward,sheet_transmission([0,0,1],[0,0,-1],[s]))
        self.assertEqual(sheet_transmission([2,0,-1],[2,0,1],[s]),[1,1,1])
        self.assertEqual(sheet_transmission([0,0,.1],[0,0,1],[s]),[1,1,1])
        self.assertEqual(sheet_transmission([0,0,-1],[0,0,1],[s,s]),[x*x for x in forward])

    def test_transmitted_light_filters_and_never_creates_power(self):
        m = room_fixture(2)
        before = solve(m, 2)
        s = self.sheet(); s['up']=[0,0,1]; s['center']=[0,.5,0]; s['half_width']=3; s['half_height']=3
        m['optical_sheets']=[s]
        after = solve(m, 2)
        for a,b in zip(before['direct_flux'],after['direct_flux']):
            self.assertTrue(all(y<=x+1e-12 for x,y in zip(a,b)))
        self.assertLess(sum(x[0] for x in after['direct_flux']),sum(x[0] for x in before['direct_flux']))

    def test_bad_sheet_basis_and_absorption_rejected(self):
        s = self.sheet(); s['up']=[1,0,0]
        with self.assertRaises(ValueError): validate_sheets([s])
        s = self.sheet(); s['sigma'][0]=-1
        with self.assertRaises(ValueError): validate_sheets([s])

if __name__=='__main__': unittest.main()
