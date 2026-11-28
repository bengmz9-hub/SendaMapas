# Historial de cambios

## 0.7.4 (2026-11-28)

Estado: alpha; los datos nuevos aún sin ver en el juego. Validación en Lua 5.1 con dobles: pasan `312 + 14` comprobaciones; simulación de la Guía A de principio a fin con el mismo resultado que en la 0.7.3 (cadena terminada, 737 misiones entregadas, nivel 60).

### Datos de misiones
- **Datos regenerados con QuestieDB 1.1.6** (antes 1.1.2), copiada de la versión instalada en el juego a `reutilizacion/20261128-snapshot-questiedb`. Las mismas misiones por mapa; cambian objetivos, PNJ, objetos y coordenadas según la base nueva.
- 36 misiones de las guías que no tenían datos de objetivos en la 1.1.2 los tienen ahora (Ironforge, Azshara, Mount Hyjal, Blackmaw Hold, Stranglethorn y otras), y 47 misiones que ya existían ganan coordenadas válidas: misiones con todos los objetivos localizados, de 1290 a 1372.
- Cambios de la propia QuestieDB que se aceptan tal cual: en Mount Hyjal (y unos pocos PNJ de otras zonas) varios enemigos pasan de un área de apariciones a un único punto; «Raene's Cleansing» (1046) cede la calavera de Ran Bloodtooth a la misión 1045; «Unstable Magic» (96603) se queda sin marcas de objetivo porque la base ya no dice quién suelta la mota; algunos objetos pierden fuentes de botín sobrantes.
- Sin cambios en los maestros de vuelo, en la tabla de zonas ni en las rutas guiadas.

### Créditos
- El README del addon indica que los datos de misiones, PNJ, objetos y coordenadas proceden de QuestieDB (proyecto Questie, GPL-3.0), usados con permiso de sus autores.
