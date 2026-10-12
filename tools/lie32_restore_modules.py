"""Restore SHA-256 locked LIE32 joint-masonry master bank from repository."""
from pathlib import Path
import hashlib,json,zlib

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/"gpu_compute/assets/lie32"
DEST=ROOT/"gpu_compute/captures/lie32cluster"


def restore():
    metadata=json.loads((SOURCE/"catalog.json").read_text())
    blob=zlib.decompress((SOURCE/"module_bank.zlib").read_bytes())
    assert len(blob)==metadata["bytes"]==metadata["sample_count"]*80
    assert hashlib.sha256(blob).hexdigest()==metadata["sha256"]
    DEST.mkdir(parents=True,exist_ok=True)
    (DEST/"library.bin").write_bytes(blob)
    (DEST/"catalog.json").write_text(json.dumps(metadata,indent=2))
    print("LIE32 4 joint modules verified",metadata["sample_count"])


if __name__=="__main__":
    restore()
