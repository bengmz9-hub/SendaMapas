# Historial de cambios

## 0.6.5-alpha (2026-11-24)

Estado: alpha; la aceptación automática y el selector Aspecto|Flecha aún sin ver en el juego. Validación en Lua 5.1 con dobles: pasan `221 + 14` comprobaciones.

### Opciones
- **«Flecha» se fusiona con «Aspecto»** (2026-11-24; `Options.lua`): desaparece la pestaña lateral «Flecha». La pestaña «Aspecto» lleva ahora un selector «Aspecto | Flecha» arriba, con dos páginas del mismo tamaño y contenido que antes (no cabían en una sola sin desplazamiento: 312 + 376 px frente a 384). Quedan 9 pestañas y el décimo hueco de la columna libre (y = -408 a -440). `/smapas` y los ajustes guardados no cambian; una pestaña `arrow` guardada abre la página «Flecha». Sin ver en el juego: el aspecto real del selector.

### Panel
- **Aceptación automática de las misiones que pide la guía** (2026-11-24; `AutoTurnin.lua`, `Guia.lua`, `Options.lua`; `/smapas autoaceptar [si|no]`, exportable como `autoAccept`): al hablar con un PNJ, acepta solo las misiones de la primera parada «recoger» del plan guiado (`ns:GuideWantsQuest`), p. ej. la siguiente de la cadena en el PNJ donde acabas de entregar. Ignora las que la guía no lista, las saltadas, las grises (`isTrivial`) o muy por debajo de tu rango de nivel (salvo el siguiente paso de una cadena), y no actúa dentro de instancias, sin la ruta guiada ni con Mayús pulsado. Las entregas siempre van primero. Una misma misión no se vuelve a elegir en 10 s. Sin interruptor en Opciones (la pestaña Seguimiento está llena). En ventanas de «solo misiones» (`QUEST_GREETING`) no elige sola (no da el id), pero acepta al abrirse la misión que pide la guía. Sin probar en el cliente 16001: `C_GossipInfo.GetAvailableQuests` / `SelectAvailableQuest` (id o posición), `GetQuestID` y `AcceptQuest` en la ventana de misión.
