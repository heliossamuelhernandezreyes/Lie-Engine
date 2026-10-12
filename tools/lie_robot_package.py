#!/usr/bin/env python3
"""Package attributed assets and exact native evidence; source code stays in Git."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import zipfile
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
GPU = ROOT/'gpu_compute'
LABELS = {'plate_flat':'Placa plana', 'plate_shell':'Placa curva',
          'plate_bracket':'Soporte angular', 'joint':'Articulación',
          'shaft':'Vástago / pistón', 'cable':'Cable corrugado'}


def digest(path):
    return hashlib.file_digest(path.open('rb'), 'sha256').hexdigest()


def font(size):
    return ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', size)


def panel(canvas, source, bounds, crop=False):
    picture = Image.open(source).convert('RGBA')
    if crop and picture.getbbox(): picture = picture.crop(picture.getbbox())
    picture.thumbnail((bounds[2], bounds[3]), Image.Resampling.LANCZOS)
    canvas.alpha_composite(picture, (bounds[0]+(bounds[2]-picture.width)//2,
                                   bounds[1]+(bounds[3]-picture.height)//2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--session', type=Path, required=True)
    parser.add_argument('--materials', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--diagnostics', type=Path)
    args = parser.parse_args(); args.output.mkdir(parents=True, exist_ok=True)
    evidence = json.loads((args.session/'robot-agent-verification.json').read_text())
    for item in evidence['captures']:
        assert digest(args.session/item['name']) == item['sha256'], item['name']
    assert all(c['ok'] for c in evidence['checks'])
    catalog = json.loads((GPU/'captures/robot_modular/catalog.json').read_text())
    assert digest(GPU/'captures/robot_modular/library.bin') == catalog['sha256']
    assert (GPU/'captures/robot_modular/library.bin').stat().st_size == catalog['bytes']
    hero = Image.new('RGBA', (1120, 860), (5, 8, 12, 255)); draw = ImageDraw.Draw(hero)
    draw.text((34, 24), 'R1 / LIE ENGINE', font=font(38), fill='#e5f3fb')
    draw.text((36, 78), 'Robot modular · captura del compositor nativo', font=font(20), fill='#60d8ef')
    panel(hero, args.session/'R1-Robot.png', (16, 126, 716, 716))
    panel(hero, args.session/'R1-Cabeza.png', (764, 154, 324, 250), crop=True)
    panel(hero, args.session/'R1-Brazo-Flexionado.png', (764, 474, 324, 314), crop=True)
    draw.text((764, 123), 'Placas y sensores', font=font(20), fill='#e5f3fb')
    draw.text((764, 441), 'Codo · cable · pinza', font=font(20), fill='#e5f3fb')
    hero.convert('RGB').save(args.output/'R1-Robot.png')
    sheet = Image.new('RGBA', (1120, 800), (5, 8, 12, 255)); draw = ImageDraw.Draw(sheet)
    draw.text((28, 22), 'R1 / SEIS MAESTROS REUTILIZABLES', font=font(29), fill='#e5f3fb')
    draw.text((30, 65), 'Tres placas · articulación · vástago · cable | renderizado nativo', font=font(18), fill='#60d8ef')
    for index, (master, label) in enumerate(LABELS.items()):
        x, y = 16+(index%3)*368, 120+(index//3)*328
        panel(sheet, args.session/f'R1-Maestro-{master}.png', (x, y, 348, 270), crop=True)
        draw.text((x+12, y+282), label, font=font(21), fill='#e5f3fb')
    sheet.convert('RGB').save(args.output/'R1-Maestros.png')
    frames = []
    for name in evidence['walk_frames']:
        picture = Image.open(args.session/name).convert('RGBA')
        canvas = Image.new('RGBA', (768, 830), (5, 8, 12, 255)); canvas.alpha_composite(picture, (0, 62))
        ImageDraw.Draw(canvas).text((24, 16), 'R1 / 16 poses nativas de LIE', font=font(25), fill='#e5f3fb')
        frames.append(canvas.convert('RGB'))
    frames[0].save(args.output/'R1-Caminata.gif', save_all=True, append_images=frames[1:],
                   duration=100, loop=0, disposal=2, optimize=False)
    files = []
    def add(path, name):
        assert path.is_file(); files.append((path, name))
    for path in sorted((GPU/'assets/robot_modular').iterdir()):
        if path.suffix in ('.glb', '.blend', '.json'): add(path, 'assets/robot_modular/'+path.name)
    for path in sorted((GPU/'captures/robot_modular').iterdir()):
        if path.suffix in ('.bin', '.json', '.png'): add(path, 'captures/robot_modular/'+path.name)
    for path in sorted(args.materials.iterdir()):
        if path.is_file(): add(path, 'source-materials/'+path.name)
    for path in sorted(args.session.iterdir()):
        if path.suffix == '.png' or path.name in ('robot-agent-verification.json', 'r1-rest.lie.json',
                                                'r1-assembly.json', 'r1-walk-assembly.json', 'godot.log'):
            add(path, 'evidence/native/'+path.name)
    for name in ('robot-rig-verification.json', 'robot-gpu-verification.json',
                 'robot-capture-verification.json', 'robot-source-export-verification.json'):
        add(GPU/name, 'evidence/'+name)
    for name in ('R1-Robot.png', 'R1-Maestros.png', 'R1-Caminata.gif'):
        add(args.output/name, 'previews/'+name)
    if args.diagnostics:
        for path in sorted(args.diagnostics.iterdir()):
            if path.is_file(): add(path, 'diagnostics/'+path.name)
    manifest = dict(schema=1, engine='Godot 4.7.2 / Vulkan llvmpipe', bank_sha256=catalog['sha256'],
                    files=[dict(path=name, bytes=p.stat().st_size, sha256=digest(p)) for p,name in files])
    readme = '''R1 · Robot modular de Lie Engine

Restauración: usar la rama experiment/lie-robot-modular del repositorio
https://github.com/heliossamuelhernandezreyes/Lie-Engine
Copiar assets/robot_modular y captures/robot_modular dentro de gpu_compute.
Abrir lie_robot_lab.tscn con Godot 4.7.2 o lanzar --lab robot con el launcher.
Las instrucciones y el código están en docs/LIE_ROBOT_MASTERKIT.md del repo.

R1-Robot.glb: geometría original ensamblada en reposo (metros, Y arriba).
R1-Robot.blend: editable; frame 0 reposo, frames 1–17 caminata horneada.
robot-masterkit.blend: seis maestros mecánicos y suelo, con materiales empacados.
evidence/native/r1-rest.lie.json: estado restaurable del laboratorio nativo.

Las imágenes y poses de caminata proceden del compositor de LIE. Blender/GLB
son fuentes editables: el motor no dibuja esas mallas durante esta prueba.
La velocidad del GIF no mide FPS del motor. Dispositivo: Vulkan por software.
Cables con longitud guiada por el rig; todavía sin colisiones, elasticidad,
controlador para recorrer la casa ni build Android. Modelo y manos por pulir.

Mapas fotografiados CC0 / Rob Tuytel / Poly Haven:
https://polyhaven.com/a/blue_metal_plate
https://polyhaven.com/a/metal_plate_02
Ocho mapas 4K; procedencia y hashes completos en source-materials/provenance.json.
Geometría original del proyecto Lie Engine. MANIFEST.json verifica cada archivo.
diagnostics conserva fallos iniciales corregidos y registros de verificación.
'''
    target = args.output/'R1-Robot-Maestros.zip'; temporary = target.with_suffix('.zip.tmp')
    with zipfile.ZipFile(temporary, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path, name in files: archive.write(path, name)
        archive.writestr('MANIFEST.json', json.dumps(manifest, indent=2)+'\n')
        archive.writestr('LEEME.txt', readme)
    with zipfile.ZipFile(temporary) as archive: assert archive.testzip() is None
    os.replace(temporary, target)
    summary = dict(zip=str(target.resolve()), bytes=target.stat().st_size, sha256=digest(target),
                   files=len(files)+2, bank_sha256=catalog['sha256'], native_checks=evidence['passed'])
    (args.output/'package-summary.json').write_text(json.dumps(summary, indent=2)+'\n')
    print(json.dumps(summary), flush=True)


if __name__ == '__main__': main()
