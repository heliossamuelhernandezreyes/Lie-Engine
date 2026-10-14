"""Lossless receiver-CSR packing of source-to-receiver float32 light factors.

The source matrix is unchanged. Zero edges are omitted; every positive weight
keeps its original float32 bits and ascending source accumulation order.
No NumPy/runtime dependency, approximation, threshold or renormalization.
"""
from __future__ import annotations
import hashlib
import math
import struct


def pack(dense: bytes, count: int) -> tuple[bytes, dict]:
    if isinstance(count, bool) or not isinstance(count, int) or not 1 <= count <= 1024:
        raise ValueError("Expected 1..1024 transport patches")
    if len(dense) != count * count * 4:
        raise ValueError("Invalid dense factor dimensions")
    values = struct.unpack(f"<{count*count}f", dense)
    if any(not math.isfinite(v) or v < 0 for v in values):
        raise ValueError("Factors must be finite and nonnegative")
    if any(math.fsum(values[s*count:(s+1)*count]) > 1.00001 for s in range(count)):
        raise ValueError("Outgoing transfer exceeds the source energy budget")
    offsets = [0]
    edges = []
    for receiver in range(count):
        for source in range(count):
            index = source * count + receiver
            if values[index] > 0:
                edges.extend((source, struct.unpack_from("<I", dense, index*4)[0]))
        offsets.append(len(edges)//2)
    edge_base = 4 + count + 1
    words = [count, len(edges)//2, 4, edge_base] + offsets + edges
    result = struct.pack(f"<{len(words)}I", *words)
    return result, {"schema": "lie-receiver-csr-f32/1", "patches": count,
        "edges": len(edges)//2, "dense_bytes": len(dense), "bytes": len(result),
        "dense_sha256": hashlib.sha256(dense).hexdigest(),
        "sha256": hashlib.sha256(result).hexdigest(), "zero_threshold": 0,
        "weights_requantized": False, "source_order_preserved": True}


def unpack(packet: bytes) -> bytes:
    if len(packet) < 24 or len(packet) % 4:
        raise ValueError("Truncated CSR packet")
    words = struct.unpack(f"<{len(packet)//4}I", packet)
    n, edge_count, offset_base, edge_base = words[:4]
    if not 1 <= n <= 1024 or offset_base != 4 or edge_base != n+5 or len(words) != edge_base+edge_count*2:
        raise ValueError("Invalid CSR layout")
    offsets = words[offset_base:edge_base]
    if offsets[0] != 0 or offsets[-1] != edge_count or any(a>b or b>edge_count for a,b in zip(offsets,offsets[1:])):
        raise ValueError("Invalid CSR row offsets")
    dense = bytearray(n*n*4)
    outgoing = [0.0]*n
    for receiver in range(n):
        last = -1
        for edge in range(offsets[receiver], offsets[receiver+1]):
            source, bits = words[edge_base+edge*2:edge_base+edge*2+2]
            weight = struct.unpack("<f", struct.pack("<I", bits))[0]
            if source <= last or source >= n or not math.isfinite(weight) or weight <= 0:
                raise ValueError("Invalid or unordered CSR source/weight")
            struct.pack_into("<I", dense, (source*n+receiver)*4, bits)
            outgoing[source] += weight
            last = source
    if max(outgoing) > 1.00001:
        raise ValueError("CSR energy budget exceeded")
    return bytes(dense)
