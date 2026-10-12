"""Pack a prepared cylinder capture with an independent source-surface check."""
from pathlib import Path
import json
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lie15_pack_blender


def main():
    root = Path(sys.argv[sys.argv.index('--') + 1]).resolve()
    # Reuse the tested packer while explicitly selecting this master's oracle.
    triangles = root.parents[1] / 'assets/workshop/cylinder-triangles.json'
    lie15_pack_blender.pack(root, triangle_path=triangles, master_id='lie-original-cylinder-v1')
    data = json.loads((root / 'master.json').read_text())
    data['source'] = {'kind': 'original procedural cylinder', 'license': 'project distribution license pending'}
    data['collision']['approximation'] = 'conservative oriented box'
    (root / 'master.json').write_text(json.dumps(data, indent=2) + '\n')


if __name__ == '__main__':
    main()
