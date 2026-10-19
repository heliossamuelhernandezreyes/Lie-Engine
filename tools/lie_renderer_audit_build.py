"""Stage/export the causal diagnosis. No representation change is accepted here."""
import argparse, json, re, shutil
from pathlib import Path
import lie_wall24_android_build as previous
ROOT = Path(__file__).resolve().parents[1]

def config_key(text, key, value):
    text, count = re.subn(r'^' + re.escape(key) + r'=.*$', key + '=' + value, text, flags=re.M)
    if count != 1: raise ValueError('Expected exactly one configuration key: ' + key)
    return text

def configure_project(destination):
    # Assign the final identity explicitly. Older staging helpers rebuild
    # reference fixtures and can leave an earlier laboratory's settings.
    project = destination / 'project.godot'; text = project.read_text()
    for key, value in {'config/name': '"LIE Diagnostico 2.2"', 'config/version': '"2.2.0"', 'run/main_scene': '"res://lie_renderer_audit_lab.tscn"'}.items():
        text = config_key(text, key, value)
    project.write_text(text)
    preset = destination / 'export_presets.cfg'; text = preset.read_text()
    for key, value in {'version/code': '23', 'version/name': '"2.2.0-causal-audit"', 'package/unique_name': '"org.lieengine.wallruntime.v220"', 'package/name': '"LIE Diagnostico 2.2"'}.items():
        text = config_key(text, key, value)
    line = re.search(r'^include_filter="([^"]*)"$', text, re.M)
    if not line: raise ValueError('Missing export asset filter')
    filters = line[1].split(',')
    for name in ['addons/lie_gpu_probe/licenses/*.txt', 'addons/lie_gpu_probe/bin/*/build.json']:
        if name not in filters: filters.append(name)
    preset.write_text(config_key(text, 'include_filter', '"' + ','.join(filters) + '"'))

def stage_project(destination):
    report = previous.stage_project(destination); source = ROOT / 'gpu_compute'
    pending = ['lie_renderer_audit_lab.tscn', 'test_lie_renderer_audit_commands.gd', 'test_lie_renderer_audit_gpu.gd']; copied = set()
    pattern = re.compile(r'(?:\bextends\s+|\b(?:preload|load)\s*\(\s*|\bpath\s*=\s*)"res://([^"]+)"')
    while pending:
        name = pending.pop()
        if name in copied: continue
        path = source / name; out = destination / name
        out.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(path, out); copied.add(name)
        if path.suffix in ('.gd', '.tscn', '.tres'): pending.extend(pattern.findall(path.read_text()))
    configure_project(destination)
    report['causal_audit'] = 'cumulative diagnostic ablations and separate full-kernel query census; no conventional-equivalence claim'
    return report

if __name__ == '__main__':
    p = argparse.ArgumentParser(); p.add_argument('--stage', type=Path, required=True)
    for name in ['godot', 'sdk', 'keystore', 'output']: p.add_argument('--' + name, type=Path)
    args = p.parse_args(); report = stage_project(args.stage.resolve())
    if args.output:
        import lie_runtime_android_build as base
        report.update(base.export(args.stage.resolve(), args.godot.resolve(), args.sdk.resolve(), args.keystore.resolve(), args.output.resolve()))
        report.update(package='org.lieengine.wallruntime.v220', version='2.2.0-causal-audit')
        (args.output.parent / 'android-build.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
