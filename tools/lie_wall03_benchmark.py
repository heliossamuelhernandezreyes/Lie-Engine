"""Repeatable GPU timestamp comparison of LIE-WALL03 coverage ON/OFF.

Requires an already launched Godot workshop. Benchmarking Mesa llvmpipe does
NOT tell us physical Android/PC GPU FPS: machine/device label is mandatory.
The same camera poses/light, exact sample bank and output resolution are used.
"""
from __future__ import annotations
import argparse
import json
import statistics
import time
from pathlib import Path
from lie_workshop_client import WorkshopClient,WorkshopBusy

def benchmark(directory: Path,poses: int=8) -> dict:
    client=WorkshopClient(directory,timeout=180)

    def request(msg):
        for trial in range(16):
            try:return client.request(msg)
            except WorkshopBusy:
                if trial==15:raise
                time.sleep(.25)

    def snapshot():
        x=request({"op":"snapshot"})
        assert x["result"]["ok"],x
        return x["result"]["snapshot"]

    def change(**values):
        resp=request({"op":"set_values","values":values})
        assert resp["result"]["ok"],resp

    def wait_for_frame(before: int,seconds: float=35.0):
        until=time.monotonic()+seconds
        while time.monotonic()<until:
            snap=snapshot()
            if snap["coverage_profiler"]["frame_count"]>before:return snap
            time.sleep(.12)
        raise RuntimeError("Godot renderer didn't complete a new frame")

    # Strictly same scanned wall, camera, lighting and absorption on both sweeps.
    change(distance_factor=1.0,camera_elevation=9.0,lighting_preset="neutral",
           light_azimuth=-22.0,clay_absorption=0.0,direct_shadow_proxies=True,
           shadows=True)
    sweeps={}
    # Alternating order limits warmup/thermal/dataset cache bias.
    for cycle,enabled in enumerate((False,True,True,False)):
        stage=f"{'on' if enabled else 'off'}_{cycle}"
        change(coverage_enabled=enabled)
        start=snapshot()
        before_count=int(start["coverage_profiler"]["sample_count"])
        timings=[]
        elapsed=[]
        for i in range(poses):
            yaw=8.0+i*1.25+(0.1 if cycle%2 else 0.0)
            previous=snapshot()["coverage_profiler"]["frame_count"]
            t0=time.monotonic()
            change(camera_yaw=yaw)
            settled=wait_for_frame(previous)
            elapsed.append((time.monotonic()-t0)*1000.)
            stats=settled["coverage_profiler"]
            chron=stats.get("chronological_gpu_ms_tail",[])
            if chron:
                timings.append(float(chron[-1]))
        # Last frame GPU timestamp may be collected on next change; this is
        # a descriptive GPU timestamp sample, not guaranteed per-pose exact.
        sweeps[stage]={
            "coverage_enabled":enabled,
            "completed_camera_frames":poses,
            "gpu_timestamps_samples":len(timings),
            "median_captured_gpu_ms":float(statistics.median(timings)) if timings else None,
            "min_captured_gpu_ms":float(min(timings)) if timings else None,
            "median_command_to_frame_ms":float(statistics.median(elapsed)),
            "gpu_memory_MiB":float(stats["gpu_allocation_MiB"]),
            "device_kind":"Mesa Vulkan software reference, NOT phone GPU",
        }
    off=[v["median_captured_gpu_ms"] for v in sweeps.values()
         if not v["coverage_enabled"] and v["median_captured_gpu_ms"] is not None]
    on=[v["median_captured_gpu_ms"] for v in sweeps.values()
        if v["coverage_enabled"] and v["median_captured_gpu_ms"] is not None]
    report={
        "benchmark":"LIE-WALL03 controlled coverage flag, same authentic scan and RGB node field",
        "vulkan_shader_output":[1080,1080],
        "hardware":"Mesa software Vulkan CI unless user executes on physical Vulkan device",
        "physical_android_gpu_tested":False,
        "samples_per_sweep":poses,
        "sweeps":sweeps,
        "median_off_gpu_ms":float(statistics.median(off)) if off else None,
        "median_on_gpu_ms":float(statistics.median(on)) if on else None,
        "benchmark_is_fps_claim":False,
        "limitations":"GPU timestamp captures may lag one submission; host IPC and Mesa emulator make times unsuitable for Android FPS projection",
    }
    (directory/"LIE-WALL03-coverage-benchmark.json").write_text(json.dumps(report,indent=2)+"\n")
    print(json.dumps(report,indent=2),flush=True)
    return report


if __name__=="__main__":
    p=argparse.ArgumentParser()
    p.add_argument("--directory",type=Path,required=True)
    p.add_argument("--poses",type=int,default=8)
    args=p.parse_args()
    if not 4<=args.poses<=15:
        p.error("poses must be in [4,15]")
    benchmark(args.directory,args.poses)
