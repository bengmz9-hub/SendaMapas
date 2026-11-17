# Historial de cambios

## 0.2.0-alpha (2026-11-17)

Estado: alpha sin probar aún en el cliente real de WoW Forever (`Interface 16001`). Se ha validado con Lua 5.1 y dobles de la API de WoW (66 + 13 comprobaciones), y el paquete con `validar_paquete_sendamapas.py`.

### Nuevo
- **Todo desde las opciones**: pestaña «Acciones» (saltar, devolver saltadas, quitar destino, recolocar flecha, ir al mapa donde estás, mapa anterior/siguiente, releer progreso, resumen, borrar errores) y todos los ajustes con control en el panel; los comandos `/smapas` siguen existiendo. Tabla «comando → dónde está» en el README.
- **Entrega automática de misiones** (activada por defecto; `Shift` la pausa; `/smapas autoentregar no` o el interruptor de Seguimiento la quitan). Solo entrega misiones terminadas, nunca acepta; con varias recompensas deja la ventana abierta y no la reabre hasta la siguiente entrega. En gossip prueba `questID`, índice y la API antigua. Aviso explicativo la primera vez.
- **Atajos de teclado** (`Bindings.xml`): mostrar/ocultar panel, misión siguiente/anterior, marcar destino, selector de mapas, saltar.
- **Saltar misiones**: `/smapas saltar`, clic derecho en la fila o botón; contador en el pie; `/smapas restaurar` las devuelve.
- **Orden de la lista por cercanía** (opcional, `/smapas orden progresion|cercania`).
- **Tooltips**: filas del panel (id, nivel, PX, inicio, cadena con estados), pines del minimapa y `Alt+clic` para abrir la misión previa o siguiente aunque esté en otro mapa.
- **Accesibilidad y diagnóstico**: tamaño de texto (Pequeño/Normal/Grande), símbolos de estado opcionales (`[!] [*] [?] [v]`), sonido opcional al completar, ventana de diagnóstico copiable con `[!]` cuando hay errores, `/smapas api`, exportar/importar configuración visual (sin progreso).
- **Mapa elegido a mano**: se mantiene hasta que cambias de zona.

### Mapa y minimapa
- Iconos y malla nuevos: malla roja para matar y azul para recoger, línea de ruta con flechas, estrella de destino.
- Los «!» de misiones que aún no puedes recoger (previas o nivel) salen grises con el motivo en el tooltip, sin objetivos ni malla (`/smapas bloqueadas off` los oculta); nunca tapan un «?» de entrega y el «?» se dibuja encima.
- Las misiones de tu registro nunca dibujan «!» de recoger; las de objetivos terminados no dibujan malla ni monstruos.
- Objetivos dentro de una mazmorra: se marcan como «Entrada de <mazmorra>» sin malla de objetivo.
- Clic en una marca del mapa: marca la ruta; otro clic la quita y deja libre el destino.
- Mapas sin misiones registradas muestran un aviso en lugar de «no se reconoce el mapa».

### Aspectos
- Siete aspectos; Táctico con fondo oscuro y botones turquesa con texto azul marino; indicador `+`/`-` de fila desplegable en todos; botón «Marcar destino» con rol principal; más contraste en Códice y Expedición; Táctico definido como datos en el generador.

### Motor
- Caché de estados por refresco (≈10× menos consultas), minimapa sin trabajo repetido por fotograma y con soporte de minimapa cuadrado, cachés de nombres de zona, respaldo de APIs, versión y migración de los datos guardados, y manejador de errores que se reengancha sin romper a otros addons.
- Arreglos: panel que se desplazaba con texto Pequeño/Grande, protección del minimapa en combate, `RenderHUD` con `pcall`, avisos duplicados, línea de ruta del minimapa, importación de configuración y otros.
- Objetivos emparejados por posición cuando el cliente no está en inglés.

### Datos y generadores
- Misiones ordenadas respetando cadenas y agrupando por zona y cercanía (violaciones previa→siguiente 229 → 0; saltos grandes −35 %).
- Enlaces de cadena sin mapa o sin nombre: 131 → 0 y 87 → 0 (datos locales de QuestieDB).
- Misiones con todos los objetivos con coordenadas: 70,7 % → 79,9 %; 272 objetivos de mazmorra resueltos a su entrada exterior.
- 19 módulos de datos; `ns.Index.missingMaps` con los 8 mapas sin módulo.
- QuestieDB fijado en una copia del proyecto (`reutilizacion/20261117-snapshot-questiedb`, huella SHA-256 registrada en `MODULOS.md`); el generador falla si falta o si quedan módulos huérfanos. `THIRD_PARTY.md` detalla qué campos proceden de Wowhead Forever.

Nota: la redistribución pública de los datos derivados de Wowhead Forever no está verificada (ver `THIRD_PARTY.md`); por eso no se publica en CurseForge/Wago por ahora.

## 0.1.0-alpha (2026-11-15)
- Primera versión pública: guía de misiones por mapa, panel con aspectos, flecha propia, marcas en mapa y minimapa, filtros y ventana de opciones.
