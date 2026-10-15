extends RefCounted
## Timestamp deltas, asynchronously collected; no GPU synchronization/readback.
var _rows: Array=[]
var _seen: Dictionary={}
var _mutex:=Mutex.new()
func marker(owner_id: int,serial: int,pass_name: String,edge: String) -> String:
    return "liepass|%d|%d|%s|%s" % [owner_id,serial,pass_name,edge]
func collect(rd: RenderingDevice,owner_id: int) -> void:
    var groups: Dictionary={}
    for i in range(rd.get_captured_timestamps_count()):
        var parts: PackedStringArray=rd.get_captured_timestamp_name(i).split("|")
        if parts.size()!=5 or parts[0]!="liepass" or parts[1]!=str(owner_id):continue
        var key: String=parts[2]+"|"+parts[3]
        if not groups.has(key):groups[key]={"serial":int(parts[2]),"pass":parts[3]}
        groups[key][parts[4]]=rd.get_captured_timestamp_gpu_time(i)
    _mutex.lock()
    for key in groups:
        var row: Dictionary=groups[key]
        if _seen.has(key) or not row.has_all(["begin","end"]) or row["end"]<=row["begin"]:continue
        _seen[key]=true;_rows.append({"serial":row["serial"],"pass":row["pass"],"gpu_ns":row["end"]-row["begin"]})
    if _rows.size()>840:
        _rows=_rows.slice(_rows.size()-840);_seen.clear()
        for row in _rows:_seen[str(row["serial"])+"|"+row["pass"]]=true
    _mutex.unlock()
func snapshot() -> Dictionary:
    _mutex.lock();var rows: Array=_rows.duplicate(true);_mutex.unlock()
    var buckets: Dictionary={};var result: Dictionary={}
    for row in rows:
        var name: String=row["pass"]
        if not buckets.has(name):buckets[name]=[]
        buckets[name].append(float(row["gpu_ns"])/1000000.)
    for name in buckets:
        var samples: Array=buckets[name];samples.sort();var n: int=samples.size()
        result[name]={"samples":n,"p50_ms":samples[clampi(ceili(.5*n)-1,0,n-1)],"p95_ms":samples[clampi(ceili(.95*n)-1,0,n-1)]}
    return {"available":not rows.is_empty(),"units":"GPU milliseconds","passes":result,"rows":rows,"scope":"changed-image solves only; cached idle has no new samples"}
