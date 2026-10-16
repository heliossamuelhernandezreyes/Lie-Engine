"""Reproducible GDExtension builds; no vendor binaries or device permissions bundled."""
import argparse,hashlib,json,os,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
DEPENDENCIES={
    'godot-cpp':('https://github.com/godotengine/godot-cpp.git','e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77'),
    'libGPUCounters':('https://github.com/ARM-software/libGPUCounters.git','378c7b59e2dae87cbbffb0ac9cf96ed13c939823'),
}
def run(args,**kw):return subprocess.run(list(map(str,args)),check=True,**kw)
def dependencies(cache):
    paths={}
    for name,(url,sha) in DEPENDENCIES.items():
        path=cache/name
        if not (path/'.git').exists():
            path.mkdir(parents=True,exist_ok=True);run(['git','init',path]);run(['git','-C',path,'remote','add','origin',url])
        run(['git','-C',path,'fetch','--depth','1','origin',sha]);run(['git','-C',path,'checkout','--detach',sha])
        assert subprocess.check_output(['git','-C',str(path),'rev-parse','HEAD'],text=True).strip()==sha
        assert not subprocess.check_output(['git','-C',str(path),'status','--porcelain'],text=True).strip()
        paths[name]=path
    return paths
def build(cache,platform,ndk=None):
    paths=dependencies(cache);dest=ROOT/'gpu_compute/addons/lie_gpu_probe';build_dir=cache/('build-'+platform)
    args=['cmake','-S',ROOT/'native/hardware_probe','-B',build_dir,'-DCMAKE_BUILD_TYPE=Release','-DCMAKE_POLICY_VERSION_MINIMUM=3.5',f'-DLIE_GODOT_CPP={paths["godot-cpp"]}',f'-DLIE_GPU_COUNTERS={paths["libGPUCounters"]}']
    if platform=='android.arm64':
        if not ndk:raise ValueError('NDK path required')
        args += [f'-DCMAKE_TOOLCHAIN_FILE={ndk}/build/cmake/android.toolchain.cmake','-DANDROID_ABI=arm64-v8a','-DANDROID_PLATFORM=android-26','-DANDROID_STL=c++_static','-DGODOTCPP_PLATFORM=android','-DGODOTCPP_ARCH=arm64']
    run(args);run(['cmake','--build',build_dir,'-j','4'])
    output=dest/'bin'/platform/'liblie_gpu_probe.so';output.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(build_dir/'liblie_gpu_probe.so',output)
    # Activate only after a real native build. An ordinary source checkout must
    # remain usable by laboratories which do not build this optional module.
    shutil.copy2(ROOT/'native/hardware_probe/lie_gpu_probe.gdextension.in',dest/'lie_gpu_probe.gdextension')
    licenses=dest/'licenses';licenses.mkdir(exist_ok=True)
    for name,path in paths.items():
        source=next((path/n for n in ['LICENSE','LICENSE.txt','LICENSE.md'] if (path/n).exists()),None)
        if source is None:raise ValueError('license missing '+name)
        shutil.copy2(source,licenses/(name+'.txt'))
    proof={'schema':'lie-native-probe-build/1','platform':platform,'dependencies':{n:{'url':u,'sha':s} for n,(u,s) in DEPENDENCIES.items()},'library_bytes':output.stat().st_size,'library_sha256':hashlib.sha256(output.read_bytes()).hexdigest(),'cmake':subprocess.check_output(['cmake','--version'],text=True).splitlines()[0],'ndk':str(ndk) if ndk else None,'scope':'native build proof, not evidence of Mali counter access or speed'}
    (output.parent/'build.json').write_text(json.dumps(proof,indent=2)+'\n');return proof
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--cache',type=Path,required=True);p.add_argument('--platform',choices=['linux.x86_64','android.arm64'],required=True);p.add_argument('--ndk',type=Path);a=p.parse_args();print(json.dumps(build(a.cache.resolve(),a.platform,a.ndk),indent=2))
