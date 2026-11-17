# Origen del código y de los datos

## Datos de misiones

Los módulos `SendaMapas_*` contienen datos de misiones generados por
`preparar_sendamapas.py` a partir de `guia-mapas-forever/` (captura local del
15-11-2026). La fuente declarada de esa captura es **wowhead.com/forever**
(listas de zonas y misiones y páginas de misión), complementada en la propia
captura con comprobaciones contra una base local.

- Estos datos son **para uso local**. No se ha revisado si los términos de uso
  de Wowhead permiten redistribuirlos. **Antes de publicar o compartir el
  paquete hay que comprobar esos términos** (y, si procede, pedir permiso o
  sustituir los datos).
  Campos concretos del paquete que proceden de `guia-mapas-forever/` (rastreables
  en `preparar_sendamapas.py`):
  - En `SendaMapas/Index.lua` (de `MAPAS_INDICE.json` y `mapas/*.json`):
    `source` (`capturedAt`), `order` (`progressionOrder.mergedWorldOrder` y
    `dungeons`), `maps[zoneId]` (`n` `name`, `g` `continentGroup`, `k`
    `instanceType`, `lo`/`hi` `wowheadMinLevel`/`wowheadMaxLevel`, `lb`
    `wowheadLevelRangeLabel`, `t` y `c` recuentos de misiones),
    `missingMaps[zoneId]` (`name` de los 8 mapas `MISSING`) y `modules`
    (agrupación y títulos).
  - En `SendaMapas/Data/SendaMapas_*.lua` (de `mapas/*.json` en `compact_map`
    y `entity`): `z` (`zoneId`/`zoneName` de inicio, entrega y spawns), `h`
    (`hubs[].hubName`), `q[]` (`i` `id`, `n` `name`, `l` `level`, `r` `reqLevel`,
    `x` `xp`, `f` máscara de `flags`, `sd` `side`, `h` índice de hub, `s`/`e`
    entidades `start`/`end` con `k`/`i`/`n`/`z`/`zn`/`c`/`d`, `o`
    `objectives.text`, `ot` nombres de `objectives.creatures`/`objects`/`items`,
    `p`/`nx`/`ex` de `chain`, `c`/`ra`/`pf` de `flags`) y `lk`
    (`chain.crossMapLinks`, completados con `QuestieDB` local cuando faltaban
    nombre o zona en la captura).
- **Posiciones de objetivos y tabla de zonas**: los campos `ob` de las
  misiones (puntos donde matar, recoger o usar, compactados a 6 puntos por zona
  y objetivo, más el campo opcional `e` con el nombre de la mazmorra cuando la
  coordenada apunta a su entrada exterior) y la tabla `areaUi` del índice (zona
  del juego -> mapa de interfaz) proceden de **QuestieDB**
  (https://github.com/Questie/QuestieDB, GPL-3.0), leída sin ejecutarla desde la
  copia fijada dentro del proyecto (`reutilizacion/20261108-203754/QuestieDB`,
  huella verificada en `MODULOS.md`). Son
  hechos del juego extraídos y reducidos por los scripts de
  `datos-navegacion/scripts`; no se incluye código ni la base completa de
  Questie, y **SendaMapas no necesita Questie ni ningún otro addon para
  funcionar**. Como estos datos derivan de una obra GPL-3.0, el paquete
  completo se rige por GPL-3.0-or-later (`LICENSE.txt`); Questie sigue siendo
  la fuente y sus avisos de licencia aplican a esos datos.
- No se incluye LibForeverData ni el resto de la base QuestieDB que lleva
  SendaMejora.
- Los datos se copian sin inventar valores. Transformaciones: campos
  reducidos, banderas en máscara de bits, nombres de clase (en español en la
  fuente) y de raza (en inglés) traducidos a los identificadores del juego
  (`WARRIOR`, `NightElf`...), misiones ordenadas por nivel dentro de cada mapa.
  `HighElf` como identificador de raza del cliente Forever **no está
  confirmado**.

## Código

El código Lua de SendaMapas reutiliza y adapta código de SendaMejora (mismo
proyecto local ADDONWOW): cargador bajo demanda, HUD, ventana de opciones,
flecha propia y lectura del registro de misiones; TomTom puede usarse como flecha alternativa si el jugador lo tiene, pero no hace falta.
SendaMejora declara su código propio como GPL-3.0-or-later; SendaMapas
mantiene esa licencia (texto en `LICENSE.txt`).

SendaMapas no depende de otros addons: no declara dependencias y no incluye ningún archivo de TomTom, Questie ni OpenMap.

## Imágenes y aspectos

Las imágenes de `Media/Arrow_*.tga` (flechas Lance, Solar, Aether, Talon, Pulse y Plume) y los seis aspectos de `Skins.lua` (colores, marcos y estructuras) son diseños originales hechos para este proyecto a partir de una especificación propia, sin recursos de terceros; las imágenes se generan con scripts de Python de la biblioteca estándar. La flecha «Blizzard» usa la textura del propio juego (`Interface\\Minimap\\ROTATING-MINIMAPARROW`), que no se incluye.
