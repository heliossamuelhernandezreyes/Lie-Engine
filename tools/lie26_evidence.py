"""Persist actual motion frames, functionality passes and visual failures."""
import argparse,hashlib,json,subprocess,zipfile
from pathlib import Path
import numpy as np
from PIL import Image
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

def main():
    p=argparse.ArgumentParser();p.add_argument('--project',type=Path,default=Path('gpu_compute'));p.add_argument('--out',type=Path,required=True);p.add_argument('--logs',type=Path,required=True);args=p.parse_args();project=args.project;root=project/'captures/anatomy26';out=args.out;out.mkdir(parents=True,exist_ok=True)
    master=json.loads((root/'master.json').read_text());gpu=json.loads((project/'lie26-diagnostic.json').read_text());comparison=json.loads((project/'lie26-native-comparison.json').read_text())
    if gpu['failed'] or gpu['checks']!=99 or gpu['sample_count']!=master['sample_count'] or comparison.get('sample_sha256')!=master['buffers']['samples.bin']['sha256'] or comparison.get('shader_sha256')!=hashlib.file_digest((project/'shaders/lie26_motion.glsl').open('rb'),'sha256').hexdigest():raise ValueError('Stale or failing functional evidence')
    for name,meta in master['buffers'].items():
        path=root/name
        if path.stat().st_size!=meta['bytes'] or hashlib.file_digest(path.open('rb'),'sha256').hexdigest()!=meta['sha256']:raise ValueError('Bank integrity: '+name)
    for name in ['lie26-import.log','lie26-rig-test.log','lie26-python-test.log']:
        text=(args.logs/name).read_text()
        if 'SCRIPT ERROR:' in text or 'ERROR:' in text or (name.endswith('rig-test.log') and 'PASS 247 checks' not in text) or (name.endswith('python-test.log') and 'OK (skipped=1)' not in text):raise ValueError('Validation log: '+name)
    # Standard scientific figure of unmodified renderer frames; no imagegen.
    fig,axes=plt.subplots(2,3,figsize=(12,9),facecolor='#101720')
    frames=[('Reposo','rest-lit'),('Codos','elbow-lit'),('Alcanzar','reach-lit'),('Marcha con IK','walk'),('Músculos en movimiento','walk-muscles'),('Huesos articulados','bones-lit')]
    for ax,(title,name) in zip(axes.flat,frames):
        ax.set_facecolor('#101720');ax.imshow(Image.open(project/f'lie26-{name}.png'));ax.set_title(title,color='white',fontsize=13,pad=8);ax.axis('off')
    fig.suptitle('Lie · movimiento anatómico',color='white',fontsize=23,y=.98)
    fig.text(.5,.018,'Capturas reales · 15 huesos · cuatro capas · calidad visual experimental',color='#b7c4d4',ha='center',fontsize=11)
    fig.subplots_adjust(left=.02,right=.98,top=.92,bottom=.05,wspace=.04,hspace=.12);fig.savefig(out/'LIE26-Movimiento-Por-Capas.png',dpi=130,facecolor=fig.get_facecolor());plt.close(fig)
    images=[]
    for i in range(24):
        image=Image.open(project/f'lie26-frames/frame-{i:03d}.png').convert('RGBA');background=Image.new('RGBA',image.size,'#101720');background.alpha_composite(image);images.append(background.convert('RGB'))
    images[0].save(out/'LIE26-Movimiento.gif',save_all=True,append_images=images[1:],duration=80,loop=0,optimize=False)
    lines=['# Lie · primera prueba de movimiento anatómico','',
        'Ya funciona un rig común para cabeza, torso, brazos y piernas. Sus quince huesos dirigen las capturas de piel, músculos, esqueleto e interiores. Hay límites, IK para manos/pies y una marcha procedural sin necesitar un clip de animación externo.','',
        '**Estado: funcionalidad verificada; calidad visual todavía experimental.** La comparación independiente contra los triángulos originales conserva sus objetivos y sus fallos. Esta entrega no certifica calidad final ni rendimiento en GPU física.','',
        '## Verificación funcional','',
        '- 247 comprobaciones del rig: ejes, jerarquía, límites, objetivos alcanzables e inalcanzables y apoyo de pies.',
        '- 99 comprobaciones Vulkan: posiciones GPU/CPU, huesos rígidos, capas, proxies invisibles, IK, transacciones y una sola carga del banco.',
        '- 66 pruebas Python: correctas, con una omitida por un maestro externo ausente.',
        '- Cero MeshInstance3D del modelo médico en ejecución. Las referencias de juntas guían capturas y no dibujan polígonos.',
        f'- Backend real de esta ejecución: {gpu["device"]}. Es Vulkan por software.','',
        '## Memoria y estructura','',
        '| Recurso | Medida |','| --- | ---: |',
        f'| Muestras residentes | {master["sample_count"]:,} |',
        f'| Banco de muestras | {(root/"samples.bin").stat().st_size/1048576:.2f} MiB |',
        f'| Asignaciones propias del compositor Lie | {gpu["allocation_bytes"]/1048576:.2f} MiB |',
        f'| Vértices lógicos adicionales para juntas | {master["sparse_joint_bindings"]["vertices"]:,} |',
        f'| Triángulos lógicos adicionales | {master["sparse_joint_bindings"]["triangles"]:,} |',
        f'| Muestras ligadas a esas juntas | {master["sparse_joint_bindings"]["samples"]:,} |','',
        'La memoria medida incluye buffers y texturas de Lie. No es la RAM total de Godot. Esta densidad corresponde a un cuerpo con cuatro capas y no establece un presupuesto móvil. Para cambiar la pose se actualizan quince registros de huesos; el banco se carga una vez.','',
        '## Comparación visual independiente','',
        'Referencia: rayos de perspectiva contra los triángulos del fuente original deformados por el rig offline, con el mismo muestreo 1024→512. IoU mide coincidencia de silueta. Objetivos: IoU global ≥0.98, juntas ≥0.96, error RGB ≤0.03, profundidad media ≤3 mm y p95 ≤8 mm.','',
        '| Pose | IoU global | Peor junta | Profundidad media (mm) | p95 (mm) | Objetivo |','| --- | ---: | ---: | ---: | ---: | --- |']
    for c in comparison['cases']:
        lines.append(f'| {c["name"]} | {c["silhouette_iou"]:.4f} | {min(j["iou"] for j in c["joint_patches"]):.4f} | {c["depth_mae_m"]*1000:.3f} | {c["depth_p95_m"]*1000:.3f} | {"Pasa" if c["passed"] else "No pasa"} |')
    lines+=['','La aceptación visual completa '+('pasó.' if comparison['passed'] else '**no pasó**. Quedan diferencias de cobertura en uniones, axilas y estructuras finas. La transformación correcta de los puntos no garantiza todavía una superficie visual perfecta.'),'',
        'Las sombras de muestras están disponibles por código, pero desactivadas por defecto en este laboratorio de movimiento. La iluminación directa y el color siguen activos. La piel no tiene texturas de color; los músculos no se contraen fisiológicamente. Dedos individuales, ropa, ragdoll, terrenos/colisiones de juego y cortes quedan pendientes.','',
        '## Probarlo','',
        '1. Usa la rama `feat/lie-26-anatomical-motion` del repositorio Lie-Engine.',
        '2. Extrae `gpu_compute/captures/anatomy26/` del archivo de evidencia dentro del proyecto.',
        '3. Importa `gpu_compute/project.godot` con Godot 4.7.2 y Vulkan.',
        '4. Abre `lie26_motion_lab.tscn`, o Taller → Laboratorios → Movimiento anatómico · FK / IK.',
        '5. Prueba Reposo, Codos, Alcanzar y Caminar / pausar; oculta las capas para comprobar que siguen el mismo rig.','',
        'La animación GIF contiene 24 poses realmente renderizadas de un ciclo; su velocidad de reproducción no es una medición de FPS.','',
        '## Fuente y derechos','',
        '3DAnatomyman by Always3D; derivado de BodyParts3D © DBCLS. Modificado mediante segmentación, capturas, rig y color para Lie. Los assets derivados conservan [CC BY-SA 2.1 JP](https://creativecommons.org/licenses/by-sa/2.1/jp/). [Fuente](https://always3d.gumroad.com/l/haJWL). La licencia del código del motor permanece separada.','',
        'SHA-256 del Blender original: `'+master['source_sha256']+'`.','',
        'El original ya está recuperado: no hace falta enviarlo por teléfono. El paquete contiene el banco exacto, galerías, referencias, fotogramas, resultados y registros. No incluye correo, recibos ni enlaces privados de compra.','']
    report=out/'LIE26-Prueba-Movimiento.md';report.write_text('\n'.join(lines))
    # Archive only complete runtime galleries, never unfinished staging files.
    files=set(root/name for name in ['master.json','samples.bin','vertices.bin','triangles.bin','source-counts.json'])
    files.update(root/view for g in master['capture_views'] for view in g['views']);files.update(root/f'native-{c["name"]}.npz' for c in master['cases'])
    for path in files:
        if path.suffix=='.npz':
            with np.load(path) as z:
                for key in z.files:_=z[key].shape
    package=out/'LIE26-Movimiento-Evidencia.zip'
    with zipfile.ZipFile(package,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for path in sorted(files):z.write(path,str(path.relative_to(project.parent)))
        for path in sorted(project.glob('lie26-*.png')):z.write(path,'frames/'+path.name)
        for path in sorted(project.glob('lie26-*.bin')):z.write(path,'frames/'+path.name)
        for path in [project/'lie26-diagnostic.json',project/'lie26-native-comparison.json']:z.write(path,'results/'+path.name)
        for path in sorted((project/'lie26-frames').glob('frame-*.png')):z.write(path,'animation/'+path.name)
        for path in sorted(args.logs.glob('lie26-*.log')):z.write(path,'logs/'+path.name)
        for path in [report,out/'LIE26-Movimiento-Por-Capas.png',out/'LIE26-Movimiento.gif']:z.write(path,path.name)
        z.write(args.logs/'README-original.txt','README-original.txt')
    with zipfile.ZipFile(package) as z:
        bad=z.testzip()
        if bad:raise ValueError('Archive CRC: '+bad)
    print(json.dumps(dict(files=[dict(path=str(p.resolve()),bytes=p.stat().st_size) for p in [out/'LIE26-Movimiento.gif',out/'LIE26-Movimiento-Por-Capas.png',report,package]],visual_acceptance=comparison['passed'],functional_checks=gpu['checks'])))

if __name__=='__main__':main()
