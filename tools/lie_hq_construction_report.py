"""Contact sheets of actual native captures and matched source ray references."""
import argparse,json
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
FONT='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
BG=(24,30,38);PANEL=(34,41,50)
def font(n):return ImageFont.truetype(FONT,n)
def paste(canvas,path,rect):
    im=Image.open(path).convert('RGBA');bounds=im.getchannel('A').getbbox()
    if bounds:im=im.crop(bounds)
    x,y,w,h=rect;im.thumbnail((w-24,h-24),Image.Resampling.LANCZOS);panel=Image.new('RGBA',(w,h),PANEL+(255,));panel.alpha_composite(im,((w-im.width)//2,(h-im.height)//2));canvas.paste(panel.convert('RGB'),(x,y))
def build(stage,comparison,out):
    out.mkdir(parents=True,exist_ok=True);canvas=Image.new('RGB',(1600,1530),BG);d=ImageDraw.Draw(canvas)
    d.text((35,24),'LIE · CONSTRUCCIÓN / v5',font=font(38),fill='white');d.text((35,77),'Capturas nativas Vulkan · Formas 3D detalladas y materiales fotográficos 8K',font=font(22),fill='#c7d1dc')
    for x,name,label in [(30,'corner-front','Esquina intercalada · abertura real'),(815,'corner-back','Reverso · profundidad conservada')]:
        paste(canvas,stage/(name+'.png'),(x,126,755,750));d.text((x,888),label,font=font(24),fill='white')
    for x,name,label in [(30,'opening-front','Dintel, alféizar y marco'),(550,'roof-front','Cubierta de tablillas de madera'),(1070,'door-open','Puerta con giro rígido')]:
        paste(canvas,stage/(name+'.png'),(x,946,500,450));d.text((x,1410),label,font=font(20),fill='white')
    d.text((30,1460),'Nuevos perfiles de autoría; no son nuevos escaneos completos. Sin vidrio ni herrajes metálicos.',font=font(20),fill='#b9c6d4');d.text((30,1492),'Powered by Poly Haven · Ladrillo: Centre-of-Archaeology (CC BY 4.0)',font=font(18),fill='#a1b0bf');canvas.save(out/'LIE_Construccion_v5.png')
    names=['mortar_bed','concrete_lintel','wood_beam'];canvas=Image.new('RGB',(1600,1450),BG);d=ImageDraw.Draw(canvas);d.text((30,24),'LIE · FUENTE FRENTE A RECONSTRUCCIÓN',font=font(32),fill='white');d.text((30,72),'Misma cámara, luz y material · Referencia por rayos sobre los triángulos originales',font=font(22),fill='#c7d1dc');d.text((30,114),'Izquierda: fuente 3D + fotografías   |   Derecha: captura LIE de 120 000 muestras',font=font(21),fill='#d5dce6')
    for i,name in enumerate(names):
        prefix='quality_'+name+'_front';row=json.loads((comparison/(prefix+'.json')).read_text());y=170+i*390
        d.text((30,y),{'mortar_bed':'Mortero fotografiado de una junta real','concrete_lintel':'Concreto · dintel','wood_beam':'Madera · viga'}[name],font=font(25),fill='white')
        for x,path in [(30,comparison/(prefix+'-reference.png')),(815,stage/(prefix+'.png'))]:paste(canvas,path,(x,y+45,755,270))
        d.text((30,y+330),f"Cobertura interior: {row['interior_coverage']*100:.2f} %  ·  PSNR RGB: {row['rgb_psnr_db']:.2f} dB  ·  Error de profundidad: {row['depth_rmse_m']*1000:.3f} mm",font=font(21),fill='#b9c6d4')
    d.text((30,1360),'La reconstrucción pierde parte del microdetalle. Esta prueba no certifica hiperrealismo.',font=font(22),fill='#dfc490');d.text((30,1400),'Referencia independiente de las muestras LIE · Sin sombras en esta comparación · Powered by Poly Haven',font=font(18),fill='#a1b0bf');canvas.save(out/'LIE_Calidad_v5.png')
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--stage',type=Path,required=True);p.add_argument('--comparison',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();build(a.stage,a.comparison,a.output)
