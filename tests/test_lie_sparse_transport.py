"""Independent dense-matrix oracles and real source-bank conservation."""
from pathlib import Path
import hashlib
import json
import math
import struct
import sys
import unittest
import zlib
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
from lie_sparse_transport import pack, unpack
from lie_sparse_shader import sparse_source, PAIRS


class SparseTransfer(unittest.TestCase):
    def test_real_wall_weights_preserve_bits_and_energy(self):
        directory=ROOT/"gpu_compute/assets/lie_wall04"
        dense=zlib.decompress((directory/"indirect_factors.zlib").read_bytes())
        locked=json.loads((directory/"indirect_factors.json").read_text())
        self.assertEqual(hashlib.sha256(dense).hexdigest(),locked["sha256"])
        packet,meta=pack(dense,872)
        self.assertEqual(unpack(packet),dense)
        self.assertEqual(meta["edges"],2618)
        self.assertLess(meta["bytes"],meta["dense_bytes"]*.01)
        matrix=np.frombuffer(dense,"<f4").reshape(872,872).astype(np.float64)
        self.assertLessEqual(matrix.sum(1).max(),1.00001)
        print("REAL WALL04 CSR",json.dumps(meta,sort_keys=True))

    def test_generations_match_independent_numpy_dot(self):
        rng=np.random.default_rng(804)
        matrix=rng.random((19,19));matrix[matrix<.8]=0
        matrix/=np.maximum(matrix.sum(1,keepdims=True),1)
        dense=matrix.astype("<f4").tobytes(); packet,_=pack(dense,19)
        words=struct.unpack(f"<{len(packet)//4}I",packet);base=words[3]
        expected=rng.random((19,3));actual=expected.copy()
        rho=rng.random((19,3))
        matrix=np.frombuffer(dense,"<f4").reshape(19,19).astype(np.float64)
        for _ in range(5):
            next_value=np.zeros_like(actual)
            for receiver in range(19):
                for edge in range(words[4+receiver],words[5+receiver]):
                    source,bits=words[base+2*edge:base+2*edge+2]
                    weight=struct.unpack("<f",struct.pack("<I",bits))[0]
                    next_value[receiver]+=actual[source]*weight
            expected=(matrix.T@expected)*rho
            actual=next_value*rho
            np.testing.assert_allclose(actual,expected,rtol=1e-14,atol=1e-14)

    def test_empty_graph_and_asymmetric_receiver_orientation(self):
        for matrix in (np.zeros((3,3),"<f4"),np.array([[0,.3,0],[0,0,.7],[.2,0,0]],"<f4")):
            raw=matrix.tobytes();packet,_=pack(raw,3);self.assertEqual(unpack(packet),raw)

    def test_bad_data_and_energy_fail_closed(self):
        for value in (-.1,math.nan,math.inf,1.01):
            with self.assertRaises(ValueError):pack(struct.pack('<4f',0,value,0,0),2)
        with self.assertRaises(ValueError):pack(b'\0'*4,2)
        with self.assertRaises(ValueError):pack(b'\0'*4,True)
        packet,_=pack(struct.pack('<4f',0,.3,.4,0),2)
        with self.assertRaises(ValueError):unpack(packet[:-4])
        malformed=bytearray(packet);struct.pack_into('<I',malformed,16,1)
        with self.assertRaises(ValueError):unpack(malformed)

    def test_sparse_shader_is_derived_from_dense_physics(self):
        for name in PAIRS:
            directory=ROOT/'gpu_compute/shaders'
            self.assertEqual((directory/(name+'_sparse.glsl')).read_text(),sparse_source((directory/(name+'.glsl')).read_text()))


if __name__=='__main__':unittest.main()
