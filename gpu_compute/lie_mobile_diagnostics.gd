extends RefCounted
## Pure reduction of real timestamp rows. Never estimates GPU work from FPS.
const TITLES={"clear":"Preparación", "project":"Proyección", "raster":"Profundidad y cobertura", "material_filter":"Filtro de material", "coarse_light":"Iluminación base", "fused_base":"Iluminación y composición", "compose":"Composición", "recovery_build":"Reconstrucción de huecos", "recovery_reuse":"Recuperación reutilizada", "surface_light":"Material, relieve y sombras", "visibility_keys":"Claves de sombras", "visibility_invalidate":"Invalidación de sombras", "source_visibility":"Visibilidad 3D", "world_visibility":"Visibilidad 3D", "filter_recovery_clear":"Preparación del filtro", "output":"Salida"}
static func percentiles(values: Array) -> Dictionary:
    if values.is_empty():return {"samples":0}
    var ordered: Array=values.duplicate();ordered.sort();var n: int=ordered.size()
    return {"samples":n,"p50_ms":ordered[clampi(ceili(.5*n)-1,0,n-1)],"p95_ms":ordered[clampi(ceili(.95*n)-1,0,n-1)],"max_ms":ordered[-1]}
static func summarize(profile: Dictionary, minimum_serial: int=0, event_kinds: Dictionary={}) -> Dictionary:
    var events: Dictionary={};var groups: Dictionary={};var rejected: int=0
    for row in profile.get("rows",[]):
        var serial: int=int(row.get("serial",-1));var ns: float=float(row.get("gpu_ns",-1))
        if serial<minimum_serial:continue
        if not is_finite(ns) or ns<0 or not row.get("context") is Dictionary:rejected+=1;continue
        if not events.has(serial):
            var context: Dictionary=row["context"].duplicate(true)
            if event_kinds.has(serial):context["diagnostic_kind"]=event_kinds[serial]
            events[serial]={"context":context,"passes":{}}
        events[serial]["passes"][str(row["pass"])]=ns/1e6
    for serial in events:
        var event: Dictionary=events[serial];var context: Dictionary=event["context"];var passes: Dictionary=event["passes"]
        # All accepted solves end with output. Incomplete asynchronous rows are
        # retained in the raw report but excluded from sums and rankings.
        if not passes.has("output"):continue
        if context.get("event_kind")=="geometry" and not passes.has_all(["clear","project","raster"]):continue
        var key: String=JSON.stringify(context,"",true,true)
        if not groups.has(key):groups[key]={"context":context,"serials":[],"pass_samples":{},"totals":[]}
        var group: Dictionary=groups[key];var total: float=0.
        for name in passes:
            total+=float(passes[name])
            if not group["pass_samples"].has(name):group["pass_samples"][name]=[]
            group["pass_samples"][name].append(passes[name])
        group["totals"].append(total);group["serials"].append(serial)
    var result: Array=[]
    for key in groups:
        var group: Dictionary=groups[key];var ranking: Array=[];var median_sum: float=0.
        for name in group["pass_samples"]:
            var stats: Dictionary=percentiles(group["pass_samples"][name]);stats["pass"]=name;stats["title"]=TITLES.get(name,name)
            median_sum+=stats["p50_ms"];ranking.append(stats)
        ranking.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:return a["p50_ms"]>b["p50_ms"])
        for row in ranking:row["share_of_pass_medians_percent"]=100.*row["p50_ms"]/median_sum if median_sum>0 else 0.
        result.append({"last_serial":group["serials"].max(),"context":group["context"],"serials":group["serials"],"total_instrumented_gpu":percentiles(group["totals"]),"ranking":ranking,"largest_gpu_pass":ranking[0]["pass"] if not ranking.is_empty() else ""})
    result.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:return a["last_serial"]<b["last_serial"])
    return {"available":not result.is_empty(),"groups":result,"rejected_rows":rejected,"scope":"Disjoint appearance passes grouped by identical options, resolution and event kind. GPU sum excludes CPU, transport and uninstrumented engine work. Largest GPU pass is not proof of a whole-system bottleneck."}
static func brief(summary: Dictionary) -> String:
    var groups: Array=summary.get("groups",[])
    if groups.is_empty():return "GPU: todavía sin eventos completos. Mueve la vista o pulsa Medir modo actual."
    var group: Dictionary=groups[-1];var context: Dictionary=group["context"];var stats: Dictionary=group["total_instrumented_gpu"]
    var text: String="GPU · %s · %d px · %d eventos\nSuma de etapas: p50 %.2f ms · p95 %.2f ms" % [context.get("diagnostic_kind",context.get("event_kind","cambio")),context.get("internal_size",0),stats["samples"],stats["p50_ms"],stats["p95_ms"]]
    for row in group["ranking"].slice(0,3):text+="\n%s: %.2f ms (%.0f%%)" % [row["title"],row["p50_ms"],row["share_of_pass_medians_percent"]]
    return text
