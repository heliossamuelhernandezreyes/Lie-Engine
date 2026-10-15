extends RefCounted
## Shared import/runtime identity contract; no per-pixel file lookup.
static func validate(manifest: Variant,catalog: Dictionary) -> Dictionary:
    if not manifest is Dictionary or manifest.get("schema")!="lie-asset-contract/1":return {"ok":false,"error":"asset_contract_schema"}
    if manifest.get("bank_sha256")!=catalog.get("sha256") or int(manifest.get("bytes",-1))!=int(catalog.get("bytes",0)):return {"ok":false,"error":"asset_contract_bank"}
    var assets: Variant=manifest.get("assets",{})
    if not assets is Dictionary or assets.is_empty():return {"ok":false,"error":"asset_contract_masters"}
    if assets.size()!=catalog.get("masters",{}).size():return {"ok":false,"error":"asset_contract_masters"}
    var ids: Dictionary={}
    for master in catalog.get("masters",{}):
        if not assets.has(master):return {"ok":false,"error":"asset_contract_master"}
        var entry: Dictionary=assets[master]
        if entry.get("bank_sha256")!=catalog["sha256"] or entry.get("stride")!=80 or entry.get("levels")!=catalog["masters"][master]["levels"]:return {"ok":false,"error":"asset_contract_ranges"}
        var id: String=str(entry.get("asset_id",""))
        var ranges: PackedStringArray=[]
        for level in entry["levels"]:ranges.append(str(int(level["start"]))+":"+str(int(level["count"])))
        var recipe: String=str(catalog["sha256"])+"|"+str(master)+"|80|"+",".join(ranges)
        if id.length()!=64 or ids.has(id) or recipe.sha256_text()!=id:return {"ok":false,"error":"asset_contract_id"}
        ids[id]=master
    return {"ok":true,"assets":assets.size(),"source_identity":catalog["sha256"]}
