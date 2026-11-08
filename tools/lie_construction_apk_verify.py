"""Verify APK identity, complete immutable assets, native ELF and entry scene."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import zipfile

def verify(path,badging):
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None
        names=archive.namelist()
        proof=json.loads(archive.read('assets/build-source.json'))
        assert proof['package']=='org.lieengine.construction.v630' and proof['version']=='6.3.0-hierarchical-camera'
        for name,expected in proof['source_files_sha256'].items():
            with archive.open('assets/'+name) as stream:
                assert hashlib.file_digest(stream,'sha256').hexdigest()==expected,name
        assert b'lie_construction_proxy_lab.tscn' in archive.read('assets/project.binary')
        binaries=[name for name in names if name.startswith('lib/') and name.endswith('.so')]
        assert binaries and all(name.startswith('lib/arm64-v8a/') for name in binaries)
        assert any(name.endswith('/liblie_gpu_probe.so') for name in binaries)
        elf=[]
        for name in binaries:
            raw=archive.read(name)
            assert raw[:6]==b'\x7fELF\x02\x01' and struct.unpack_from('<H',raw,18)[0]==183,name
            phoff=struct.unpack_from('<Q',raw,32)[0];size,count=struct.unpack_from('<HH',raw,54);alignments=[]
            for index in range(count):
                at=phoff+index*size
                if struct.unpack_from('<I',raw,at)[0]==1:alignments.append(struct.unpack_from('<Q',raw,at+48)[0])
            assert alignments and min(alignments)>=16384,(name,alignments)
            elf.append({'file':name,'sha256':hashlib.sha256(raw).hexdigest(),'pt_load_alignment':alignments})
        for dep in ['godot-cpp','libGPUCounters']:assert len(archive.read('assets/addons/lie_gpu_probe/licenses/'+dep+'.txt'))>1000
        credits=archive.read('assets/ATTRIBUTION.txt')
        assert b'Centre-of-Archaeology' in credits and b'Poly Haven' in credits and b'Godot' in credits
    text=badging.read_text()
    assert "name='org.lieengine.construction.v630'" in text and "versionName='6.3.0-hierarchical-camera'" in text
    permissions=re.findall(r"uses-permission(?:-sdk-23)?: name='([^']+)'",text)
    assert not any(name in permissions for name in ['android.permission.INTERNET','android.permission.READ_EXTERNAL_STORAGE','android.permission.WRITE_EXTERNAL_STORAGE']),permissions
    with path.open('rb') as stream:checksum=hashlib.file_digest(stream,'sha256').hexdigest()
    result={'schema':'lie-construction-apk-proof/1','filename':path.name,'apk_bytes':path.stat().st_size,'apk_sha256':checksum,
            'package':proof['package'],'version':proof['version'],'code_commit':proof['code_commit'],
            'verified_capture_and_metadata_files':len(proof['source_files_sha256']),'scene_identity':proof['scene_identity'],
            'bank_bindings':proof['immutable_v5_capture_bank_bindings'],'native_libraries':elf,'permissions':permissions,
            'source_resampling':False,'physical_android_tested':False}
    path.with_suffix('.proof.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result));return result
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--apk',type=Path,required=True);p.add_argument('--badging',type=Path,required=True);a=p.parse_args();verify(a.apk,a.badging)
