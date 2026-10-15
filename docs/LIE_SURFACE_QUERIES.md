# LIE 1.3 — consultas residentes de superficie

Base exacta: `5fee70ee0f35f5f20199000993b113897e37c3dc`; runtime 1.2
validado `fbe2e0e6fd4b21980acf52205f30d8359436ad4e`. Se conserva el banco
`ca667dfc0e5f5de19190ef12c24395a99b2be66a418420bf30e61ba9ef253340`.

## Contratos de la nueva ruta

El maestro conserva muestras, BLAS y IDs; la instancia aporta su receta de
geometría; el mundo aporta las transformaciones/oclusores; la cámara selecciona
regiones de trabajo. `lie_surface_query_plan.gd` delimita la derivación residente
por dominio, ensamblaje, receta y schedule con longitudes explícitas. Cámara,
luces, potencia y tamaño de imagen no son claves de los límites del mundo.
El callback `lie_query_geometry` conserva las operaciones del adaptador de
pared aceptado. Los includes comunes no conocen 96 ladrillos ni 97 jobs.
El adaptador de pared sigue conservando esas recetas, fuera de los componentes
nuevos. No se declara haber sustituido todos los consumidores históricos.

GPU: cada bloque de 64 referencias obtiene límites de centros y de componentes
de normales, luego cada padre une hasta 16 bloques. Se generan una sola vez por
derivación del mundo. Cada cambio de cámara consulta primero padres y bloques,
aplica rechazo conservador por planos de vista/profundidad y orientación, y
construye un dispatch indirecto de bloques para proyección y raster. El halo
incluye el radio máximo del splat (8 píxeles), floor/ceil y margen numérico.
Los intervalos amplios pueden admitir trabajo de más; no sustituyen cobertura
ni profundidad. Todos los miembros seleccionados conservan sus slots originales.
La selección se mide antes de proyección: su coste no desaparece del informe.

Es una primera jerarquía residente, no un nuevo LOD adaptativo por error de
material ni un renderer completamente dirigido por tiles. Las muestras y los
LOD existentes permanecen iguales. También siguen iguales las ecuaciones de
recuperación; esta etapa reduce los candidatos antes de ejecutarlas.

## Testigos de oclusión

Se guarda un candidato (instancia de escena, ID de disco capturado) por referencia
y canal de luz. Un desplazamiento de luz puede conservar el candidato aunque
invalide el valor anterior de visibilidad. Para reutilizarlo se repite la
intersección EXACTA del disco, en las coordenadas locales de la instancia y con
el alcance/bias actuales. Se verifica dominio/rango y exclusión de la propia
muestra exclusivamente en su propia instancia.

Solo se certifica el caso completamente bloqueado: existe una intersección
válida entre bias y 0.75*limit. Esa evidencia basta para el resultado cero de
la ecuación existente aunque existan otros obstáculos. Un testigo fallido,+ausente, parcial o fuera de capacidad vuelve al recorrido global aceptado.
No se reutilizan respuestas de espacio libre ni se interpolan sombras entre
posiciones. Un candidato incorrecto nunca se acepta por su identidad: se retesta.
La codificación admite 1,024 instancias y source IDs menores de 4,194,303;
superar la capacidad simplemente deja el testigo vacío y conserva el recorrido.

Los testigos son pistas privadas del consumidor, no colores compartidos entre
instancias. La geometría maestra sí conserva las leases compartidas existentes.
Cambios de potencia continúan usando la caché geométrica anterior; los testigos
aceleran sus fallos cuando una luz cambia de posición. El transporte indirecto
sigue resolviendo su campo actual: actualización regional del grafo y
certificados de espacio libre permanecen investigación posterior.

## Recursos y compatibilidad

Dos SSBO adicionales: arena de cola/límites, y memoria de controles/estadísticas/
testigos. La ruta completa usa 32 SSBO, frente a 30 de 1.2; la primera propuesta
de cinco búferes se compactó antes de publicar para no elevarla a 35. El límite
se consulta con RenderingDevice.LIMIT_MAX_STORAGE_BUFFERS_PER_SHADER_STAGE.
Si el dispositivo ofrece menos de 32, se selecciona el shader 1.2 sin crear los
dos búferes adicionales, y el informe lo declara mediante supported=false.
Referencia primaria de la API:
https://github.com/godotengine/godot-docs/blob/master/classes/class_renderingdevice.rst

Memoria de testigos: 256 + referencias*32 bytes, cerca de 24.7 MB en esta pared.
La arena añade cola y jerarquía de bloques/padres, sin otra imagen completa.
Todo tiene vida útil y liberación dentro del consumidor existente. Runtime sin
lecturas de imagen/búfer; los contadores se leen solo por captura explícita de
los ensayos. La instrumentación atómica continúa apagada por defecto.

Comparaciones independientes surface_queries / occlusion_witnesses; informe
compacto y diagnóstico por cámara/potencia/posición heredados de 1.2. No hay
una afirmación de FPS del Mali antes de prueba física.

## Aceptación y negativos

Pruebas Python: shader generado, presupuesto de descriptores, 3,000 regiones
contra proyecciones individuales y 2,000 escenas de discos contra la condición
de bloqueo. Godot headless: 14 contratos de derivación, tipos/transacciones,
controles y copia compacta. Se compilan también los dos scripts de prueba GPU.
La primera ejecución local encontró una declaración múltiple de variables
GDScript inválida; se separó y se repitió el contrato (14 PASS). Se conserva
este negativo, sin atribuirlo a Vulkan o Android.

La CI dedicada debe comprobar contra float64 los testigos originales/movidos,+huecos, otro ejemplar del maestro, escala/rotación, metric fade, IDs inválidos y
ocho canales; comparar la imagen real con 1.2 y con ambos interruptores OFF,
vistas oblicuas y reversas, LOD, continuidad, área, resize y diagnóstico.
Los benchmarks de cámara fuerzan igual geometría por modo con luz restablecida;
los de posición usan el mismo punto de partida por modo. Cada etapa conserva
su serial GPU. No se mezclan CPU y GPU ni se presentan tiempos de software
Vulkan como rendimiento de Android. Los resultados se añadirán tras ejecutar.
