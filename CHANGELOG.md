# Historial de cambios

## 0.6.7-alpha (2026-11-24)

Estado: alpha; traducción al español de misiones, pasos y consejos de las rutas guiadas aún sin ver en el juego. Validación en Lua 5.1 con dobles: pasan `221 + 14` comprobaciones.

### Traducción al español
- **Misiones de los mapas hasta Wetlands y de las rutas guiadas A y B** (`datos-navegacion/traducciones_misiones_es.json`, `preparar_sendamapas.py`, `SendaMapas/Data/*.lua`, `Index.lua`): `2.038` misiones traducidas al español (títulos `n`, textos de objetivo `o`, enlaces entre mapas `lk`/`rn` y cabeceras/intermedias de `Index.lua`), conservando en inglés los nombres propios de PNJ, criaturas, objetos, hechizos y lugares y manteniendo intactos los nombres de seguimiento `ob.n` para el cruce con `C_QuestLog.GetQuestObjectives`.
- **Guía A y Guía B completas en español** (`datos-navegacion/traducciones_textos_es.json`, `datos-navegacion/traducciones_tips_es.json`, `rutas-locales/generar_rutas_locales.py`, `SendaMapas/Rutas.lua`): traducidos los títulos de paso `name` (`1.708` misiones únicas de A y B), `1.215` textos únicos de paso `text` y todos los consejos `tips` de las `42` guías A y `53` guías B, manteniendo `g.name`, `g.next` y `label` (nombres propios) en inglés.

## 0.6.6-alpha (2026-11-24)

Estado: alpha; el interruptor de la aceptación automática aún sin ver en el juego. Validación en Lua 5.1 con dobles: pasan `221 + 14` comprobaciones.

### Opciones
- **Interruptor «Aceptar las misiones que pide la guía» en Seguimiento** (2026-11-24; `Options.lua`, `AutoTurnin.lua`, `Core.lua`): bajo «Entregar misiones automáticamente», activado por defecto (sin valor guardado cuenta como «Sí»; solo un `false` explícito lo apaga). Para que cupiera en los 384 px de la pestaña, la nota de arriba pasa a dos líneas (sin «Cercanía» ni «en No, con Marcar destino») y desaparece la nota «Nunca acepta misiones…», que ya no era cierta; los interruptores de debajo suben 2 px o más. El mensaje de «Primera vez» nombra también la aceptación y `/smapas autoaceptar no`.

## 0.6.5-alpha (2026-11-24)

Estado: alpha; la aceptación automática y el selector Aspecto|Flecha aún sin ver en el juego. Validación en Lua 5.1 con dobles: pasan `221 + 14` comprobaciones.

### Opciones
- **«Flecha» se fusiona con «Aspecto»** (2026-11-24; `Options.lua` y tests): desaparece la pestaña lateral «Flecha». La pestaña «Aspecto» lleva ahora un selector «Aspecto | Flecha» arriba, con dos páginas del mismo tamaño y contenido que antes (no cabían en una sola sin desplazamiento: 312 + 376 px frente a 384). Quedan 9 pestañas y el décimo hueco de la columna libre (y = -408 a -440). `/smapas` y los ajustes guardados no cambian; una pestaña `arrow` guardada abre la página «Flecha». Sin ver en el juego: el aspecto real del selector.

### Panel
- **Aceptación automática de las misiones que pide la guía** (2026-11-24; `AutoTurnin.lua`, `Guia.lua`, `Options.lua`; `/smapas autoaceptar [si|no]`, exportable como `autoAccept`): al hablar con un PNJ, acepta solo las misiones de la primera parada «recoger» del plan guiado (`ns:GuideWantsQuest`), p. ej. la siguiente de la cadena en el PNJ donde acabas de entregar. Ignora las que la guía no lista, las saltadas, las grises (`isTrivial`) o muy por debajo de tu rango de nivel (salvo el siguiente paso de una cadena), y no actúa dentro de instancias, sin la ruta guiada ni con Mayús pulsado. Las entregas siempre van primero. Una misma misión no se vuelve a elegir en 10 s. Sin interruptor en Opciones (la pestaña Seguimiento está llena). En ventanas de «solo misiones» (`QUEST_GREETING`) no elige sola (no da el id), pero acepta al abrirse la misión que pide la guía. Sin probar en el cliente 16001: `C_GossipInfo.GetAvailableQuests` / `SelectAvailableQuest` (id o posición), `GetQuestID` y `AcceptQuest` en la ventana de misión.

## 0.6.4-alpha (2026-11-24)

Estado: alpha; correcciones de la ruta guiada aún sin ver en el juego. Validación en Lua 5.1 con dobles: pasan `220 + 13` comprobaciones.

### Ruta guiada
- **Piedra y vuelo con zona `to` ya no se marcan por estar ya en esa zona** (2026-11-24; `Guia.lua`): `GuideTick` solo los marca cuando ve al jugador llegar a `to` desde otra zona; antes un paso aún lejano en la guía quedaba hecho solo por estar en su zona (visto en tus ajustes guardados: pasos `hearth` marcados sin usar la piedra).
- **El «ponerse al día» no cuenta como progreso** una misión saltada ni una entrada que no te corresponde (`only`, como las de mazmorra con `guideflag`).
- **Evento de hechizos solo del jugador** (`Guia.lua`): `UNIT_SPELLCAST_SUCCEEDED` se registra con `RegisterUnitEvent("player")` si el cliente lo tiene, para no ejecutar el manejador con cada hechizo del grupo o de la ciudad.

### Panel
- **Cabecera de parada: el PNJ que más misiones comparte** (`Ruta.lua`): se cuenta por PNJ y no por tabla de datos, así que sale el mayoritario y no siempre el primero.

## 0.6.3-alpha (2026-11-24)

Estado: alpha; el «ponerse al día» aún sin ver en el juego.

### Ruta guiada
- **Ponerse al día** (2026-11-24; `Guia.lua`, `sendamapas_guia2_test.lua`; `/smapas guia alcanzar si|no`): en rutas v2, las recogidas que nunca tomaste y que quedan antes de tu último progreso en la guía (misión entregada, o recogida y aún en el registro) se dan por superadas y dejan de arrastrarte atrás; también cuenta para elegir la guía. Activado por defecto (`saved.guideCatchUp`). Sin probar en el cliente 16001.

## 0.6.2-alpha (2026-11-24)

Estado: alpha; corrección vista en el juego. Validación en Lua 5.1 con dobles: pasan `218 + 13` comprobaciones.

### Flecha
- **La flecha ya no desaparece si se eligió TomTom sin tenerlo instalado** (2026-11-24; `Navigation.lua`, `Options.lua`, tests): con «Flecha a usar: TomTom» y TomTom ausente, ninguna misión ni marca manual creaba destino («No se puede marcar la ruta de esta misión»). Ahora se usa la flecha propia hasta que TomTom esté instalado, y la opción lo indica («TomTom (no instalado: flecha propia)»).

