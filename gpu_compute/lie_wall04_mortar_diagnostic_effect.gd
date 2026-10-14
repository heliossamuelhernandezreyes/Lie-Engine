extends "res://lie_wall04_mortar_effect.gd"
## Diagnostic ONLY. Green identifies samples of photographed mortar that have
## survived native GPU raster/projection and depth tests. Not product lighting.
const MortarCoverageDiagnosticShader: RDShaderFile=preload("res://shaders/lie_wall04_mortar_coverage_diagnostic.glsl")
func shader_resource() -> RDShaderFile:
    return MortarCoverageDiagnosticShader
