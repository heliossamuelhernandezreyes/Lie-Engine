extends SceneTree
class AuditLab extends "res://lie_construction_proxy_lab.gd":
    const AuditEffect=preload("res://lie_architecture_audit_effect.gd")
    func _create_effect() -> CompositorEffect:return AuditEffect.new(output_resolution)
var failed: bool=false
func _initialize() -> void:call_deferred("run")
func settle(n: int) -> void:
    for i in range(n):await process_frame
func run() -> void:
    var lab:=AuditLab.new();lab.state.field_lighting=false;lab.output_resolution=960;root.add_child(lab);await settle(18)
    var rows: Array=[]
    for close_view in [false,true]:
        var name: String="close" if close_view else "whole"
        var command: Dictionary={"mode":"corner","seed":2102,"field_lighting":false,"camera_guard":false,"camera_culling":close_view,"yaw":0. if close_view else -25.,"elevation":0. if close_view else 22.,"zoom":.25 if close_view else 1.,"focus_x":.6 if close_view else 0.,"focus_y":0.,"reverse_banks":false}
        if not lab.command({"op":"set_values","values":command}).ok or not lab.metrics.get("configured",false):failed=true;break
        await settle(10)
        var start_serial: int=lab.effect.frame_count+2
        for i in range(6):
            # Existing validated diagnostic control forces an independent
            # rerasterization at a FIXED pose; final ordering is canonical.
            var before: int=lab.effect.frame_count;lab.command({"op":"set_values","values":{"reverse_banks":i%2==0}})
            var advanced: bool=false
            for wait_frame in range(600):
                await process_frame
                if lab.effect.frame_count>before:advanced=true;break
            if not advanced:failed=true;break
            await settle(6)
        await settle(10)
        lab.effect.export_fixture(ProjectSettings.globalize_path("res://architecture-fixtures/"+name),start_serial)
        var result: Dictionary={}
        for i in range(600):
            await process_frame;result=lab.effect.export_result()
            if not result.is_empty():break
        if result.is_empty() or not result.has_all(["godot_profile","godot_cpu"]) or result.godot_profiles.size()!=5:failed=true;break
        rows.append(result)
    var file:=FileAccess.open("res://architecture-godot.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failed":failed,"cases":rows,"physical_android_tested":false},"  "));file.close()
    lab.queue_free();await settle(16);print("ARCHITECTURE EXPORT ","FAIL" if failed else "PASS"," ",rows.size());quit(1 if failed else 0)
