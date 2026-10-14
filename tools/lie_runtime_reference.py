"""Independent float64 oracles for the real Vulkan transport acceptance."""
from pathlib import Path
import json
from lie_light_transport import room_fixture, solve

ROOT=Path(__file__).resolve().parents[1]


def main():
    base=room_fixture(4)
    scenarios={}
    for mode in ('power','irradiance'):
        model=json.loads(json.dumps(base))
        model['secondary_radii']={'mode':mode,'radius_max':6,'radius_decay':.82,
             'power_reference':.015,'irradiance_cutoff':.001}
        scenarios[mode]={'model':model,'reference':solve(model,2)}
    model=json.loads(json.dumps(scenarios['irradiance']['model']))
    model['optical_sheets']=[{'center':[0,.5,0],'right':[1,0,0],'up':[0,0,1],
       'half_width':3,'half_height':3,'thickness':.02,'sigma':[2,.4,.1],'ior':1.5}]
    scenarios['transmission']={'model':model,'reference':solve(model,2)}
    output=ROOT/'gpu_compute/fixtures/lie-runtime-reference.json'
    output.write_text(json.dumps({'scenarios':scenarios},indent=2)+'\n')
    print(output)


if __name__=='__main__':main()
