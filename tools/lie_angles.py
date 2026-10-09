"""Engine-neutral reference for Lie's camera/view addressing.

Coordinate convention: +Z front = azimuth 0, +X right = azimuth 90.
Y is up. All camera-node vectors are expressed in node-local space.
"""
from __future__ import annotations

from math import atan2, cos, degrees, floor, hypot, radians, sin
from typing import Sequence


def view_code(azimuth_index: int, elevation_index: int) -> str:
    if azimuth_index < 0 or elevation_index < 0:
        raise ValueError("View indices cannot be negative")
    return f"az_{azimuth_index:02d}_el_{elevation_index:02d}"


def capture_direction(azimuth_index: int, azimuth_steps: int, elevation_deg: float) -> tuple[float, float, float]:
    if azimuth_steps < 4:
        raise ValueError("At least four azimuth samples are required")
    az = 2.0 * 3.141592653589793 * azimuth_index / azimuth_steps
    el = radians(elevation_deg)
    return (sin(az) * cos(el), sin(el), cos(az) * cos(el))


def select_view(
    camera_xyz: Sequence[float],
    node_xyz: Sequence[float],
    yaw_deg: float,
    azimuth_steps: int,
    elevation_degrees: Sequence[float],
) -> tuple[int, int, str]:
    """Nearest direction index for yaw-only node rotation (capture convention).

    Godot runtime handles full 3D Basis rotation; this Python implementation is
    intentionally a yaw-only offline reference, NOT a replacement for runtime.
    """
    if azimuth_steps < 4 or not elevation_degrees:
        raise ValueError("Invalid angular sampling")
    dx, dy, dz = (float(camera_xyz[i]) - float(node_xyz[i]) for i in range(3))
    yaw = radians(yaw_deg)
    local_x = cos(yaw) * dx - sin(yaw) * dz
    local_z = sin(yaw) * dx + cos(yaw) * dz
    azimuth = degrees(atan2(local_x, local_z)) % 360.0
    increment = 360.0 / azimuth_steps
    az = int(floor(azimuth / increment + 0.5)) % azimuth_steps
    elevation = degrees(atan2(dy, hypot(local_x, local_z)))
    el = min(range(len(elevation_degrees)), key=lambda i: abs(elevation - elevation_degrees[i]))
    return az, el, view_code(az, el)
