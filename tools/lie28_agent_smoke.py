"""Verify actual LIE28 desktop controls and rendered pixels in a disposable session."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import time
from collections import deque
import numpy as np
from PIL import Image
from lie_workshop_client import WorkshopClient, WorkshopBusy

def run(directory):
    directory=Path(directory);client=WorkshopClient(directory,120);checks=[]
    def check(ok,label):
        checks.append(dict(check=label,ok=bool(ok)))
        if not ok:raise AssertionError(label)
    def command(request,ok=True):
        # Busy means this request was never queued; a bounded retry is safe.
        # A timeout is deliberately not retried because it may still execute.
        for attempt in range(5):
            try:
                response=client.request(request);break
            except WorkshopBusy:
                if attempt==4:raise
                time.sleep(.25)
        check(response['result']['ok']==ok,'command '+request['op']);return response
    def capture(name,kind='compositor'):
        response=command(dict(op='capture',kind=kind,filename=name+'.png'))
        path=Path(response['result']['path']);image=np.asarray(Image.open(path).convert('RGBA'))
        check((image[:,:,3]>0).sum()>1000,'nonempty rendered '+name)
        return path,image
    initial=command(dict(op='snapshot'))
    check(initial['snapshot']['runtime']['gpu_ready'],'Vulkan compositor initialized')
    state=copy.deepcopy(initial['snapshot']['state'])
    check(set(state)==set(initial['snapshot']['capabilities']['fields']),'all controls discoverable')
    check(initial['snapshot']['metrics']['configured'],'complete house fits budget')
    capture('LIE28-Casa');capture('LIE28-Escritorio','window')
    changed=copy.deepcopy(state)
    changed.update(master='concrete_panel',camera_yaw=20,camera_elevation=30,distance_factor=1.1,
                   light_azimuth=45,light_power=.8,exposure=1.7,variation=.2,explode=.25,roof=False,shadows=False)
    check(command(dict(op='set_values',values=changed))['snapshot']['state']==changed,'all control fields round-trip')
    lit,_=capture('LIE28-Casa-Otra-Luz')
    check(lit.read_bytes()!=(directory/'LIE28-Casa.png').read_bytes(),'lighting and house controls change actual pixels')
    command(dict(op='set_values',values=state))
    command(dict(op='save_state',filename='house.lie.json'))
    for yaw,elevation,name in [(0,15,'LIE28-Casa-Frente'),(145,28,'LIE28-Casa-Atras'),(32,65,'LIE28-Casa-Sin-Techo')]:
        command(dict(op='set_values',values=dict(camera_yaw=yaw,camera_elevation=elevation,roof=name!='LIE28-Casa-Sin-Techo')))
        capture(name)
    command(dict(op='load_state',filename='house.lie.json'));restored,_=capture('LIE28-Casa-Restaurada')
    check(restored.read_bytes()==(directory/'LIE28-Casa.png').read_bytes(),'saved house restores identical image')
    before=command(dict(op='snapshot'))['snapshot']
    rejected=command(dict(op='set_values',values=dict(roof=1,explode=.5)),False)['snapshot']
    check(rejected['state']==before['state'] and rejected['revision']==before['revision'],'invalid edit is atomic')
    command(dict(op='set_values',values=dict(explode=.5),expected_revision=before['revision']-1),False)
    command(dict(op='set_values',values=dict(mode='wall',camera_yaw=0,camera_elevation=0,variation=0)))
    _,wall=capture('LIE28-Muro-Frente')
    # Independent perspective projection of clear door/window centres.
    denominator=(4.4-.06)*np.tan(np.deg2rad(42)/2)
    for x,y,label in [(-1,.96,'door'),(1,1.2,'window')]:
        px=round((x/denominator+1)*256);py=round((1-(y-1.15)/denominator)*256)
        check((wall[py-3:py+4,px-3:px+4,3]==0).all(),'clear '+label+' opening in actual compositor')
    px=round((-1/denominator+1)*256);py=round((1-(2.20-1.15)/denominator)*256)
    check((wall[py-3:py+4,px-3:px+4,3]>0).all(),'solid wall over door')
    command(dict(op='set_values',values=dict(camera_yaw=28,camera_elevation=15)));capture('LIE28-Muro')
    assets=[]
    for master in initial['snapshot']['control_contract']['masters']:
        command(dict(op='set_values',values=dict(mode='master',master=master,camera_yaw=28,camera_elevation=22,variation=0)))
        path,image=capture('LIE28-Maestro-'+master);assets.append(dict(master=master,sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    command(dict(op='set_values',values=dict(mode='fragments',explode=0,camera_yaw=28,camera_elevation=22,variation=0)))
    assembled,_=capture('LIE28-Ladrillo-Reunido')
    command(dict(op='set_values',values=dict(explode=1)));exploded,exploded_image=capture('LIE28-Ladrillo-Fragmentado')
    check(assembled.read_bytes()!=exploded.read_bytes(),'fragment transforms change real pixels')
    mask=exploded_image[:,:,3]>20;areas=[]
    while mask.any():
        y,x=np.argwhere(mask)[0];queue=deque([(y,x)]);mask[y,x]=False;area=0
        while queue:
            y,x=queue.popleft();area+=1
            for dy,dx in [(-1,0),(1,0),(0,-1),(0,1)]:
                a,b=y+dy,x+dx
                if 0<=a<mask.shape[0] and 0<=b<mask.shape[1] and mask[a,b]:mask[a,b]=False;queue.append((a,b))
        areas.append(area)
    check(sum(a>500 for a in areas)==4,'four distinct visible fragment pieces')
    command(dict(op='set_values',values=dict(explode=0)));again,_=capture('LIE28-Ladrillo-Reunido-Restaurado')
    check(assembled.read_bytes()==again.read_bytes(),'fragments return to identical assembled image')
    command(dict(op='load_state',filename='house.lie.json'))
    final=command(dict(op='snapshot'))['snapshot']
    check(final['runtime']['asset_uploads']==1,'single resident master bank across all views')
    check(final['metrics']['instances']<=128 and final['metrics']['sample_invocations']<=750000,'actual house respects instance and work budgets')
    capture('LIE28-Escritorio','window')
    for asset in assets:
        path=directory/('LIE28-Maestro-'+asset['master']+'.png')
        check(hashlib.sha256(path.read_bytes()).hexdigest()==asset['sha256'],'stable complete capture '+asset['master'])
    report=dict(checks=checks,passed=len(checks),assets=assets,final_snapshot=final,
                note='Native Godot desktop / actual software Vulkan (llvmpipe). No physical GPU speed claim.')
    (directory/'lie28-agent-verification.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(dict(passed=len(checks),metrics=final['metrics'])))
    return report

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--directory',required=True,type=Path)
    run(parser.parse_args().directory)
