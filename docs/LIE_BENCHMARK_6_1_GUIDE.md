# LIE Benchmark 6.1.0

Esta versión corrige trabajo redundante de reconstrucción detectado al analizar
tu benchmark físico de 6.0.1. Conserva las capturas, los materiales, el LOD y la
resolución predeterminada de salida 960 / interna 1920.

## Instalar y medir

1. Instala `LIE-Construccion-v6.1.0.apk` y abre **LIE Benchmark 6.1.0**.
   Se instala junto a 6.0.1; puedes conservar ambas para comparar.
2. Para empezar usa `corner`, semilla 2102 y salida 960 / interna 1920.
3. Pulsa **Benchmark y copiar informe**, arriba de la imagen. No hace falta
   recorrer los controles ni mover manualmente la luz durante la prueba.
4. Espera el mensaje **Informe copiado**, vuelve a ChatGPT y pégalo.

La prueba mueve cámara y luz en ambos modos: directa sin rebotes y dos rebotes.
Restaura tus controles al terminar. **Detener** cancela y conserva el contenido
anterior del portapapeles; **Copiar informe** permite copiar expresamente una
prueba parcial. El JSON completo puede guardarse desde el diálogo de informe.

El benchmark utiliza tu vista actual como base. El informe anterior tenía
giro −32.068°, elevación −2.164°, zoom 1 y centro sin desplazar. La vista inicial
de la app es distinta; comparar tiempos de cámaras diferentes no mide por sí
solo una aceleración exacta. El informe conserva esos controles para comprobar
la equivalencia. Mantén condiciones comparables del teléfono y no cambies la
resolución entre versiones al atribuir una ganancia a la corrección.

## Qué cambia

- Mover una luz conserva proyección, profundidad y acumulación material de la
  cámara. Girar la cámara conserva la sombra fina de una luz que no se movió.
- La geometría y su receta se preparan una vez mientras no cambie el conjunto.
- Cada banco despacha sus propios trabajos, manteniendo los propietarios y las
  direcciones globales de las muestras.
- Los splats recorren candidatos conservadores de la misma elipse; la
  acumulación descarta candidatos ocultos antes de comprobar soporte de fuente.
- El informe añade tiempos de GPU por etapa y contadores de pases ejecutados.
  Un pase conservado no aparece como un cálculo de cero milisegundos.
- La interfaz distingue FPS de presentación y tiempo de reconstrucción GPU.
  Presentar una imagen reutilizada no significa generar una imagen nueva.

La prueba comparativa directa/dos rebotes no es una comparación con un renderer
convencional. El radio energético conserva el valor que elegiste; la prueba
física anterior lo tenía apagado. Puede activarse en una segunda prueba para
estudiarlo, conservando la misma escena y vista.

## Qué falta comprobar en el teléfono

Las verificaciones nativas comparan las imágenes de esta versión con el código
fijado 6.0.1 y los mismos bancos. El Vulkan de CI es software: valida resultados,
pero sus tiempos no certifican la velocidad, temperatura ni consumo del Poco.
La nueva medición física dirá cuánto se redujeron los aproximadamente 512 ms de
apariencia y qué etapa sigue limitando el rendimiento. No se declara alcanzado
el objetivo de 60 FPS antes de esa medición.

RSS, PSS y las asignaciones gráficas son contabilidades diferentes y no se
suman. La app solo informa temperatura o frecuencia de GPU cuando Android
permite leerlas; no las estima a partir de los FPS.

Fuentes y diagnóstico técnico: `LIE_CONSTRUCTION_RECONSTRUCTION.md` en GitHub.
