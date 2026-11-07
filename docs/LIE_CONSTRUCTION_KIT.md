# Banco de construcción y conjuntos de assets

Esta fase identifica lo que admite el capturador actual, crea ocho fuentes de
autoría y las integra con el ladrillo real mediante conjuntos por referencia.
El escaneo y sus medios ladrillos conservan intacto el banco anterior.

## Compatibilidad del capturador actual

La compatibilidad corresponde al compilador opaco de 80 bytes y al consumidor
de construcción; importar una fuente no certifica su calidad visual.

| Familia | Estado | Condiciones |
| --- | --- | --- |
| Ladrillo, piedra, hormigón, mortero | Admitidos como geometría estática opaca | Marco, escala, procedencia y aceptación por pieza |
| Madera, yeso, cerámica, plástico opaco | Admitidos por la misma ruta | Material no metálico; geometría y normales reales |
| Bloques huecos, marcos, escombros | Admisibles con pruebas específicas | Verificar huecos, silueta y LOD |
| Suelo, rocas y terreno por fragmentos | Candidatos compatibles | Densidad y presupuesto de captura por fragmento |
| Tela rígida u otras láminas | Condicional | Geometría de ambas caras/espesor; no asumir doble cara por una bandera |
| Metal expuesto | Otra ruta de material | El compilador rechaza metallicFactor distinto de cero |
| Vidrio, agua, hojas mediante alpha | Otra ruta de captura/material | No hay transparencia, transmisión ni refracción en este ABI |
| Personajes con skinning/deformación | Integración específica | Capturar una pose no implementa deformación genérica |

Entrada: GLB/GLTF autorizado u OBJ con reinterpretación de material declarada.
Blender/FBX necesitan conversión conservando unidades, ejes y propiedades
soportadas. Este backend no captura normal maps tangentes, displacement, AO
separado, emisión o extensiones arbitrarias; no se eliminan silenciosamente.

Ya existen maestros históricos LIE28: bloque hueco, panel, losa, dintel,
esquinero, muros con aberturas y fragmentos. Su aceptación histórica está en
LIE_28_MODULAR_BUILDING.md; no implica que estén residentes en este banco.

El experimento assets/lie_mortar01/catalog.json declara que no está aceptado
y que sus recortes pueden contener píxeles de ladrillo. No se incorporó como
mortero fotográfico verificado. La clasificación comprobable se guarda en
assets/construction_kit/inventory.json.

## Ocho fuentes incorporadas

| Maestro | Papel |
| --- | --- |
| mortar_bed | Cama horizontal, con frente ligeramente cóncavo |
| mortar_head | Junta vertical independiente del ladrillo |
| mortar_corner | Retorno geométrico en L disponible para conjuntos |
| concrete_lintel | Cabezal sobre aberturas y pieza de marco |
| concrete_sill | Alféizar con superficie superior inclinada |
| plaster_panel | Panel opaco de revoco |
| timber_beam | Viga opaca, con variación de color de autoría |
| ceramic_tile | Teja curva cerrada de espesor finito |

Estas piezas son **geometría y materiales de autoría**, no nuevos escaneos ni
materiales fotográficos certificados. Tienen GLB, perfil Y arriba/Z al frente
en metros, dimensiones, procedencia, SHA, normales, color lineal y rugosidad.
El ladrillo sigue siendo el escaneo atribuido a Centre-of-Archaeology; sus
medios ladrillos siguen siendo cortes derivados.

## Composición por referencias

lie_asset_sets.py compila asset-sets.json. Un nodo referencia un maestro o
un conjunto hijo. Los padres admiten rotación propia y traslación; las escalas
positivas se declaran en hojas de autoría. Ladrillos escaneados y cortados
mantienen escala identidad. Se rechazan espejos, shear, escalado indirecto del
escaneo, ciclos, referencias ausentes, posiciones no finitas e IDs duplicados.

La identidad queda ligada al SHA del banco. Cada hoja recibe un propietario
estable según el banco y su ruta. No se fusionan las capturas en una malla
gigante de casa ni se sube un banco por ladrillo. El pool RenderingDevice
conserva su contrato.

Hay colecciones de albañilería, aberturas y acabado/cubierta: 37 definiciones
de conjunto contando variantes por semilla/estilo, y 46 escenas compiladas.
Se incluyen conjuntos anidados de vigas + tejas, un marco, una galería y ocho
vistas individuales. Esto no es todavía un solver genérico de conexiones.

## Juntas y aberturas

