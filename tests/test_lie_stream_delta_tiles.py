"""Lossless stream worklist packet regression and keyframe fallback tests."""
from __future__ import annotations
import importlib.util
from pathlib import Path
import unittest
import numpy as np

SCRIPT=Path(__file__).resolve().parents[1]/'tools'/'lie_stream_delta_tiles.py'
spec=importlib.util.spec_from_file_location('lie_stream_delta_tiles',SCRIPT)
delta=importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(delta)
HASH='a'*64

class DeltaWorklist(unittest.TestCase):
    def test_corner_and_critical_pixels_are_bit_exact(self):
        mask=np.zeros(delta.N,bool)
        for k in [0,7,8,719,720,434*720+416,delta.N-1]:mask[k]=True
        result=delta.encode(mask,HASH,2,1)
        self.assertEqual(result['mode'],'P')
        decoded,meta=delta.decode(result['encoded'],HASH,1)
        np.testing.assert_array_equal(decoded,mask)
        self.assertEqual(meta['frame_index'],2)

    def test_random_sparse_roundtrip(self):
        mask=np.random.default_rng(343).random(delta.N)<.0008
        packet=delta.encode(mask,HASH,3,2)
        self.assertEqual(packet['mode'],'P')
        output,_=delta.decode(packet['encoded'],HASH,2)
        np.testing.assert_array_equal(output,mask)

    def test_budget_overflow_requires_keyframe_and_never_truncates(self):
        mask=np.ones(delta.N,bool)
        data=delta.encode(mask,HASH,3,2,max_tiles=2000)
        self.assertEqual(data['mode'],'I_REQUIRED')
        self.assertIsNone(data['encoded'])
        self.assertTrue(data['no_flags_dropped'])

    def test_reference_crc_and_geometry_identity(self):
        mask=np.zeros(delta.N,bool);mask[1000]=True
        packet=delta.encode(mask,HASH,5,4)['encoded']
        with self.assertRaises(ValueError):delta.decode(packet,HASH,3)
        with self.assertRaises(ValueError):delta.decode(packet,'b'*64,4)
        invalid=bytearray(packet);invalid[-1]^=1
        with self.assertRaises(ValueError):delta.decode(bytes(invalid),HASH,4)

if __name__=='__main__':unittest.main()
