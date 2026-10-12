"""Launch a native Lie laboratory with a discoverable local agent session."""
from __future__ import annotations
import argparse,json,subprocess,sys,time
from pathlib import Path

LABS={"workshop":"lie18_workshop.tscn",**{f"lie{i}":name for i,name in [(20,"lie20_human_lab.tscn"),(21,"lie21_human_lab.tscn"),(22,"lie22_modular_lab.tscn"),(23,"lie23_face_lab.tscn"),(24,"lie24_modular_face_lab.tscn"),(25,"lie25_anatomy_lab.tscn"),(26,"lie26_motion_lab.tscn"),(27,"lie27_regions_lab.tscn")]}}

def launch(godot: str,project: Path,directory: Path,lab: str,timeout: float=60,audio_driver: str|None=None) -> dict:
    project=project.resolve();directory=directory.resolve()
    if not (project/'project.godot').is_file():raise ValueError('Use the gpu_compute Godot project.')
    directory.mkdir(parents=True,exist_ok=True)
    existing=directory/'session.json'
    if existing.exists():raise ValueError('Use a fresh session directory; an earlier session may still be running.')
    log=directory/'godot.log'
    with log.open('wb') as stream:
        options=['--audio-driver',audio_driver] if audio_driver else []
        process=subprocess.Popen([godot,'--path',str(project),'--rendering-driver','vulkan','--rendering-method','forward_plus',*options,'res://'+LABS[lab],'--','--lie-agent-directory',str(directory)],stdout=stream,stderr=subprocess.STDOUT)
    deadline=time.monotonic()+timeout
    while time.monotonic()<deadline:
        if process.poll() is not None:raise RuntimeError(f'Godot exited with {process.returncode}; see {log}')
        try:
            data=json.loads(existing.read_text())
            if data.get('pid')==process.pid and data.get('lab')==lab:
                return {'pid':process.pid,'directory':str(directory),'session':data,'log':str(log)}
        except (FileNotFoundError,json.JSONDecodeError):pass
        time.sleep(.1)
    # Do not terminate a running user's application or launch a duplicate.
    raise TimeoutError(f'Godot is still running as pid {process.pid}; inspect {log} and {directory} before retrying.')

def main() -> int:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot',default='godot');parser.add_argument('--project',type=Path,default=Path(__file__).resolve().parents[1]/'gpu_compute')
    parser.add_argument('--lab',choices=LABS,default='lie27');parser.add_argument('--directory',type=Path,required=True);parser.add_argument('--timeout',type=float,default=60)
    parser.add_argument('--audio-driver',help='Optional Godot audio driver, e.g. Dummy for a renderer-only CI desktop')
    args=parser.parse_args()
    try:
        print(json.dumps(launch(args.godot,args.project,args.directory,args.lab,args.timeout,args.audio_driver),indent=2));return 0
    except (OSError,ValueError,RuntimeError,TimeoutError) as error:
        print(json.dumps({'ok':False,'error':str(error)}),file=sys.stderr);return 2

if __name__=='__main__':raise SystemExit(main())