El adaptador construye mortero horizontal donde ambas hiladas tienen piezas,
y vertical donde contactan dos piezas. La red no atraviesa puertas o ventanas.
La profundidad del frente usa el percentil 20 observado en bordes de fuentes
adyacentes, menos 1.5 mm de retranqueo. Es un ajuste conservador aproximado:
no demuestra contacto exacto en cada poro ni certifica acabado interior o
relleno estructural completo. El XYZ/RGB del ladrillo permanece intacto.

Dinteles y alféizares sustituyen las piezas de la hilada prevista. Una pieza
parcialmente afectada pasa al medio ladrillo correcto; no se estira ni queda
un ladrillo entero superpuesto sobre el nuevo cabezal. Las dimensiones son
de esta cuadrícula visual, no un cálculo estructural.

La casa de semilla 2102 contiene 7,228 instancias, incluidas 2,421 camas y
2,298 juntas verticales. Conserva la cubierta gris anterior; vigas y tejas se
entregan como conjunto independiente. El retorno en L y el revoco están en
el banco y sus conjuntos; no se afirma que las esquinas ya estén resueltas.

## Mejoras comunes de captura

Los perfiles nuevos declaran grupos planos: se validan índices, partición
única, normales y coplanaridad. Se usa normal geométrica de cara y rectángulo
de soporte del grupo. Un radio máximo explícito permite cubrir piezas largas
sin el límite histórico de 9 mm elegido para ladrillos.

Son rectángulos de grupos, no recortes exactos de polígonos arbitrarios.
Persisten pequeñas imperfecciones en biseles/LOD; las pruebas de interior
opaco no certifican silueta perfecta. Los perfiles anteriores no activan
estas opciones y el prefijo del banco v2 permanece idéntico.

## Pruebas y presupuesto

Banco: **60,262,400 bytes**, 13 maestros (5 anteriores + 8 nuevos), dentro de
64 MiB. Se compone un banco residente; no se implementa streaming multibanco.
La biblioteca de fuentes puede crecer, pero se presupuestan los paquetes.

Local: Godot 4.7.2 / Mesa 25 / llvmpipe LLVM 19. **112 comprobaciones nativas**:
controles previos de geometría/material/caché, render de cada fuente y conjunto,
interior opaco, abertura sin invasión de dintel/alféizar y comandos inválidos.
Python: 275 pruebas, 274 aprobadas y una omitida. Rig 247; agente 25.
El verificador independiente revisa fuentes cerradas, procedencia, prefijo
inmutable, conjuntos y mortero sin cruce de aberturas.

Casa: 2,781,760 invocaciones, unos 463.3 MB de buffers/texturas exclusivos
más 60.3 MB compartidos, con salida 720 e interno 1440. No equivale a PSS ni
demuestra rendimiento Android. La luz continúa como GGX puntual + ambiente;
el campo indirecto compartido y las mediciones físicas móviles siguen pendientes.
CI run 42341452152 aprobó además 42 controles nativos de compatibilidad
y 112 del kit en llvmpipe LLVM 21.1.8. Sus 275 pruebas Python finalizaron
con 274 aprobadas y una omitida. El SHA del banco coincide exactamente con
el local. El checkpoint registra el artefacto y la evidencia de CI.

## Uso

Con el banco de LIE_Construccion_Intercalada_v2.zip, requirements-ci.txt y
el código de esta rama:

    PYTHONPATH=tools python tools/lie_construction_kit.py --base /ruta/bond --sources /tmp/kit-sources --output /tmp/kit-bank
    PYTHONPATH=tools python tools/lie_construction_verify.py --base /ruta/bond --bank /tmp/kit-bank --sources /tmp/kit-sources
    PYTHONPATH=tools python tools/lie_scanned_masonry_stage.py --bank /tmp/kit-bank --stage /tmp/kit-stage --test test_lie_construction_kit.gd

Abrir el proyecto aislado con Godot 4.7.2 Mobile/Vulkan. La interfaz usa
command() para pieza, muro, casa, galería, marco, cubierta, semilla, estilo y
acercamiento. Las mallas fuente no se dibujan en la cámara de LIE.

## Negativos conservados

La primera partición horizontal superó el límite de instancias: se reunieron
tramos compatibles. El primer render pasó controles numéricos pero mostró
huecos en piezas largas y muestras de bisel invadiendo aberturas; no se cuenta
como aceptación visual. El soporte por caras y las pruebas nuevas corrigen
esos casos principales. Se rechazaron tapas no planas de teja y se sustituyó
el abanico por triangulación de polígono. Se guarda el error inicial de tipado
en un test GDScript. Las limitaciones finas que continúan se indican arriba.
