"""Assemble only actual matched renderer frames; export cadence is not engine FPS."""
import json
import subprocess
import sys
import tempfile
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont


def font(size):
    return ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', size)


def card(root, frame, width=768):
    output = Image.new('RGB', (width * 2, width + 144), '#101921')
    draw = ImageDraw.Draw(output)
    scale = width / 768
    draw.text((24, 16), 'LIE 17 · misma entrada, suavizado opcional', fill='#e4edf0', font=font(round(30 * scale)))
    for index, (mode, label) in enumerate([('off', 'Filtro apagado'), ('on', 'Filtro encendido')]):
        draw.text((index * width + 24, 65), label, fill='#74d8dc', font=font(round(24 * scale)))
        image = Image.open(root / f'lie17-motion-{mode}-{frame:02d}.png').convert('RGB')
        image = image.resize((width, width), Image.Resampling.LANCZOS)
        output.paste(image, (index * width, 108))
    draw.text((24, width + 115), 'Fotogramas reales · exportación 25 fps · temporal apagado para aislar el filtro',
              fill='#a9bac4', font=font(18 if width == 768 else 10))
    return output


def build(root, destination):
    root, destination = Path(root), Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    report = json.loads((root / 'lie17-diagnostic.json').read_text())
    count = report['paired_real_motion_frames']
    for mode in ['off', 'on']:
        for frame in range(count):
            if not (root / f'lie17-motion-{mode}-{frame:02d}.png').is_file():
                raise ValueError('Missing actual frame; never fabricate an intermediate image')
    reduction = 100 * (1 - report['analytic_diagonal_mean_rmse_with_filter'] /
                       report['analytic_diagonal_mean_rmse_without_filter'])
    comparison = Image.new('RGB', (1536, 1572), '#101921')
    comparison.paste(card(root, 0), (0, 0))
    draw = ImageDraw.Draw(comparison)
    draw.text((24, 930), 'Detalle · mismo recorte y misma ampliación en ambos lados', fill='#e4edf0', font=font(24))
    for index, mode in enumerate(['off', 'on']):
        image = Image.open(root / f'lie17-motion-{mode}-00.png').convert('RGB')
        detail = image.crop((240, 100, 528, 340)).resize((576, 480), Image.Resampling.NEAREST)
        comparison.paste(detail, (index * 768 + 96, 974))
    draw.text((24, 1467), f'Tres diagonales sintéticas: {reduction:.1f}% menos error medio frente al área exacta del píxel',
              fill='#74d8dc', font=font(21))
    draw.text((24, 1505), 'Ese porcentaje es del oráculo sintético, no una medida global de calidad del robot.',
              fill='#cbd6dd', font=font(20))
    draw.text((24, 1542), '128 px por captura · reconstrucción 384 px · Vulkan por software · filtro con coste adicional',
              fill='#a9bac4', font=font(18))
    comparison.save(destination / 'lie17-comparacion.png')
    frames = [card(root, frame, 384) for frame in range(count)]
    frames[0].save(destination / 'lie17-movimiento.gif', save_all=True, append_images=frames[1:],
                   duration=40, loop=0, disposal=2, optimize=False)
    with tempfile.TemporaryDirectory(prefix='lie17-video-') as temp:
        for frame in range(count):
            card(root, frame).save(Path(temp) / f'frame-{frame:03d}.png')
        subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-framerate', '25',
                        '-i', str(Path(temp) / 'frame-%03d.png'), '-c:v', 'libx264', '-crf', '18',
                        '-pix_fmt', 'yuv420p', '-movflags', '+faststart',
                        str(destination / 'lie17-movimiento.mp4')], check=True)
    print(json.dumps({'frames': count, 'export_fps': 25, 'generated_frames': 0,
                      'analytic_diagonal_error_reduction_percent': reduction}))


if __name__ == '__main__':
    build(sys.argv[1], sys.argv[2])
