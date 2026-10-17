import hashlib,json,struct,sys,tempfile,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from lie_runtime_android_build import verify_android_extensions

class AndroidExtensionInputs(unittest.TestCase):
    def test_missing_empty_wrong_architecture_and_wrong_hash_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);(root/'probe.gdextension').write_text('[libraries]\nandroid.arm64 = "res://probe.so"\n')
            with self.assertRaisesRegex(ValueError,'Missing'):verify_android_extensions(root)
            p=root/'probe.so';p.write_bytes(b'')
            with self.assertRaisesRegex(ValueError,'Invalid'):verify_android_extensions(root)
            raw=bytearray(64);raw[:6]=b'\x7fELF\x02\x01';struct.pack_into('<H',raw,18,62);p.write_bytes(raw)
            with self.assertRaisesRegex(ValueError,'Invalid'):verify_android_extensions(root)
            struct.pack_into('<H',raw,18,183);p.write_bytes(raw)
            proof=root/'build.json';proof.write_text(json.dumps({'library_sha256':'wrong'}))
            with self.assertRaisesRegex(ValueError,'hash mismatch'):verify_android_extensions(root)
            proof.write_text(json.dumps({'library_sha256':hashlib.sha256(raw).hexdigest()}));verify_android_extensions(root)

    def test_legacy_project_without_extension_is_unchanged(self):
        with tempfile.TemporaryDirectory() as temp:verify_android_extensions(Path(temp))

if __name__=='__main__':unittest.main()
