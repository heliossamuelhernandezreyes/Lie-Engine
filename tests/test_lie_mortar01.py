"""Isolated LIE-MORTAR-01 checks. Synthetic fixtures are tests, NEVER source assets."""
from __future__ import annotations
import hashlib,json,sys,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
import lie_mortar01_acquire as acquisition
import lie_mortar01_extract as extraction

class Mortar01Tests(unittest.TestCase):
    def test_source_provenance_and_api_resolver(self):
        manifest=json.loads((ROOT/"assets/material_masters/mortar/hero/real_masonry_joint/material_manifest.json").read_text())
        self.assertEqual(manifest["provenance"]["license"],"CC0-1.0")
        self.assertEqual(manifest["provenance"]["asset_id"],"brick_wall_13")
        self.assertFalse(manifest["physical_scale"]["height_scale_absolute_verified"])
        data={name:{"8k":{"png":{"url":"https://dl.polyhaven.org/file/source.png"}}}
              for name in ("Diffuse","nor_gl","Displacement","Rough")}
        result=acquisition.resolve(manifest,"8k",data)
        self.assertEqual(set(result),set(acquisition.REQUIRED))
        data["AO"]={"8k":{"png":{"url":"http://evil.example/incorrect.png"}}}
        with self.assertRaises(ValueError): acquisition.resolve(manifest,"8k",data)

    def test_uniform_source_cannot_be_certified(self):
        with self.assertRaises(extraction.UncertainSegmentation):
            extraction._normalized_height(np.ones((256,512),dtype=np.float32))
        with self.assertRaises(extraction.UncertainSegmentation):
            extraction.detect(np.ones((256,512),dtype=np.float32))

    def test_staggered_trough_detector_fixture(self):
        H,W=400,800
        y,x=np.mgrid[:H,:W]
        clay=np.zeros((H,W),dtype=bool)
        for row in range(8):
            clay|=(np.abs(y-(row*50+25))<19)&(((x+row%2*49)%100)<90)
        height=np.where(clay,220.,25.).astype(np.float32)
        height+=2*np.sin(x*.12)*np.sin(y*.17)
        result=extraction.detect(extraction._normalized_height(height),min_row_spacing=20)
        self.assertGreaterEqual(len(result["rows"]),2)
        self.assertGreaterEqual(result["vertical_count"],2)
        self.assertLess(result["coverage_fraction"],.2)

    def test_sha_lock_rejects_corruption(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            (root/"source").mkdir()
            manifest=json.loads((ROOT/"assets/material_masters/mortar/hero/real_masonry_joint/material_manifest.json").read_text())
            (root/"material_manifest.json").write_text(json.dumps(manifest))
            files={}
            for name in acquisition.REQUIRED:
                filename=name+".png";path=root/"source"/filename
                Image.new("RGB",(512,512),(31,51,71)).save(path)
                files[name]={"filename":filename,"bytes":path.stat().st_size,
                    "sha256":hashlib.sha256(path.read_bytes()).hexdigest(),
                    "image":{"width":512,"height":512,"mode":"RGB"}}
            lock={"schema":"lie-source-lock/1.0","material_id":manifest["id"],
                  "license":"CC0-1.0","source_page":manifest["provenance"]["page"],
                  "resolution":"8k","files":files}
            (root/"source/source-lock.json").write_text(json.dumps(lock))
            self.assertEqual(acquisition.inspect_lock(root),lock)
            with (root/"source/height.png").open("ab") as f: f.write(b"corrupt")
            with self.assertRaises(ValueError): acquisition.inspect_lock(root)

if __name__=="__main__":unittest.main()
