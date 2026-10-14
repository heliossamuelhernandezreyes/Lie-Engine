"""Close exactly one disposable Lie session through its validated protocol.

No process signal or broad kill is used. The session identity is required;
Xvfb must remain alive until Godot has released the scene and exited.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import sys
import time
from lie_workshop_client import WorkshopClient


def running(pid: int) -> bool:
    # The launcher may have exited; a reparented zombie is already stopped.
    stat=Path(f'/proc/{pid}/stat')
    try:
        return stat.read_text().rsplit(')',1)[1].split()[0]!='Z'
    except FileNotFoundError:
        return False


def stop(directory: Path,timeout: float=30) -> dict:
    if sys.platform!='linux':raise RuntimeError('This CI helper currently requires Linux /proc; use the shutdown protocol directly on other platforms')
    session=json.loads((directory/'session.json').read_text())
    pid=session['pid']
    if not isinstance(pid,int) or isinstance(pid,bool) or pid<=0:
        raise ValueError('Invalid session PID')
    client=WorkshopClient(directory,timeout=timeout)
    response=client.request({'op':'shutdown','expected_session':session['session_id']})
    if not response.get('result',{}).get('ok'):
        raise RuntimeError('Shutdown rejected: '+json.dumps(response))
    deadline=time.monotonic()+timeout
    while running(pid):
        if time.monotonic()>=deadline:raise TimeoutError(f'Session {pid} did not exit; Xvfb must stay alive')
        time.sleep(.1)
    return {'ok':True,'pid':pid,'session_id':session['session_id'],'stopped':True}


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory',type=Path,required=True)
    parser.add_argument('--timeout',type=float,default=30)
    args=parser.parse_args()
    print(json.dumps(stop(args.directory,args.timeout),sort_keys=True))
