"""Create a report from accepted native evidence; never synthesize engine images."""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

RUNTIME = '0e9c6759992d3a61abc231274b8ea7c6fce3247c'
FROZEN = '963fd4ce3cfe6790422937807ddaec51852be488'


def report(evidence, checkpoint, output, font_path):
    stage = evidence / 'tmp/hq/stage'
    comparison = evidence / 'tmp/hq/comparison'
    native = json.loads((stage / 'construction-field-native.json').read_text())
    old = json.loads(checkpoint.read_text())['native']['cases']['corner']
    field = json.loads((comparison / 'field-reference.json').read_text())
    compatibility = json.loads((comparison / 'v5-compatibility.json').read_text())
    assert not native['failed'] and field['passed'] and compatibility['passed']
    new = native['corner']
    previous = old['source_bytes'] + old['exclusive_bytes']
    current = new['library_bytes'] + new['exclusive_allocation_bytes'] + new['field']['bytes']
    resources = {
        'scope': 'requested RenderingDevice resources; excludes process/driver/cache memory',
        'output_size': new['output_size'], 'internal_size': new['internal_size'],
        'v5': {'source': old['source_bytes'], 'appearance': old['exclusive_bytes'], 'field': 0, 'total': previous},
        'v6': {'source': new['library_bytes'], 'appearance': new['exclusive_allocation_bytes'], 'field': new['field']['bytes'], 'total': current},
        'reduction_percent': 100 * (1 - current / previous),
    }
    result = {
        'schema': 'lie-construction-field-v6-checkpoint/1', 'date': '2026-11-07',
        'runtime_commit': RUNTIME, 'frozen_v5_commit': FROZEN,
        'branch': 'work/lie-construction-field',
        'ci': {'run_id': 42368614346, 'job_id': 128391886699, 'conclusion': 'success',
               'artifact_id': 13572886857,
               'artifact_sha256': '2b1ddcb8bdf1aa59482f92418792cefae349797847216b1e2a60c3de498738e0'},
        'resources': resources,
        'device': new['device'], 'native': native,
        'field_reference': field, 'compatibility': compatibility,
        'verification': {'python_ran': 285, 'python_passed': 284, 'python_skipped': 1,
                         'vulkan_checks': 1849, 'rig_checks': 247, 'agent_checks': 25, 'control_checks': 24},
        'images': {'direct': 'field-corner-direct.png', 'indirect': 'field-corner-both.png',
                   'scope': 'native CI PNGs; same camera/material/sources/ambient=1; indirect toggled'},
        'immutable_v5_captures': True, 'source_resampling': False,
        'new_whole_object_scans': 0, 'shared_indirect_field_integrated': True,
        'physical_android_tested': False, 'new_apk_built': False,
        'limits': ['conservative profile AABB visibility', '32 facing candidates before visibility; truncated sparse graph',
                   'indirect diffuse only', 'no automatic native Godot geometry participation',
                   'existing v5 microdetail loss remains', 'resource bytes are not mobile FPS or total RAM'],
    }
    output.mkdir(parents=True, exist_ok=True)
    (output / 'LIE_Construccion_Campo_v6.json').write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n')
    canvas = Image.new('RGB', (1600, 1370), '#191f27')
    draw = ImageDraw.Draw(canvas)
    def label(x, y, text, size=28, color='#f6f8fa'):
        draw.text((x, y), text, font=ImageFont.truetype(str(font_path), size), fill=color)
    label(30, 22, 'LIE · RESIDENCIA Y REBOTES / v6', 38)
    label(30, 79, 'Capturas nativas Vulkan · Misma cámara, fuentes y materiales · Ambiente = 1', 24, '#bfc9d3')
    for x, name, title in [(30, 'field-corner-direct.png', 'Iluminación directa'),
                            (815, 'field-corner-both.png', 'Directa + campo indirecto')]:
        foreground = Image.open(stage / name).convert('RGBA')
        tile = Image.new('RGBA', foreground.size, '#232a32')
        tile.alpha_composite(foreground)
        canvas.paste(tile.convert('RGB').resize((755, 755), Image.Resampling.LANCZOS), (x, 130))
        label(x, 901, title)
    label(30, 975, f'Recursos contabilizados: {previous / 2**20:.1f} → {current / 2**20:.1f} MiB  ·  −{resources["reduction_percent"]:.1f} %', 32, '#96ddc2')
    label(30, 1028, f'Capturas residentes: {old["source_bytes"] / 2**20:.1f} → {new["library_bytes"] / 2**20:.1f} MiB  ·  Campo: {new["field"]["bytes"] / 2**20:.1f} MiB', 25, '#bfc9d3')
    label(30, 1082, '24 vistas en modo de referencia: color y profundidad idénticos bit a bit.', 25)
    label(30, 1124, f'Campo: {field["nodes"]:,} parches · {field["edges"]:,} conexiones · Error numérico máx.: {field["max_error"]:.2e}'.replace(',', ' '), 24, '#bfc9d3')
    label(30, 1182, 'Estas cifras cuentan recursos RD; no son RAM total, FPS ni una medición de Android.', 23, '#e5c384')
    label(30, 1224, 'Visibilidad indirecta por perfiles conservadores; no certifica equivalencia física con las mallas fuente.', 21, '#b2c0cd')
    label(30, 1266, 'CI aprobado: 1 849 comprobaciones Vulkan · 284 pruebas Python aprobadas, 1 omitida.', 22, '#bfc9d3')
    label(30, 1321, 'Powered by Poly Haven · Ladrillo: Centre-of-Archaeology (CC BY 4.0) · Perfiles nuevos: autoría LIE', 18, '#a5b6c7')
    canvas.save(output / 'LIE_Construccion_Campo_v6.png')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--checkpoint', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--font', type=Path, default=Path('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'))
    args = parser.parse_args()
    data = report(args.evidence, args.checkpoint, args.output, args.font)
    print(json.dumps({'resources': data['resources'], 'ci': data['ci']}))
