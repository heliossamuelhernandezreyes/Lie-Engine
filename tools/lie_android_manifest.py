"""Normalize typed uses-feature attributes emitted by Godot's prebuilt exporter.

Godot 4.7.2 writes newly appended Vulkan required/version values as strings
and omits the resource-map entry for android:version. Android SDK aapt rejects
that form. Preserve the values, give them proper binary XML types/resource IDs,
The exporter also assigns the FileProvider authority to AndroidX Startup.
Give Startup its own authority. zipalign/apksigner rebuild alignment/signature;
the scene, scripts, libraries and capture payload remain unchanged.
"""
import struct
import zipfile

def normalize_features(data: bytes) -> tuple[bytes, int]:
    kind, header, length = struct.unpack_from("<HHI", data)
    if kind != 3 or header != 8 or length != len(data):
        raise ValueError("Invalid binary Android manifest")
    chunks = []
    offset = header
    while offset < len(data):
        kind, chunk_header, size = struct.unpack_from("<HHI", data, offset)
        if size < chunk_header or offset + size > len(data):
            raise ValueError("Invalid manifest chunk")
        chunks.append((kind, bytearray(data[offset:offset+size])))
        offset += size
    pool = next(chunk for kind, chunk in chunks if kind == 1)
    pool_header = struct.unpack_from("<H", pool, 2)[0]
    count, _, flags, start = struct.unpack_from("<IIII", pool, 8)
    strings = []
    def read_length(position, utf8):
        fmt, width, marker = ("<B", 1, 0x80) if utf8 else ("<H", 2, 0x8000)
        value = struct.unpack_from(fmt, pool, position)[0]
        position += width
        if value & marker:
            value = ((value & (marker-1)) << (width*8)) | struct.unpack_from(fmt, pool, position)[0]
            position += width
        return value, position
    for index in range(count):
        position = start + struct.unpack_from("<I", pool, pool_header + index*4)[0]
        size, position = read_length(position, bool(flags & 0x100))
        if flags & 0x100:
            size, position = read_length(position, True)
            strings.append(pool[position:position+size].decode("utf-8"))
        else:
            strings.append(pool[position:position+size*2].decode("utf-16le"))
    changed = 0
    version_indices = set()
    for kind, chunk in chunks:
        if kind != 0x102 or strings[struct.unpack_from("<I", chunk, 20)[0]] != "provider":
            continue
        attr_start, attr_size, attr_count = struct.unpack_from("<HHH", chunk, 24)
        attributes = {}
        for index in range(attr_count):
            position = 16 + attr_start + index*attr_size
            name = strings[struct.unpack_from("<I", chunk, position+4)[0]]
            if chunk[position+15] == 3:
                attributes[name] = (position, strings[struct.unpack_from("<I", chunk, position+16)[0]])
        if attributes.get("name", (0, ""))[1] != "androidx.startup.InitializationProvider":
            continue
        position, authority = attributes["authorities"]
        if not authority.endswith(".fileprovider"):
            continue
        authority = authority.removesuffix(".fileprovider") + ".androidx-startup"
        if struct.unpack_from("<I", pool, 12)[0] != 0:
            raise ValueError("Styled manifest strings not supported")
        encoded = authority.encode("utf-8" if flags & 0x100 else "utf-16le")
        if len(encoded) > 127:
            raise ValueError("Unexpected long startup authority")
        new_string = (bytes([len(authority), len(encoded)])+encoded+b"\0") if flags & 0x100 else (struct.pack("<H", len(encoded)//2)+encoded+b"\0\0")
        string_data = pool[start:]
        new_pool = pool[:pool_header+count*4] + struct.pack("<I", len(string_data)) + pool[pool_header+count*4:start] + string_data + new_string
        new_pool.extend(b"\0" * (-len(new_pool) % 4))
        struct.pack_into("<I", new_pool, 4, len(new_pool))
        struct.pack_into("<I", new_pool, 8, count+1)
        struct.pack_into("<I", new_pool, 20, start+4)
        for i, (chunk_kind, _) in enumerate(chunks):
            if chunk_kind == 1:
                chunks[i] = (1, new_pool)
                break
        struct.pack_into("<I", chunk, position+8, count)
        struct.pack_into("<I", chunk, position+16, count)
        changed += 1
    for kind, chunk in chunks:
        if kind != 0x102 or strings[struct.unpack_from("<I", chunk, 20)[0]] != "uses-feature":
            continue
        attr_start, attr_size, attr_count = struct.unpack_from("<HHH", chunk, 24)
        for index in range(attr_count):
            position = 16 + attr_start + index*attr_size
            name_index = struct.unpack_from("<I", chunk, position+4)[0]
            name = strings[name_index]
            if name not in ("required", "version"):
                continue
            if name == "version":
                version_indices.add(name_index)
            if chunk[position+15] != 3:
                continue
            value = strings[struct.unpack_from("<I", chunk, position+16)[0]]
            if name == "required":
                if value not in ("true", "false"):
                    raise ValueError("Unexpected required value")
                chunk[position+15] = 0x12
                number = 0xffffffff if value == "true" else 0
            else:
                chunk[position+15] = 0x11 if value.startswith("0x") else 0x10
                number = int(value, 0)
            struct.pack_into("<I", chunk, position+16, number)
            changed += 1
    if version_indices:
        resource_map = next(chunk for kind, chunk in chunks if kind == 0x180)
        resource_map.extend(b"\0" * max(0, 8+4*(max(version_indices)+1)-len(resource_map)))
        for index in version_indices:
            struct.pack_into("<I", resource_map, 8+4*index, 0x01010519) # Android attr/version, SDK public.xml.
        struct.pack_into("<I", resource_map, 4, len(resource_map))
    result = bytearray(data[:8]) + b"".join(chunk for _, chunk in chunks)
    struct.pack_into("<I", result, 4, len(result))
    return bytes(result), changed

def normalize_apk(source, destination):
    with zipfile.ZipFile(source) as original, zipfile.ZipFile(destination, "w") as output:
        changed = 0
        for entry in original.infolist():
            data = original.read(entry)
            if entry.filename == "AndroidManifest.xml":
                data, changed = normalize_features(data)
            output.writestr(entry, data)
    return changed
