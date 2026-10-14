extends "res://lie_wall05_optical_transport.gd"
func transport_root() -> String:return "res://captures/liewall06/"
func optical_capture_root() -> String:return "res://captures/liewall06/"
func optical_metrics() -> Dictionary:
    var result: Dictionary=super.optical_metrics()
    result["graph"]="WALL06 rebuilt CSR from rigidly aligned scan and recalibrated photo mortar"
    return result
