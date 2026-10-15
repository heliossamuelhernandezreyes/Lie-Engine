"""Offline source geometry, correct sample ABI and provenance regression."""
from __future__ import annotations
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

import numpy as np
import trimesh

ROOT=Path(__file__).resolve().parents[1]
import sys
sys.path.insert(0,str(ROOT/"tools"))
def module(filename,alias):
    spec=importlib.util.spec_from_file_location(alias,ROOT/"tools"/filename)
    m=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m

capture=module("lie_brick02_capture_scan.py","brick02_capture")
fixture=module("lie_brick02_fixture.py","brick02_fixture")


class RealGeometryPipelineTest(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.root=Path(self.tmp.name)
        self.source,self.provenance=fixture.build(self.root/"source")
    def tearDown(self):
        self.tmp.cleanup()

    def test_direct_gltf_vertex_colors_preserve_source_data(self):
        colored=trimesh.creation.box(extents=(.2032,.053,.094))
        rgba=np.zeros((len(colored.vertices),4),dtype=np.uint8)
        rgba[:,0]=np.arange(len(rgba))*19+61
        rgba[:,1]=91
        rgba[:,2]=43
        rgba[:,3]=255
        colored.visual=trimesh.visual.ColorVisuals(vertex_colors=rgba)
        direct=self.root/"vertex_COLOR_0.glb"
        direct.write_bytes(colored.export(file_type="glb"))
        extracted=capture.load_source(direct)
        self.assertEqual(len(extracted),1)
        self.assertEqual(len(extracted[0].faces),12)
        self.assertIn("lie_vertex_colors_linear",extracted[0].metadata)
        read=np.asarray(extracted[0].metadata["lie_vertex_colors_linear"])
        self.assertEqual(read.shape,(len(colored.vertices),3))
        self.assertAlmostEqual(float(read[:,1].mean()),91./255.,places=5)
        provenance=json.loads(self.provenance.read_text())
        provenance["expected_sha256"]=hashlib.sha256(direct.read_bytes()).hexdigest()
        self.provenance.write_text(json.dumps(provenance))
        result=capture.capture(direct,self.provenance,self.root/"vertex_bank",
                               counts=(500,200,100))
        self.assertTrue(result["source_vertex_colors_used"])
        self.assertFalse(result["source_photo_texture_uv_used"])
        self.assertEqual(result["sample_count"],800)

    def test_common_compiler_uses_authored_frame_for_another_master(self):
        profile={'master':'curved_test_piece','source_to_lie':[[0,0,1],[0,1,0],[-1,0,0]],'meters_per_source_unit':2.,'source_pivot':[0,0,0],'material_zone':5,'optical_material':{'metallic':0.,'transmission':0.,'ior':1.5,'roughness_origin':'source_factor'}}
        result=capture.capture(self.source,self.provenance,self.root/'generic',counts=(600,200,100),asset_profile=profile)
        self.assertIn('curved_test_piece',result['masters']);self.assertTrue(result['asset_frame']['semantic_frame_verified'])
        data=np.fromfile(self.root/'generic/library.bin',dtype='<f4').reshape(-1,20);self.assertTrue((data[:,8]==5).all())
        self.assertGreater(result['source_bbox_m'][2],.4)
        self.assertTrue((self.root/'generic/asset-contract.json').is_file())

    def test_external_gltf_normal_map_and_obj_do_not_silently_fall_back(self):
        profile={'master':'piece','source_to_lie':np.eye(3).tolist(),'meters_per_source_unit':1,'source_pivot':[0,0,0],'material_zone':5,'optical_material':{'metallic':0.,'transmission':0.,'ior':1.5,'roughness_origin':'source_factor'}}
        unsupported=self.root/'unsupported.gltf';unsupported.write_text(json.dumps({'asset':{'version':'2.0'},'materials':[{'pbrMetallicRoughness':{'metallicFactor':0},'normalTexture':{'index':0}}]}))
        identity=json.loads(self.provenance.read_text());identity['expected_sha256']=hashlib.sha256(unsupported.read_bytes()).hexdigest();self.provenance.write_text(json.dumps(identity))
        with self.assertRaisesRegex(ValueError,'requires_another_capture_backend'):capture.capture(unsupported,self.provenance,self.root/'refused',counts=(200,100,100),asset_profile=profile)
        unsupported=self.root/'unsupported.obj';unsupported.write_text('# unsupported material fixture')
        identity['expected_sha256']=hashlib.sha256(unsupported.read_bytes()).hexdigest();self.provenance.write_text(json.dumps(identity))
        with self.assertRaisesRegex(ValueError,'requires_declared_material_override'):capture.capture(unsupported,self.provenance,self.root/'refused',counts=(200,100,100),asset_profile=profile)

    def test_source_fixture_has_texture_and_real_triangles(self):
        meshes=capture.load_source(self.source)
        self.assertGreater(len(meshes[0].faces),500)
        self.assertGreater(np.ptp(meshes[0].vertices,axis=0).min(), .04)
        self.assertEqual(meshes[0].visual.kind,"texture")

    def test_three_lod_samples_one_box_and_provenance(self):
        catalog=capture.capture(self.source,self.provenance,self.root/"first",
                                length_m=.2032,counts=(1000,300,120),seed=73)
        path=self.root/"first"/"library.bin"
        raw=path.read_bytes()
        self.assertEqual(len(raw),1420*80)
        self.assertEqual(hashlib.sha256(raw).hexdigest(),catalog["sha256"])
        self.assertEqual(catalog["source_sha256"],hashlib.sha256(self.source.read_bytes()).hexdigest())
        self.assertTrue(catalog["expected_source_sha_verified"])
        self.assertFalse(catalog["source_mesh_drawn"])
        self.assertFalse(catalog["hero_quality_accepted"])
        self.assertFalse(catalog["photo_reference_ab_test_passed"])
        self.assertEqual(catalog["collision_proxy_count_per_active_brick"],1)
        self.assertEqual([x["count"] for x in catalog["masters"]["brick_full"]["levels"]],[1000,300,120])
        bank=np.frombuffer(raw,dtype="<f4").reshape(-1,20)
        self.assertTrue(np.isfinite(bank).all())
        self.assertEqual(len(bank),1420)
        self.assertGreater(np.std(bank[:,0]),.02)
        self.assertGreater(np.std(bank[:,12]),.002)
        self.assertLess(float(np.max(np.abs(bank[:,:3]))),.105)
        self.assertTrue(np.all(bank[:,3]>.0))
        self.assertGreater(float(np.mean(bank[:,10])), .3)
        self.assertEqual(catalog["masters"]["brick_full"]["bounds_size"],catalog["envelope_size_m"])
        self.assertGreater(catalog["envelope_size_m"][0],.2032)
        second=capture.capture(self.source,self.provenance,self.root/"repeat",
                               length_m=.2032,counts=(1000,300,120),seed=73)
        self.assertEqual(second["sha256"],catalog["sha256"])

    def test_provenance_hash_mismatch_fails_closed(self):
        data=json.loads(self.provenance.read_text())
        data["expected_sha256"]="0"*64
        self.provenance.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError,"SHA-256"):
            capture.capture(self.source,self.provenance,self.root/"rejected",
                            counts=(200,200,200))

    def test_reject_untextured_geometry(self):
        bad=self.root/"untextured.glb"
        bad.write_bytes(trimesh.creation.box(extents=(.2,.05,.1)).export(file_type="glb"))
        with self.assertRaisesRegex(ValueError,"texture"):
            capture.load_source(bad)

    def test_reject_flat_mesh(self):
        flat=trimesh.creation.box(extents=(.2,.0001,.1))
        with self.assertRaisesRegex(ValueError,"flat"):
            capture.frame_for_brick([flat],.2032)

    def test_size_and_sample_budget_checks(self):
        with self.assertRaises(ValueError):
            capture.frame_for_brick(capture.load_source(self.source),0)
        with self.assertRaisesRegex(ValueError,"LOD"):
            capture.capture(self.source,self.provenance,self.root/"bad",counts=(749900,100,100))


if __name__=="__main__":
    unittest.main()
