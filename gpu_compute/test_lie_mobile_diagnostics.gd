extends SceneTree
const D=preload("res://lie_mobile_diagnostics.gd")
var checks: int=0
var failed: bool=false
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failed=true;printerr("DIAGNOSTIC FAIL ",label)
func _initialize() -> void:
    var rows: Array=[]
    var context: Dictionary={"internal_size":1080,"event_kind":"geometry","physical_lights":2}
    for serial in range(1,4):
        for pair in [["clear",1.],["project",2.],["raster",8.],["output",1.]]:
            rows.append({"serial":serial,"pass":pair[0],"gpu_ns":pair[1]*1e6,"context":context})
    rows.append({"serial":4,"pass":"raster","gpu_ns":999e6,"context":context})
    rows.append({"serial":5,"pass":"output","gpu_ns":2e6,"context":{"internal_size":1440,"event_kind":"exposure","physical_lights":8}})
    rows.append({"serial":6,"pass":"output","gpu_ns":NAN,"context":context})
    var result: Dictionary=D.summarize({"rows":rows})
    check(result["groups"].size()==2 and result["rejected_rows"]==1,"separate contexts and reject invalid duration")
    var group: Dictionary=result["groups"][0]
    check(group["serials"]==[1,2,3],"incomplete asynchronous event excluded")
    check(group["total_instrumented_gpu"]["p50_ms"]==12. and group["total_instrumented_gpu"]["samples"]==3,"sum actual disjoint passes by solve")
    check(group["largest_gpu_pass"]=="raster" and is_equal_approx(group["ranking"][0]["share_of_pass_medians_percent"],200./3.),"dominant GPU pass with explicit denominator")
    check(D.summarize({"rows":rows},5)["groups"].size()==1,"old samples excluded by serial")
    check(not D.summarize({})["available"],"missing timestamps never become zero-time success")
    check(D.percentiles([1.,2.,3.,4.,5.])["p95_ms"]==5.,"nearest-rank p95")
    check(D.brief(result).contains("1440"),"summary reports its own context")
    print("DIAGNOSTIC SUMMARY ",checks," ","FAIL" if failed else "PASS");quit(1 if failed else 0)
