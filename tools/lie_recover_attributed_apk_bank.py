"""Recover the EXACT attributed LIE 2.5 wall packets from its verified APK.

Does not reconstruct or fabricate geometry. The source is the public, verified
GitHub Actions APK. Recover at runtime for testing; NEVER commit binary assets.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import zipfile

ASSET_PREFIX='assets/captures/liewall06/'
EXPECTED={
 'library.bin':'ca667dfc0e5f5de19190ef12c24395a99b2be66a418420bf30e61ba9ef253340',
 'direct/depth.bin':'8e75f4e8db9700bf71b210dc0af89be09f6b8f83e2e983eb20177d404ca90200',
 'direct/normal.bin':'5790182c867ee788f2ae6725a21fe0df53b579f534a87a77875bd14a830afdcc',
 'direct/color.bin':'5614ec705a17165d643e9024aba7d2dce6a649c1b176100b7e022a28b434a0ba',
}


def recover(apk: Path,out: Path,expected=EXPECTED):
    if not apk.is_file():raise FileNotFoundError(apk)
    out.mkdir(parents=True,exist_ok=True)
    files={}
    with zipfile.ZipFile(apk) as z:
        for member in z.infolist():
            name=member.filename
            if not name.startswith(ASSET_PREFIX) or member.is_dir():continue
            suffix=name[len(ASSET_PREFIX):]
            parts=PurePosixPath(suffix)
            if not suffix or '..' in parts.parts or parts.is_absolute():
                raise ValueError('Unsafe archive path '+repr(suffix))
            path=out.joinpath(*parts.parts)
            path.parent.mkdir(parents=True,exist_ok=True)
            size=0
            h=hashlib.sha256()
            with z.open(member) as source,path.open('wb') as target:
                while True:
                    chunk=source.read(1<<20)
                    if not chunk:break
                    size+=len(chunk);h.update(chunk);target.write(chunk)
            files[suffix]={'bytes':size,'sha256':h.hexdigest()}
    for key,sha in expected.items():
        if key not in files or files[key]['sha256']!=sha:
            raise ValueError('Original attributed APK bank checksum mismatch: '+key)
    return {'schema':'lie-attributed-apk-recovery/1','apk_sha256':hashlib.file_digest(apk.open('rb'),'sha256').hexdigest(),
        'source_type':'recovered original mobile APK packets, not original Blender source mesh',
        'paths':files,'file_count':len(files),'destination':str(out),
        'limits':'Packet identity alone does not establish correspondence to original scanned mesh, or certify Vulkan rendering'}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--apk',type=Path,required=True)
    p.add_argument('--out',type=Path,required=True)
    p.add_argument('--report',type=Path,required=True)
    args=p.parse_args()
    result=recover(args.apk,args.out)
    args.report.parent.mkdir(parents=True,exist_ok=True)
    args.report.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps({'apk_sha256':result['apk_sha256'],'files':result['file_count'],
        'library_sha256':result['paths']['library.bin']['sha256'],
        'original_blender_mesh_available':False},indent=2))


if __name__=='__main__':main()
