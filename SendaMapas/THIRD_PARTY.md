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
- **Posiciones de objetivos y tabla de zonas**: los campos `ob` de las
  misiones (puntos donde matar, recoger o usar, compactados a 6 puntos por zona
  y objetivo) y la tabla `areaUi` del índice (zona del juego -> mapa de interfaz)
  proceden de **QuestieDB** (https://github.com/Questie/QuestieDB, GPL-3.0),
  leída sin ejecutarla en la instalación local de Forever el 15-11-2026. Son
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
