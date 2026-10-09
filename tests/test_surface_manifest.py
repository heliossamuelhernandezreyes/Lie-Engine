from pathlib import Path
import json
import sys
import tempfile
import unittest
import hashlib
import struct
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from validate_lie_surface import validate


def tiny_rgba_png(bit_depth: int):
    # 1x1 rgba at 8 or 16 bits, no alpha interpolation.
    raw = b"\x00" + bytes([10, 20, 30, 255] if bit_depth == 8
        else [0, 10, 0, 20, 0, 30, 255, 255])
    def chunk(t, p):
        return struct.pack(">I", len(p)) + t + p + struct.pack(">I", zlib.crc32(t + p) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, bit_depth, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


class SurfaceManifestTests(unittest.TestCase):
    def create_fixture(self, path):
        views = []
        for az in range(4):
            key = f"az_{az:02d}_el_00"
            channels = {}
            digests = {}
            for ch in ("albedo", "normal", "depth"):
                n = f"{key}.{ch}.png"
                data = tiny_rgba_png(8 if ch == "albedo" else 16)
                (path / n).write_bytes(data)
                channels[ch] = n
                digests[ch] = hashlib.sha256(data).hexdigest()
            views.append({"code": key, "azimuth_index": az, "elevation_index": 0,
                          "channels": channels, "sha256": digests})
        manifest = {"schema_version": 2, "projection": "orthographic",
                    "linear_depth_meters": {"near": 1, "far": 8},
                    "resolution": [1, 1], "azimuth_steps": 4,
                    "elevation_degrees": [0], "views": views}
        (path / "manifest.json").write_text(json.dumps(manifest))
        return manifest

    def test_complete_bundle(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            self.create_fixture(root)
            self.assertEqual(validate(root), 12)

    def test_bad_digest_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            m = self.create_fixture(root)
            m["views"][0]["sha256"]["depth"] = "0" * 64
            (root / "manifest.json").write_text(json.dumps(m))
            with self.assertRaisesRegex(ValueError, "checksum"):
                validate(root)

    def test_missing_view_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            m = self.create_fixture(root)
            m["views"].pop()
            (root / "manifest.json").write_text(json.dumps(m))
            with self.assertRaisesRegex(ValueError, "incomplete"):
                validate(root)


if __name__ == "__main__":
    unittest.main()
