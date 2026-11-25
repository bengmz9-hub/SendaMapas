# Historial de cambios

## 0.7.2 (2026-11-25)

Estado: alpha; el cartel del paso y el resumen al cambiar de guía aún sin ver en el juego. Validación en Lua 5.1 con dobles: pasan `296 + 14` comprobaciones; simulación de la Guía A de principio a fin (humano y enano) con las mismas misiones entregadas que en la 0.7.1.

### Cartel del paso
- **La orden del paso actual, en grande, junto a la flecha** (`Cartel.lua`; `/smapas cartel [si | no]`, guardado en `stepBanner`): icono y verbo de la acción (RECOGE, MATA, CONSIGUE, USA, HAZ, ENTREGA; en la ruta guiada también VUELA, APRENDE EL VUELO, FIJA LA PIEDRA, USA LA PIEDRA, ENTRENA, COMPRA / VENDE, SUBE A NIVEL N, VE A <zona> y las notas), con quién o qué y el progreso («5 / 8»), y la misión debajo. Varias misiones en la misma parada: «RECOGE N misiones» con el PNJ y los primeros nombres. Funciona en todos los órdenes y con el panel cerrado.
- Va bajo la flecha y, si la flecha está oculta (paso sin coordenadas, TomTom), ocupa su sitio. Sigue los aspectos y el tamaño de la flecha, deja pasar los clics y se ilumina 0,6 s al cambiar de paso, sin sonido. Se recalcula una vez por refresco, nunca por fotograma.

### Ruta guiada
- **Ponerse al día al cambiar de guía** (`Guia.lua`): los pasos que no son misión (vuelos, posadas, entrenadores, vendedores, notas) que quedan antes de tu progreso en la guía se dan por pasados, como ya ocurría con las recogidas, sin escribir marcas a mano; también los objetivos y entregas de misiones nunca recogidas anteriores a ese progreso. No se salta ninguna misión por nivel. `/smapas guia alcanzar no` desactiva todo el «ponerse al día», también lo que antes quedaba oculto tras una entrega.
- **Resumen** (`/smapas guia resumen`): al cambiar de guía (A/B, siguiente, anterior, activar la ruta guiada o pasar al orden «Ruta») un aviso dice «N pasos ya hechos de M · ahora: …»; «Ver» abre una ventana copiable con las misiones entregadas, las del registro, los pasos pasados al ponerse al día y los 5 siguientes. Una vez por cambio; espera en combate y dentro de una instancia; sin nada hecho no avisa.

### Otros
- El cartel y el aviso del instructor se exportan e importan con los ajustes; `/smapas avisos no` quita también el aviso del resumen; el medidor de rendimiento mide el cartel.
