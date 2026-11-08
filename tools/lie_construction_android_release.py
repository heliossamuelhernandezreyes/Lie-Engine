"""Assemble user deliverables only from a complete, SHA-verified CI artifact."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import zipfile
APK_NAME='LIE-Construccion-v6.2.0.apk'
PREFIX='LIE_Benchmark_v6.2.0'

def digest(path):
    with path.open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()
def release(artifact,expected,guide,output,run_id,job_id):
    if digest(artifact)!=expected:raise ValueError('actions_artifact_sha256')
    output.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(artifact) as source:
        names=source.namelist()
        if any(Path(n).is_absolute() or '..' in Path(n).parts for n in names):raise ValueError('artifact_path_escape')
        def unique(suffix):
            matches=[n for n in names if n.endswith('/'+suffix) or n==suffix]
            if len(matches)!=1:raise ValueError('expected_one:'+suffix)
            return matches[0]
        proof=json.loads(source.read(unique(Path(APK_NAME).with_suffix('.proof.json').name)))
        native=json.loads(source.read(unique('construction-mobile-native.json')))
        field=json.loads(source.read(unique('construction-field-native.json')))
        construction=json.loads(source.read(unique('hq-construction-native.json')))
        hardware=json.loads(source.read(unique('hardware-probe-native.json')))
        comparison=json.loads(source.read(unique('reconstruction-comparison.json')))
        reconstruction=json.loads(source.read(unique('mobile-ci/construction-reconstruction-native.json')))
        proxy=json.loads(source.read(unique('construction-proxy-native.json')))
        physics=json.loads(source.read(unique('construction-proxy-physics.json')))
        assert not proxy['failed'] and not physics['failed'] and proxy['rgba_exact'] and proxy['depth_exact']
        assert proxy['report']['complete'] and proxy['report']['restored'] and proxy['report']['appearance_reused'] and proxy['report']['field_reused']
        assert [row['proxy']['physics_shapes'] for row in proxy['report']['physics']]==[781,5]
        assert not reconstruction['failed'] and len(comparison['cases'])==10
        assert all(r['depth_bit_exact'] and r['alpha_bit_exact'] and r['peak_rgba_error']<=1e-6 for r in comparison['cases'])
        assert not any(d['failed'] for d in [native,field,construction,hardware])
        assert native['checks']>=28 and native['report']['complete'] and native['report']['restored']
        assert proof['verified_capture_and_metadata_files']==90 and not proof['source_resampling']
        apk=output/APK_NAME
        with source.open(unique(apk.name)) as src,apk.open('wb') as dest:shutil.copyfileobj(src,dest)
        assert digest(apk)==proof['apk_sha256'] and apk.stat().st_size==proof['apk_bytes']
        # Verify registration, not just the presence of a native .so file.
        with zipfile.ZipFile(apk) as packaged:
            descriptor=packaged.read('assets/addons/lie_gpu_probe/lie_gpu_probe.gdextension').decode()
            assert 'android.arm64' in descriptor
            registration=packaged.read('assets/.godot/extension_list.cfg')
            assert b'lie_gpu_probe.gdextension' in registration
        checkpoint={'schema':'lie-construction-android-release/1','run_id':run_id,'job_id':job_id,
                    'artifact_sha256':expected,'apk':proof,'native_checks':{'construction':construction['checks'],
                    'field':field['checks'],'mobile':native['checks'],'hardware':hardware['checks'],
                    'mobile_metrics':8,'rig':247,'agent':25},'full_quality':native['full_quality'],
                    'physical_android_tested':False,'native_registration_in_apk':True,
                    'automatically_copies_completed_report':True,'cancellation_preserves_clipboard':True,
                    'reconstruction_comparison':comparison,
                    'native_reconstruction_checks':reconstruction['checks'],
                    'proxy_physics':physics,'proxy_native':proxy,
                    'preserved_negative_reconstruction_run':42436770047}
        (output/(PREFIX+'_Verificacion.json')).write_text(json.dumps(checkpoint,indent=2)+'\n')
        preview=source.read(unique('construction-proxy-ui.png'));(output/(PREFIX+'_Interfaz.png')).write_bytes(preview)
        target_guide=output/(PREFIX+'_Guia.md')
        if guide.resolve()!=target_guide.resolve():shutil.copyfile(guide,target_guide)
        evidence=output/(PREFIX+'_Pruebas.zip')
        with zipfile.ZipFile(evidence,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as dest:
            for name in names:
                if name.endswith('/') or name.endswith('.apk'):continue
                dest.writestr('CI/'+name,source.read(name))
            dest.write(output/(PREFIX+'_Verificacion.json'),PREFIX+'_Verificacion.json')
            dest.write(target_guide,target_guide.name)
        with zipfile.ZipFile(evidence) as check:assert check.testzip() is None
    print(json.dumps({'apk':str(apk),'bytes':apk.stat().st_size,'sha256':proof['apk_sha256'],
                      'evidence':str(evidence),'evidence_bytes':evidence.stat().st_size,'run_id':run_id}))
    return checkpoint
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--artifact',type=Path,required=True);p.add_argument('--sha256',required=True);p.add_argument('--guide',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--run-id',type=int,required=True);p.add_argument('--job-id',type=int,required=True);a=p.parse_args();release(a.artifact,a.sha256,a.guide,a.output,a.run_id,a.job_id)
