"""Restore only the SHA-pinned accepted v6 scene from its Actions artifact."""
import argparse
import hashlib
from pathlib import Path
import zipfile

EXPECTED='2b1ddcb8bdf1aa59482f92418792cefae349797847216b1e2a60c3de498738e0'
def restore(archive,output):
    with archive.open('rb') as stream:
        if hashlib.file_digest(stream,'sha256').hexdigest()!=EXPECTED:raise ValueError('accepted_v6_zip_sha256')
    if output.exists():raise ValueError('fresh_input_directory_required')
    with zipfile.ZipFile(archive) as source:
        for name in source.namelist():
            path=Path(name)
            if path.is_absolute() or '..' in path.parts:raise ValueError('artifact_path_escape')
        for name in source.namelist():
            if name.startswith('tmp/hq/scene/') and not name.endswith('/'):
                target=output/Path(name).relative_to('tmp/hq/scene');target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(source.read(name))
    if not (output/'manifest.json').is_file():raise ValueError('accepted_scene_missing')
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--archive',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();restore(a.archive,a.output)
