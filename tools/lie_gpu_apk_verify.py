"""Independent APK layout/hash/ELF verification, not a physical-device test."""
import hashlib,json,struct,sys,zipfile
from pathlib import Path
def verify(path):
    z=zipfile.ZipFile(path);assert z.testzip() is None
    root='assets/captures/liewall06/'
    cat=json.loads(z.read(root+'catalog.json'));proof=json.loads(z.read(root+'shadow-view.json'))
    bank=z.read(root+'library.bin');view=z.read(root+'shadow-view.bin')
    assert hashlib.sha256(bank).hexdigest()==cat['sha256']==proof['source_bank_sha256']
    assert len(view)==proof['bytes'] and hashlib.sha256(view).hexdigest()==proof['sha256']
    assert proof['stride']==32 and proof['original_stride']==80
    assert view==b''.join(bank[i:i+32] for i in range(0,len(bank),80))
    names=[n for n in z.namelist() if n.startswith('lib/arm64-v8a/') and n.endswith('liblie_gpu_probe.so')]
    assert len(names)==1,names
    raw=z.read(names[0]);assert raw[:6]==b'\x7fELF\x02\x01' and struct.unpack_from('<H',raw,18)[0]==183
    phoff=struct.unpack_from('<Q',raw,32)[0];entry_size,entry_count=struct.unpack_from('<HH',raw,54)
    load=[]
    for i in range(entry_count):
        offset=phoff+i*entry_size
        if struct.unpack_from('<I',raw,offset)[0]==1:load.append(struct.unpack_from('<Q',raw,offset+48)[0])
    assert load and min(load)>=16384,load
    for name in ['godot-cpp','libGPUCounters']:assert len(z.read('assets/addons/lie_gpu_probe/licenses/'+name+'.txt'))>1000
    assert 'assets/addons/lie_gpu_probe/lie_gpu_probe.gdextension' in z.namelist()
    result={'schema':'lie-gpu-apk-proof/1','apk_sha256':hashlib.sha256(Path(path).read_bytes()).hexdigest(),'apk_bytes':Path(path).stat().st_size,'native_library':names[0],'native_sha256':hashlib.sha256(raw).hexdigest(),'pt_load_alignment':load,'bank_sha256':cat['sha256'],'shadow_view':proof,'physical_android_tested':False}
    Path(path).with_suffix('.proof.json').write_text(json.dumps(result,indent=2)+'\n');return result
if __name__=='__main__':print(json.dumps(verify(sys.argv[1]),indent=2))