## 0.6.1-alpha (2026-11-24)

Estado: alpha; un solo addon en el juego. Validación en Lua 5.1 con dobles (`validar_sendamapas_lua.py`, 49 archivos compilados): pasan `218 + 13` comprobaciones (`sendamapas_test.lua` + `sendamapas_autoentrega_test.lua`), los 9 `test_generador_*.py` (`*_OK`), `validar_rutas_locales.lua` (`RUTAS_LOCALES_LUA_V2_OK`) y `validar_paquete_sendamapas.py` (`PASS_PACKAGING`). Paquete único: `SendaMapas-0.6.1-alpha.zip` (una sola carpeta `AddOns\SendaMapas\`).

### Empaquetado
- **Las rutas van dentro del addon: una sola carpeta** (2026-11-24; `Rutas.lua`, `SendaMapas.toc`, `Guia.lua`, `preparar_sendamapas.py`, `README.md`): `Rutas.lua` (Guía A y Guía B, contrato v2) pasa a vivir dentro de `SendaMapas/` y se carga desde `SendaMapas.toc` justo después de `Guia.lua`; desaparece el addon aparte `SendaMapas_Rutas` y el paquete «completo». Si `Rutas.lua` falta o está vacío, el lector sigue funcionando sin error y `/smapas guia` responde «sin rutas incluidas».

## 0.6.0-alpha (2026-11-24)

Estado: alpha; la ruta guiada v2 aún sin ver en el juego. Validación en Lua 5.1 con dobles (`validar_sendamapas_lua.py`, 48 archivos compilados): pasan `217 + 13` comprobaciones (`sendamapas_test.lua` + `sendamapas_autoentrega_test.lua`), los 9 `test_generador_*.py` (`*_OK`), `validar_rutas_locales.lua` (`RUTAS_LOCALES_LUA_V2_OK`) y `validar_paquete_sendamapas.py` (`PASS_PACKAGING`). Paquetes: `SendaMapas-0.6.0-alpha.zip` (el addon) y `SendaMapas-0.6.0-alpha-completo.zip` (el addon y la carpeta aparte `SendaMapas_Rutas`).

### Ruta guiada v2
- **Pasos que no son misión** (2026-11-24; `Guia.lua`, `Modules.lua`, `Core.lua`, `HUD.lua`): con datos de contrato `version = 2` en `SendaMapas_Rutas`, la guía añade paradas `paso` en su orden para vuelos (`fp`, `fly`), piedra de hogar (`home`, `hearth`), entrenadores (`train`), vendedores (`vendor`), subida de nivel (`level`) e instrucciones con coordenadas (`note`), con fila propia en el panel, glifo y texto de tipo propios (`Vuelo`, `Volar`, `Posada`, `Piedra`, `Entrenador`, `Vendedor`, `Nivel`, `Paso`) y tooltip propio (sin «Misión #-…» ni «Nv ?»). Con `version = 1`, sin `SendaMapas_Rutas` o dentro de una instancia, todo funciona como en `0.5.0-alpha`.
  - **Detección automática y marcas a mano** (`Guia.lua`, `HUD.lua`, `Core.lua`): nunca compara etiquetas en inglés contra texto del cliente (usa posición —≤ 50 yd en ventanas de PNJ y ≤ 20 yd en `note`, con respaldo en unidades de mapa—, ids numéricos y constantes del cliente; nada dentro de instancias). Detecta `home` (`HEARTHSTONE_BOUND` cerca), `hearth` (`UNIT_SPELLCAST_SUCCEEDED` 8690/556 o llegada a `to`), `fp` (`UI_INFO_MESSAGE` `ERR_NEWTAXIPATH` y memoria por personaje `saved.guideTaxi` desde `TAXIMAP_OPENED` con nodos actuales o alcanzables), `fly` (`PLAYER_CONTROL_LOST` + `UnitOnTaxi` a los 0,5 s o llegada a `to`), `train` (`TRAINER_SHOW`/`TRAINER_CLOSED` descartando `IsTradeskillTrainer` o hechizos conocidos por `C_SpellBook.IsSpellKnown` → `IsPlayerSpell` → `IsSpellKnown`), `vendor` (`MERCHANT_SHOW`/`MERCHANT_CLOSED`), `level` (nivel del contexto) y `note` (llegada a ≤ 20 yd). Cada detección automática muestra el aviso breve «Paso hecho: <tipo>» con «Deshacer» (sin chat; respeta `/smapas avisos no`). Además, `Mayús+clic` en una fila de la guía, clic derecho en una fila de paso (nunca escribe en `saved.skipped`) y `/smapas guia hecho [no]` marcan o deshacen en `saved.guideDone` (con aviso «Deshacer» y poda de marcas de guías inexistentes). Los pasos anteriores a una entrega ya hecha (o al final de un tramo cuando el siguiente ya tiene una entrega hecha) se dan por superados.
  - **Consejos del paso** (`Guia.lua`, `HUD.lua`): los consejos (`guide.tips[n]`, en inglés) se muestran en la información desplegada de la fila («Consejo: …») y en líneas grises al final del tooltip, limitados a 3 consejos y 160 caracteres con `|` saneado a `/`, sin escribir en el chat.
  - **Misiones sin datos en el addon y zonas fuera del índice** (`Guia.lua`, `Modules.lua`): en v2 las misiones que no están en los datos de Senda Mapas (como misiones de clase) reciben un registro mínimo en memoria (`ns.guideRecords`, sin filtrarse a `Entries`, `MapSummary` ni exportación) para tener fila, estado real del cliente por id y flecha. Las entradas cuya zona `a` no esté en `Index.maps` nunca generan parada `zona` ni registro sintético: quedan en espera (`waiting`) y el tramo avanza sin ellas.
  - **Flecha a las coordenadas de la guía** (`Guia.lua`): en v2, `ns:Navigate` apunta a las coordenadas de la guía de la fila (flecha propia sin lista de puntos alternativos y TomTom); sin punto de guía, usa la navegación de siempre.
  - **Filtros y ramas de mazmorra** (`Guia.lua`, `Core.lua`): las misiones ocultas por filtros o por el rango de nivel ya no frenan la guía ni se anotan en `saved.skipped` y se informan en `/smapas guia` («N ocultas por filtros»). Las ramas `guideflag` se activan o desactivan con `/smapas guia mazmorras si|no` (`saved.guideDungeons`, por defecto no, sin exportar; `hardcore` sigue falso).
  - **Misiones sobrantes del registro y ventana genérica de abandonar** (`Options.lua`, `Guia.lua`, `Core.lua`): `ns:ShowForgetWindow` se generaliza en `ns:ShowAbandonWindow(opts)` conservando los textos y el comportamiento de «Olvidar misiones sin XP» sin cambios, y añade `ns:ShowOrphanWindow(ids)` («Misiones fuera de la guía»). En v2, `Guia.lua` calcula las misiones del registro fuera de las entradas pendientes de la cadena (memorizado por firma) y muestra el aviso «N misiones del registro fuera de la guía» + «Revisar» (mismas condiciones que `CheckForgetNotice`, retenido en combate, sin chat y sin abandonar nada sin clic de confirmación).
  - **Diagnóstico y `/smapas api`** (`Guia.lua`): `/smapas guia diag` muestra la primera entrada `o` pendiente de la guía actual («misión q, objetivo n.º o») y las líneas de `C_QuestLog.GetQuestObjectives` pasadas por `ns.Plain` (no disponible en instancias). `/smapas api` añade la línea «API Ruta guiada» solo con rutas instaladas (funciones de detección y `C_EventUtils.IsEventValid` por evento).
  - **Contrato de datos v2 (`SendaMapas_Rutas`)**: `version = 2` en Guía A (42 guías, 4.581 entradas) y Guía B (53 guías, 8.570 entradas, 0 áreas fuera de `Index.maps`).
  - Pruebas: `sendamapas_abandonar_test.lua` y `sendamapas_guia2_test.lua` (total `217 + 13`), `validar_rutas_locales.lua` y simulador v2 (6 corridas A/B en Humano, Enano y Elfo de la noche hasta nivel 60 con `a_mano=0`). Sin probar en el cliente 16001: disparo real de los eventos de pasos, `GetQuestObjectives`, `C_EventUtils.IsEventValid`, abandono real desde la ventana y aspecto visual de filas, avisos y consejos.

## 0.5.0-alpha (2026-11-24)

Estado: alpha; la ruta guiada aún sin ver en el juego. Validación en Lua 5.1 con dobles (`validar_sendamapas_lua.py`, 48 archivos compilados): pasan `198 + 13` comprobaciones (`sendamapas_test.lua` + `sendamapas_autoentrega_test.lua`) y los 9 `test_generador_*.py` (`*_OK`); paquete validado con `validar_paquete_sendamapas.py` (`PASS_PACKAGING`). Paquetes: `SendaMapas-0.5.0-alpha.zip` (el addon) y `SendaMapas-0.5.0-alpha-completo.zip` (el addon y la carpeta aparte `SendaMapas_Rutas`).

### Panel
- **Orden «Ruta» guiado por rutas de leveo locales** (2026-11-24; `Guia.lua` nuevo, `Core.lua`, `HUD.lua`, `SendaMapas.toc`; `/smapas guia`): con el addon aparte `SendaMapas_Rutas` instalado, el orden «Ruta» sigue sus rutas de leveo, que vienen en dos juegos: **Guía A** y **Guía B**. Senda Mapas no incluye ninguna ruta: solo lee las de ese addon. Sin él, con la ruta guiada desactivada, dentro de una instancia o en un mapa de mazmorra, «Ruta» usa su planificador de siempre y todo queda como en `0.4.0-alpha`; si el plan guiado falla, se anota como «Ruta guiada» en la lista de errores y también se usa el de siempre.
  - **La guía se elige sola** (`Guia.lua`): por la raza y el nivel del personaje. De los tramos de la guía, se usa el primero, desde el de tu nivel, que tenga algo que se pueda hacer ahora, así que avanza sin tocar nada. Las paradas siguen el orden de la guía (recoger, hacer, entregar) y juntan las entradas seguidas del mismo sitio; los objetivos se leen del cliente por número, no por nombre.
  - **Parada nueva «Ve a <zona>»** (`Guia.lua`): cuando lo siguiente de la guía está en otra zona, la parada dice «N · Ve a <zona>», con el glifo y el color de transporte.
  - **Pie y botón A/B** (`HUD.lua`): el pie dice «Orden: Ruta guiada · <tramo> · Quedan N paradas»; con los dos juegos instalados dice «Ruta guiada A» o «Ruta guiada B» y, solo entonces, la cabecera muestra un botón «A»/«B» junto al de orden: un clic cambia de guía sin escribir en el chat.
  - **`/smapas guia [auto | siguiente | anterior | si | no | a | b]`** (`Core.lua`, `Guia.lua`): sin palabra dice la guía en uso y cuántas entradas esperan, cuántas no tienen datos y cuántas aguardan hueco en el registro; `auto` deja elegir a la raza y el nivel; `siguiente` y `anterior` fijan el tramo vecino; `si` y `no` activan o desactivan la ruta guiada; `a` y `b` eligen el juego (la guía fijada a mano se suelta al cambiar de juego).
  - **Respeta lo mismo que «Ruta»**: el nivel requerido (una recogida que pide más nivel espera), el registro lleno (las recogidas esperan hueco y cada entrega libera uno), las misiones saltadas y los filtros de la lista. Una entrada cuya misión no tiene datos en Senda Mapas no frena la guía, salvo que la misión esté en el registro.
  - Pruebas: `sendamapas_guia_test.lua` (total `198 + 13`). Sin probar en el cliente: el orden de carga del addon aparte (el primer plan puede salir del planificador de siempre hasta el siguiente refresco), que el número de objetivo de las rutas coincida con el del cliente, el tope real del registro y el aspecto del botón «A»/«B» en los 8 aspectos.

## 0.4.0-alpha (2026-11-23)

Estado: alpha; probada en cliente solo con `/smapas api` y el diagnóstico del usuario; «Ruta» aún sin ver en el juego. Validación en Lua 5.1 con dobles (`validar_sendamapas_lua.py`, 47 archivos compilados): pasan `178 + 13` comprobaciones (`sendamapas_test.lua` + `sendamapas_autoentrega_test.lua`) y los 9 `test_generador_*.py` (`*_OK`); paquete validado con `validar_paquete_sendamapas.py` (`PASS_PACKAGING`).

### Panel
- **Orden «Ruta», nuevo orden por defecto** (2026-11-23; `Ruta.lua` nuevo, `Core.lua`, `HUD.lua`, `Rows_kit.lua`, `Options.lua`, `Modules.lua`, `Navigation.lua`, `SendaMapas.toc`; `/smapas orden ruta`, exportable): el panel agrupa las misiones en **paradas**: recoger todas las de un sitio, hacer los objetivos por cercanía y entregarlas juntas, respetando las misiones previas, el hueco del registro, los filtros, las saltadas, «Solo destacadas», «Ocultar terminadas» y el rango de nivel. La misión elegida sola es la primera de la primera parada (una elegida a mano se mantiene hasta que cambia su estado o el orden). Cabeceras de parada («1 · Recoge 3 misiones · junto a …», «Haz …», «Entrega … al terminarlas»), rótulo «RUTA · N PARADAS», contador «N en ruta · N fuera» y pie «Quedan N paradas», hasta 12 líneas. Las misiones de profesión, repetibles, JcJ, de banda, de evento y las atenuadas por nivel no se planifican y van a «Fuera de la ruta»; las entregas en otra zona y las misiones sin posición van al final; en mapas de mazmorra se ve la lista de siempre. Es el **orden por defecto**: sin valor guardado o con uno desconocido (que se migra a ese defecto y no se exporta). El botón de orden alterna Ruta → Paso a paso → Progresión → Ruta y el interruptor de Seguimiento añade Cercanía. `/smapas ruta on|off` no cambia: sigue siendo la línea de ruta del mapa. No se cambia ningún formato de datos. Pruebas: `sendamapas_ruta_test.lua` y `sendamapas_f18_test.lua` (total `178 + 13`). Sin probar en el cliente: el tope real del registro (`GetMaxNumQuestsCanAccept` / `MAX_QUESTS`), la posición del jugador en zonas propias de Forever y el ancho real de las cabeceras.
  - **Correcciones en «Ruta»** (2026-11-23; `Ruta.lua`, `sendamapas_ruta_test.lua`): las misiones excluyentes se deciden tras construir la lista dando prioridad a las disponibles sobre las bloqueadas (p. ej. 4023 frente a 4022 en Las Estepas Ardientes); las misiones sin datos de objetivos pero con texto y el mismo PNJ de inicio y entrega pasan a `sinpos` en lugar de entrega instantánea (p. ej. 81745–81747 en Bosque del Ocaso); cuando no cabe todo en el registro, `visit()` recoge primero las entregas inmediatas en el mismo sitio, después las completables en la zona y por último las que retienen hueco (`viajar` o `sinpos`).
  - **Misiones sin posición diferidas (D5)** (2026-11-23; `Ruta.lua`, `sendamapas_ruta_test.lua`): las misiones disponibles sin posición de objetivo (`nopos`) ya no se recogen durante el bucle principal ni atraen visitas, evitando que llenen el registro antes que las planificables; se recogen al final mientras quede hueco libre por cercanía de sitio (desempate por orden del módulo) y el resto queda en `lleno`.
  - **Indicador de orden siempre visible** (2026-11-23; `HUD.lua`, `sendamapas_f18_test.lua`): el pie del panel antepone `Orden: <nombre> · ` en los cuatro órdenes (`Ruta`, `Paso a paso`, `Progresión` y `Cercanía`) conservando todos los contadores y avisos existentes, y el tooltip del botón de orden añade `Clic: cambiar el orden.` bajo el título.

### Datos
- **Coordenadas de PNJ de Dun Morogh desde datos locales** (2026-11-23; `preparar_sendamapas.py`, `SendaMapas_EK01.lua`, `Index.lua`, `MODULOS.md`): los PNJ sin coordenadas en la captura (como los dadores y receptores de 59 misiones en Dun Morogh; **44 PNJ** completados en total) toman sus apariciones dentro de `[0, 100]` de la base auxiliar local fijada.
- **Limpieza de coordenadas fuera de rango y misión Horda 4004** (2026-11-23; `preparar_sendamapas.py`, `SendaMapas_MAZ01.lua`, `Index.lua`): el generador descarta al leer cualquier coordenada fuera de `[0, 100]` (eliminando los centinelas `[-1, -1]` de Lorekeeper Lydros en La Masacre y dejando la entidad sin `c`) y excluye la misión exclusiva de la Horda `4004` (*The Princess Saved?*, capturada con `side=3`), pasando el total a **2.838** misiones y `Index.hz` a **33** previas.
- **Coordenadas de objetivo en su propia zona (lote 2)** (2026-11-23; `preparar_sendamapas.py`, `SendaMapas/Data/SendaMapas_*.lua`, `MODULOS.md`): integradas las **46 misiones** resueltas en su propia zona con confianza `high` (39) y `medium` (7) a partir del lote local fijado para que el orden «Ruta» las planifique en paradas `hacer` en lugar de «sin posición en esta zona» (`+5.668` B en 9 módulos; la agrupación de los 19 módulos no cambia). En `174`, `564` y `80001` se añade únicamente `z[zona propia]` a los objetivos existentes que carecían de ella, sin alterar ninguna coordenada previa; los 3 registros `low` (`3785`, `3791`, `5206`) y los de otra zona exterior quedan fuera.

## 0.3.0-alpha (2026-11-18; publicada el 2026-11-21)

Estado: alpha en pruebas tempranas en el cliente real de WoW Forever (`Interface 16001`; solo se ha probado in-game `/smapas api` en personaje Humano nv. 27 y lo que el usuario ha ido contando, el resto sigue pendiente de probar en el cliente). Solo Alianza y solo WoW Forever; el addon es de leveo. Validación en Lua 5.1 con dobles (`validar_sendamapas_lua.py`, 46 archivos compilados): pasan `142 + 13` comprobaciones (`sendamapas_test.lua` + `sendamapas_autoentrega_test.lua`) y los 8 `test_generador_*.py` (`*_OK`); `validar_paquete_sendamapas.py` queda pendiente de regenerar el ZIP (en los informes previos pasó salvo el ZIP desfasado a propósito). Recoge las fases 8 a 18 (incluidos los pasos 1 y 2 de la fase 17, la fase 15 de piedra de hogar y la fase 18 de botones del panel y deshacer salto), cabeceras de cadena y sus correcciones, modo instancia y valores secretos, chat sin avisos automáticos, correcciones en Forever/revisión y misión manual en Duskwood.

### Flecha (fases 8, 9 y 14c)
- **Placa F2**: bajo la flecha, una placa con el título (destino o tramo), la distancia y, a la derecha, el tiempo estimado con un reloj (sin «~» en la placa; el «~» se queda en el resto). Símbolo y borde de color según el destino: barco, dirigible, portal, tranvía o vuelo, «Tu cadáver» o marca manual; «has llegado» al llegar. Con varios tramos, una barra de segmentos enseña los hechos y los que faltan. El marco mide S + 48 (150×96 a 48 px).
- **Diez diseños**: se añaden **Quilla**, **Galón** y **Norte**, que se tiñen según el estado (acento del aspecto; cadáver; marca manual; verde al llegar; con *Sonido según el rumbo*, de cara / desviado / de espaldas). Los siete de antes no cambian; por defecto sigue **Lance**.
- **Tiempo estimado de llegada**, **sonido según el rumbo**, **flecha al cadáver** (sin tocar el destino ni la marca manual) y **destino en el mapa de vuelos** (fase 8). En la 14c, el nodo de vuelo se resalta con un anillo del color de transporte y un ala.
- **Ruta con transporte** (fase 9; `/smapas transporte on|off`): barcos, portales, tranvía, dirigible y 33 maestros de vuelo de Alianza o neutrales de WoW Forever; la flecha apunta al primer embarque y pasa sola al tramo siguiente. Sin Horda ni datos de otras versiones; sin barco Ventormenta ↔ Auberdine; sin datos para Mount Hyjal ni Shen'dralas; el barco Bahía del Botín ↔ Trinquete, sin comprobar en el cliente.

### Panel (fases 12, 12b, 12c y 14b)
- **Cadenas destacadas** (fase 12; `/smapas destacadas on|off` y botón ★ «Destacadas» junto a «Mapas»): equipo verde o azul que usas, cadenas de 6 o más, misiones de tu clase, acceso a mazmorras y llaves, monturas, mascotas y bolsas. Siguen visibles las en curso y el siguiente paso. Recompensas finales de cada cadena en el tooltip.
- **Solo leveo** (fase 12c): el acceso cuenta solo para **mazmorras de hasta 5 jugadores** y sus llaves. En Forever la Cumbre de Roca Negra (también UBRS) es de 5, así que el Seal of Ascension cuenta. Las cadenas cuya meta es una banda (10 o más jugadores: Onyxia y su Drakefire Amulet, Núcleo de Magma, Zul'Gurub, Ahn'Qiraj, Naxxramas…) ya no salen como acceso (22 cadenas, más la del tranvía). El generador las reconoce para un futuro apartado de bandas (`RAID_HIGHLIGHTS`, apagado).
- **Llaves de mazmorra** (fase 12d, del análisis de Argon): las cadenas que empiezan en un mapa de mazmorra conservan solo la marca de llave (de 21 a 25 cadenas con llave: Shadowforge Key 3801, Krol'dok Compound Key 94980, Seal of Ascension 4742 y Scepter of Celebras 7044), y las llaves salen en «Recompensa final» con cualquier calidad (también blancas), como para ti.
- **Filas «Realce»** (fase 14b): etiquetas de color con símbolo («EQUIPO AZUL», «CLASE», «CADENA LARGA»…) que se acortan a icono o «+N» si no caben; línea de nivel propia solo cuando hay etiquetas; símbolo de estado (recoger, en curso, entregar, candado); barra de progreso fina con la fila cerrada; brillo en la fila elegida; misión bloqueada con el nombre atenuado. En los siete diseños de fila.
- **Orden «Paso a paso»** (`Core.lua`, `Options.lua`; `/smapas orden pasos|paso`, tercer valor del interruptor «Orden de la lista del panel»: Progresión → Cercanía → Paso a paso, exportable): la misión elegida sola es la primera de la lista en el registro, por entregar o disponible, en orden, sin priorizar el registro ni la continuación de cadena (respeta el rango de nivel). Fue el orden por defecto hasta la llegada de «Ruta» (en `0.4.0-alpha`); un «Paso a paso», «Progresión» o «Cercanía» ya guardado se conserva y se exporta.
- **Olvidar misiones sin XP** (`Navigation.lua`, `Core.lua`, `Options.lua`, `AutoTurnin.lua`; `/smapas olvidar [aviso si|no]`, botón «Olvidar misiones sin XP (N)» en Acciones, interruptor «Aviso de misiones sin XP al subir» en Nivel, exportable): ventana con las misiones grises del registro y las excluidas con su motivo (para entregar, destacadas, cadena que aún da XP o en otro mapa, clase, profesión, elegida a mano, sin datos); solo con «Abandonar todas» las abandona por `questID` (una cada 0,3 s, comprobando el registro; API NO CONFIRMADA en 16001, con plan B de abandono a mano) y quedan como saltadas; aviso con «Revisar» al subir de nivel; `/smapas api` línea 11.
- **Vista de pasos y botón de orden** (fase 19, diseño de Fable, variante A; `HUD.lua`, `Rows_kit.lua`, `Core.lua`, `Options.lua`): con «Paso a paso» el panel enseña la ruta numerada (`ns:Steps`) con «PASO N DE M», entregadas, bloqueadas, atenuadas y saltadas a la vista (clic en una saltada la devuelve sola, `ns:Unskip`), hasta 12 pasos visibles y pie «Paso N de M»; la cabecera pierde el título «SENDA MAPAS», «Abrir todas» pasa a su sitio y a su lado un botón que dice el orden y alterna «Paso a paso» / «Progresión» con un clic (sin glifos nuevos; la estrella «Destacadas» no cambia).
- **Marco del panel** (14b): emblema, barra del progreso del mapa bajo la cabecera y mensaje propio cuando el filtro Destacadas deja el mapa vacío.
- **Correcciones de la fase 12b**: roles por clase, valor solo de los objetos finales, objetos que no son equipo (bolsa, montura, mascota, llave, carcaj solo para cazadores), nombres y distancias de otros mapas, siguiente paso por las ramas realmente entregadas, nota de la pestaña Equipo más corta.

### Equipo (fases 10 y 14c)
- **Cadenas con equipo** (fase 10; pestaña **Equipo**, `/smapas equipo on|off` y `/smapas rol …`): la primera misión de una cadena dice «Equipo azul» o «Equipo verde» si alguna rama da equipo de esa calidad que tu personaje usa con su rol. Guerreros y paladines, malla hasta 40 y placas desde 40; cazadores y chamanes, cuero hasta 40 y malla desde 40 (dato del usuario).
- **Selector E2** (14c): seis segmentos con símbolo (Auto, Tanque, Cuerpo, Distancia, Hechizos, Sanación); el elegido, en el color de acento con texto oscuro sin sombra. Debajo, una muestra de cómo se leen las etiquetas.

### Mapa y minimapa (fase 14a)
- Marcas nuevas del pack «Esmalte amarillo» (mismos nombres). La misión aún no disponible tiene su propio «!» gris entero. **Iconos para mapas claros** (`/smapas iconos claros|normales`, Opciones → Mapa (M)).
- El destino se resalta con un anillo del color de acento del aspecto. Coordenadas del mapa en una placa: «Tú x, y» y «Cursor x, y».
- Botón del minimapa con la marca «Rumbo». **Corregidas las rutas del aro y del resaltado del botón del minimapa**: tenían una sola barra invertida y el juego no las encontraba.

### Aspectos (fases 12b y 14a)
- Aspecto nuevo **Azul Real** (8 en total).
- **Colores con significado** iguales en todos los aspectos (equipo azul y verde, cadena, clase, acceso, premio en rosa, transporte, cadáver, marca manual y recompensa), todos con contraste de 4,5:1 o más en las filas. El generador falla si alguno no llega.
- **Táctico**: texto de los botones turquesa en **`#03231d` sin sombra** (decisión del usuario); la regla «texto oscuro y plano sobre relleno claro» vale ya para cualquier texto sobre un relleno del aspecto.

### Opciones (fase 14c)
- Pestañas con símbolo; la elegida, resaltada con una barra de color (ya no se desactiva). Título con emblema.
- Las opciones de Sí/No son interruptores (pista con pomo); las de más valores siguen como botón de texto.
- Pestaña **Flecha**: diez diseños en dos filas de cinco e interruptores con símbolo. Pestaña **Seguimiento**: interruptor nuevo de avisos.

### Avisos y recompensa (fases 8 y 14c)
- **Recompensa más valiosa** (fase 8): moneda sobre la recompensa que más vale vendida, sin elegirla nunca. En la 14c, moneda nueva de 20 px y borde dorado alrededor de esa recompensa.
- **Avisos junto al panel** (14c; `/smapas avisos panel|chat|no`, por defecto junto al panel):
  - «Elige tú la recompensa (N opciones)» con la que más vale, mientras la ventana está abierta;
  - «Entregada: <misión>» con los PX, 4 s, tras una entrega automática;
  - el aviso del chat de antes solo con «Panel y chat».
  
  Es un componente con cola por prioridad, preparado para los avisos de la piedra de hogar.

### Datos (fases 9, 10, 11 y 12)
- Tabla de transporte generada (`Data/SendaMapas_Transporte.lua`); equipo y recompensas finales de las cadenas (`rw`, `fq`, `rf`, `rn`); cadenas destacadas (`hl`, `hn`, `hc`). Los 19 módulos conservan sus mapas.
- **Coordenadas de objetivos adicionales (lote 1)** (fase 11): 46 misiones completadas, entre ellas los **11 registros de confianza `medium`** que el usuario decidió integrar (90, 116, 565, 713, 714, 715, 716, 1073, 1141, 1203 y 6026: la misión pide el objeto, así que dónde comprarlo es útil). Misiones con todos los objetivos con coordenadas: 1290 → 1335 de 1614.
- Iconos y glifos versionados en `iconos-fuente/fase13/` con su manifiesto SHA-256; `generar_iconos.py` los valida y los copia a `Media/`.

### Piedra de hogar (fase 15, pasos 1 y 2)
- **Tabla de posadas generada** (`Data/SendaMapas_Transporte.lua`, 6.018 → 12.723 B): **35 posadas** de Alianza y neutrales en **31 de 48 mapas exteriores**, **17 mapas puente** con su posada habitual y **4 puntos de inicio**; cada posadero se valida contra la base auxiliar local (bit 128, `subName == "Innkeeper"`, sin Horda, coordenadas a ≤ 0,5). Excluidos asistente de Dalaran (`32411`), Horda (`9501`) e ID erróneo (`7731`).
- **Aviso «Fija tu piedra en …»** (`Piedra.lua`, paso 1): compara `GetBindLocation()` con `C_Map.GetAreaInfo`, nombres en español (cuando están completos) e inglés (estado `known`/`ambiguous`/`unknown`; nunca avisa si es `unknown`). Sale junto al panel (máx. 1/min y una vez por posada y sesión) si estás en la zona cargada, tiene posada, tu piedra está en otro mapa y hay ≥ 5 misiones en rango; nunca en combate, taxi, muerto ni mazmorra. La opción de Seguimiento pasa a **«Avisos de entrega, recompensa y piedra»**.
- **Tramo y aviso «Usa la piedra»** (paso 2): en la ruta con transporte (`ns:HearthRoute`), si la piedra está lista (enfriamiento de **1 hora**; ≤ 1,5 s cuenta como listo por GCD), tiene posada conocida sin distancias sin medir y **ahorra al menos 6 minutos** (contando 10 s de lanzamiento + 15 s de carga), la flecha añade el tramo «Usa la piedra de hogar a …» y muestra el aviso «Usa la piedra: te lleva a … / y ahorras ~N min» tras 3 s ganando (forma corta si pasa de 44 caracteres; con `/smapas avisos no` se apaga el aviso pero el tramo sigue en la flecha).
- **Comando `/smapas piedra`**: muestra en 5 líneas dónde está fijada, la posada de la zona (o habitual), si compensa usarla hacia el destino actual, el estado de los avisos y la ayuda.
- **Correcciones tras revisión**: pareja del Cráter de Dalaran tratada como un único lugar conocido en ambas pasadas (M1); `/smapas avisos no` limpia los avisos de piedra visibles (B1); `CurrentInn` descarta `(0, 0)` (B2).

### Rango de nivel (fase 17, pasos 0 y 1)
- **Perfil de nivel y `/smapas api`** (paso 0): añadido el grupo «Nivel y raza» y la línea de valores reales a `/smapas api`; perfil de nivel por mapa exterior (`g ~= "MAZ"`, incluido Blackrock Spire `1583`) en `Index.lua` (`lv`, `lvR`, `xm`, `p85`, `st` en las 4 zonas iniciales `{12, 141, 1, 16593}`; +4.751 B) y nivel de criaturas objetivo `ml` en 91 misiones (solo informativo, NPC hostiles de la misma zona sin raros ni jefes ni marcadores `9999`/`Credit`).
- **Alias `HighElf` ↔ `Skyborne`**: unificados en `Filters.lua` (`RaceKey`) y en el generador (`preparar_sendamapas.py`) mientras se confirma `UnitRace` in-game para esa raza.
- **Rango configurable y pestaña «Nivel»** (paso 1): nueva **10.ª pestaña «Nivel»** en Opciones (`Glyph_spark`, divisor bajado a 8 px), exportable/importable y con `/smapas nivel [abajo arriba | atenuar | ocultar | aviso si|no]`. Rango por defecto **4 por debajo y 2 por encima** (0 a 10).
- **Atenuar u ocultar fuera de rango**: por defecto se atenúan al **alfa 0,7** (contraste verificado por Fable) y pasan al final de la lista con etiqueta «Bajo el rango», «Sobre el rango» o «Pide nv N»; **la fila elegida y su marca no se atenúan**, y las demás marcas fuera de rango pasan a 0,35. En modo «Se ocultan», el pie indica «N ocultas por el rango de nivel» y si la elegida queda oculta se suelta. Nunca se atenúan ni ocultan las misiones del registro, las listas para entregar ni el siguiente paso de una cadena; las cadenas destacadas fuera de rango se atenúan en lugar de ocultarse.
- **Aviso «Objetivo nv N»**: etiqueta e indicación en ficha y tooltip cuando `ml >= nivel + 3`; solo informa, nunca bloquea.
- **Correcciones tras revisión**: `SelectQuest` y `ApplySkin` redibujan pines con el mapa abierto; `levelShowCache` se vacía al abrir el mapa, en `PLAYER_LEVEL_UP` (con suelo `levelFloor`) y en `InvalidateStates`; `AutoTurnin` limpia intentos previos al abrir `QUEST_COMPLETE`/`QUEST_PROGRESS` incluso con `Mayús`.

### Cabecera de cadena
- **«Empieza la cadena en…»** (`Navigation.lua`, `UI.lua`, `HUD.lua`, `Rows_kit.lua`): en misiones con previas pendientes («Faltan previas»), `ChainHead` recorre hacia atrás por los módulos cargados y por las tablas nuevas de `Index.lua` (`heads`: 111 cabeceras, `cp`: 307 previas, `cz`: 307 mapas, `hz`: 34 previas exclusivas de la Horda; +20.289 B, dejando `Index.lua` en **37.508 B**).
- **Indicadores y Alt+clic directo**: muestra dónde empieza o continúa la cadena en la fila y en el tooltip («Empieza en: …», «Sigue en: …», «Entrega antes: …», «Completa antes: …», descartando Horda y ramas cerradas por excluyentes `ex`), y **Alt+clic** salta directo al inicio o paso siguiente aunque esté en otro mapa.

### Correcciones en WoW Forever y visor de errores
- **Capa `ns:ItemInfo` / `ns:ItemInfoInstant`** (`Core.lua`): tras comprobar en `/smapas api` (Forever 16001) que no existen las globales `GetItemInfo` ni `GetItemInfoInstant`, las lecturas de recompensa más valiosa y de equipo verde/azul en cadenas usan respaldo automático a `C_Item.*` (aceptando valores sueltos, tabla o lista) y `/smapas api` prueba en vivo el objeto `6948`.
- **Opciones con el mismo fondo y opacidad**: el marco de Opciones comparte la superficie `panel` y sigue el deslizador de opacidad del panel de misiones.
- **Protección frente a textos «secretos» en `scanName`** (`Navigation.lua`): los nombres leídos del tooltip oculto comprueban `issecretvalue` para ignorar valores secretos del cliente Forever sin error de comparación.
- **Visor de errores aislado por addon** (`Errores.lua`): separa y etiqueta los errores ajenos (`de otro addon, no es de Senda Mapas`, máx. 10) sin contarlos en el indicador `[!]` ni en el total de errores propios.

### Modo instancia y valores secretos
Resumen recogido de `results/20261118-instancias-secretos-opus-resultado.md`:
- **Saneamiento central de valores secretos** (`Core.lua`): añade `ns.Plain(v)` (descarta valores secretos sin compararlos ni concatenarlos), aplica `ns.Plain` en `ns.Call`, `ns.PointXY`, `ns:PlayerMapXY`, `ReadLog`, `AllObjectivesFinished` y en los eventos `QUEST_TURNED_IN` y `PLAYER_LEVEL_UP`.
- **Detección de instancia e identidad recordada** (`Core.lua`, `ApiSupport`): incorpora `ns:InInstance()` (`IsInInstance()` o zona actual/guardada con `g == "MAZ"`) y `ns:PlayerIdentity()`, que lee fuera de instancia mediante `ns.Plain` y reutiliza el último valor válido en sesión dentro de instancias (se mantienen las lecturas de nombre de zona y posición/orientación/mapa del jugador vía `Plain`/`PlayerMapXY`; en `/smapas api`, las líneas 8 y 10 indican «no se leen dentro de una instancia.» cuando procede).
- **Navegación, objetivos y flecha en instancias** (`Navigation.lua`, `HUD.lua`, `MapResolver.lua`, `MapPins.lua`, `Arrow.lua`, `Piedra.lua`): `NpcName` usa el nombre de datos o caché sin tooltip oculto dentro de instancias; `UnfinishedObjectives` resuelve por posición dentro y `Plain` fuera; `LiveObjectives` devuelve `nil` en instancias para usar los objetivos de datos (y «Objetivo» como respaldo fuera); `Arrow.lua` evita `GetUnitSpeed`, `UnitIsGhost` y `UnitIsDeadOrGhost` dentro de instancias; `Piedra.lua` conserva el último texto de posada en `BindText`, prioriza `InInstance` en `HearthBlocked` y usa `PlayerMapXY` en `CurrentInn`; `RouteLeg` evita `UnitOnTaxi` dentro y `ChainGear`/`ChainValue`/`DetectGearRole` usan `PlayerIdentity` (pendiente proteger `Errores.lua` si un error arrastrara un valor secreto).
- **Autoentrega por ID en instancias** (`AutoTurnin.lua`): `questTitle(v)` devuelve `nil` dentro de instancia o si el título es secreto; las opciones de diálogo se emparejan por `questID` y `waiting[GetQuestID()]` en `QUEST_COMPLETE`, mostrando el aviso «Entregada: la misión» en instancia y filtrando XP y objeto/precio de recompensa con `Plain`.
- **Batería de pruebas de secretos e instancias** (`tests_sendamapas/sendamapas_secretos_test.lua`): 9 comprobaciones dedicadas (total `113 + 13` en `validar_sendamapas_lua.py`).

### Siguiente zona (fase 17, paso 2)
- **Motor `ns:NextZone` y `ns:AnalyzeCurrentMap`** (`Navigation.lua`): recomienda la siguiente zona cuando el mapa actual está listo (`empty`, sin entregas y `<= 3` misiones útiles) o queda por debajo del nivel del jugador (`overlevel`, frente a `p85 + abajo`), puntuando misiones en rango, saltos entre regiones y fronteras. Excluye mazmorras (`g == "MAZ"`), las capitales (Ventormenta, Forjaz y Darnassus), las zonas de inicio desde nivel 11, el mapa ya cargado y zonas con menos de 6 misiones útiles.
- **Zonas sin ruta conocida y estadísticas locales**: prioriza las zonas con ruta conocida y mantiene Mount Hyjal y Shen'dralas como alternativa 2.ª o 3.ª con «sin ruta conocida». Guarda en `saved.zoneStats` (por personaje, sin exportar) lo restante de los mapas visitados para acotar el histograma de `lv` / `lvR`.
- **Aviso «Ve a X» y controles** (`Navigation.lua`, `HUD.lua`, `UI.lua`, `Options.lua`, `Piedra.lua`): aviso junto al panel (10 s, una vez por zona/destino/nivel y máx. 1/min; bloqueos compartidos en `ns:PlayerBlocked()` con la piedra), texto en el pie (`· Ve a X (Nm[, sin ruta])`) y en panel vacío, etiquetas «Recomendada #1» / «Alternativa #N (sin ruta)» en el selector de mapas, interruptor + estado + botón «Abrir recomendada» en la pestaña **Nivel** y comando `/smapas zona [si|no|ir]`.

### Botones del panel y deshacer salto (fase 18)
- **Botón con glifo «Actualizar» y actualización a fondo** (`HUD.lua`, `Core.lua`): nuevo botón `32 × 24` en la cabecera junto a «Opciones» (`TOPRIGHT -52, -7`) con `Glyph_refresh` (se atenúa 1 s al pulsarlo); ejecuta `ns:FullRefresh()` / `ns:UpdateProgress()`, que vacía `navFail`, estados, caché de nombres y de flecha, relee misiones completadas, salta al mapa actual incluso con `auto off`, conserva la misión elegida válida, renueva el destino aunque «Seguir la misión elegida» esté apagado (respetando `manualMark`) y refresca mapa/minimapa (diferido con `pendingUpdate` si está en combate). La insignia `[!]` de `Errores.lua` pasa de `-50` a `-90` para hacerle sitio.
- **Botón «Devolver» en la segunda fila** (`HUD.lua`, `Core.lua`): sustituye al botón de texto «Actualizar» en la segunda fila (`TOPRIGHT -108, -36`, `78 × 24`); permanece siempre visible y devuelve todas las misiones saltadas (`RestoreAllSkipped`), mostrándose deshabilitado al 0,5 de alfa como «Devolver» sin saltadas o habilitado como «Devolver (N)» cuando las hay (el pie recupera el ancho `width - 165`).
- **Aviso «Misión saltada» de 8 s y `/smapas deshacer`** (`Core.lua`, `AutoTurnin.lua`, `Navigation.lua`): `ShowNotice` admite botones de acción (`296 × 66`); al saltar muestra «Deshacer» (`UndoSkip`, también en `/smapas deshacer`) y «Devolver todas» si hay más de una saltada (incluso con los avisos generales en `no`), con confirmación de 4 s y tooltip de fila actualizado.
- **Eventos, glifos y contraste** (`Core.lua`, `HUD.lua`, `MANIFIESTO.json`): registra `QUEST_ACCEPTED` y `QUEST_REMOVED` en `QueueRefresh`; añade `Glyph_refresh.tga` y `Glyph_undo.tga` (**62** entradas en el manifiesto de iconos); tiñe el icono de «Opciones» con `buttonText` en **Táctico** (contraste < 3:1 sobre el botón con `headerText`).

### Chat silencioso (sin mensajes automáticos)
- **Eliminados los avisos automáticos en el chat** (`Core.lua`, `Modules.lua`, `Navigation.lua`, `Arrow.lua`, `HUD.lua`, `UI.lua`): ya no se imprimen mensajes al entrar o cambiar de mapa (sin «Alpha cargada…» ni `PrintMapSummary()` automático en `LoadMap`; la nota de «Primera vez» sobre la entrega automática se mantiene, una sola vez por personaje), ni mensajes automáticos de navegación, marcación de ruta o respaldo de vuelos al abrir el mapa de vuelo.
- **Retirado el modo «Panel y chat» (`both`)** (`AutoTurnin.lua`, `Piedra.lua`, `Navigation.lua`, `Core.lua`, `Options.lua`): `/smapas avisos` admite solo `panel | no`; cualquier valor `"both"` ya guardado en `SendaMapasDB` o importado se migra automáticamente a `"panel"` en `Migrate()` e `ImportSettings()`.
- **Interacción en el panel sin chat**: ningún clic dentro del panel ni en el selector de mapas escribe en el chat (`LoadMap` usa parámetro `silent`, `FullRefresh`/`SetOpenAll`/`Navigate`/`OpenChainLink` silenciosos desde panel); solo responden en chat los comandos `/smapas …` y los botones explícitos de informe/acción en Opciones.

### Correcciones tras revisión (piedra, errores, opacidad y cabeceras)
- **Piedra de hogar al limpiar ruta o cambiar posada** (`Arrow.lua`, `Piedra.lua`): `ClearDestination` limpia `self.route` y oculta `hearth_use`; `HearthUseText` exige `self.dest` activo; `HEARTHSTONE_BOUND` reinicia `ns.route`, retira `hearth` y `hearth_use` y refresca la flecha.
- **Visor de errores y opacidad real** (`Errores.lua`, `Options.lua`, `HUD.lua`): fusión/deduplicación del búfer temprano en `InitErrors`, poda priorizando el error ajeno más antiguo al pasar del tope (50 propios / 10 ajenos), respaldo para errores de taint puro (`tainted by '<addon>'` excluyendo `SendaMapas` y `Blizzard_*`), botón «Borrar errores guardados» habilitado también con solo errores ajenos, y `RenderOpacityControl()` mostrando el porcentaje real de opacidad original por aspecto (`80 %` en Táctico, `91–95 %` en el resto).
- **Cabeceras de cadena (`H1`–`H4`)** (`preparar_sendamapas.py`, `Index.lua`, `Navigation.lua`, `HUD.lua`, `UI.lua`): nueva tabla `Index.ci` con restricciones y nombre de los **39 intermedios** restringidos de `cp` (`Index.lua` pasa a **39.783 B**); `walk` corta ramas cerradas por `ex` o exclusivas de la Horda y propaga restricciones de clase/raza con memo por `(misión, otra)` sin explosión en diamantes; `ChainHead` difiere la construcción de texto de PNJ a las 2 primeras entradas visibles y `HUDInstructionParts` evita recalcular la cabecera mediante el parámetro `noHead`; tests de cabecera simulando módulos reales sin cargar (`hideModule`).

### Datos manuales (Duskwood)
- **Misión 81716 en Duskwood** (`datos-navegacion/misiones_manuales.json`, `preparar_sendamapas.py`, `SendaMapas_EK04.lua`, `Index.lua`): añadida manualmente **«Recover Incursion Field Report: Duskwood»** (id `81716`, nivel 27, req. 23, 1.100 XP, inicio/entrega en Field Captain Palandar, +10 Emerald Wardens; incorporada el 2026-11-18 sin alterar la base principal; Duskwood pasa de 96 a 97 misiones y el total a **2.839**). Enlazada como previa de **81730 «Duskwood Mission I: Defeat Worgen»** (enlace **inferido** del texto; sus objetivos carecen de coordenadas de posición).

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
- Enlaces de cadena sin mapa o sin nombre: 131 → 0 y 87 → 0 (datos auxiliares locales).
- Misiones con todos los objetivos con coordenadas: 70,7 % → 79,9 %; 272 objetivos de mazmorra resueltos a su entrada exterior.
- 19 módulos de datos; `ns.Index.missingMaps` con los 8 mapas sin módulo.
- Base auxiliar fijada en una copia local del proyecto (huella SHA-256 registrada en `MODULOS.md`); el generador falla si falta o si quedan módulos huérfanos.

Nota: paquete de uso personal y privado; no se publica en portales públicos.

## 0.1.0-alpha (2026-11-15)
- Primera versión pública: guía de misiones por mapa, panel con aspectos, flecha propia, marcas en mapa y minimapa, filtros y ventana de opciones.
