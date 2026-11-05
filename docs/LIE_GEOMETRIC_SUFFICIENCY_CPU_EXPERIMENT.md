# Primer experimento de suficiencia geométrica — fixtures CPU

**Fecha:** 2026-11-04. **Estado:** ejecutado localmente con Python/NumPy, seis tests satisfactorios. **NO es una prueba del shader Vulkan de LIE**, ni utiliza los bancos de Blender ni demuestra que el fallo concreto del teléfono tenga esta causa.

Código: [herramienta](../tools/lie_geometric_sufficiency_probe.py) y [pruebas](../tests/test_lie_geometric_sufficiency_probe.py).

## Hipótesis separadas

- **Original (source):** superficie analítica consultada por un rayo ortográfico paralelo a -Z.
- **Captura (representation):** muestras de posiciones y pendiente de plano tangente en una retícula de 0.25 metros, soporte rectangular finito de 0.125 metros por eje. No se consulta el original al reconstruir.
- **Consumidor (consumer):** segunda implementación CPU que proyecta las mismas muestras por regiones de píxeles y resuelve la superficie más cercana. Es independiente del bucle ray-by-ray del oráculo de representación, **pero no es una ejecución ni reproducción bit a bit del shader de LIE**.

La resolución es 160x160. Umbral de aviso de profundidad: 5 mm. Para el plano, la pared y el bulto solo se examina la superficie frontal. El cilindro se representa únicamente por su semicircunferencia frontal y una banda vertical: este experimento no cubre tapas traseras, giro de cámara ni oclusión general. Las tolerancias y el muestreo son deliberados y **no representan parámetros de LIE-27**.

## Resultado observado en ejecución local

| Caso | Muestras | Original→Representación (faltantes/extra) | Profundidades >5 mm | Máximo error de profundidad | Representación→Consumidor |
|---|---:|---:|---:|---:|---|
| Plano | 81 | 0 / 0 | 0 | 0 | Sin diferencias |
| Pared con hueco | 80 | 0 / 176 | 0 | 0 | Sin diferencias |
| Cilindro | 35 | 480 / 2,000 | 6,240 | 0.073254 m | Sin diferencias |
| Plano con relieve oculto | 81 | 0 / 0 | 148 | 0.293024 m | Sin diferencias |

**Interpretación:**
1. Plano: control positivo, ambas representaciones y el consumidor coinciden.
2. Hueco: una muestra fuera del borde puede extender su parche a una región que el original define vacía; es pérdida de fidelidad del soporte capturado.
3. Cilindro: los planos tangentes locales no reproducen exactamente una superficie curva; parte de la silueta se pierde o se inventa.
4. Relieve oculto: dos superficies diferentes producen **exactamente el mismo conjunto de muestras (mismo SHA-256)** porque el relieve suave cae entre puntos de captura. La reconstrucción no puede identificar qué superficie original existía.

Los cuatro casos coinciden entre el oráculo de *representación* y el *consumidor CPU*, incluyendo la identidad ganadora y la profundidad calculada. Esto **no** implica que el consumidor GPU de LIE sea correcto: solo prueba que el experimento clasifica limpiamente ciertos errores de información antes de entrar en Vulkan.

## Reproducción

Con Python 3 y NumPy en la raíz del repositorio:

~~~bash
python -m unittest discover -s tests -p 'test_lie_geometric_sufficiency_probe.py' -v
python tools/lie_geometric_sufficiency_probe.py --output /tmp/lie-geometric-sufficiency.json
~~~

El JSON conserva cantidad de impactos, diferencia de profundidad, identificador del parche ganador y SHA-256 de las muestras. El hash del plano es igual al del relieve oculto: ae17347bd2b956c7d7a1efa2de3e4d56e14f2851e643654ed794a04f9cdf30f9.

## Qué podemos concluir y qué NO

**Sí podemos concluir:** para una familia de representaciones basada solo en centros, normales/pendientes y parches finitos, existen escenas que no pueden distinguirse a partir de sus capturas. La proyección posterior no recupera datos nunca registrados.

**No podemos concluir:** que los activos reales de LIE carezcan de esa información; que cambiar el esquema de muestreo solucione sus fallos; que el rendimiento móvil sea insuficiente; que la reproducción GPU ya haya sido verificada aquí; ni que este resultado justifique migrar a mallas rasterizadas, SDF u otra tecnología.

## Siguiente discriminador que falta

1. Ejecutar las pruebas existentes de LIE-14, LIE-22 y LIE-27 con sus bancos de captura completos, oráculos nativos y capturas reales de ganadores/profundidad, no de este consumidor CPU.
2. En la rama work/lie-native-depth, comparar **fuente Blender → celda finita → GPU** en la pose reproducible del teléfono; los resultados preservados comparan sobre todo regiones/celdas, no establecen equivalencia con la fuente Blender.
3. Emitir máscara/propietario/profundidad antes de iluminación; comparar después imagen con y sin sombras. Si la representación coincide con fuente pero GPU difiere, clasificar como consulta; si GPU coincide pero RGB difiere, como apariencia.
4. Solo después de clasificar los fallos de datos concretos, considerar un nuevo contrato de superficie canónica, sin renunciar a la jerarquía/colisiones invisibles de LIE.

**Decisión:** no cambiar el renderizador ni main con este experimento; avanzar al oráculo de fuente con activos reales antes de fijar arquitectura.
