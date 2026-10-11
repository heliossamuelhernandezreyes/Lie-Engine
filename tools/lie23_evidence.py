"""Package inspected GPU frames, native references and editable authoring data."""
import argparse
import io
import json
from pathlib import Path
import zipfile
from PIL import Image,ImageDraw,ImageFont


def build(before,after,out):
    before,after,out=map(Path,(before,after,out));out.mkdir(parents=True,exist_ok=True)
    capture=after/'captures/face23'
    data=json.loads((after/'lie23-diagnostic.json').read_text())
    metrics=json.loads((after/'lie23-native-comparison.json').read_text())
    master=json.loads((capture/'master.json').read_text())
    assert not data['failed']
    font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',21)
    small=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',13)

    def panel(path,label):
        frame=Image.new('RGB',(512,555),(12,15,19));frame.paste(Image.open(path).convert('RGB'),(0,40))
        ImageDraw.Draw(frame).text((16,9),label,font=font,fill=(235,240,248))
        return frame

    portrait=Image.new('RGB',(1024,1140),(12,15,19))
    for row,pose in enumerate(['open','closed']):
        portrait.paste(panel(before/f'lie23-{pose}.png','Anterior · Lie'),(0,row*555))
        portrait.paste(panel(after/f'lie23-{pose}.png','Nuevo · Lie'),(512,row*555))
    ImageDraw.Draw(portrait).text((16,1117),'Misma cámara y luz · fotogramas reales de Vulkan por software',font=small,fill=(185,195,209))
    portrait.save(out/'LIE23-Rostro-Antes-Despues.png')
    comparison=Image.new('RGB',(1024,1695),(12,15,19))
    for row,pose in enumerate(['open','closed']):
        comparison.paste(panel(after/f'lie23-{pose}.png','Lie · capturas deformadas'),(0,row*555))
        comparison.paste(panel(capture/f'native-{pose}-beauty.png','Blender · maestro nativo'),(512,row*555))
    comparison.paste(panel(after/'lie23-closed-albedo.png','Lie · albedo sin iluminación'),(0,1110))
    comparison.paste(panel(capture/'native-closed-albedo.png','Blender · albedo sin iluminación'),(512,1110))
    ImageDraw.Draw(comparison).text((16,1673),'Belleza: materiales e iluminación aproximados; albedo: comparación controlada de piel.',font=small,fill=(185,195,209))
    comparison.save(out/'LIE23-Maestro-y-Lie.png')
    frames=[]
    for i in range(13):
        frame=Image.new('RGB',(1024,584),(12,15,19))
        frame.paste(panel(before/f'lie23-blink-{i:02d}.png','Anterior · párpados'),(0,0))
        frame.paste(panel(after/f'lie23-blink-{i:02d}.png','Nuevo · párpados'),(512,0))
        ImageDraw.Draw(frame).text((16,563),'Vulkan por software · cadencia de reproducción, sin medición de FPS móviles',font=small,fill=(185,195,209))
        frames.append(frame)
    palette=Image.new('RGB',(1024,584*len(frames)))
    for i,frame in enumerate(frames):palette.paste(frame,(0,584*i))
    palette=palette.quantize(colors=256)
    indexed=[frame.quantize(palette=palette,dither=Image.Dither.FLOYDSTEINBERG) for frame in frames]
    indexed[0].save(out/'LIE23-Parpados-Antes-Despues.gif',save_all=True,append_images=indexed[1:],duration=[650]+[120]*11+[650],loop=0,disposal=2)
    report='''# LIE-23: párpados conectados y comparación con el maestro

La unión orbital comparte vértices con el rostro y conserva las UV por esquina.
El párpado usa una abertura almendrada, una pose correctiva intermedia y
normales suaves por pose. Las capturas de deformación conservan una covarianza
completa en el plano tangente. Las sombras proyectan la huella elíptica hacia
un mapa de 1024². La representación visible sigue siendo de muestras capturadas.

El maestro y Lie cierran sin propietarios oculares visibles. El cierre se
comprueba también sin sombras y en primer plano, conservando el ojo presente
en el búfer. La comparación con triángulos nativos usa la misma cámara y
albedo sin iluminación. El error de color excluye bordes y material ocular.

| Pose | IoU de silueta | Error RGB medio de piel (0–1) |
| --- | ---: | ---: |
'''
    for case in metrics['cases']:
        report+=f"| {case['pose']} | {case['silhouette_iou']:.6f} | {case['skin_rgb_mae']:.6f} |\n"
    report+=f'''
Comprobaciones Vulkan: {data['checks']}, fallos: {data['failed']}.
Ojos visibles cerrados: {data['closed_eye_pixels']}; primer plano:
{data['closed_close_eye_pixels']}. Diferencia RGBA por recolorear el iris
oculto: {data['hidden_iris_color_delta']}.

Unión orbital: {master['orbital_boundary_count']} vértices compartidos.
Muestras almacenadas: {data['stored_samples']:.0f}; invocaciones:
{data['sample_invocations']:.0f}. Una biblioteca ocular y una subida de datos.
Fuente: {data['source_bytes']/1048576:.2f} MiB; reservas propias del compositor:
{data['allocation_bytes']/1048576:.2f} MiB, excluyendo CPU, motor y controlador.

El rostro sigue siendo un prototipo. Quedan irregularidades de sombra y
material, una córnea sin refracción y detalles anatómicos por mejorar.
Las imágenes de belleza de Cycles usan materiales/iluminación aproximados;
no se presentan como una comparación física equivalente. Vulkan usa
{data['device']}; no hay mediciones de GPU física o Android.
El GIF reproduce fotogramas exportados, sin medir FPS del motor.

Fuente: Lee Perry-Smith / Infinite-Realities, CC BY 3.0.
Código y reproducción: https://github.com/heliossamuelhernandezreyes/Lie-Engine/pull/23
'''
    (out/'LIE23-Parpados-Validacion.md').write_text(report)
    archive=out/'LIE23-Parpados-Evidencia.zip'
    buffer=io.BytesIO()
    with zipfile.ZipFile(buffer,'w',zipfile.ZIP_DEFLATED) as z:
        for path in sorted(out.iterdir()):
            if path.is_file() and path!=archive:z.write(path,path.name)
        for path in sorted(after.glob('lie23-*.png')):z.write(path,'Vulkan/'+path.name)
        for path in sorted(after.glob('lie23-*.json')):z.write(path,'diagnosticos/'+path.name)
        for path in sorted(capture.glob('native-*.png')):z.write(path,'Blender/'+path.name)
        for name in ['master.json','native-oracle.json','orbital-boundary.json','native-image-checks.json']:
            z.write(capture/name,'maestro/'+name)
        for name in ['human-open-eyes.blend','ATTRIBUTION.md']:
            z.write(after/'assets/lie23'/name,'maestro/'+name)
        z.write(after/'assets/lie20/LeePerrySmith_License.txt','maestro/LeePerrySmith_License.txt')
    archive.write_bytes(buffer.getvalue())
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None
    print(json.dumps({'files':[str(p) for p in sorted(out.iterdir())],'zip_bytes':archive.stat().st_size}))


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('before');p.add_argument('after');p.add_argument('out')
    args=p.parse_args();build(args.before,args.after,args.out)
