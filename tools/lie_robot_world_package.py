"""Package native R2 evidence and restore assets; repository code stays in Git."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import zipfile
from PIL import Image,ImageDraw
from lie_robot_package import digest,font,panel

ROOT=Path(__file__).resolve().parents[1];GPU=ROOT/'gpu_compute'

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--session',type=Path,required=True);p.add_argument('--hands',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--diagnostics',type=Path)
    a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
    native=json.loads((a.session/'r2-native-verification.json').read_text());hands=json.loads((a.hands/'r2-hand-verification.json').read_text())
    assert all(x['ok'] for x in native['checks']) and hands['actual_changed_pixels']
    for report,folder in [(native,a.session),(hands,a.hands)]:
        for x in report['captures']:assert digest(folder/x['name'])==x['sha256'],x['name']
    for name in ('robot-world-motion-verification.json','robot-world-gpu-verification.json','robot-gpu-verification.json'):
        assert not json.loads((GPU/name).read_text())['failed'],name
    for name in ('robot_refined','robot_world'):
        c=json.loads((GPU/'captures'/name/'catalog.json').read_text());assert digest(GPU/'captures'/name/'library.bin')==c['sha256']
    hero=Image.new('RGBA',(1120,860),(5,8,12,255));draw=ImageDraw.Draw(hero)
    draw.text((32,24),'R2 / LIE ENGINE',font=font(38),fill='#e5f3fb')
    draw.text((34,78),'Robot con colisiones · recorrido por la casa modular',font=font(20),fill='#60d8ef')
    panel(hero,a.session/'R2-Entrada.png',(16,126,716,716))
    panel(hero,a.session/'R2-Interior.png',(764,162,324,270))
    panel(hero,a.hands/'R2-Pinza-Cerrada-Detalle.png',(774,488,308,310),crop=True)
    draw.text((764,124),'Dentro de la casa',font=font(21),fill='#e5f3fb')
    draw.text((764,447),'Pinza con pulgar opuesto',font=font(19),fill='#e5f3fb')
    hero.convert('RGB').save(a.output/'R2-Robot-Casa.png')
    comparison=Image.new('RGBA',(1120,650),(5,8,12,255));draw=ImageDraw.Draw(comparison)
    draw.text((28,22),'R2 / PINZAS REUTILIZABLES',font=font(30),fill='#e5f3fb')
    for x,name,label in [(20,'R2-Pinza-Abierta-Detalle.png','Abierta'),(575,'R2-Pinza-Cerrada-Detalle.png','Cerrada')]:
        panel(comparison,a.hands/name,(x,100,525,490),crop=True);draw.text((x+16,603),label,font=font(22),fill='#60d8ef')
    comparison.convert('RGB').save(a.output/'R2-Pinzas.png')
    frames=[]
    for name in native['journey_frames']:
        frame=Image.new('RGBA',(768,830),(5,8,12,255));frame.alpha_composite(Image.open(a.session/name).convert('RGBA'),(0,62))
        ImageDraw.Draw(frame).text((24,16),'R2 / Recorrido nativo con colisiones',font=font(22),fill='#e5f3fb');frames.append(frame.convert('RGB'))
    frames[0].save(a.output/'R2-Recorrido.gif',save_all=True,append_images=frames[1:],duration=130,loop=0,disposal=2,optimize=False)
    files=[]
    def add(path,name):assert path.is_file();files.append((path,name))
    for bank in ('robot_refined','robot_world'):
        for path in sorted((GPU/'captures'/bank).iterdir()):
            if path.suffix in ('.bin','.json','.png'):add(path,f'captures/{bank}/'+path.name)
    for name in ('R2-Robot.glb','R2-Robot.blend','source-surfaces.json','provenance.json'):
        add(GPU/'assets/robot_modular'/name,'assets/robot_modular/'+name)
    for path in sorted((GPU/'assets/lie28').iterdir()):
        if path.name in ('building-masters.blend','source-surfaces.json','provenance.json') or path.stem in ('wall','door_base','door_head','window_wall','corner','slab','lintel') and path.suffix=='.glb':add(path,'assets/lie28/'+path.name)
    for path in sorted(a.session.iterdir()):
        if path.suffix in ('.png','.lie.json') or path.name.endswith('.lie.json') or path.name in ('r2-native-verification.json','r2-journey-assembly.json','r2-world-assembly.json','r1-assembly.json','r1-walk-assembly.json','godot.log'):add(path,'evidence/native/'+path.name)
    for path in sorted(a.hands.iterdir()):
        if path.suffix=='.png' or path.name=='r2-hand-verification.json':add(path,'evidence/hands/'+path.name)
    for name in ('robot-world-motion-verification.json','robot-world-gpu-verification.json','robot-capture-verification.json','robot-gpu-verification.json','robot-rig-verification.json','robot-world-bank-verification.json','robot-source-export-verification.json'):
        add(GPU/name,'evidence/'+name)
    for name in ('R2-Robot-Casa.png','R2-Pinzas.png','R2-Recorrido.gif'):add(a.output/name,'previews/'+name)
    if a.diagnostics:
        for path in sorted(a.diagnostics.iterdir()):
            if path.is_file():add(path,'diagnostics/'+path.name)
    manifest=dict(schema=1,files=[dict(path=name,bytes=path.stat().st_size,sha256=digest(path)) for path,name in files])
    readme='''R2 · Robot y casa de Lie Engine

Código: rama experiment/lie-robot-world de
https://github.com/heliossamuelhernandezreyes/Lie-Engine
Copiar captures/robot_refined y captures/robot_world dentro de gpu_compute/captures.
Abrir lie_robot_world_lab.tscn con Godot 4.7.2, o lanzar --lab robot_world.
WASD/flechas: mover; Q/E: girar; espacio: pausar; arrastrar imagen: cámara.
Los botones y agentes usan los mismos controles. Se guardan todos los apoyos,
posición, velocidad, fase y campos de cámara. El estado de entrada e interior
está en evidence/native. Reproducción: docs/LIE_ROBOT_WORLD.md en GitHub.

Las imágenes y el recorrido proceden de LIE con física CharacterBody3D y Vulkan.
R2-Robot.blend/GLB son geometría original editable; el motor no dibuja esas mallas.
El Blender contiene una caminata del rig horneada en 16 fases; el GIF registra
32 estados del recorrido físico por la casa. Su reproducción no mide FPS.

Materiales 4K CC0 / Rob Tuytel / Poly Haven, con procedencia en assets/*/provenance.json.
Las fuentes y capturas R1 originales siguen preservadas en R1-Robot-Maestros.zip;
la casa original está en LIE28-Assets-Maestros.zip. No se necesita bajar esos
paquetes anteriores para ejecutar la escena R2 con los bancos incluidos aquí.

Límites: colisión del cuerpo aproximada por cápsula; manos y cables sin colisiones
individuales, elasticidad o agarre físico. Área de prueba limitada; umbral calibrado,
sin salto ni controlador general de escaleras. Construcción usa LOD previo de LIE28,
sombras 512 y reflejos de estudio aproximados. Diferencias de profundidad en bordes
de ladrillos se conservan en los informes. Software Vulkan; sin APK Android.

MANIFEST.json verifica los archivos. diagnostics conserva fallos y pruebas.
'''
    target=a.output/'R2-Robot-Casa.zip';temporary=target.with_suffix('.zip.tmp')
    with zipfile.ZipFile(temporary,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for path,name in files:z.write(path,name)
        z.writestr('MANIFEST.json',json.dumps(manifest,indent=2)+'\n');z.writestr('LEEME.txt',readme)
    with zipfile.ZipFile(temporary) as z:assert z.testzip() is None
    os.replace(temporary,target)
    summary=dict(bytes=target.stat().st_size,sha256=digest(target),files=len(files)+2,native_checks=native['passed'],journey_frames=len(frames))
    (a.output/'package-summary.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps(summary))

if __name__=='__main__':main()
