"""Apply the derived v6 overlay only to its exact immutable v5 data dependency."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def safe_path(root, name):
    relative = Path(name)
    if relative.is_absolute() or '..' in relative.parts:
        raise ValueError('invalid_relative_path')
    result = root / relative
    if not result.resolve().is_relative_to(root.resolve()):
        raise ValueError('path_escape')
    return result


def apply(overlay, scene):
    requirements = json.loads((overlay / 'requirements.json').read_text())
    if requirements['schema'] != 'lie-construction-field-overlay/1':
        raise ValueError('overlay_schema')
    manifest = json.loads((scene / 'manifest.json').read_text())
    if manifest['scene_identity'] != requirements['scene_identity']:
        raise ValueError('base_scene_identity')
    for name, expected in requirements['base_files_sha256'].items():
        if digest(safe_path(scene, name)) != expected:
            raise ValueError('base_file_sha256:' + name)
    copies = []
    for name, expected in requirements['overlay_files_sha256'].items():
        source = safe_path(overlay / 'scene-overlay', name)
        target = safe_path(scene, name)
        if digest(source) != expected:
            raise ValueError('overlay_file_sha256:' + name)
        if target.exists():
            if not target.is_file() or digest(target) != expected:
                raise ValueError('target_overlay_conflict:' + name)
        else:
            copies.append((source, target))
    # Validate all immutable inputs and conflicts before the first write.
    for source, target in copies:
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
    print(json.dumps({'scene_identity': manifest['scene_identity'], 'copied': len(copies),
                      'validated': len(requirements['overlay_files_sha256']),
                      'source_captures_modified': False}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scene', type=Path, required=True)
    parser.add_argument('--overlay', type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    apply(args.overlay, args.scene)
