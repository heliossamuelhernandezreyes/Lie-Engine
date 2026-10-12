"""LIE29: deterministic, reusable brick-instance layout (offline authoring).

Produces placements only. Meshes, photographic materials and GPU capture banks
remain shared masters in LIE28; this module never duplicates their sample data.
All dimensions are metres. Variation uses stable integer hashing, not process-
dependent Python hash(), to remain unchanged across machines and runs.
"""
from __future__ import annotations

import argparse
import json
from dataclasses import asdict, dataclass
from pathlib import Path


@dataclass(frozen=True)
class Brick:
    master_id: int
    row: int
    column: int
    position: tuple[float, float, float]
    yaw_degrees: float
    tone: float
    roughness_offset: float
    seed: int


def _hash32(x: int) -> int:
    x &= 0xFFFFFFFF
    x ^= x >> 16
    x = (x * 0x7FEB352D) & 0xFFFFFFFF
    x ^= x >> 15
    x = (x * 0x846CA68B) & 0xFFFFFFFF
    return (x ^ (x >> 16)) & 0xFFFFFFFF


def _value(seed: int, row: int, col: int, channel: int) -> float:
    h = _hash32(
        (seed * 0x9E3779B1)
        ^ (row * 0x85EBCA77)
        ^ (col * 0xC2B2AE3D)
        ^ (channel * 0x27D4EB2F)
    )
    return h / 0xFFFFFFFF


def make_wall(
    columns: int = 100,
    rows: int = 100,
    *,
    seed: int = 29,
    masters: int = 3,
    brick_length: float = 0.24,
    brick_height: float = 0.07,
    brick_depth: float = 0.12,
    mortar: float = 0.01,
    tone_variation: float = 0.12,
    roughness_variation: float = 0.06,
    bond: str = "running",
) -> list[Brick]:
    """Return 10,000 shared-master placements by default.

    The running bond offsets alternate rows by half the nominal brick pitch.
    Half end bricks / trimming against fixed wall boundaries are deliberately
    NOT manufactured here; this is an array test, not construction CAD.
    """
    if not (1 <= rows <= 1000 and 1 <= columns <= 1000):
        raise ValueError("rows/columns must be between 1 and 1000")
    if not (1 <= masters <= 3):
        raise ValueError("master count must be 1..3")
    if bond not in ("running", "stack"):
        raise ValueError("bond must be running or stack")
    if min(brick_length, brick_height, brick_depth) <= 0 or mortar < 0:
        raise ValueError("invalid brick dimensions or mortar")
    if not (0 <= tone_variation <= 0.5 and 0 <= roughness_variation <= 0.5):
        raise ValueError("variation out of range")

    pitch_x = brick_length + mortar
    pitch_y = brick_height + mortar
    result: list[Brick] = []
    for row in range(rows):
        x_offset = pitch_x * 0.5 if bond == "running" and row % 2 else 0.0
        for col in range(columns):
            u = _value(seed, row, col, 0)
            v = _value(seed, row, col, 1)
            m = min(int(_value(seed, row, col, 2) * masters), masters - 1)
            result.append(Brick(
                master_id=m, row=row, column=col,
                position=(round(col * pitch_x + x_offset, 6),
                          round(row * pitch_y, 6), 0.0),
                yaw_degrees=0.0,
                tone=round((u * 2 - 1) * tone_variation, 6),
                roughness_offset=round((v * 2 - 1) * roughness_variation, 6),
                seed=seed,
            ))
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--columns", type=int, default=100)
    parser.add_argument("--rows", type=int, default=100)
    parser.add_argument("--masters", type=int, default=3)
    parser.add_argument("--seed", type=int, default=29)
    parser.add_argument("--bond", choices=("running", "stack"), default="running")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    bricks = make_wall(args.columns, args.rows, masters=args.masters,
                       seed=args.seed, bond=args.bond)
    # Only per-instance references, not copied mesh vertices or image samples.
    payload = {"schema": 1, "type": "lie29_brick_placements",
               "masters": args.masters, "instances": len(bricks),
               "bond": args.bond, "seed": args.seed,
               "bricks": [asdict(b) for b in bricks]}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(payload, separators=(",", ":")), encoding="utf-8")
    print(f"Saved {len(bricks)} placements in {args.out}")


if __name__ == "__main__":
    main()
