"""Independent float64 transport oracle for an actual coded Blender capture."""
import argparse
import copy
import json
from pathlib import Path
from lie_light_transport import solve, validate

def scenario(base, name):
    model = copy.deepcopy(base)
    if name == "direct": model["bounces"] = 0
    elif name == "absorbing":
        for key in model["materials"]:
            if "bounce red" in key: model["materials"][key]["absorption_code"] = 980
    elif name == "moved": model["lights"][0]["position"] = [.8, .6, .5]
    elif name == "cool": model["lights"][0]["power_rgb"] = [7, 17.5, 35]
    elif name == "dark": model["lights"][0]["power_rgb"] = [0, 0, 0]
    elif name != "bounce": raise ValueError(name)
    return model

def write_reference(root):
    root = Path(root)
    base = json.loads((root/"light-model.json").read_text())
    validate(base)
    output = {"schema": 1, "reference": "Python float64 + independent triangle segment tests; shared static BVH visibility cache", "scenarios": {}}
    for name in ["direct", "bounce", "absorbing", "moved", "cool", "dark"]:
        model = scenario(base, name)
        result = solve(model, model["bounces"])
        output["scenarios"][name] = {k: result[k] for k in ("irradiance", "total_flux", "energy_by_generation")}
        print("LIE-12 ORACLE", name, "nodes", len(model["patches"]), flush=True)
    (root/"light-reference.json").write_text(json.dumps(output, separators=(",", ":"))+"\n")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("root")
    write_reference(parser.parse_args().root)
