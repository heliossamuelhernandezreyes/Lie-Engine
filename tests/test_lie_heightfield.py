import hashlib,json,tempfile,unittest
from pathlib import Path
import numpy as np
from PIL import Image
from unittest.mock import patch
from lie_heightfield_source import sample_array,load_heightfield,sample_material,linear_albedo

class HeightfieldTests(unittest.TestCase):
    def test_uv_pixel_centres_and_wrap(self):
        a=np.arange(4,dtype=np.float32).reshape(2,2)
        np.testing.assert_array_equal(sample_array(a,np.array([[.25,.75],[.75,.25],[1.25,.75]])),[0,3,0])
    def source(self,p):
        maps={}
        for name in ('Diffuse','Rough','Displacement','nor_gl'):
            f=p/(name+'.exr');f.write_bytes(name.encode());maps[name]={'path':f.name,'sha256':hashlib.sha256(f.read_bytes()).hexdigest()}
        d={'schema':'lie-photographic-heightfield/1','normal_policy':'retain_original_not_consumed_by_80B','maps':maps,'provider_dimensions_m':[2,1],'uv_crop':[.25,.25,.75,.75],'grid_vertices_per_axis':3,'displacement_scale_m':.01,'displacement_midlevel':.5,'diffuse_encoding':'linear'}
        f=p/'test.heightfield.json';f.write_text(json.dumps(d));return f
    def test_geometry_and_photometric_channels_remain_separate(self):
        with tempfile.TemporaryDirectory() as td:
            source=self.source(Path(td))
            color=np.full((4,4,3),.123456,dtype=np.float32);rough=np.full((4,4),.765432,dtype=np.float32)
            with patch('lie_heightfield_source.read_map',side_effect=lambda p,k:color if k=='Diffuse' else rough if k=='Rough' else np.tile(np.linspace(0,1,4),(4,1))):mesh=load_heightfield(source)[0]
            self.assertEqual(len(mesh.faces),8);np.testing.assert_allclose(mesh.extents[:2],[1,.5]);self.assertTrue((mesh.face_normals[:,2]>0).all())
            rgb,r=sample_material(mesh,np.array([[.5,.5]]));np.testing.assert_allclose(rgb,.123456);np.testing.assert_allclose(r,.765432)
            self.assertNotIn('lie_vertex_colors_linear',mesh.metadata)
    def test_tampered_original_is_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            source=self.source(Path(td));(Path(td)/'Diffuse.exr').write_bytes(b'changed')
            with self.assertRaisesRegex(ValueError,'source_map_hash'):load_heightfield(source)
    def test_encoding_is_explicit_and_decoded_before_filtering(self):
        a=np.array([[[0.,.5,1.],[1.,.5,0.]]],dtype=np.float32)
        linear=linear_albedo(a,'srgb');np.testing.assert_allclose(linear[0,0],[0,.21404114,1],rtol=1e-6)
        self.assertAlmostEqual(float(sample_array(linear,np.array([[.5,.5]]))[0,0]),.5)
        with self.assertRaisesRegex(ValueError,'explicit_diffuse_encoding'):linear_albedo(a,None)
