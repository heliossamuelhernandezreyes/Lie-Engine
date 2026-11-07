"""Package exact derived pages/fields and accepted CI evidence over immutable v5."""
import argparse
import hashlib
import json
import shutil
import zipfile
from pathlib import Path
from lie_construction_field_apply_overlay import digest

ROOT = Path(__file__).resolve().parents[1]
V5_SHA = '3a6d9b713a54f9561337fbbfce1d12c3f4a2b78f6731c062335c22f0b4f828f0'


def build(evidence, v5_archive, reports, output):
    scene = evidence / 'tmp/hq/scene'
    manifest = json.loads((scene / 'manifest.json').read_text())
    if digest(v5_archive) != V5_SHA:
        raise ValueError('immutable_v5_zip_sha256')
    if output.exists():
        raise ValueError('use_fresh_package_directory')
    originals, additions, metadata_differences = {}, {}, {}
    for path in sorted(scene.rglob('*')):
        if not path.is_file():
            continue
        name = path.relative_to(scene).as_posix()
        if name.startswith('fields/') or path.name == 'pages.json':
            additions[name] = digest(path)
        else:
            originals[name] = digest(path)
    # Check against the delivered v5 archive, rather than assuming its manifest
    # implies every original source and recipe is the same as the CI input.
    with zipfile.ZipFile(v5_archive) as source:
        prefix = 'LIE_Banco_Construccion_v5/scene/'
        for name, expected in list(originals.items()):
            with source.open(prefix + name) as stream:
                delivered = hashlib.file_digest(stream, 'sha256').hexdigest()
            if delivered != expected:
                # The archived source-frame audit was serialized on two CPU
                # environments. It is not read by the native consumer. Allow
                # only its recorded tiny numeric rounding, keep the delivered
                # metadata untouched, and bind the overlay to its actual bytes.
                if name != 'banks/brick/asset-profile.json':
                    raise ValueError('v5_library_ci_mismatch:' + name)
                left = json.loads(source.read(prefix + name))
                right = json.loads((scene / name).read_text())
                deltas = []
                def equivalent(a, b):
                    if a == b:
                        return True
                    if isinstance(a, dict) and isinstance(b, dict):
                        return a.keys() == b.keys() and all(equivalent(a[k], b[k]) for k in a)
                    if isinstance(a, list) and isinstance(b, list):
                        return len(a) == len(b) and all(equivalent(x, y) for x, y in zip(a, b))
                    if type(a) in (int, float) and type(b) in (int, float):
                        deltas.append(abs(a - b))
                        return deltas[-1] <= 1e-12
                    return False
                if not equivalent(left, right):
                    raise ValueError('v5_source_audit_not_rounding:' + name)
                metadata_differences[name] = {
                    'library_sha256': delivered, 'ci_sha256': expected,
                    'numeric_entries': len(deltas), 'max_absolute_delta': max(deltas),
                    'scope': 'offline source-frame audit only; not loaded by native consumer; retained unchanged',
                }
                originals[name] = delivered
    output.mkdir(parents=True)
    for name in additions:
        target = output / 'scene-overlay' / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(scene / name, target)
    requirements = {
        'schema': 'lie-construction-field-overlay/1',
        'scene_identity': manifest['scene_identity'],
        'runtime_commit': '0e9c6759992d3a61abc231274b8ea7c6fce3247c',
        'code_branch': 'work/lie-construction-field',
        'dependency': {'filename': v5_archive.name, 'sha256': V5_SHA,
                       'library_file_id': 'libfile_80ab02b4e89c8191b49956b3916f285c'},
        'base_files_sha256': originals,
        'overlay_files_sha256': additions,
        'bank_bindings': manifest['bank_bindings'],
        'ci_metadata_differences': metadata_differences,
        'source_captures_modified': False,
        'physical_android_tested': False, 'new_apk_built': False,
    }
    (output / 'requirements.json').write_text(json.dumps(requirements, indent=2) + '\n')
    shutil.copyfile(ROOT / 'tools/lie_construction_field_apply_overlay.py', output / 'apply_overlay.py')
    shutil.copyfile(ROOT / 'docs/LIE_CONSTRUCTION_FIELD_V6.md', output / 'INFORME.md')
    for path in reports.glob('LIE_Construccion_Campo_v6.*'):
        if path.suffix in ('.json', '.png'):
            shutil.copyfile(path, output / path.name)
    proof = output / 'evidence'
    proof.mkdir()
    for subdir in ['tmp/hq/comparison', 'tmp/hq/stage', 'home/runner/work/Lie-Engine/Lie-Engine']:
        for path in (evidence / subdir).iterdir():
            if path.is_file() and path.suffix in ('.json', '.png', '.log'):
                shutil.copyfile(path, proof / path.name)
    (output / 'README.md').write_text('''# Construcción LIE v6: actualización sobre v5

Código: https://github.com/heliossamuelhernandezreyes/Lie-Engine/tree/work/lie-construction-field
Runtime aceptado: 0e9c6759992d3a61abc231274b8ea7c6fce3247c
CI: https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/42368614346

Requiere LIE_Banco_Construccion_v5.zip, ya entregado:
https://chatgpt.com/library?file_id=libfile_80ab02b4e89c8191b49956b3916f285c&account_id=personal

1. Extraer el banco v5 y esta actualización en directorios distintos.
2. Ejecutar: python apply_overlay.py --scene /ruta/LIE_Banco_Construccion_v5/scene
3. Usar el código publicado en la rama indicada. El código incluido en el ZIP v5 es anterior.
4. Seguir INFORME.md para generar referencias, preparar una escena nueva e importar en Godot 4.7.2.

El aplicador verifica todos los archivos base, los datos nuevos y los conflictos
antes de copiar. Sólo añade índices y campos: no toca las capturas originales.
Se puede repetir la aplicación de estos mismos datos de forma idempotente.

El informe y las imágenes proceden de la ejecución nativa aceptada de CI.
evidence/ conserva capturas, resultados JSON y registros de las suites nativas.
El total de 1 849 comprobaciones Vulkan cuenta las suites del consumidor actual;
la ejecución adicional del consumidor v5 es la referencia congelada.

Los recursos contabilizados disminuyen 51.4 % incluyendo el campo indirecto.
No son una medición de RAM total ni de FPS de un teléfono. No se entrega una APK.
La visibilidad indirecta es aproximada por perfiles; véanse los límites del informe.

Powered by Poly Haven. Ladrillo: Centre-of-Archaeology, CC BY 4.0.
Se conservan atribuciones y licencias de v5; no hay nuevas fuentes fotográficas.
''', encoding='utf-8')
    archive = output.with_suffix('.zip')
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as target:
        for path in sorted(output.rglob('*')):
            if path.is_file():
                target.write(path, Path(output.name) / path.relative_to(output))
    with zipfile.ZipFile(archive) as target:
        assert target.testzip() is None
        assert not any(name.endswith(('library.bin', 'optical-normals.bin')) for name in target.namelist())
    result = {'filename': archive.name, 'bytes': archive.stat().st_size, 'sha256': digest(archive),
              'original_files_verified': len(originals), 'overlay_files': len(additions)}
    archive.with_suffix('.sha256').write_text(result['sha256'] + '  ' + archive.name + '\n')
    print(json.dumps(result))
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--v5-archive', type=Path, required=True)
    parser.add_argument('--reports', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    build(args.evidence, args.v5_archive, args.reports, args.output)
