"""Assemble REAL CI frames into a comparison, GIF and MP4; no frame synthesis.

Requires Pillow and ffmpeg. Export cadence is authored and is not engine FPS.
Usage: python3 tools/lie16_evidence.py EXTRACTED_ARTIFACT DESTINATION
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont


def font(size):
    for name in ['/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
                 '/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf']:
        if Path(name).exists():
            return ImageFont.truetype(name, size)
    return ImageFont.load_default()


def make_card(root, frame, width=768):
    card = Image.new('RGB', (width * 2, width + 144), '#101921')
    draw = ImageDraw.Draw(card)
    draw.text((24, 16), 'LIE · mismo robot, cámara y pose', fill='#e4edf0', font=font(30))
    for index, (mode, label) in enumerate([('baseline', 'LIE 15 · base'), ('quality', 'LIE 16 · calidad estable')]):
        draw.text((index * width + 24, 65), label, fill='#74d8dc', font=font(24))
        image = Image.open(root / f'lie16-motion-{mode}-{frame:02d}.png').convert('RGB')
        if image.size != (width, width):
            image = image.resize((width, width), Image.Resampling.LANCZOS)
        card.paste(image, (index * width, 108))
    draw.text((24, width + 115), 'Fotogramas reales · cadencia de exportación: 25 fps · rendimiento de GPU física pendiente',
              fill='#a9bac4', font=font(18 if width >= 768 else 10))
    return card


def build(root, destination):
    root, destination = Path(root), Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    report = json.loads((root / 'lie16-diagnostic.json').read_text())
    count = report['paired_real_motion_frames']
    for mode in ['baseline', 'quality']:
        for frame in range(count):
            if not (root / f'lie16-motion-{mode}-{frame:02d}.png').is_file():
                raise ValueError('Missing real frame; never fabricate an intermediate image')
    raw = report['temporal']['raw_mean_rgb_variance']
    resolved = report['temporal']['resolved_mean_rgb_variance']
    variance_reduction = (1 - resolved / raw) * 100
    far = report['adaptive_work_and_image_error']['far']
    sample_reduction = (1 - far['adaptive_sample_invocations'] / far['full_sample_invocations']) * 100
    comparison = Image.new('RGB', (1536, 1460), '#101921')
    comparison.paste(make_card(root, 0), (0, 0))
    draw = ImageDraw.Draw(comparison)
    draw.text((24, 930), 'Detalle de la misma imagen · ampliación idéntica en ambos lados', fill='#e4edf0', font=font(24))
    # A fixed source rectangle and identical nearest filtering expose the real
    # reconstruction pixels rather than smoothing one side during assembly.
    for index, mode in enumerate(['baseline', 'quality']):
        image = Image.open(root / f'lie16-motion-{mode}-00.png').convert('RGB')
        detail = image.crop((240, 100, 528, 340)).resize((576, 480), Image.Resampling.NEAREST)
        comparison.paste(detail, (index * 768 + 96, 974))
    # Keep the complete detail panel and metrics without clipping.
    expanded = Image.new('RGB', (1536, 1572), '#101921')
    expanded.paste(comparison, (0, 0))
    draw = ImageDraw.Draw(expanded)
    draw.text((24, 1467), f'Escena quieta: {variance_reduction:.1f}% menos variación RGB entre fotogramas', fill='#74d8dc', font=font(23))
    draw.text((24, 1505), f'Cámara lejana: {sample_reduction:.1f}% menos muestras que LIE 16 con detalle completo', fill='#cbd6dd', font=font(21))
    draw.text((24, 1542), 'Son dos pruebas distintas. 128 px por captura · reconstrucción 384 px · Vulkan por software.', fill='#a9bac4', font=font(18))
    expanded.save(destination / 'lie16-comparacion.png')
    frames = []
    for frame in range(count):
        frames.append(make_card(root, frame, 384))
    frames[0].save(destination / 'lie16-movimiento.gif', save_all=True,
                   append_images=frames[1:], duration=40, loop=0, disposal=2, optimize=False)
    with tempfile.TemporaryDirectory(prefix='lie16-video-') as temp:
        for frame in range(count):
            make_card(root, frame).save(Path(temp) / f'frame-{frame:03d}.png')
        subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-framerate', '25',
                        '-i', str(Path(temp) / 'frame-%03d.png'), '-c:v', 'libx264', '-crf', '18',
                        '-preset', 'medium', '-pix_fmt', 'yuv420p', '-movflags', '+faststart',
                        str(destination / 'lie16-movimiento.mp4')], check=True)
    print(json.dumps({'frames': count, 'export_fps': 25, 'temporal_variance_reduction_percent': variance_reduction,
                      'far_sample_reduction_percent': sample_reduction, 'generated_frames': 0}))


if __name__ == '__main__':
    build(sys.argv[1], sys.argv[2])
