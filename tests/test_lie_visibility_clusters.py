import hashlib
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from lie_visibility_clusters import build_bank, STRIDE
from lie_construction_scene_shader import outputs


class VisibilityClusters(unittest.TestCase):
    def test_source_partition_bounds_and_integrity(self):
        rng = np.random.default_rng(7319)
        source = rng.uniform(-.5, .5, (257, 20)).astype('<f4')
        source[:, 4:7] /= np.linalg.norm(source[:, 4:7], axis=1)[:, None]
        raw = source.tobytes()
        sha = hashlib.sha256(raw).hexdigest()
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            (folder / 'library.bin').write_bytes(raw)
            (folder / 'catalog.json').write_text(json.dumps({'stride': 80, 'sha256': sha}))
            entries = {}
            for start, count in [(0, 193), (193, 64)]:
                entries[f'{start}:{count}'] = {'start': start, 'count': count,
                    'core_sha256': hashlib.sha256(raw[start * 80:(start + count) * 80]).hexdigest()}
            (folder / 'pages.json').write_text(json.dumps({'bank_sha256': sha, 'entries': entries}))
            result = build_bank(folder)
            binary = (folder / result['file']).read_bytes()
            indices = np.fromfile(folder / result['indices_file'], dtype='<u4')
            self.assertEqual(hashlib.sha256(binary).hexdigest(), result['sha256'])
            self.assertEqual((folder / 'library.bin').read_bytes(), raw)
            for key, entry in result['entries'].items():
                start, count = map(int, key.split(':'))
                next_offset = 0
                order = indices[entry['index_first']:entry['index_first']+count]
                self.assertEqual(sorted(order.tolist()),list(range(count)))
                for i in range(entry['first'], entry['first'] + entry['clusters']):
                    offset, amount, *bounds = struct.unpack_from('<II12f', binary, i * STRIDE)
                    self.assertEqual(offset, next_offset)
                    points = source[start:start+count][order[offset:offset+amount]]
                    for channel, low, high in [(points[:, :3], bounds[:3], bounds[3:6]),
                                               (points[:, 4:7], bounds[6:9], bounds[9:12])]:
                        self.assertTrue(np.all(channel >= low) and np.all(channel <= high))
                    next_offset += amount
                self.assertEqual(next_offset, count)
            self.assertEqual(build_bank(folder), result)
            (folder / 'library.bin').write_bytes(raw[:-1] + bytes([raw[-1] ^ 1]))
            with self.assertRaisesRegex(ValueError, 'source_identity'):
                build_bank(folder)

    def test_generated_projection_sources_are_current(self):
        for name, data in outputs().items():
            self.assertEqual((ROOT / name).read_text(), data, name)


if __name__ == '__main__':
    unittest.main()
