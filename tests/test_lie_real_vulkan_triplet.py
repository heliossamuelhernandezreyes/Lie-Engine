"""CPU integration tests only; fabricated fixtures never count as GPU measurements."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

import numpy as np

module_path=Path(__file__).resolve().parents[1]/'tools'/'lie_real_vulkan_triplet.py'
spec=importlib.util.spec_from_file_location('lie_real_vulkan_triplet',module_path)
triplet=importlib.util.module_from_spec(spec)
spec.loader.exec_module(triplet)
blend_path=Path(__file__).resolve().parents[1]/'tools'/'lie_blender_original_raycast.py'
blend_spec=importlib.util.spec_from_file_location('lie_blender_original_raycast',blend_path)
blend=importlib.util.module_from_spec(blend_spec)
blend_spec.loader.exec_module(blend)


class RealVulkanBridgeTests(unittest.TestCase):
    def test_selects_all_readback_disagreements(self):
        a=np.array([[0,0,0,1],[0,0,0,1],[0,0,0,0],[0,0,0,2]],dtype='<f4')
        b=np.array([[0,0,0,1],[0,0,0,0],[0,0,0,0],[0,0,0,3]],dtype='<f4')
        ids=triplet.choose_pixels(a,b,max_valid=0,max_empty=0)
        np.testing.assert_array_equal(ids,[1,3])

    def test_no_source_is_not_presented_as_blender(self):
        rep={'hit':[True,False],'depth_m':[2.,None],'owner_id':[1,None]}
        gpu={'hit':[True,False],'depth_m':[2.,None],'owner_id':[1,None]}
        r=triplet.assess_layers(rep,gpu)
        self.assertIn('NOT PROVIDED',r['source_status'])
        self.assertNotIn('source_to_representation',r)

    def test_source_can_disagree_with_both_capture_and_gpu(self):
        source={'hit':[True],'depth_m':[1.],'owner_id':[2]}
        rep={'hit':[True],'depth_m':[2.],'owner_id':[1]}
        gpu={'hit':[True],'depth_m':[2.],'owner_id':[1]}
        r=triplet.assess_layers(rep,gpu,source)
        self.assertEqual(r['attribution_sample_counts']['source_only'],1)
        self.assertEqual(r['source_to_representation']['owner_mismatches'],1)
        self.assertEqual(r['representation_to_vulkan']['depth_over_tolerance'],0)

    def test_manifest_requires_matching_camera_packet(self):
        with tempfile.TemporaryDirectory() as td:
            p=Path(td)/'raycast.npz'
            meta={'kind':'independent-original-mesh-raycast',
                  'view_packet_sha256':'0'*64,'source_mesh_sha256':'a'*64,
                  'owner_namespace':'lie-native-wall-owner-v1','owner_mapping_sha256':'b'*64}
            np.savez(p,pixel_ids=np.array([0]),distance_m=np.array([2.]),
                     owner_id=np.array([1]),manifest=json.dumps(meta))
            with self.assertRaisesRegex(ValueError,'camera packets differ'):
                triplet.load_source(p,np.array([0]),'b'*64)

    def test_source_must_have_exact_selected_indices(self):
        with tempfile.TemporaryDirectory() as td:
            p=Path(td)/'raycast.npz'
            meta={'kind':'independent-original-mesh-raycast',
                  'view_packet_sha256':'0'*64,'source_mesh_sha256':'a'*64,
                  'owner_namespace':'lie-native-wall-owner-v1','owner_mapping_sha256':'b'*64}
            np.savez(p,pixel_ids=np.array([0,3]),distance_m=np.array([2.,2.]),
                     owner_id=np.array([1,1]),manifest=json.dumps(meta))
            with self.assertRaisesRegex(ValueError,'pixel IDs'):
                triplet.load_source(p,np.array([0,1]),'0'*64)

    def test_adapter_reads_real_binary_layout_using_synthetic_fixture(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);exp=root/'experiment'/'tools';exp.mkdir(parents=True)
            (exp/'lie_native_oracle.py').write_text(
                'import numpy as np\n'
                'def trace(eye, dirs, proxies):\n'
                ' n=len(dirs)\n'
                ' return np.full(n,2.),np.ones(n),np.full(n,np.inf),np.zeros(n)\n')
            bank=root/'bank'/'direct';bank.mkdir(parents=True)
            (bank/'surface.json').write_text(json.dumps({'height':2,'width':2}))
            np.zeros((2,2,4),dtype='<f4').tofile(bank/'depth.bin')
            np.zeros((4,2,2,4),dtype='<f2').tofile(bank/'normal.bin')
            cap=root/'native';cap.mkdir()
            native=np.tile(np.array([0,0,2,1],dtype='<f4'),(4,1))
            regions=native.copy();regions[1,3]=0
            native.tofile(cap/'0-native-world.bin')
            regions.tofile(cap/'0-regions-world.bin')
            np.zeros((97,48),dtype='<f4').tofile(cap/'0-native-proxies.bin')
            view=np.zeros(20,dtype='<f4');view[14]=1
            view.tofile(cap/'0-native-views.bin')
            result=triplet.analyze(cap,root/'bank',root/'experiment',all_pixels=True)
            self.assertEqual(result['samples'],4)
            self.assertEqual(result['selected_pixel_ids'],[0,1,2,3])
            self.assertEqual(result['summary']['representation_to_vulkan']['missing'],0)
            self.assertEqual(result['summary']['representation_to_vulkan']['owner_mismatches'],0)
            self.assertEqual(result['summary']['regions_to_vulkan']['extra'],1)
            self.assertEqual(result['disagreement_pixels'],[])
            self.assertIn('NOT PROVIDED',result['summary']['source_status'])


    def test_valid_original_source_packet(self):
        with tempfile.TemporaryDirectory() as td:
            p=Path(td)/'raycast.npz'
            meta={'kind':'independent-original-mesh-raycast','view_packet_sha256':'0'*64,
                  'source_mesh_sha256':'a'*64,'owner_namespace':'lie-native-wall-owner-v1',
                  'owner_mapping_sha256':'b'*64}
            np.savez(p,pixel_ids=np.array([3,0]),distance_m=np.array([2.,1.]),
                     owner_id=np.array([4,1]),manifest=json.dumps(meta))
            layer,manifest=triplet.load_source(p,np.array([0,3]),'0'*64)
            self.assertEqual(layer['depth_m'],[1.,2.])
            self.assertEqual(layer['owner_id'],[1,4])
            self.assertEqual(manifest['source_mesh_sha256'],'a'*64)

    def test_source_mapping_is_mandatory(self):
        with tempfile.TemporaryDirectory() as td:
            p=Path(td)/'raycast.npz'
            meta={'kind':'independent-original-mesh-raycast','view_packet_sha256':'0'*64,
                  'source_mesh_sha256':'a'*64}
            np.savez(p,pixel_ids=np.array([0]),distance_m=np.array([2.]),
                     owner_id=np.array([1]),manifest=json.dumps(meta))
            with self.assertRaisesRegex(ValueError,'owner mapping'):
                triplet.load_source(p,np.array([0]),'0'*64)


    def test_blender_rays_are_native_camera_rays(self):
        with tempfile.TemporaryDirectory() as td:
            cap=Path(td)
            view=np.zeros(20,dtype='<f4')
            view[14]=1.
            view[4]=1.
            view[9]=1.
            view[18]=1.
            view.tofile(cap/'0-native-views.bin')
            eye,dirs,view_path=blend.camera(cap,0,np.array([0]),2)
            np.testing.assert_allclose(eye,[0.,0.,0.])
            expected=np.array([-.5,.5,1.])
            expected/=np.linalg.norm(expected)
            np.testing.assert_allclose(dirs[0],expected)
            self.assertEqual(view_path.name,'0-native-views.bin')

    def test_blender_transform_must_be_invertible(self):
        with tempfile.TemporaryDirectory() as td:
            mat=Path(td)/'matrix.json'
            mat.write_text(json.dumps({'runtime_to_blender':np.eye(4).tolist()}))
            np.testing.assert_array_equal(blend.matrix_from_file(mat),np.eye(4))
            mat.write_text(json.dumps({'runtime_to_blender':np.zeros((4,4)).tolist()}))
            with self.assertRaises(ValueError):
                blend.matrix_from_file(mat)

    def test_mismatched_readback_dimensions_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            p=Path(td)/'bad.bin'
            np.zeros(7,dtype='<f4').tofile(p)
            with self.assertRaisesRegex(ValueError,'multiple of 4'):
                triplet.load_world(p)

if __name__=='__main__':unittest.main()
