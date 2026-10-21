"""Stage/export the independent view-visible architecture experiment."""
import argparse
import json
from pathlib import Path
import lie_direct_build as previous

def stage_project(destination):
    report = previous.stage_project(destination)
    project = destination / 'project.godot'
    text = project.read_text()
    for key, value in {'config/name':'"LIE Vistas capturadas 2.5"','config/version':'"2.5.0"','run/main_scene':'"res://lie_direct_views_lab.tscn"'}.items():
        text = previous.previous.config_key(text, key, value)
    project.write_text(text)
    preset = destination / 'export_presets.cfg'; text = preset.read_text()
    for key, value in {'version/code':'26','version/name':'"2.5.0-captured-views"','package/unique_name':'"org.lieengine.wallruntime.v250"','package/name':'"LIE Vistas capturadas 2.5"'}.items():
        text = previous.previous.config_key(text, key, value)
    preset.write_text(text)
    return report

if __name__ == '__main__':
    p = argparse.ArgumentParser(); p.add_argument('--stage', type=Path, required=True)
    for name in ['godot','sdk','keystore','output']: p.add_argument('--' + name, type=Path)
    a = p.parse_args(); report = stage_project(a.stage.resolve())
    if a.output:
        import lie_runtime_android_build as base
        report.update(base.export(a.stage.resolve(), a.godot.resolve(), a.sdk.resolve(), a.keystore.resolve(), a.output.resolve()))
        report.update(package='org.lieengine.wallruntime.v250', version='2.5.0-captured-views')
        (a.output.parent / 'android-build.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
