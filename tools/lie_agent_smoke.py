"""Exercise a running native LIE-27 desktop through the external agent client.

Use a disposable fresh application session: this test changes every control,
restores saved states, captures images and navigates between laboratories.
"""
from __future__ import annotations
import argparse,copy,hashlib,json,time
from pathlib import Path
from lie_workshop_client import WorkshopClient

def run(directory: Path,timeout: float=90) -> dict:
    client=WorkshopClient(directory,timeout);checks=[]
    def check(ok,label):
        checks.append({'check':label,'ok':bool(ok)})
        if not ok:raise AssertionError(label)
    def command(request,ok=True):
        response=client.request(request);check(response['result']['ok']==ok,'command '+request['op']);return response
    def ready():
        deadline=time.monotonic()+timeout
        while time.monotonic()<deadline:
            response=command({'op':'snapshot'})
            if response['snapshot']['runtime']['gpu_ready']:return response
            time.sleep(.2)
        raise TimeoutError('Renderer did not become ready')
    start=ready();initial=copy.deepcopy(start['snapshot']['state']);session=start['snapshot']['session_id']
    capabilities=start['snapshot']['capabilities']
    check(set(capabilities['fields'])==set(initial),'all current control fields discoverable')
    check(len(capabilities['face_keys'])==7 and 'right_index' in capabilities['pose_limits'],'face and digit control ranges discoverable')
    values=copy.deepcopy(initial)
    values.update(mask=15,camera_yaw=12,object_yaw=5,light_azimuth=25,light_power=80,distance=.4,
                  unlit=True,shadows=True,light_color=[.9,.8,.7],pose={'head_yaw':5,'right_index':20},targets={},
                  mode='manual',playing=False,time=.5,speed=.8,focus='face',show_regions=True,face_playing=False,brows=False)
    values['palette'][0]=[.55,.30,.19];values['eyes']['iris']=[.025,.12,.42]
    values['face']={key:.2 for key in capabilities['face_keys']}
    changed=command({'op':'set_values','values':values,'expected_revision':start['snapshot']['revision'],'expected_session':session,'expected_lab':'lie27'})
    check(changed['snapshot']['state']==values,'all desktop controls round-trip through the actual lab')
    target={'right_hand':{'position':[-.25,1.2,.36],'pole':[-.5,.8,.5]}}
    ik=command({'op':'set_values','values':{'targets':target}})
    check(ik['snapshot']['state']['targets']==target,'IK targets round-trip to native rig controls')
    changed=command({'op':'set_values','values':{'targets':{},'mode':'walk','playing':True,'face_playing':True}})
    moving_time=changed['snapshot']['state']['time'];time.sleep(.3)
    moving=command({'op':'snapshot'})
    check(moving['snapshot']['state']['time']!=moving_time,'walking and blink playback advance in the desktop process')
    changed=command({'op':'set_values','values':{'mode':'manual','playing':False,'face_playing':False}})
    before=changed['snapshot']['state'];revision=changed['snapshot']['revision']
    rejected=command({'op':'set_values','values':{'brows':1,'light_power':0}},False)
    check(rejected['snapshot']['state']==before and rejected['snapshot']['revision']==revision,'invalid transaction leaves complete state unchanged')
    stale=command({'op':'set_values','values':{'brows':True},'expected_revision':revision-1},False)
    check(stale['snapshot']['state']==before,'stale revision leaves state unchanged')
    command({'op':'set_values','values':initial})
    command({'op':'set_values','values':{'focus':'face','distance':.35,'show_regions':False,'unlit':False}})
    saved=command({'op':'save_state','filename':'verified-face.lie.json'})
    face_state=copy.deepcopy(saved['snapshot']['state'])
    open_capture=command({'op':'capture','filename':'agent-face-open.png'})
    window=command({'op':'capture','kind':'window','filename':'agent-desktop.png'})
    check(open_capture['result']['width']==512 and window['result']['width']>=1000,'compositor and actual desktop window captured')
    face=copy.deepcopy(face_state['face']);face['blink_left']=face['blink_right']=1
    command({'op':'set_values','values':{'face':face}})
    closed=command({'op':'capture','filename':'agent-face-closed.png'})
    open_hash=hashlib.sha256(Path(open_capture['result']['path']).read_bytes()).hexdigest()
    closed_hash=hashlib.sha256(Path(closed['result']['path']).read_bytes()).hexdigest()
    check(open_hash!=closed_hash,'external eyelid command changes rendered pixels')
    command({'op':'load_state','filename':'verified-face.lie.json'})
    restored=command({'op':'capture','filename':'agent-face-restored.png'})
    check(hashlib.sha256(Path(restored['result']['path']).read_bytes()).hexdigest()==open_hash,'save/load restores identical compositor image')
    command({'op':'capture','filename':'../escape.png'},False)
    command({'op':'set_pose','values':{'right_index':30,'head_yaw':15}})
    check(command({'op':'snapshot'})['snapshot']['state']['pose']['right_index']==30,'digit and head controls share native UI state')
    command({'op':'load_state','filename':'verified-face.lie.json'})
    token=command({'op':'snapshot'})['snapshot']['session_id']
    moved=command({'op':'open_lab','lab':'lie25'})
    check(moved['snapshot']['lab']=='lie25' and moved['snapshot']['session_id']!=token,'same endpoint survives laboratory navigation')
    command({'op':'set_values','values':{'mask':1},'expected_session':token},False)
    command({'op':'open_lab','lab':'lie27'});ready()
    command({'op':'load_state','filename':'verified-face.lie.json'})
    final=command({'op':'snapshot'})
    check(final['snapshot']['state']==face_state,'saved face survives scene destruction and reopening')
    check(final['snapshot']['runtime']['asset_uploads']==1,'current desktop bank remains resident after reopening')
    report={'protocol':'lie-agent-session-v1','checks':checks,'passed':len(checks),'failed':False,
            'final_snapshot':final['snapshot'],'open_sha256':open_hash,'closed_sha256':closed_hash,
            'note':'Native desktop on software Vulkan; no physical GPU performance or external mouse automation claim.'}
    (directory/'agent-verification.json').write_text(json.dumps(report,indent=2))
    return report

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--directory',type=Path,required=True);parser.add_argument('--timeout',type=float,default=90)
    args=parser.parse_args();result=run(args.directory,args.timeout)
    print(json.dumps({'passed':result['passed'],'failed':False,'lab':result['final_snapshot']['lab']},indent=2))

if __name__=='__main__':main()
