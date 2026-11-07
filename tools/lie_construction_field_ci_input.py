"""Verify and restore the accepted v5 Actions artifact, without recapturing."""
import argparse,hashlib,json,zipfile,shutil
from pathlib import Path
EXPECTED='01532bc9c2a286e34b6b5880846a5154a7cee26be3c8fdfde0152a891fd9f135'
def restore(archive,output):
    with archive.open('rb') as f:actual=hashlib.file_digest(f,'sha256').hexdigest()
    if actual!=EXPECTED:raise ValueError('pinned_v5_artifact_zip_sha256')
    unpack=output.parent/'v5-artifact'
    with zipfile.ZipFile(archive) as z:
        for name in z.namelist():
            p=Path(name)
            if p.is_absolute() or '..' in p.parts:raise ValueError('artifact_path_escape')
        z.extractall(unpack)
    found=[]
    for path in unpack.rglob('manifest.json'):
        try:d=json.loads(path.read_text())
        except (ValueError,UnicodeError):continue
        if d.get('schema')=='lie-hq-construction/1':found.append(path)
    if len(found)!=1:raise ValueError('v5_scene_manifest_count')
    source=found[0].parent;output.mkdir(parents=True);shutil.copytree(source/'banks',output/'banks')
    for path in source.glob('*.json'):shutil.copy2(path,output/path.name)
    manifest=json.loads((output/'manifest.json').read_text())
    for bank in manifest['banks']:
        folder=output/'banks'/bank;c=json.loads((folder/'catalog.json').read_text())
        for name,expected in [('library.bin',c['sha256'])]+([(c['optical_normal_sidecar']['file'],c['optical_normal_sidecar']['sha256'])] if c.get('optical_normal_sidecar') else []):
            with (folder/name).open('rb') as f:assert hashlib.file_digest(f,'sha256').hexdigest()==expected
    print('RESTORED ACCEPTED V5',manifest['scene_identity'],flush=True)
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--archive',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();restore(a.archive,a.output)
