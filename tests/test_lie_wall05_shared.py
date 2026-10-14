import hashlib,json,sys,tempfile,unittest
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from lie_wall05_shared import build
from lie_wall02_bake import transform_real_samples

class SharedWall(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.tmp=tempfile.TemporaryDirectory();cls.dest=Path(cls.tmp.name);cls.cat=build(cls.dest)
  cls.raw=np.fromfile(cls.dest/'library.bin',dtype='<f4').reshape(-1,20)
  cls.refs=np.fromfile(cls.dest/'sample-refs.bin',dtype='<u4')
  cls.old=np.fromfile(ROOT/'gpu_compute/captures/liewall04/library.bin',dtype='<f4').reshape(-1,20)
  cls.oldcat=json.loads((ROOT/'gpu_compute/captures/liewall04/catalog.json').read_text())
 @classmethod
 def tearDownClass(cls):cls.tmp.cleanup()
 def test_original_master_and_photo_mortar(self):
  original=(ROOT/'gpu_compute/captures/liebrick02/library.bin').read_bytes()
  self.assertEqual((self.dest/'library.bin').read_bytes()[:len(original)],original)
  self.assertEqual(len(self.raw)*80,self.cat['bytes']);self.assertLess(self.cat['bytes']+self.refs.nbytes,len(self.old)*80)
  for lod,jobs in enumerate(self.cat['wall05']['instance_jobs']):
   start,count,_,_=jobs[-1];actual=self.raw[self.refs[start:start+count]]
   level=self.oldcat['masters']['real_scan_wall']['levels'][lod];old=self.old[level['start']:level['start']+level['count']];old=old[old[:,9]>=864]
   self.assertEqual(actual.tobytes(),old.tobytes())
 def test_every_virtual_brick_matches_locked_baseline(self):
  for lod,jobs in enumerate(self.cat['wall05']['instance_jobs']):
   old_start=self.oldcat['masters']['real_scan_wall']['levels'][lod]['start']
   for i,(start,count,_,_) in enumerate(jobs[:-1]):
    pose=self.cat['wall05']['poses'][i]
    virtual=transform_real_samples(self.raw[self.refs[start:start+count]],pose['center'],pose['yaw_rad'],pose['tone'],pose['node_start'],self.cat['wall05']['brick_radius_by_lod'][lod])
    original=self.old[old_start+i*count:old_start+(i+1)*count]
    self.assertEqual(virtual.tobytes(),original.tobytes(),(lod,i))
 def test_ids_and_lod_ownership(self):
  self.assertLess(int(self.refs.max()),len(self.raw))
  for jobs in self.cat['wall05']['instance_jobs']:
   self.assertEqual(len(jobs),97);self.assertEqual([j[2] for j in jobs],list(range(97)))
   self.assertEqual(jobs[-1][3]+jobs[-1][1],sum(j[1] for j in jobs))
  for name in ('sample-refs.bin','optics.bin','shadow-caps.bin','outgoing-csr.bin'):
   data=(self.dest/name).read_bytes();meta=self.cat['wall05'].get(name,{})
   self.assertEqual(hashlib.sha256(data).hexdigest(),meta.get('sha256',self.cat['wall05']['reference_sha256']))
 def test_passive_graph_capture_and_shadow_plane(self):
  packet=np.fromfile(self.dest/'outgoing-csr.bin',dtype='<u4');offset=packet[2];edge=packet[3]
  for src in range(872):
   values=[packet[edge+int(i)*2+1:edge+int(i)*2+2].view('<f4')[0] for i in range(packet[offset+src],packet[offset+src+1])]
   self.assertLessEqual(sum(values),1.00001)
  opt=np.fromfile(self.dest/'optics.bin',dtype='<f4')[4:].reshape(872,16)
  self.assertTrue(np.isfinite(opt).all());self.assertTrue((opt[:,:3]>=0).all());self.assertTrue((opt[:,:3]<=1).all())
  self.assertTrue((opt[:,4:6]==0).all());self.assertTrue((opt[:,6]==1.5).all())
  self.assertLess(np.max(np.abs(np.linalg.norm(opt[:,12:15],axis=1)-1)),1e-6)
  n=self.cat['wall05']['shadow_front_plane']['normal'];self.assertGreater(n[2],.9);self.assertAlmostEqual(np.linalg.norm(n),1)
if __name__=='__main__':unittest.main()
