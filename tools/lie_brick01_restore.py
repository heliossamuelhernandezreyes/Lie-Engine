"""Restore exact, separately tested LIE-BRICK01 immutable PBR sample bank."""
from __future__ import annotations
import hashlib,json,zlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/"gpu_compute/assets/lie_brick01"
DEST=ROOT/"gpu_compute/captures/liebrick01"


def restore(destination:Path=DEST)->Path:
    meta=json.loads((SOURCE/"catalog.json").read_text())
    blob=zlib.decompress((SOURCE/"hero_bank.zlib").read_bytes())
    if meta["stride"]!=80 or len(blob)!=meta["bytes"] or len(blob)!=meta["sample_count"]*80:
        raise ValueError("Corrupt hero brick sample length")
    if hashlib.sha256(blob).hexdigest()!=meta["sha256"]:
        raise ValueError("Corrupt hero brick sample SHA256")
    if len(meta["masters"])!=2:
        raise ValueError("Expected hero full/half masters")
    destination.mkdir(parents=True,exist_ok=True)
    (destination/"library.bin").write_bytes(blob)
    (destination/"catalog.json").write_text(json.dumps(meta,indent=2))
    print("Verified hero samples",meta["sample_count"],"bank SHA",meta["sha256"])
    return destination/"library.bin"


if __name__=="__main__":restore()
