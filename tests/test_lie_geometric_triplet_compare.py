"""Validates separation of capture information errors vs consumer errors."""
import importlib.util
import pathlib
import unittest

spec=importlib.util.spec_from_file_location('lie_triplet_compare',pathlib.Path(__file__).resolve().parents[1]/'tools'/'lie_geometric_triplet_compare.py')
probe=importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


def frame(src,rep,con,tol=.005):
    def layer(m,z,ids=None):
        o={'hit':m,'depth_m':z}
        if ids is not None:o['owner_id']=ids
        return o
    return {'schema':probe.SCHEMA,'width':2,'height':2,'depth_tolerance_m':tol,
        'layers':{'source':layer(*src),'representation':layer(*rep),'consumer':layer(*con)}}


class TripletTest(unittest.TestCase):
    def test_identical_layers(self):
        a=([1,0,1,0],[0.,None,.2,None])
        r=probe.assess(frame(a,a,a))
        self.assertEqual(r['attribution_pixel_counts']['neither'],4)
        self.assertEqual(r['source_to_representation']['iou'],1.)
        self.assertEqual(r['representation_to_consumer']['missing'],0)

    def test_missing_data_vs_missing_consumer(self):
        src=([1,1,1,0],[.1,.1,.1,None])
        rep=([1,0,1,0],[.1,None,.1,None])
        con=([1,0,0,0],[.1,None,None,None])
        r=probe.assess(frame(src,rep,con),include_pixel_causes=True)
        self.assertEqual(r['attribution_pixel_counts'],{'data_only':1,'consumer_only':1,'both':0,'neither':2})
        self.assertEqual(r['source_to_representation']['missing'],1)
        self.assertEqual(r['representation_to_consumer']['missing'],1)
        self.assertEqual(r['pixel_causes'],['neither','data_only','consumer_only','neither'])

    def test_ambiguous_overlap_not_forced_into_one_cause(self):
        src=([1,0,0,0],[.1,None,None,None])
        rep=([0,0,0,0],[None,None,None,None])
        con=([1,0,0,0],[.1,None,None,None])
        r=probe.assess(frame(src,rep,con))
        self.assertEqual(r['attribution_pixel_counts']['both'],1)

    def test_depth_and_owner(self):
        src=([1,0,0,0],[.2,None,None,None])
        rep=([1,0,0,0],[.2,None,None,None],[1,None,None,None])
        con=([1,0,0,0],[.22,None,None,None],[2,None,None,None])
        r=probe.assess(frame(src,rep,con))
        self.assertEqual(r['source_to_representation']['owner_mismatches'],None)
        self.assertEqual(r['representation_to_consumer']['owner_mismatches'],1)
        self.assertEqual(r['representation_to_consumer']['depth_over_tolerance'],1)
        self.assertAlmostEqual(r['representation_to_consumer']['depth_max_m'],.02)

    def test_bad_dimensions_rejected(self):
        a=([1,0,0,0],[.1,None,None,None])
        p=frame(a,a,a);p['width']=3
        with self.assertRaises(ValueError):probe.assess(p)

    def test_miss_depth_must_be_null(self):
        a=([1,0,0,0],[.1,None,None,None])
        p=frame(a,a,a);p['layers']['source']['depth_m'][1]=0.
        with self.assertRaises(ValueError):probe.assess(p)

    def test_empty_screen_iou_is_one(self):
        a=([0,0,0,0],[None,None,None,None])
        self.assertEqual(probe.assess(frame(a,a,a))['source_to_representation']['iou'],1.)

if __name__=='__main__':unittest.main()
