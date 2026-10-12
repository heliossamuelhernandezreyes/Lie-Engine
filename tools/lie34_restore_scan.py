"""Restore real Draco-photogrammetry surface sample bank, checking SHA and CC BY."""
import json,hashlib,zlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SRC=ROOT/"gpu_compute/assets/lie34"
DEST=ROOT/"gpu_compute/captures/lie34scan"


def restore():
    doc=json.loads((SRC/"catalog.json").read_text())
    raw=zlib.decompress((SRC/"scanned_facade_bank.zlib").read_bytes())
    assert len(raw)==doc["bytes"]==doc["sample_count"]*80
    assert hashlib.sha256(raw).hexdigest()==doc["sha256"]
    assert doc["source_original_triangles"]==5500320
    assert doc["license"]=="CC BY 4.0"
    DEST.mkdir(parents=True,exist_ok=True)
    (DEST/"library.bin").write_bytes(raw)
    (DEST/"catalog.json").write_text(json.dumps(doc,indent=2))
    print("LIE34 verified original scanned geometry → LIE samples",
          doc["sample_count"],doc["sha256"])


if __name__=="__main__":restore()
