import unittest
import numpy as np
from lie_masonry_bond import recipe,row_cells,subtract,turn,FLIPS
from lie_scanned_masonry import canonical_bytes
SIZE=[.199519617,.057407229,.100615652]
class BondTests(unittest.TestCase):
    def test_half_lap_grid_and_boundary_pieces(self):
        for n in (2,3,12,22):
            for row in (0,1):
                cells=row_cells(n,row);self.assertEqual([u for a,b in cells for u in range(a,b)],list(range(2*n)))
                self.assertEqual(len(cells),n+row)
            even={b for a,b in row_cells(n,0)[:-1]};odd={b for a,b in row_cells(n,1)[:-1]};self.assertFalse(even&odd)
    def test_openings_and_mortar_never_bridge(self):
        r=recipe(SIZE,'a',2102,'house')
        for e in r['instances']:
            if 'row' not in e:continue
            a,b=e['interval_half_cells']
            for h in r['openings']:
                if h['section']==e['section'] and h['row']<=e['row']<h['row']+h['rows']:
                    self.assertTrue(b<=h['column']*2 or a>=(h['column']+h['columns'])*2)
            if e['master']!='authored_box':self.assertIn(b-a,(1,2));self.assertEqual(e['master']=='scanned_brick',b-a==2)
    def test_rigid_rotations_preserve_all_distances(self):
        corners=np.array([[x,y,z] for x in (-1,1) for y in (-1,1) for z in (-1,1)])*np.array(SIZE)/2
        for e in recipe(SIZE,'a',2102,'house')['instances']:
            if e['master'] not in ('scanned_brick','half_left','half_right'):continue
            R=np.array(e['basis_columns']).T;np.testing.assert_allclose(R.T@R,np.eye(3),atol=1e-12);self.assertAlmostEqual(np.linalg.det(R),1);self.assertEqual(e['scale'],[1,1,1])
            np.testing.assert_allclose(np.linalg.norm((corners[1:]-corners[0])@R.T,axis=1),np.linalg.norm(corners[1:]-corners[0],axis=1),atol=1e-12)
    def test_small_angles_and_jitter_keep_neighbor_clearance(self):
        r=recipe(SIZE,'a',7319,'house');rows={};x,y,z=SIZE
        for e in r['instances']:
            if e['master'] not in ('scanned_brick','half_left','half_right'):continue
            yaw=(0,np.pi,np.pi/2,-np.pi/2)[e['section']];frame=turn(1,yaw);R=frame.T@np.array(e['basis_columns']).T;center=frame.T@np.array(e['origin']);half=np.array([x if e['master']=='scanned_brick' else (x-.008)/2,y,z])/2;extent=abs(R)@half
            rows.setdefault((e['section'],e['row']),[]).append((center-extent,center+extent))
        for entries in rows.values():
            entries.sort(key=lambda v:v[0][0])
            for a,b in zip(entries,entries[1:]):self.assertGreater(b[0][0]-a[1][0],.004)
        for (section,row),entries in rows.items():
            if (section,row+1) in rows:self.assertGreater(min(v[0][1] for v in rows[section,row+1])-max(v[1][1] for v in entries),.004)
    def test_caps_face_the_shortened_side_after_flips(self):
        for e in recipe(SIZE,'a',7319,'house')['instances']:
            if e['master'] not in ('half_left','half_right'):continue
            yaw=(0,np.pi,np.pi/2,-np.pi/2)[e['section']];R=turn(1,yaw).T@np.array(e['basis_columns']).T
            actual=R@np.array([1 if e['master']=='half_left' else -1,0,0]);expected=1 if e['cut_face']=='right' else -1
            self.assertGreater(actual[0]*expected,.999)
    def test_material_bounds_and_four_source_orientations(self):
        bricks=[e for e in recipe(SIZE,'a',2102,'house')['instances'] if 'orientation' in e];self.assertEqual({e['orientation'] for e in bricks},{0,1,2,3})
        for e in bricks:self.assertTrue(all(.835<=v<=1.177 for v in e['tint']));self.assertTrue(-.045<=e['roughness_delta']<=.045)
        self.assertGreater(np.std([e['tint'][0] for e in bricks]),.04)
    def test_seed_and_uniform_controls(self):
        for seed in (0,2102,7319,2**32-1):self.assertEqual(canonical_bytes(recipe(SIZE,'a',seed,'house')),canonical_bytes(recipe(np.nextafter(SIZE,np.inf),'a',seed,'house')))
        self.assertNotEqual(canonical_bytes(recipe(SIZE,'a',2102)),canonical_bytes(recipe(SIZE,'a',7319)))
        for e in recipe(SIZE,'a',2102,'house',False)['instances']:
            if 'orientation' in e:self.assertEqual(e['tint'],[1,1,1]);self.assertEqual(e['roughness_delta'],0);self.assertEqual(e['orientation'],0)
    def test_invalid_inputs(self):
        for seed in (True,-1,2**32,1.5):
            with self.assertRaises(ValueError):recipe(SIZE,'a',seed)
        with self.assertRaises(ValueError):recipe(SIZE,'a',2102,'bad')
    def test_interval_subtraction(self):
        self.assertEqual(subtract((0,12),[(2,4),(6,10)]),[(0,2),(4,6),(10,12)])
