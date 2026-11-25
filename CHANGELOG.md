# Historial de cambios

## 0.7.0 (2026-11-25)

Estado: alpha; los cambios de fluidez y robustez de esta versión aún sin ver en el juego. Validación en Lua 5.1 con dobles: pasan `265 + 14` comprobaciones.

### Fluidez
- **Minimapa** (`MinimapPins.lua`): las marcas ya no se recolocan en cada fotograma si nada cambió (sin giro del minimapa, solo al medir cada 0,1 s; con giro, solo cuando cambia el rumbo) y se paran con el minimapa oculto.
- **Panel** (`HUD.lua`, `Core.lua`): no se construye mientras está oculto (un solo pintado al mostrarlo); un clic en una misión lo pinta una vez en vez de dos; la ventana de Opciones solo se repinta si está abierta; las peticiones de refresco que ya atendió otro refresco no se repiten.
- **Mapa del mundo** (`MapPins.lua`): la línea de ruta no trabaja con el mapa cerrado ni se redibuja si nada cambió; el zoom con la rueda lanza un solo refresco; las marcas reutilizan la lectura del registro del refresco en curso.
- **Ruta con transporte y orden «Cercanía»** (`Navigation.lua`, `Arrow.lua`): la posición mundial de los puntos fijos se recuerda en vez de pedirse en cada comparación.
- **Ruta guiada** (`Guia.lua`, `Ruta.lua`): las condiciones de clase y raza de los pasos y la cadena de guías se calculan una vez; el planificador sin guía deja el trabajo de puntos y objetivos para cuando el plan cambia de verdad.
- **Equipo de las cadenas** (`Navigation.lua`): cambiar de actitud, sigilo o forma sin cambio de rol, o cargar objetos que no son de una cadena, ya no refresca el panel.
- **Selector de mapas** (`UI.lua`, `Aspecto.lua`): cada nombre de mapa se pide una vez por pintado y no se pinta al cerrarlo ni estando oculto.
- **Piedra de hogar y filtros** (`Piedra.lua`, `Filters.lua`, `Modules.lua`): las comprobaciones baratas van primero; un texto de piedra sin sitio conocido se reintenta cada 30 s y no en cada refresco; un módulo de datos que falla no se vuelve a compilar con el mismo contenido.

### Robustez
- **Arranque** (`Core.lua`): los ids de misiones completadas se validan uno a uno antes de usarse; la lectura antigua del registro descarta ids que no son números mayores que 0.
- **Filas del panel** (`Rows.lua`, `Rows_kit.lua`, `HUD.lua`): una fila reutilizada se mide desde cero (el texto de varias líneas ya no sale recortado); el último tramo del raíl no queda colgando al recortar por altura; un objetivo sin datos no se indexa.
- **Ruta guiada en combate** (`Guia.lua`, `Core.lua`): una misión cuyo mapa no se pudo cargar en combate ya no recibe un registro falso; el plan se rehace al salir de combate. La flecha se vuelve a marcar cuando cambia el punto de la guía de la misión marcada. El aviso de misiones fuera de la guía nota las saltadas y las listas para entregar. La aceptación automática ve el plan al día aunque haya un refresco en cola.
- **Saltar** (`Core.lua`): saltar un paso de la guía que no es una misión lo marca como hecho en vez de guardarlo entre las saltadas; al dejar el orden «Ruta» no queda elegido un paso de la guía ni una misión de otro mapa.
- **Registro de errores** (`Errores.lua`, `Modules.lua`): un error repetido solo suma a su contador sin volver a construir la traza; no poder cambiar de mapa en combate ya no cuenta como error.
- **Mapa y minimapa** (`MapPins.lua`, `MinimapPins.lua`): al cerrar el mapa se oculta también la marca de destino; la estrella de destino recupera su segundo brillo al reutilizar una marca; las coordenadas del cursor y el tamaño del mapa se validan antes de comparar.
- **Nombres de PNJ** (`Navigation.lua`): el segundo intento de leer un nombre no se hace si ya estás dentro de una instancia.

### Cambios visibles
- **Flecha con varios puntos**: entre dos puntos de un objetivo a casi la misma distancia se queda en el que tenía; cambia cuando otro está más cerca por 15 m o un 10 %.
- **Pasos de la guía**: una nota, la piedra o un vuelo solo se marcan solos cuando son el paso que toca.
- **Misión terminada con 4 o más objetivos**: conserva la línea «Terminada: entrégala a…», con el nombre del PNJ en el idioma del juego.
