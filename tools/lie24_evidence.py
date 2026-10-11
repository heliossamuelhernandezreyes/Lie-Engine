"""Package actual Vulkan frames, native comparisons and reusable capture data."""
import argparse
import io
import json
from pathlib import Path
import zipfile
from PIL import Image, ImageDraw, ImageFont


def build(project, output, pr_url):
    project=Path(project);output=Path(output);output.mkdir(parents=True,exist_ok=True)
    root=project/'captures/face24';m=json.loads((root/'master.json').read_text())
    gpu=json.loads((project/'lie24-diagnostic.json').read_text());comparison=json.loads((project/'lie24-native-comparison.json').read_text())
    verified=json.loads((project/'lie24-source-verification.json').read_text())
    assert not gpu['failed'] and gpu['inactive_owners']==0
    font_path='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
    def font(size):
        try:return ImageFont.truetype(font_path,size)
        except OSError:return ImageFont.load_default(size=size)
    background=(15,21,32);white=(235,242,250);muted=(157,177,198);accent=(99,213,233)
    names=['Base sin nariz','Nariz clásica','Nariz corta','Nariz ancha']
    def picture(nose,yaw):
        path=project/f'lie24-nose-{nose}-yaw-{yaw}-presentation.png'
        image=Image.open(path).convert('RGBA');base=Image.new('RGBA',image.size,background+(255,));base.alpha_composite(image);return base.convert('RGB')
    overview=Image.new('RGB',(1024,1180),background);draw=ImageDraw.Draw(overview)
    draw.text((28,20),'LIE-24 · Construcción facial modular',font=font(31),fill=white)
    draw.text((28,62),'Una cabeza base · tres narices capturadas · profundidad común',font=font(19),fill=muted)
    for nose in range(4):
        x=(nose%2)*512;y=108+(nose//2)*512
        overview.paste(picture(nose,0),(x,y));draw.text((x+26,y+12),names[nose],font=font(24),fill=accent)
    draw.text((28,1140),'Vulkan por software · luz frontal, sombras desactivadas · prototipo',font=font(17),fill=muted)
    overview_path=output/'LIE24-Rostro-Modular.png';overview.save(overview_path)
    profiles=Image.new('RGB',(1024,1660),background);draw=ImageDraw.Draw(profiles)
    draw.text((28,18),'LIE-24 · Los rasgos conservan volumen',font=font(30),fill=white)
    for nose in range(4):
        for column,yaw in enumerate([0,90]):
            image=picture(nose,yaw).resize((384,384),Image.Resampling.LANCZOS)
            x=64+column*512;y=100+nose*384;profiles.paste(image,(x,y))
            draw.text((x+10,y+8),names[nose]+(' · frente' if yaw==0 else ' · perfil'),font=font(20),fill=accent)
    draw.text((28,1635),'Fotogramas del compositor Vulkan · mismos assets desde diferentes cámaras',font=font(16),fill=muted)
    profile_path=output/'LIE24-Frente-y-Perfil.png';profiles.save(profile_path)
    frames=[]
    for nose in range(4):
        frame=Image.new('RGB',(1024,600),background);draw=ImageDraw.Draw(frame)
        draw.text((28,16),'LIE-24 · '+names[nose],font=font(28),fill=white)
        frame.paste(picture(nose,0),(0,66));frame.paste(picture(nose,90),(512,66))
        draw.text((28,575),'Fotogramas reales · reproducción de variantes, sin medición de FPS',font=font(16),fill=muted)
        frames.append(frame)
    gif_path=output/'LIE24-Variantes-Faciales.gif'
    frames[0].save(gif_path,save_all=True,append_images=frames[1:],duration=1200,loop=0,optimize=False)
    reduction=(1-m['vertex_count']/m['original_vertex_count'])*100
    source_mib=verified['source_bytes']/1048576;own_mib=gpu['allocation_bytes']/1048576
    report=f'''# LIE-24: construcción facial modular

Una base conserva el volumen de la cabeza y permite sustituir su región nasal.
Hay una base sin nariz y tres variantes capturadas —clásica, corta y ancha—
de una misma familia visual. Los labios, cejas y mejillas aún pertenecen al
escaneo original; no se presenta una biblioteca facial completa.

Las cuatro opciones comparten {verified['assemblies'][0]['shared_boundary_vertices']} vértices externos de montaje, con separación máxima
de {verified['max_collar_gap_m']:.1f} metros. La base usa piel triangulada sin pliegues y sin los colores de las fosas.
Las regiones rígidas conservan XYZ de sus capturas y siguen directamente la
cabeza. Párpados y cuello mantienen su soporte detallado. La profundidad
común decide qué muestra queda visible; los módulos inactivos no aportan
imagen ni sombra. Cambiar de nariz conserva una sola subida del maestro.

| Medida | Resultado |
| --- | ---: |
| Vértices de deformación anteriores | {m['original_vertex_count']:,} |
| Vértices actuales, incluida la biblioteca nasal | {m['vertex_count']:,} |
| Reducción de vértices | {reduction:.2f}% |
| Muestras rígidas sin soporte denso | {m['rigid_face_sample_count']:,} |
| Muestras almacenadas | {m['sample_count']:,} |
| Invocaciones, contando ambos ojos | {m['invocation_count']:,} |
| Buffers fuente | {source_mib:.2f} MiB |
| Reservas propias del compositor | {own_mib:.2f} MiB |
| Comprobaciones Vulkan | {gpu['checks']} |
| Propietarios de módulos inactivos | {gpu['inactive_owners']} |
| Error máximo frente a posiciones nativas | {gpu['max_native_position_error_m']:.10g} m |
| IoU mínimo de silueta, 13 cámaras/variantes | {comparison['min_silhouette_iou']:.6f} |
| Error RGB medio máximo de piel, sin iluminación | {comparison['max_skin_rgb_mae']:.6f} |

Pasaron 31 comprobaciones del documento modular, 23 del documento anterior
y las 79 pruebas Vulkan del rostro anterior. La selección valida familia,
rangos, identificadores y semilla; guardar, abrir, deshacer y rehacer conservan
el asset. La semilla repite la elección entre las tres narices compatibles.

Dispositivo de prueba: {gpu['device']}. Vulkan usa una GPU por software.
No hay mediciones de GPU física ni Android. La cadencia del GIF es de
reproducción y no representa FPS del motor. La reducción del soporte invisible
no implica menor memoria total: la biblioteca residente de alternativas
aumenta las reservas respecto a los 220.51 MiB de LIE-23. La cifra excluye CPU,
Godot, controlador y otros sistemas.

Las imágenes de presentación usan luz a −8° y sombras desactivadas para
comparar las formas. El paquete también conserva fotogramas con la luz
original, referencias nativas de Blender y comparaciones de albedo/silueta.
Las imágenes de belleza nativas usan materiales e iluminación aproximados.
El rostro aún necesita acabado de sombras, materiales y anatomía. El módulo
base solo retira la nariz; otras regiones faciales son trabajo posterior.

Fuente: Lee Perry-Smith / Infinite-Realities, CC BY 3.0. Variantes artísticas
derivadas de ese maestro. Código y reproducción: {pr_url}
'''
    report_path=output/'LIE24-Validacion.md';report_path.write_text(report)
    zip_path=output/'LIE24-Modulos-Faciales-Evidencia.zip';data=io.BytesIO()
    with zipfile.ZipFile(data,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
        for path in [overview_path,profile_path,gif_path,report_path]:archive.write(path,path.name)
        for path in sorted(project.glob('lie24-*.png')):archive.write(path,'vulkan/'+path.name)
        for path in sorted(project.glob('lie24-*.json')):archive.write(path,'validacion/'+path.name)
        for path in sorted(root.rglob('*')):
            if path.is_file() and path.suffix in ['.bin','.json','.png']:archive.write(path,'capturas/face24/'+str(path.relative_to(root)))
        archive.write(project/'assets/lie24/modular-face.blend','maestro/modular-face.blend')
        for path in [project/'assets/lie24/ATTRIBUTION.md',project/'assets/lie20/LeePerrySmith_License.txt']:
            archive.write(path,'licencia/'+path.name)
    zip_path.write_bytes(data.getvalue())
    with zipfile.ZipFile(zip_path) as archive:assert archive.testzip() is None;entries=len(archive.infolist())
    for path in [overview_path,profile_path,gif_path]:
        with Image.open(path) as image:image.verify()
    print(json.dumps({'files':[str(p) for p in [overview_path,profile_path,gif_path,report_path,zip_path]],'zip_bytes':zip_path.stat().st_size,'zip_entries':entries,'vertex_reduction_percent':reduction},indent=2))


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--project',default='gpu_compute');parser.add_argument('--output',required=True);parser.add_argument('--pr-url',required=True)
    args=parser.parse_args();build(args.project,args.output,args.pr_url)
