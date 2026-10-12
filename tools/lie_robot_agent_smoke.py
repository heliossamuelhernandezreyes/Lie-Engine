"""Exercise the real robot desktop, retain views and a deterministic walk cycle."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import time
import numpy as np
from PIL import Image
from lie_workshop_client import WorkshopClient,WorkshopBusy

def run(directory):
    directory=Path(directory);client=WorkshopClient(directory,120);checks=[];captures=[]
    def check(ok,label):
        checks.append(dict(check=label,ok=bool(ok)))
        if not ok:raise AssertionError(label)
    def command(request,ok=True):
        for attempt in range(5):
            try:r=client.request(request);break
            except WorkshopBusy:
                if attempt==4:raise
                time.sleep(.25)
        check(r['result']['ok']==ok,'command '+request['op']);return r
    def capture(name,kind='compositor'):
        response=command(dict(op='capture',kind=kind,filename=name+'.png'));path=Path(response['result']['path'])
        pixels=np.asarray(Image.open(path).convert('RGBA'));check((pixels[:,:,3]>20).sum()>1000,'actual nonempty '+name)
        item=dict(name=path.name,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),kind=kind,revision=response['snapshot']['revision'],state=copy.deepcopy(response['snapshot']['state']))
        captures.append(item);return path,response
    initial=command(dict(op='snapshot'))['snapshot'];state=copy.deepcopy(initial['state'])
    check(initial['runtime']['gpu_ready'] and initial['metrics']['configured'],'actual robot GPU initialized')
    check(set(initial['capabilities']['fields'])==set(state),'all control fields discoverable')
    check(len(initial['capabilities']['pose_limits'])==len(initial['control_contract']['pose_limits']),'semantic joint limits discoverable')
    capture('R1-Robot');capture('R1-Escritorio','window');command(dict(op='save_state',filename='r1-rest.lie.json'))
    (directory/'r1-assembly.json').write_text(json.dumps(initial,indent=2)+'\n')
    changed=copy.deepcopy(state);changed.update(mode='reach',focus='arm',master='joint',camera_yaw=20,camera_elevation=12,distance_factor=.9,light_azimuth=55,light_power=.8,exposure=1.15,variation=.12,time=.2,speed=.8,grip=.8,
        playing=False,cables=False,floor=False,shadows=False,foot_ik=False,unlit=True,coat_color=[.9,.8,.7],pose={'right_elbow':95,'left_elbow':35},targets={})
    check(command(dict(op='set_values',values=changed))['snapshot']['state']==changed,'every state field round-trips')
    capture('R1-Brazo-Albedo')
    command(dict(op='load_state',filename='r1-rest.lie.json'));restored,_=capture('R1-Robot-Restaurado')
    check(restored.read_bytes()==(directory/'R1-Robot.png').read_bytes(),'save/load restores identical full robot image')
    before=command(dict(op='snapshot'))['snapshot'];bad=command(dict(op='set_values',values=dict(cables=1,grip=.5)),False)['snapshot']
    check(bad['state']==before['state'] and bad['revision']==before['revision'],'invalid edit is atomic')
    command(dict(op='set_pose',values={'right_elbow':200}),False)
    command(dict(op='set_values',values=dict(grip=.5),expected_revision=before['revision']-1),False)
    command(dict(op='capture',filename='../escape.png'),False)
    for yaw,elevation,name in [(0,7,'R1-Frente'),(145,12,'R1-Espalda'),(-70,10,'R1-Lateral')]:
        command(dict(op='set_values',values=dict(camera_yaw=yaw,camera_elevation=elevation)));capture(name)
    command(dict(op='load_state',filename='r1-rest.lie.json'))
    command(dict(op='set_values',values=dict(focus='head',camera_yaw=18,camera_elevation=5)));capture('R1-Cabeza')
    command(dict(op='set_values',values=dict(focus='arm',camera_yaw=25,camera_elevation=12)));straight,_=capture('R1-Brazo')
    command(dict(op='set_pose',values={'right_elbow':110,'right_shoulder':25,'right_wrist':-20}));command(dict(op='set_values',values=dict(grip=.85)))
    bent,response=capture('R1-Brazo-Flexionado');check(bent.read_bytes()!=straight.read_bytes(),'elbow/wrist/grip change rendered pixels')
    for p in response['snapshot']['cable_paths']:
        check(not p['clamped'] and abs(p['length']-p['requested_length'])<.0001,'cable guide preserves calibrated length')
    for master in initial['control_contract']['masters']:
        if master=='ground':continue
        command(dict(op='set_values',values=dict(focus='master',master=master,camera_yaw=25,camera_elevation=12,distance_factor=1.0,unlit=False)))
        capture('R1-Maestro-'+master)
    command(dict(op='load_state',filename='r1-rest.lie.json'));command(dict(op='set_values',values=dict(mode='walk',playing=False,camera_yaw=25,floor=True)))
    frames=[];frame_snapshots=[]
    for i in range(16):
        command(dict(op='set_values',values=dict(time=i/16)));path,response=capture(f'R1-Paso-{i:02d}');frames.append(path.name);frame_snapshots.append(response['snapshot'])
        for target in response['snapshot']['metrics']['ik'].values():check(target['residual_m']<.003 and not target['clamped'],'walking foot targets remain reachable')
    check(len({hashlib.sha256((directory/p).read_bytes()).hexdigest() for p in frames})>8,'walk cycle changes actual articulated geometry')
    start=command(dict(op='set_values',values=dict(playing=True)))['snapshot']['state']['time'];time.sleep(.3)
    end=command(dict(op='snapshot'))['snapshot']['state']['time'];check(start!=end,'native playback advances')
    command(dict(op='set_values',values=dict(playing=False)));command(dict(op='load_state',filename='r1-rest.lie.json'));capture('R1-Escritorio-Final','window')
    final=command(dict(op='snapshot'))['snapshot'];check(final['runtime']['asset_uploads']==1,'one resident bank throughout all modes')
    check(final['metrics']['instances']<=128 and final['metrics']['sample_invocations']<=750000 and final['metrics']['visible_source_meshes']==0,'actual assembly respects budgets without source-mesh draw')
    for item in captures:
        check(hashlib.sha256((directory/item['name']).read_bytes()).hexdigest()==item['sha256'],'stable complete capture '+item['name'])
    report=dict(checks=checks,passed=len(checks),captures=captures,walk_frames=frames,final_snapshot=final,note='Actual Godot desktop / Vulkan llvmpipe. No physical GPU or Android performance claim.')
    (directory/'robot-agent-verification.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(dict(passed=len(checks),metrics=final['metrics'])))
    (directory/'r1-walk-assembly.json').write_text(json.dumps(frame_snapshots,indent=2)+'\n')
    return report

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--directory',required=True,type=Path);run(parser.parse_args().directory)
