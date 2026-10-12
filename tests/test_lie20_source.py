"""Boundary and provenance contracts, independent of Blender and Vulkan."""
import hashlib
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import lie20_source


class SourceContracts(unittest.TestCase):
    def test_locked_asset_license_and_commit(self):
        lock=json.loads((lie20_source.ROOT/'source-lock.json').read_text())
        self.assertEqual(lock['license'],'CC-BY-3.0')
        self.assertEqual(len(lock['commit']),40)
        self.assertEqual(len({x['name'] for x in lock['files']}),len(lock['files']))
        self.assertTrue(any(x['name']=='LeePerrySmith_License.txt' for x in lock['files']))
        for entry in lock['files']:
            self.assertEqual(len(entry['sha256']),64)
            self.assertGreater(entry['bytes'],0)

    def test_corrupted_glb_header_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'bad.glb';path.write_bytes(struct.pack('<III',0,2,12))
            with self.assertRaises(ValueError):lie20_source.read_mesh(path)

    def test_current_locked_source_if_present(self):
        path=lie20_source.ROOT/'LeePerrySmith.glb'
        if not path.exists():self.skipTest('locked source is acquired by Blender workflow')
        lock=json.loads((lie20_source.ROOT/'source-lock.json').read_text())
        expected=next(x['sha256'] for x in lock['files'] if x['name']==path.name)
        self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(),expected)
        positions,normals,uvs,faces=lie20_source.read_mesh(path)
        self.assertEqual(len(positions),9279)
        self.assertEqual(len(faces),17684)
        self.assertEqual(len(normals),len(uvs))


if __name__=='__main__':unittest.main()
