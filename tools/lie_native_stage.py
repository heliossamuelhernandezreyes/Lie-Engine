"""Isolate current source and already verified packets for untimed Vulkan QA.

No Android identity or release is produced. Restore liewall06 and compile the
existing access/views packets plus lie_native_surface.py before using this.
"""
import argparse
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]


def stage(destination):
    source = ROOT/'gpu_compute'
    destination.mkdir(parents=True, exist_ok=True)
    pending = ['lie_direct_views_lab.tscn', 'test_lie_native_depth.gd',
               'test_lie_direct_views_commands.gd', 'test_lie26_rig.gd',
               'workshop/test_lie_agent_session.gd']
    copied = set()
    pattern = re.compile(r'(?:\bextends\s+|\b(?:preload|load)\s*\(\s*|\bpath\s*=\s*)"res://([^"]+)"')
    while pending:
        name = pending.pop()
        if name in copied:
            continue
        path = source/name
        target = destination/name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
        copied.add(name)
        if path.suffix in ('.gd', '.tscn', '.tres'):
            pending.extend(pattern.findall(path.read_text()))
    shutil.copytree(source/'captures/liewall06', destination/'captures/liewall06', dirs_exist_ok=True)
    shutil.copytree(source/'fixtures', destination/'fixtures', dirs_exist_ok=True)
    (destination/'project.godot').write_text('''config_version=5
[application]
config/name="LIE Native Depth QA"
run/main_scene="res://lie_direct_views_lab.tscn"
[rendering]
renderer/rendering_method="mobile"
[display]
window/size/viewport_width=720
window/size/viewport_height=720
[editor]
import/use_multiple_threads=false
''')
    print('Staged', len(copied), 'source resources at', destination)


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--stage', required=True, type=Path)
    stage(p.parse_args().stage.resolve())
