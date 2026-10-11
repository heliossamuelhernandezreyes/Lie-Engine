"""Package measured Lie outputs and the attributed capture bank."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from PIL import Image


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--project',type=Path,default=Path('gpu_compute'))
    parser.add_argument('--source-readme',type=Path,required=True)
    parser.add_argument('--test-log',type=Path,required=True)
    parser.add_argument('--import-log',type=Path,required=True)
    parser.add_argument('--out',type=Path,required=True)
    args=parser.parse_args()
    root=args.project;bank=root/'captures/anatomy25'
    gpu=json.loads((root/'lie25-diagnostic.json').read_text())
    native=json.loads((root/'lie25-native-comparison.json').read_text())
    master=json.loads((bank/'master.json').read_text())
    test_log=args.test_log.read_text()
    test_count=re.search(r'Ran (\d+) tests',test_log)
    if not test_count or not re.search(r'^OK(?:\s|$)',test_log,re.MULTILINE):
        raise ValueError('Passing Python test log required')
    skipped=re.search(r'skipped=(\d+)',test_log)
    import_log=args.import_log.read_text()
    if re.search(r'SCRIPT ERROR|Parse Error|^ERROR:',import_log,re.MULTILINE):
        raise ValueError('Godot import errors in evidence')
    if gpu['failed'] or not native['passed'] or int(gpu['master']['sample_count'])!=master['sample_count']:
        raise ValueError('Evidence requires current passing GPU/native reports')
    for name,metadata in master['buffers'].items():
        p=bank/name
        if p.stat().st_size!=metadata['bytes'] or hashlib.file_digest(p.open('rb'),'sha256').hexdigest()!=metadata['sha256']:
            raise ValueError('Bank integrity: '+name)
    args.out.mkdir(parents=True,exist_ok=True)
    plt.rcParams.update({'font.family':'DejaVu Sans','text.color':'#f4f1eb','axes.titlecolor':'#f4f1eb'})
    fig,axes=plt.subplots(2,2,figsize=(10,11.4),facecolor='#080a0d')
    for ax,mask,title in zip(axes.flat,[15,14,12,8],['Piel','Músculos · piel oculta','Huesos e interiores','Interiores · otras capas ocultas']):
        ax.set_facecolor('#080a0d');ax.imshow(Image.open(root/f'lie25-mask{mask}.png'),interpolation='nearest');ax.axis('off');ax.set_title(title,fontsize=17,pad=12)
    fig.suptitle('LIE · Anatomía por capas',fontsize=27,y=.965)
    fig.text(.5,.923,'Capturas reales · pigmentos e iluminación por código',ha='center',fontsize=13,color='#b8c1cc')
    fig.subplots_adjust(left=.03,right=.97,top=.88,bottom=.105,wspace=.04,hspace=.13)
    fig.text(.5,.056,'3DAnatomyman · Always3D / BodyParts3D © DBCLS · CC BY-SA 2.1 JP',ha='center',fontsize=10)
    fig.text(.5,.032,'Busto rígido · Vulkan por software · sin texturas de piel ni cortes',ha='center',fontsize=10,color='#b8c1cc')
    figure=args.out/'LIE25-Anatomia-Por-Capas.png';fig.savefig(figure,dpi=125,facecolor=fig.get_facecolor());plt.close(fig)
    rows='\n'.join(f"| {r['mask']} | {r['silhouette_iou']:.6f} | {r['interior_unlit_rgb_mae']:.6f} | {'Pasa' if r['pass'] else 'Falla'} |" for r in native['cases'])
    report=f'''# LIE-25 · Prueba anatómica por capas

Piel, músculos, huesos e interiores conservan capturas separadas. Se pueden
ocultar tejidos, recolorear y cambiar iluminación sin recapturar ni subir
otra vez el asset. Profundidad común resuelve la superficie visible.

La figura utiliza exclusivamente imágenes calculadas por Lie. No se generó
ni retocó el cuerpo para esta evidencia. Los cuatro paneles usan la misma luz.

## Datos y memoria

- Maestro gratuito: 3DAnatomyman, Always3D, derivado de BodyParts3D © DBCLS.
- Descarga: 703,830,766 bytes; 671.225 MiB, unos 704 MB decimales.
- Maestro inspeccionado: 934 meshes, 26,317,506 polígonos; materiales grises,
  sin mapas de color ni armature. La prueba sustituye metalicidad 1 por tejidos
  dieléctricos y pigmentos RGB lineales constantes.
- Recorte: 38 cm superiores de la piel; pelo y cejas excluidos.
- Capturas: 36 por capa, 144 en total; resoluciones {master['capture_resolution_by_layer']}.
- Muestras: {int(master['sample_count']):,}; cada muestra ocupa 80 bytes.
- Banco de muestras: {master['buffers']['samples.bin']['bytes']:,} bytes,
  {master['buffers']['samples.bin']['bytes']/1048576:.2f} MiB sin comprimir.
- Reserva medida de recursos del compositor: {gpu['allocation_bytes']:,} bytes,
  **{gpu['allocation_bytes']/1048576:.2f} MiB**. No es RAM total del proceso.
- Dispositivo: {gpu['device']} (Vulkan por software).
- Caja: 8 vértices y 12 triángulos de referencia; nunca se rasteriza. Las
  muestras comparten giro global; no es un rig ni un collider físico.

## Validación

{gpu['checks']} comprobaciones Vulkan pasan: selección de tejidos, propietarios
válidos, restauración idéntica de imagen, cambios efectivos de pigmento y luz,
una única subida del asset, imagen vacía y controles inválidos rechazados
atómicamente. El giro de 27 grados conserva coordenadas con error máximo
{gpu['rotation_error_m']:.8f} m en las muestras verificadas. La escena dibuja
{gpu['visible_source_meshes']} meshes del maestro.

El oráculo independiente lanza rayos contra las superficies detalladas
recortadas en Blender; no usa el banco de puntos ni el algoritmo de splats.
Umbrales fijados: IoU ≥ 0.985 y MAE de RGB sin luz ≤ 0.03.

| Selección | IoU de silueta | MAE RGB sin luz | Resultado |
| --- | --- | --- | --- |
{rows}

`15`: todas; `14`: sin piel; `12`: huesos e interiores; `8`: interiores.
La comparación solo certifica esas selecciones frontales. El giro comprueba
coordenadas, no fidelidad visual en todos los ángulos.

Las {test_count.group(1)} pruebas Python existentes pasan
({skipped.group(1) if skipped else '0'} omitidas). La importación de Godot
no muestra errores de scripts. Los logs completos están en el paquete.

## Límites actuales

Este es un busto rígido con color uniforme por tejido. No tiene rig corporal,
expresiones, poros, pigmentación local ni cortes cerrados. El maestro advierte
huecos e intersecciones entre órganos; vasos y tráquea pueden ser sólidos.
Quitar capas no equivale a disponer de un sistema de gore.

La memoria sigue siendo elevada para un solo busto. Falta medir una GPU física,
FPS en Android y memoria compartida entre personajes, además de optimizar
selección de capturas y nivel de detalle. Vulkan por software no predice FPS.

## Fuente y licencia

Fuente: https://always3d.gumroad.com/l/haJWL

Crédito: 3DAnatomyman by Always3D; derivative of BodyParts3D © Database Center
for Life Science. Cropped and captured for Lie; rendered with tissue pigments.
Maestro y capturas derivadas: CC BY-SA 2.1 JP.
https://creativecommons.org/licenses/by-sa/2.1/jp/

SHA-256 original: `{master['source_sha256']}`.
El paquete incluye el README original del autor. No contiene recibos, correo
del usuario ni enlaces privados de compra. El .blend original se adquiere por
separado; los NPZ, buffers y referencias bastan para repetir el consumo en Lie.

## Uso del paquete

Extraer `captures/anatomy25` dentro de `gpu_compute/captures`. Ejecutar en el
código LIE-25 `godot --path gpu_compute res://lie25_anatomy_lab.tscn`.
Las instrucciones de captura y validación están en
`docs/LIE_25_ANATOMICAL_LAYERS.md` del repositorio Lie-Engine.
'''
    report_path=args.out/'LIE25-Prueba-Anatomica.md';report_path.write_text(report)
    package=args.out/'LIE25-Anatomia-Evidencia.zip'
    with zipfile.ZipFile(package,'w',zipfile.ZIP_DEFLATED,compresslevel=5) as z:
        for p in sorted(bank.iterdir()):
            if p.is_file():z.write(p,'captures/anatomy25/'+p.name)
        for p in sorted(root.glob('lie25-*')):
            if p.suffix in ['.png','.json','.bin']:z.write(p,'evidence/'+p.name)
        z.write(args.source_readme,'source/README-original.txt')
        z.write(args.test_log,'evidence/python-tests.log')
        z.write(args.import_log,'evidence/godot-import.log')
        z.write(figure,figure.name);z.write(report_path,report_path.name)
    print(json.dumps({'files':[str(p.resolve()) for p in [figure,report_path,package]],'package_bytes':package.stat().st_size}))


if __name__=='__main__':main()
