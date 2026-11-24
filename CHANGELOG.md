# Historial de cambios

## 0.6.6-alpha (2026-11-24)

Estado: alpha; el interruptor de la aceptación automática aún sin ver en el juego. Validación en Lua 5.1 con dobles: pasan `221 + 14` comprobaciones.

### Opciones
- **Interruptor «Aceptar las misiones que pide la guía» en Seguimiento** (2026-11-24; `Options.lua`, `AutoTurnin.lua`, `Core.lua`): bajo «Entregar misiones automáticamente», activado por defecto (sin valor guardado cuenta como «Sí»; solo un `false` explícito lo apaga). Para que cupiera en los 384 px de la pestaña, la nota de arriba pasa a dos líneas (sin «Cercanía» ni «en No, con Marcar destino») y desaparece la nota «Nunca acepta misiones…», que ya no era cierta; los interruptores de debajo suben 2 px o más. El mensaje de «Primera vez» nombra también la aceptación y `/smapas autoaceptar no`.
