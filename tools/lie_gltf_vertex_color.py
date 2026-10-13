"""Read authentic glTF COLOR_0, geometry and scene transforms for LIE.

Vertex COLOR_0 is LINEAR by the glTF 2.0 specification, unlike sRGB textures.
Original triangles are sampled offline, never drawn as meshes by LIE. The
reader refuses sparse, compressed, or invalid accessors rather than fabricating
a shape or color.
"""
from __future__ import annotations
import json
import struct
from pathlib import Path
import numpy as np
import trimesh

_COMPONENTS = {5120: np.int8, 5121: np.uint8, 5122: np.int16,
               5123: np.uint16, 5125: np.uint32, 5126: np.float32}
_ARITY = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def read_glb(path: Path) -> tuple[dict, bytes]:
    data = path.read_bytes()
    if len(data) < 28 or data[:4] != b"glTF":
        raise ValueError("Expected valid GLB 2.0")
    _, version, total = struct.unpack_from("<4sII", data)
    if version != 2 or total != len(data):
        raise ValueError("Invalid GLB size/version")
    cursor = 12
    chunks = []
    while cursor < total:
        n, kind = struct.unpack_from("<II", data, cursor)
        cursor += 8
        chunk = data[cursor:cursor+n]
        cursor += n
        if len(chunk) != n:
            raise ValueError("Truncated GLB chunk")
        chunks.append((kind, chunk))
    if len(chunks) < 2 or chunks[0][0] != 0x4e4f534a or chunks[1][0] != 0x004e4942:
        raise ValueError("GLB must start with JSON followed by BIN")
    return json.loads(chunks[0][1].decode("utf-8").strip()), chunks[1][1]


def accessor(doc: dict, binary: bytes, index: int) -> np.ndarray:
    a = doc["accessors"][index]
    if "sparse" in a or "bufferView" not in a:
        raise ValueError("Sparse or empty glTF accessors require explicit conversion")
    dt = np.dtype(_COMPONENTS[a["componentType"]]).newbyteorder("<")
    k = _ARITY[a["type"]]
    view = doc["bufferViews"][a["bufferView"]]
    if int(view.get("buffer", 0)) != 0:
        raise ValueError("Multiple GLB buffers unsupported")
    offset = int(view.get("byteOffset", 0)) + int(a.get("byteOffset", 0))
    stride = int(view.get("byteStride", dt.itemsize * k))
    count = int(a["count"])
    if stride < dt.itemsize * k or offset + (count-1)*stride + dt.itemsize*k > len(binary):
        raise ValueError("Accessor outside buffer or invalid byteStride")
    arr = np.ndarray(shape=(count, k), dtype=dt, buffer=binary, offset=offset,
                     strides=(stride, dt.itemsize)).copy()
    if a.get("normalized", False):
        if np.issubdtype(dt, np.unsignedinteger):
            arr = arr.astype(np.float32) / np.iinfo(dt).max
        elif np.issubdtype(dt, np.signedinteger):
            arr = np.maximum(arr.astype(np.float32) / np.iinfo(dt).max, -1.)
    return arr


def node_matrix(node: dict) -> np.ndarray:
    if "matrix" in node:
        return np.asarray(node["matrix"], dtype=np.float64).reshape((4, 4), order="F")
    pose = np.eye(4, dtype=np.float64)
    pose[:3, 3] = node.get("translation", [0., 0., 0.])
    x, y, z, w = node.get("rotation", [0., 0., 0., 1.])
    q = np.array([w, x, y, z], dtype=np.float64)
    q /= max(np.linalg.norm(q), 1e-12)
    w, x, y, z = q
    pose[:3, :3] = [
        [1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)],
        [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)],
        [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]]
    pose[:3, :3] @= np.diag(np.asarray(node.get("scale", [1., 1., 1.]), dtype=np.float64))
    return pose


def load_colored_glb(path: Path) -> list[trimesh.Trimesh]:
    doc, binary = read_glb(path)
    meshes = []
    gltf_meshes = doc.get("meshes", [])
    nodes = doc.get("nodes", [])
    scenes = doc.get("scenes", [])
    if not gltf_meshes or not scenes:
        raise ValueError("Missing meshes or glTF scene")
    sid = int(doc.get("scene", 0))
    if sid >= len(scenes):
        raise ValueError("Invalid glTF scene index")

    def walk(index: int, parent: np.ndarray, visited: tuple[int, ...]):
        if index in visited:
            raise ValueError("Cyclic glTF nodes")
        node = nodes[index]
        world = parent @ node_matrix(node)
        if "mesh" in node:
            for pi, primitive in enumerate(gltf_meshes[node["mesh"]]["primitives"]):
                if int(primitive.get("mode", 4)) != 4:
                    raise ValueError("Only triangle primitives supported")
                attrs = primitive.get("attributes", {})
                for field in ("POSITION", "COLOR_0"):
                    if field not in attrs:
                        raise ValueError(f"Real scan primitive lacks {field}; no invented color")
                pos = accessor(doc, binary, attrs["POSITION"]).astype(np.float64)
                col = accessor(doc, binary, attrs["COLOR_0"]).astype(np.float32)
                if len(pos) != len(col) or pos.shape[1] != 3 or col.shape[1] not in (3, 4):
                    raise ValueError("Mismatched source vertices/color attributes")
                if "indices" in primitive:
                    triangles = accessor(doc, binary, primitive["indices"]).reshape(-1).astype(np.int32)
                else:
                    triangles = np.arange(len(pos), dtype=np.int32)
                if len(triangles) % 3:
                    raise ValueError("Indices are not triangle triples")
                faces = triangles.reshape(-1, 3)
                if len(faces) == 0 or faces.min() < 0 or faces.max() >= len(pos):
                    raise ValueError("Invalid glTF indices")
                coords = (pos @ world[:3, :3].T + world[:3, 3]).astype(np.float64)
                mesh = trimesh.Trimesh(vertices=coords, faces=faces, process=False)
                if "NORMAL" in attrs:
                    normals = accessor(doc, binary, attrs["NORMAL"]).astype(np.float64)
                    if normals.shape == (len(pos), 3):
                        nr = normals @ np.linalg.inv(world[:3, :3])
                        nr /= np.maximum(np.linalg.norm(nr, axis=1, keepdims=True), 1e-9)
                        mesh.vertex_normals = nr
                colors = np.clip(col[:, :3], 0., 1.)
                if not np.isfinite(colors).all() or not np.isfinite(coords).all():
                    raise ValueError("Nonfinite original colors or geometry")
                mesh.metadata["lie_vertex_colors_linear"] = colors
                mat_idx = primitive.get("material")
                material = doc.get("materials", [])[mat_idx] if mat_idx is not None else {}
                mesh.metadata["lie_material_roughness"] = float(material.get("pbrMetallicRoughness", {}).get("roughnessFactor", .8))
                mesh.metadata["lie_gltf_mesh_index"] = int(node["mesh"])
                mesh.metadata["lie_gltf_primitive_index"] = pi
                meshes.append(mesh)
        for child in node.get("children", []):
            walk(int(child), world, visited + (index,))

    for root in scenes[sid].get("nodes", []):
        walk(int(root), np.eye(4), tuple())
    if not meshes:
        raise ValueError("No visible glTF scene primitives")
    return meshes
