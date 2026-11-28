# Historial de cambios

## 0.7.3 (2026-11-28)

Estado: alpha; el tramo de la zona aún sin ver en el juego. Validación en Lua 5.1 con dobles: pasan `312 + 14` comprobaciones; simulación de la Guía A de principio a fin con el mismo resultado que en la 0.7.2 (cadena terminada, 737 misiones entregadas, nivel 60).

### Ruta guiada
- **Tramo de la zona** (`Guia.lua`, `Core.lua`): al entrar en una zona se vuelven a leer las misiones entregadas (nunca dentro de una instancia ni en un mapa de mazmorra) y la ruta guiada pasa a la guía de tu cadena que tiene pasos pendientes en esa zona: desde la primera guía que llega a tu nivel, sin pasar de las que empiezan más de 2 niveles por encima, la primera con algo que hacer allí. El «ponerse al día» de siempre da por pasado lo anterior a tu progreso, así que el plan empieza en el primer paso que de verdad te queda. También al entrar al juego y tras `/reload` (se elige otra vez con la lista recién leída).
- La elección dura la sesión (no se guarda) y se mantiene mientras esa guía tenga algo que hacer; agotada, vuelve la elección por raza y nivel. Una zona sin tramo deja la guía que llevabas (cruzar una ciudad no cambia la guía ni repite el resumen). Una guía fijada a mano (`/smapas guia siguiente | anterior`) manda.
- En combate espera al final del combate; no actúa dentro de instancias, en mapas de mazmorra, con la ruta guiada desactivada ni con otro orden que «Ruta».
- `/smapas guia auto`, el cambio de guía A/B, `/smapas guia si`, pasar al orden «Ruta» (también importándolo con los ajustes), `/smapas guia alcanzar si | no` y `/smapas guia mazmorras si | no` vuelven a mirar la zona en la que estás. `/smapas guia` dice «automática por la zona <zona>» cuando la guía viene de la zona.
