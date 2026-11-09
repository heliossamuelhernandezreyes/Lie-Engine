import json
from pathlib import Path
import struct
import tempfile
import unittest
import numpy as np
from lie_surface_continuity_probe import cases,disk,oracle,write_fixture

class SurfaceContinuityReferenceTests(unittest.TestCase):
    def test_independent_known_visible_disks(self):
        expected={'large_disk':65532,'offscreen_center':16228,'near_center':15616,'grazing_center':1476}
        for scene in cases():
            if scene['name'] in expected:
                self.assertEqual(int((oracle(scene)['owner']>=0).sum()),expected[scene['name']])

    def test_opaque_owner_does_not_mix_a_hidden_object(self):
        for name in ['opaque_close','opaque_two_banks','opaque_equal_depth','small_front_large_back']:
            scene=next(c for c in cases() if c['name']==name);result=oracle(scene)
            self.assertEqual(int(result['owner'][128,128]),0)
            np.testing.assert_array_equal(result['color'][128,128],[1,0,0])

    def test_support_and_cut_never_close_an_open_region(self):
        full=oracle(dict(disks=[disk()]))['owner']>=0
        limited=oracle(dict(disks=[disk(support=[-.05,-.04,.05,.04])]))['owner']>=0
        cut=oracle(dict(disks=[disk(clip_sense=1.,clip_plane=0.)]))['owner']>=0
        self.assertTrue(np.all(~limited|full));self.assertGreater(int(limited.sum()),0)
        self.assertEqual(int(cut[:,128:].sum()),0);self.assertGreater(int(cut.sum()),0)

    def test_clip_crossing_centers_retain_some_visible_surface(self):
        for name in ['center_behind_eye','center_beyond_far']:
            scene=next(c for c in cases() if c['name']==name)
            self.assertGreater(int((oracle(scene)['owner']>=0).sum()),0,name)

    def test_every_selected_projection_has_a_reserved_queue_pair(self):
        scene=next(c for c in cases() if c['name']=='dense_large_queue')
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);write_fixture(root,scene)
            jobs=np.frombuffer((root/'common-2.bin').read_bytes(),dtype='<u4').reshape(-1,4)
            for bank in [0,1]:
                p=(root/f'bank-{bank}-6.bin').read_bytes();work=struct.unpack_from('<i',p,80)[0]
                header=int(struct.unpack_from('<f',p,212)[0]);raw=(root/f'bank-{bank}-20.bin').read_bytes()
                self.assertEqual(len(raw),header*16+32+work*8)
                rows=np.frombuffer(raw[:header*16],dtype='<u4').reshape(-1,4)
                self.assertEqual(len(rows),work)
                for prefix,projection,job,mode in rows:
                    self.assertEqual(int(jobs[job,3]),int(projection));self.assertEqual(int(mode),0)
                self.assertEqual(struct.unpack_from('<8I',raw,header*16),(0,1,1,0,0,0,0,0))

if __name__=='__main__':unittest.main()
