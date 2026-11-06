"""Compile the shared CSR ABI and stage only this laboratory's resources."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import numpy as np
from lie_light_field import sources
from lie_brick_reference_shader import outputs
from lie_brick_reference_math import preview
from PIL import Image
ROOT = Path(__file__).resolve().parents[1]


def stage(fixture, destination):
    if destination.exists(): raise ValueError('Use a new isolated stage')
    manifest = json.loads((fixture/'manifest.json').read_text())
    for name, data in manifest['files'].items():
        p = fixture/name
        if not p.is_file() or p.stat().st_size != data['bytes'] or hashlib.sha256(p.read_bytes()).hexdigest() != data['sha256']:
            raise ValueError('Source/reference hash mismatch: '+name)
    destination.mkdir(parents=True); source = ROOT/'gpu_compute'
    for name,text in outputs().items():(ROOT/name).write_text(text)
    pending = ['lie_brick_reference_lab.tscn', 'test_lie_brick_reference.gd', 'test_lie26_rig.gd', 'workshop/test_lie_agent_session.gd']
    copied = set(); pattern = re.compile(r'(?:\bextends\s+|\b(?:preload|load)\s*\(\s*|\bpath\s*=\s*)"res://([^"]+)"')
    while pending:
        name = pending.pop()
        if name in copied: continue
        path = source/name; out = destination/name; out.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(path, out); copied.add(name)
        if path.suffix in ('.gd', '.tscn', '.tres'): pending.extend(pattern.findall(path.read_text()))
    data = destination/'captures/brick_reference'; shutil.copytree(fixture, data, ignore=shutil.ignore_patterns('*.blend','*.blend1','*.exr','*.png'))
    # Raw buffers and numeric references are read through FileAccess, not imported.
    (data/'.gdignore').write_text('')
    for case in manifest['cases']:
        model = json.loads((fixture/(case['name']+'-model.json')).read_text())
        packets = sources(model, np.load(fixture/(case['name']+'-factors.npy')))
        root = data/case['name']; root.mkdir()
        shutil.copyfile(fixture/(case['name']+'-model.json'), root/'light-model.json')
        shutil.copyfile(fixture/'catalog.json', root/'catalog.json')
        proof = {'schema': 'lie-light-field-sources/1', 'source_bank_sha256': manifest['bank_sha256'],
                 'source_light_sha256': hashlib.sha256((root/'light-model.json').read_bytes()).hexdigest(), 'sources': {}}
        for key, raw in packets.items():
            (root/(key+'.bin')).write_bytes(raw)
            proof['sources'][key] = {'file': key+'.bin', 'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()}
        (root/'light-field.json').write_text(json.dumps(proof, indent=2)+'\n')
        full=(np.load(fixture/(case['name']+'-cycles-full.npy'))+np.load(fixture/(case['name']+'-cycles-repeat.npy')))*.5
        direct=(np.load(fixture/(case['name']+'-cycles-direct.npy'))+np.load(fixture/(case['name']+'-cycles-direct-repeat.npy')))*.5
        for mode,radiance in [('total',full),('direct',direct),('indirect',full-direct)]:
            Image.fromarray(preview(radiance[:,:,:3])).save(root/('reference-'+mode+'.png'))
    (destination/'fixtures').mkdir(exist_ok=True)
    shutil.copyfile(source/'fixtures/lie26-rig.json', destination/'fixtures/lie26-rig.json')
    (destination/'project.godot').write_text('config_version=5\n[application]\nrun/main_scene="res://lie_brick_reference_lab.tscn"\n[rendering]\nrenderer/rendering_method="mobile"\n[display]\nwindow/size/viewport_width=1280\nwindow/size/viewport_height=620\n[editor]\nimport/use_multiple_threads=false\n')
    print(json.dumps({'destination': str(destination), 'resources': len(copied), 'cases': len(manifest['cases']), 'bank_sha256': manifest['bank_sha256']}))


if __name__ == '__main__':
    p = argparse.ArgumentParser(); p.add_argument('--fixture', type=Path, required=True); p.add_argument('--stage', type=Path, required=True); a = p.parse_args(); stage(a.fixture, a.stage)
