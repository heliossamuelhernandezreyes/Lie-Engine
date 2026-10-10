"""Pinned, attributed scan acquisition and a strict decoder for this GLB.

The decoder is intentionally limited to the locked uncompressed single mesh;
it is not an alternative general-purpose glTF importer.
"""
import hashlib
import json
from pathlib import Path
import struct
import urllib.request

ROOT = Path(__file__).resolve().parents[1] / 'gpu_compute/assets/lie20'


def acquire(root=ROOT):
    lock = json.loads((root / 'source-lock.json').read_text())
    for item in lock['files']:
        path = root / item['name']
        if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest() != item['sha256']:
            url = f"https://raw.githubusercontent.com/{lock['repository']}/{lock['commit']}/{lock['directory']}/{item['name']}"
            data = urllib.request.urlopen(url, timeout=60).read()
            if len(data) != item['bytes'] or hashlib.sha256(data).hexdigest() != item['sha256']:
                raise ValueError('Source integrity mismatch: ' + item['name'])
            path.write_bytes(data)
    return lock


def read_mesh(path):
    data = Path(path).read_bytes()
    magic, version, size = struct.unpack_from('<III', data)
    if (magic, version, size) != (0x46546C67, 2, len(data)):
        raise ValueError('Invalid GLB header')
    offset, document, binary = 12, None, None
    while offset < size:
        length, kind = struct.unpack_from('<II', data, offset)
        block = data[offset+8:offset+8+length]
        if len(block) != length:
            raise ValueError('Truncated GLB')
        if kind == 0x4E4F534A:
            document = json.loads(block)
        elif kind == 0x004E4942:
            binary = block
        offset += 8 + length
    if document is None or binary is None or len(document['meshes']) != 1:
        raise ValueError('Only the locked single-mesh GLB is supported')
    primitive = document['meshes'][0]['primitives'][0]
    if len(document['meshes'][0]['primitives']) != 1 or primitive.get('mode', 4) != 4:
        raise ValueError('Single triangle primitive required')

    def accessor(index):
        value = document['accessors'][index]
        if 'sparse' in value:
            raise ValueError('Sparse accessor unsupported')
        view = document['bufferViews'][value['bufferView']]
        formats = {5123: 'H', 5125: 'I', 5126: 'f'}
        components = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3}[value['type']]
        layout = '<' + formats[value['componentType']] * components
        width = struct.calcsize(layout)
        stride = view.get('byteStride', width)
        start = view.get('byteOffset', 0) + value.get('byteOffset', 0)
        if stride < width or start + max(value['count']-1, 0)*stride + width > len(binary):
            raise ValueError('Accessor exceeds binary bounds')
        return [struct.unpack_from(layout, binary, start+i*stride) for i in range(value['count'])]

    attributes = primitive['attributes']
    positions = accessor(attributes['POSITION'])
    normals = accessor(attributes['NORMAL'])
    uvs = accessor(attributes['TEXCOORD_0'])
    indices = [x[0] for x in accessor(primitive['indices'])]
    if len(indices) % 3 or max(indices) >= len(positions) or len(normals) != len(positions) or len(uvs) != len(positions):
        raise ValueError('Invalid mesh channels')
    return positions, normals, uvs, [indices[i:i+3] for i in range(0, len(indices), 3)]


if __name__ == '__main__':
    acquire()
    print('LIE20 verified scan and texture sources')
