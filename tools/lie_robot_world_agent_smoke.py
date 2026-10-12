"""Verify a disposable native collision world and retain its actual journey frames."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import time
import numpy as np
from PIL import Image
from lie_workshop_client import WorkshopClient,WorkshopBusy

def same_state(a,b):
    # Godot JSON decimal parsing can shift a double by one ULP. Structure,
    # booleans and integers stay exact; numeric tolerance is far below f32 poses.
    if isinstance(a,bool) or isinstance(b,bool):return type(a)==type(b) and a==b
    if isinstance(a,(int,float)) and isinstance(b,(int,float)):return abs(a-b)<=1e-12
    if isinstance(a,dict) and isinstance(b,dict):return a.keys()==b.keys() and all(same_state(a[k],b[k]) for k in a)
    if isinstance(a,list) and isinstance(b,list):return len(a)==len(b) and all(same_state(x,y) for x,y in zip(a,b))
    return type(a)==type(b) and a==b

def run(directory):
    directory=Path(directory);client=WorkshopClient(directory,120);checks=[];captures=[];journey=[];poses=[]
    def check(ok,label):
        checks.append(dict(check=label,ok=bool(ok)))
        if not ok:raise AssertionError(label)
    def command(request,ok=True):
        for attempt in range(5):
            try:r=client.request(request);break
            except WorkshopBusy:
                if attempt==4:raise
                time.sleep(.2)
        check(r['result']['ok']==ok,'command '+request['op']);return r
    def capture(name,kind='compositor'):
        r=command(dict(op='capture',kind=kind,filename=name+'.png'));path=Path(r['result']['path'])
        rgba=np.asarray(Image.open(path).convert('RGBA'));check((rgba[:,:,3]>.5).sum()>1000,'actual rendered '+name)
        captures.append(dict(name=path.name,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),kind=kind,state=copy.deepcopy(r['snapshot']['state'])))
        return path,r['snapshot']
    def advance(ticks):
        r=command(dict(op='advance',ticks=ticks));target=r['result']['target_tick'];deadline=time.monotonic()+120
        while time.monotonic()<deadline:
            s=command(dict(op='snapshot'))['snapshot']
            if s['motion']['remaining_ticks']==0:break
            time.sleep(.04)
        check(s['motion']['remaining_ticks']==0 and s['state']['motion']['ticks']==target,'exact completed physics ticks')
        for ik in s['metrics']['ik'].values():check(ik['residual_m']<.003 and not ik['clamped'],'reachable actual collision pose')
        return s
    initial=command(dict(op='describe'))['snapshot'];state=copy.deepcopy(initial['state'])
    (directory/'r2-world-assembly.json').write_text(json.dumps(initial,indent=2)+'\n')
    check(initial['runtime']['gpu_ready'] and initial['metrics']['configured'],'real combined compositor ready')
    check(set(initial['capabilities']['fields'])==set(state),'every state field discoverable')
    check({'advance','reset','set_values'}.issubset(initial['commands']),'locomotion commands discoverable')
    first,_=capture('R2-Entrada');capture('R2-Escritorio','window');command(dict(op='save_state',filename='r2-entry.lie.json'))
    changed=copy.deepcopy(state);changed.update(move=[.2,.4],turn=.25,walk_speed=1.0,playing=False,view='overview',camera_yaw=22,camera_elevation=52,camera_distance=4.1,light_azimuth=35,light_power=.8,exposure=1.2,grip=.8,roof=True,shadows=False,cables=False,unlit=True)
    check(same_state(command(dict(op='set_values',values=changed))['snapshot']['state'],changed),'complete declared fields round-trip')
    capture('R2-Cubierta-Albedo');command(dict(op='load_state',filename='r2-entry.lie.json'));restored,_=capture('R2-Entrada-Restaurada')
    check(restored.read_bytes()==first.read_bytes(),'complete save/load restores exact pixels')
    before=command(dict(op='snapshot'))['snapshot'];bad=command(dict(op='set_values',values=dict(move=[0,2],grip=.9)),False)['snapshot']
    check(before['state']==bad['state'] and before['revision']==bad['revision'],'invalid input atomic')
    command(dict(op='advance',ticks=0),False);command(dict(op='set_values',values=dict(turn=.1),expected_revision=before['revision']-1),False)
    command(dict(op='capture',filename='../escape.png'),False)
    command(dict(op='set_values',values=dict(view='overview',camera_yaw=15,camera_elevation=55)));capture('R2-Casa')
    command(dict(op='load_state',filename='r2-entry.lie.json'));command(dict(op='set_values',values=dict(move=[0,1])))
    for i in range(32):
        s=advance(8);path,s=capture(f'R2-Recorrido-{i:02d}');journey.append(path.name);poses.append(s)
        check(s['state']['motion']['grounded'],'character supported by actual floor')
    position=s['state']['motion']['position'];check(position[2]<.3 and position[2]>-1.4,'robot crosses source doorway into house')
    check(s['state']['motion']['travel']>3,'actual traversed metres')
    command(dict(op='set_values',values=dict(view='overview',camera_yaw=10,camera_elevation=60)));capture('R2-Interior')
    command(dict(op='set_values',values=dict(view='third_person',camera_yaw=-90,camera_elevation=15)));advance(180);_,wall=capture('R2-Pared-Detiene-Robot')
    check(wall['state']['motion']['position'][2]>-1.46,'back wall stops travel')
    old=copy.deepcopy(wall['state']['motion']);after=advance(60)['state']['motion']
    check(np.linalg.norm(np.array(old['position'])-after['position'])<.003 and abs(old['phase']-after['phase'])<.00001,'blocked movement does not march in place')
    check(wall['camera']['fraction']<.95,'real third-person camera obstruction')
    command(dict(op='set_values',values=dict(move=[0,0],playing=True)));ticks=command(dict(op='snapshot'))['snapshot']['state']['motion']['ticks'];time.sleep(.3)
    check(command(dict(op='snapshot'))['snapshot']['state']['motion']['ticks']>ticks,'native live physics advances')
    command(dict(op='set_values',values=dict(playing=False)))
    saved=command(dict(op='save_state',filename='r2-interior.lie.json'))['snapshot']['state'];saved_image,_=capture('R2-Interior-Guardado');capture('R2-Escritorio-Interior','window')
    # Navigation and original authoring packets remain available through the same bridge.
    command(dict(op='open_lab',lab='robot'));s=command(dict(op='snapshot'))['snapshot'];check(s['lab']=='robot','existing robot editor reachable')
    (directory/'r1-assembly.json').write_text(json.dumps(s,indent=2)+'\n');capture('R2-Robot-Pulido')
    command(dict(op='set_values',values=dict(focus='arm',camera_yaw=20,camera_elevation=10,grip=0)));a,_=capture('R2-Pinza-Abierta')
    command(dict(op='set_values',values=dict(grip=.95)));b,_=capture('R2-Pinza-Cerrada');check(a.read_bytes()!=b.read_bytes(),'opposing gripper changes actual geometry')
    command(dict(op='set_values',values=dict(focus='body',mode='walk',playing=False)))
    walk=[]
    for i in range(16):walk.append(command(dict(op='set_values',values=dict(time=i/16)))['snapshot'])
    (directory/'r1-walk-assembly.json').write_text(json.dumps(walk,indent=2)+'\n')
    command(dict(op='open_lab',lab='robot_world'));command(dict(op='load_state',filename='r2-interior.lie.json'))
    resumed,_=capture('R2-Interior-Restaurado');check(resumed.read_bytes()==saved_image.read_bytes(),'moving-world restore after navigation retains exact pixels')
    final=command(dict(op='snapshot'))['snapshot'];check(final['lab']=='robot_world' and same_state(final['state'],saved),'same bridge restores complete moving-world state after navigation')
    check(final['runtime']['asset_uploads']==1 and final['metrics']['instances']<=192 and final['metrics']['sample_invocations']<=1300000,'one resident bank and declared combined budget')
    for item in captures:check(hashlib.sha256((directory/item['name']).read_bytes()).hexdigest()==item['sha256'],'stable complete capture '+item['name'])
    report=dict(passed=len(checks),checks=checks,captures=captures,journey_frames=journey,journey_positions=[x['state']['motion']['position'] for x in poses],final_snapshot=final,note='Actual Godot native desktop, CharacterBody3D physics and Vulkan llvmpipe. No Android/physical GPU FPS claim.')
    (directory/'r2-native-verification.json').write_text(json.dumps(report,indent=2)+'\n')
    (directory/'r2-journey-assembly.json').write_text(json.dumps(poses,indent=2)+'\n')
    print(json.dumps(dict(passed=len(checks),frames=len(journey),metrics=final['metrics'])),flush=True)
    return report

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--directory',required=True,type=Path);run(parser.parse_args().directory)
