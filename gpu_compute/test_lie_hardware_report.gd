extends SceneTree
const Report=preload("res://lie_hardware_report.gd")
var checks: int=0
var failed: bool=false
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failed=true;printerr("HARDWARE REPORT FAIL ",label)
func _initialize() -> void:
    var gpu: Dictionary={"groups":[{"serials":[1,2,3]}],"instrumented_gpu_ms":60.}
    var empty: Dictionary={"available":true,"counters":{"GPU active cycles":{"available":true,"value":"0"}}}
    check(not Report.corroborate(empty,gpu,3)["valid"],"positive GPU work cannot validate an all-zero counter interval")
    var sample: Dictionary=empty.duplicate(true);sample["counters"]["GPU active cycles"]["value"]="18446744073709551615"
    check(Report.corroborate(sample,gpu,3)["valid"],"uint64 decimal can corroborate without narrowing to int64")
    check(not Report.corroborate(sample,gpu,4)["valid"],"missing timestamp events stay uncorroborated")
    var idle: Dictionary={"groups":[],"instrumented_gpu_ms":0.}
    check(Report.corroborate(empty,idle,0)["valid"],"explicit idle zero is valid")
    var profile: Dictionary={"status":{"supported":[{"id":81,"name":"GPU active cycles","unit":"cycles"}]},"telemetry":{"gpu_frequency":{"available":false,"reason":"permission"}},"blocks":[]}
    for i in range(6):profile["blocks"].append({"events":[{"serial":i}],"sample":sample.duplicate(true),"telemetry_before":profile["telemetry"],"telemetry_after":profile["telemetry"]})
    var compact: Dictionary=Report.compact(profile)
    check(compact["blocks"].size()==6 and compact["blocks"][5]["serials"]==[5],"all six blocks/serials retained")
    check(compact["blocks"][0]["sample"]["counter_values"]["81"]=="18446744073709551615","uint64 decimal survives copying")
    check(compact["blocks"][0]["telemetry_after"]["gpu_frequency"]==null and compact["telemetry"]["gpu_frequency"]["reason"]=="permission","unavailable telemetry not zero and reason retained")
    check(profile["blocks"][0].has("events") and profile["blocks"][0]["sample"].has("counters"),"full raw profile unchanged")
    var rich: Dictionary=profile.duplicate(true)
    for id in range(17):
        var name: String="synthetic format fixture "+str(id)+" description".repeat(8)
        rich["status"]["supported"].append({"id":id+1000,"name":name,"unit":"fixture"})
        for block in rich["blocks"]:block["sample"]["counters"][name]={"available":true,"kind":"uint64_decimal","value":"18446744073709551615","timestamp_ns":"9000000000000000"}
    var encoded: Dictionary=Report.compact(rich)
    check(JSON.stringify(encoded).to_utf8_buffer().size()<16384,"six rich hardware blocks fit half the copied-report budget")
    check(encoded["blocks"][5]["sample"]["counter_values"].size()==18 and rich["blocks"][5]["sample"]["counters"].size()==18,"counter values and raw rows retained")
    print("HARDWARE REPORT ",checks," ","FAIL" if failed else "PASS");quit(1 if failed else 0)
