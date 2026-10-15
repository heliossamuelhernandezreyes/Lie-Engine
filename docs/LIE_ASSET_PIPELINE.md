# Maestros LIE: contrato común y reconstrucción de luz

La corrección de WALL06 resolvió un escaneo concreto. La siguiente base del
motor separa las decisiones semánticas de cada fuente de los algoritmos
compartidos. Se conservan el banco y la geometría aceptados de la pared;
esta versión no cambia la forma, fotografía ni mortero geométrico.

## Entrada común

`lie_asset_capture.py` compila GLB/GLTF/OBJ autorizado usando un perfil con
unidades, pivote, rotación propia, nombre de maestro y propiedades ópticas.
No elige arriba/frente por cuál dimensión es más larga. El capturador histórico
conserva su interfaz y banco determinista; informa su orientación como heurística.

`planar_frame` recibe una selección explícita de superficie y pistas semánticas
frente/derecha. Verifica confianza y volumen de la covarianza antes de una
rotación rígida. Rechaza superficies curvas/ambiguas: un personaje necesita
un marco autorado, no la regla del ladrillo. WALL06 ahora usa esa misma función
y reproduce el SHA anterior exacto.

El preflight común revisa SHA/ABI, finitud, normales unitarias, radios, albedo
lineal/rugosidad, soportes, precisión entera de IDs y rangos LOD. LODs que
reutilizan explícitamente el mismo rango son válidos. Los IDs se derivan de
`SHA del banco | maestro | 80 | start:count,...`. El loader común Godot verifica
esa identidad cuando existe el contrato, y la exige para nuevas capturas con
marco semántico declarado. Los bancos históricos siguen funcionando.

```sh
python tools/lie_asset_capture.py --source objeto.glb --provenance fuente.json \
  --profile perfil.json --output captura --counts 220000 52000 9000
python tools/lie_asset_contract.py --bank captura/library.bin \
  --catalog captura/catalog.json --output captura/asset-contract.json
```

Ejemplo de perfil para una fuente que ya esté en metros con ejes LIE:

```json
{"master":"pieza","source_to_lie":[[1,0,0],[0,1,0],[0,0,1]],
 "meters_per_source_unit":1,"source_pivot":[0,0,0],"material_zone":5,
 "source_material_policy":"preserve_source",
 "optical_material":{"metallic":0,"transmission":0,"ior":1.5,
                     "roughness_origin":"source_factor"}}
```

Este backend captura geometría, base color y rugosidad de fuentes opacas no
metálicas. Mantiene normales geométricas para la profundidad. No incorpora
normal maps de sombreado, transparencia ni refracción en el banco de 80 bytes.
Emisión, AO separado, extensiones de material y transformaciones/UV alternativos
también requieren otro backend o una reinterpretación explícita.
En GLB/GLTF, `preserve_source` rechaza esos atributos si no están soportados;
`declared_opaque_override` registra una reinterpretación de autoría explícita.
OBJ requiere esa declaración explícita porque este backend no certifica toda
la semántica MTL. El perfil no certifica que una propiedad esté físicamente
medida; bancos de dependencias externas y materiales complejos necesitan
proveniencia y aceptación específicos. Preflight tampoco demuestra
cobertura fotográfica de todas las vistas.

La residencia sigue usando el pool existente: un banco SHA por RenderingDevice,
IDs numéricos a su búfer, y estados de cámara separados. No hay búsqueda de
fotografías, lectura de almacenamiento por píxel o copia por ladrillo.

## Luz común

`shaders/lib/lie_irradiance_stencil.glslinc` reconstruye la irradiancia ya
resuelta por LIE11. El host suministra posición/normal/área y grupos compatibles
de nodos. Los pesos son convexos, según distancia tangencial y coherencia
normal; el piso depende del área del nodo. No agrega una luz ni difumina RGB
fotográfico. Normales opuestas y propietarios distintos quedan fuera.

El adaptador WALL07 declara un grupo por ladrillo y un grupo para el mortero
continuo. La caché de recuperación guarda la combinación RGB por nodo para
reiluminar sin buscar vecinos otra vez. La recuperación fotográfica conserva
sus comprobaciones de propietario, soporte y profundidad. La geometría y
cobertura deben coincidir con WALL06 cuando se desactiva la interpolación.
Cambiar luz/absorción conserva proyección y caché. Cambiar el modo de
reconstrucción rehace coeficientes con una reconstrucción fría una vez.

La biblioteca no conoce ladrillos, hileras o un número fijo de maestros. Este
adaptador admite hasta nueve nodos por grupo por el registro de caché existente;
no implica soporte general de cualquier número de nodos o de cualquier BSDF.
La suma convexa evita superar irradiancias vecinas, pero no certifica la
integral de flujo sobre toda la superficie ni sombras exactas: puede suavizar
fronteras de sombra de los nodos gruesos. El solver pasivo/CSR queda intacto.

## Aceptación

Regresiones con banco real escaneado y panel de hormigón LIE31 existente.
El panel deriva de geometría autorada LIE30/31; no es un escaneo nuevo de
hormigón. La prueba Vulkan de la misma biblioteca usa 80 consultas de ambas
fuentes y una referencia float64. Hay pruebas analíticas adicionales de
convexidad, luz constante, continuidad, aislamiento y modo anterior.

La aceptación de la pared compara modo OFF con WALL06, caché con reconstrucción
fría en modo ON, fuente/material/una envolvente, transporte float64 y cambio
de resolución. El APK LIE Pared 0.4 se construye offline ARM64, mantiene el
2× apagado y permite activar/desactivar “Luz continua entre regiones”.
Las mediciones Vulkan son llvmpipe; FPS y temperatura Android requieren el Poco.

Orden para nuevos tipos: fuente y perfil → contrato → banco compartido por ID
→ prueba nativa multivista/LOD/material/luz/caché → instancia en juego.
Cada nuevo fallo debe conservar su caso y convertirse en una prueba reutilizable.
No se declara “bien a la primera” solo por haber importado un modelo.

Fuentes primarias:
[Khronos glTF 2.0](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html)
y [PBRT Surface Reflection](https://pbr-book.org/4ed/Radiometry%2C_Spectra%2C_and_Color/Surface_Reflection).

## Resultados negativos conservados

El primer commit remoto `829022d` incluía solo cuatro de siete grupos de
archivos; faltaban generadores y shaders. Se completó en `05b770e` antes de
la aceptación válida. La primera ejecución local de captura no encontró
`trimesh`; se instalaron dependencias en un directorio temporal separado y
las regresiones se repitieron. No se interpretan esos casos como aceptación.
La guardia de atributos se extendió a GLTF externo y OBJ para evitar un
fallback silencioso de materiales fuera del backend soportado.
