# Senda Mapas 0.2.0-alpha (WoW Forever, Interface 16001)

Guía de misiones **por mapa**, en **una sola carpeta**. Al entrar en un mapa se
compila el módulo de datos que contiene las misiones de ese mapa (los demás
siguen como texto sin procesar). El progreso sigue el orden de
progresión de los mapas (rangos de Wowhead Forever), no el nivel del
personaje: nada se bloquea por nivel; cada misión muestra su nivel, el nivel
mínimo y la experiencia.

Estado: **alpha sin probar en el juego**. Solo se ha validado con Lua 5.1 y
dobles de la API de WoW (ver «Límites conocidos»).

## Instalación (manual)

1. Cierra el juego.
2. Descomprime `SendaMapas-0.2.0-alpha.zip` dentro de la carpeta `AddOns` del
   cliente: `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\`
   (ajusta la ruta si tu instalación es otra).
3. Debe quedar **una sola carpeta**: `AddOns\SendaMapas\` con `SendaMapas.toc`
   dentro y una subcarpeta `Data`. No hace falta ninguna otra carpeta.
4. En la lista de addons, habilita `Senda Mapas`. No hay módulos aparte que
   activar: cada mapa se compila solo cuando entras en él.
5. TomTom es opcional: el addon trae su propia flecha.

No se instala nada automáticamente: estos pasos los haces tú.

## Comandos

- `/smapas`: muestra u oculta el panel.
- `/smapas mapas`: selector de mapas (orden de progresión).
- `/smapas aqui`: carga el mapa en el que estás.
- `/smapas siguiente` · `/smapas anterior`: mapa siguiente o anterior en la progresión (las flechas `<` `>` del panel pasan de misión dentro del mapa).
- `/smapas mapa <zoneId>`: carga un mapa por su identificador (p. ej. `/smapas mapa 12`).
- `/smapas auto on` · `/smapas auto off`: seguir o no el mapa actual al cambiar de zona.
- `/smapas filtros` · `/smapas opciones`: ventana de opciones, con una pestaña por tipo de opción (Panel,
  Seguimiento, Flecha, Mapa (M), Minimapa, Filtros) y la de **Aspecto**.
- `/smapas aspecto <nombre>`: cambia el aspecto del panel (`clasico`, `bronce`, `codice`, `expedicion`, `bitacora`,
  `estandarte`, `tactico`); sin nombre lista los disponibles.
- `/smapas intensidad 1|2|3`: intensidad del color de las marcas (1 normal, 2 intensa por defecto, 3 máxima).
- `/smapas minimapa tamano <50-200>`: tamaño de los símbolos del minimapa en porcentaje (100 por defecto).
- `/smapas una` · `/smapas lista [1-8]`: una misión o lista en el panel.
- `/smapas fondo <0-100>` · `/smapas fondo original`: opacidad del fondo.
- `/smapas saltar`: salta la misión seleccionada (también con clic derecho sobre su fila): sale de la lista, del
  mapa y de la flecha. El pie del panel cuenta las saltadas.
- `/smapas bloqueadas on` · `bloqueadas off`: muestra u oculta los «!» grises de misiones que aún no puedes recoger
  (faltan previas o nivel); las misiones que ya están en tu registro nunca dibujan «!» de recoger. El «!» gris nunca
  tapa otra marca: si en el mismo sitio hay un «?» de entrega u otro símbolo, el gris no se dibuja, y el «?» va siempre encima.
- `/smapas malla on` · `malla off`: malla sobre la zona de los enemigos del objetivo (mapa M).
- `/smapas ruta on` · `ruta off`: línea de ruta con flechas hasta el destino (mapa M).
- `/smapas restaurar`: recupera las misiones saltadas.
- `/smapas limpiar`: quita el destino marcado (flecha propia o TomTom).
- `/smapas actualizar` (o el botón **Actualizar** del panel): relee las misiones completadas, salta al mapa
  donde estás aunque `auto off` esté activo y resume dónde te quedaste.
- `/smapas abrir` · `/smapas cerrar`: abre o cierra la información de todas las misiones del panel.
- `/smapas resumen`: progreso del mapa actual y lista de misiones en curso.
- `/smapas minimapa on` · `minimapa off`: símbolos en el minimapa (por defecto, activados).
- `/smapas terminadas ocultar` · `terminadas mostrar`: oculta o muestra las misiones terminadas sin entregar
  (lista, marcas y flecha).
- `/smapas destino on` · `destino off`: marcador del destino en el mapa del mundo (por defecto, activado).
- `/smapas pines entregar` (por defecto) · `pines todo` · `pines off`: marcas en el mapa del mundo.
  Por defecto solo un «?» en las misiones terminadas sin entregar; `todo` añade «!» (recoger) y los
  objetivos de las misiones por completar.
- `/smapas marcar on` · `marcar off`: marcar el destino automáticamente (por defecto, activado).
- `/smapas flecha propia` · `flecha tomtom`: elegir la flecha propia (por defecto, no necesita TomTom) o TomTom.
- `/smapas flecha tamano <24-128>`: tamaño de la flecha en píxeles (por defecto 48; también con la barra de
  la ventana de opciones).
- `/smapas flecha diseno blizzard|lance|solar|aether|talon|pulse|plume`: diseño de la flecha (también con los botones de
  la ventana de opciones, que enseñan cada diseño).
- `/smapas flecha invertir`: si la flecha propia gira al lado contrario, invierte el giro.
- `/smapas flecha reiniciar`: recoloca la flecha propia (se mueve arrastrándola).
- `/smapas autoentregar si` · `autoentregar no` (sin palabra, alterna): entrega sola las misiones terminadas al hablar
  con el NPC (activada por defecto; para quitarla, `autoentregar no` o el interruptor en Opciones → Seguimiento). Nunca acepta misiones nuevas; Shift la pausa;
  con varias recompensas para elegir deja la ventana abierta y avisa en el chat.
- `/smapas test`: diagnóstico de reglas y filtros.
- `/smapas api`: dice en el chat qué funciones del juego que usa el addon existen en este cliente (una línea
  por grupo, «sí»/«no»). Sirve para saber, en la primera prueba, qué partes funcionarán.
- `/smapas diagnostico`: abre la ventana de diagnóstico (ver «Diagnóstico» más abajo).
- `/smapas texto pequeño|normal|grande`: tamaño del texto del panel (también en Opciones → Panel).
- `/smapas simbolos on` · `simbolos off`: símbolos junto a la palabra del estado (`[!] Recoger`, `[*] En curso`,
  `[?] Entregar`, `[v] Entregada`); desactivados por defecto.
- `/smapas sonido on` · `sonido off`: sonido al completar un objetivo o la misión entera (desactivado por defecto).
- `/smapas orden progresion` · `orden cercania`: orden de la lista del panel en modo Lista: el de progresión del mapa
  (por defecto) o por cercanía (ver «Orden por cercanía» más abajo).
- `/smapas errores`: lista los últimos errores de Lua del addon (registro propio, máx. 50). Se guardan en el archivo de SavedVariables al hacer `/reload` o salir del juego. `/smapas errores borrar` lo vacía.

## Atajos de teclado

En el menú de *Atajos de teclado* del juego aparece la sección **Senda Mapas** (archivo `Bindings.xml`, que el
juego lee solo de la carpeta del addon) con seis acciones sin tecla asignada: *Mostrar u ocultar el panel*,
*Misión siguiente*, *Misión anterior*, *Marcar destino*, *Selector de mapas* y *Saltar la misión*. Hacen lo mismo
que los botones del panel; las teclas las asignas tú.

## Todo desde las opciones

Los comandos `/smapas` siguen funcionando, pero no hace falta escribir ninguno: todo está en el panel o en la
ventana de opciones (botón con la rueda del panel). Los botones de la pestaña **Acciones** no escriben en el chat,
salvo *Devolver misiones saltadas* (una línea con cuántas devolvió), *Recolocar la flecha* (una línea),
*Resumen del mapa* (su fin es escribir el resumen) y lo que ya escriben los botones de mapas (el resumen de una
línea del mapa que se carga) y *Releer el progreso* (lo mismo que el botón Actualizar).

| Comando | Dónde está sin escribir |
|---|---|
| (sin palabra) | Atajo *Mostrar u ocultar el panel* |
| `mapas`, `mapa <n>` | Botón **Mapas** del panel (selector) |
| `aqui` | Opciones → **Acciones** → *Ir al mapa donde estoy* |
| `siguiente` · `anterior` | Opciones → **Acciones** → *Mapa siguiente* · *Mapa anterior* |
| `auto on` · `auto off` | Opciones → **Seguimiento** → *Cambiar de mapa solo al entrar en otro* |
| `una` · `lista [n]` · `abrir` · `cerrar` | Opciones → **Panel** (Una, Lista, límite, información de las misiones); botón *Abrir todas* del panel |
| `fondo …` · `texto …` · `simbolos …` | Opciones → **Panel** |
| `opciones` · `filtros` | Botón de la rueda del panel; pestaña **Filtros** |
| `aspecto …` | Opciones → **Aspecto** |
| `saltar` | Clic derecho en la misión del panel; Opciones → **Acciones** → *Saltar la misión elegida*; atajo |
| `restaurar` | Opciones → **Acciones** → *Devolver misiones saltadas (n)* |
| `limpiar` | Opciones → **Acciones** → *Quitar el destino marcado* |
| `resumen` | Opciones → **Acciones** → *Resumen del mapa (chat)* |
| `actualizar` | Botón **Actualizar** del panel; Opciones → **Acciones** → *Releer el progreso* |
| `marcar on` · `marcar off` · `terminadas …` · `orden …` · `sonido …` · `autoentregar …` | Opciones → **Seguimiento** |
| `flecha propia` · `flecha tomtom` · `flecha tamano` · `flecha diseno` · `flecha invertir` | Opciones → **Flecha** |
| `flecha reiniciar` | Opciones → **Acciones** → *Recolocar la flecha* |
| `destino …` · `pines …` · `intensidad …` · `malla …` · `ruta …` · `bloqueadas …` | Opciones → **Mapa (M)** |
| `minimapa on` · `minimapa off` · `minimapa tamano` | Opciones → **Minimapa** |
| `diagnostico` · `errores` · `test` · `api` | Opciones → **Panel** → *Diagnóstico* (errores completos, prueba de reglas y API); indicador **[!]** del panel |
| `errores borrar` | Opciones → **Acciones** → *Borrar errores guardados* |
| Exportar / Importar | Opciones → **Panel** (solo botones) |

## Uso

- **Primera vez**: al entrar por primera vez con un personaje el chat avisa de que la entrega automática está
  activada (Shift la pausa; `/smapas autoentregar no` la quita) y de que el aspecto y el resto están en
  `/smapas opciones`.
- **Tooltip de cada misión del panel**: al pasar el ratón muestra el número de la misión (#id), nivel, nivel
  mínimo y PX, el estado, dónde se recoge (con coordenadas), dónde se entrega (solo cuando ya está terminada,
  como en el resto del addon) y sus previas, siguientes y excluyentes con su estado y su mapa.
  **Alt+clic** en la fila abre su misión previa (la primera que no tengas entregada) o, si no hay, la
  siguiente, aunque esté en otro mapa: se carga ese mapa y se elige la misión. Clic derecho la salta.

- **Flecha propia**: no necesita ningún otro addon. Apunta respecto a hacia
  dónde mira tu personaje (destino a la derecha, gira a la derecha) y muestra
  la distancia en metros. Usa coordenadas del mundo, así que funciona entre
  mapas del mismo continente. Si el destino está en otro continente muestra
  «Ve a: <mapa> (otro continente)»; no calcula la ruta (barcos, zepelines,
  vuelos). En interiores o instancias, donde el cliente no da posición,
  muestra «Sin posición». Usa la textura base de Blizzard
  (`Interface\\Minimap\\ROTATING-MINIMAPARROW`, con `MinimapArrow` de reserva).
- **Objetivos**: mientras una misión está en curso la flecha apunta al
  objetivo sin terminar más cercano (matar, recoger, usar); cuando los
  objetivos están hechos, a quien la entrega. Los datos traen hasta 6 puntos
  por zona y objetivo (centros de las zonas donde están, no cada bicho): la
  flecha lleva al área, no a un monstruo concreto. Parte de las misiones
  con objetivos no tiene posiciones en los datos (marcas de instancia, ítems
  sin fuente conocida): entonces no hay flecha y el chat lo dice **una sola vez** por paso
  («Esta misión no tiene coordenadas de objetivo en los datos…», o «Objetivos completados…» si ya los
  tienes hechos); la flecha vuelve cuando la misión pasa a entregarse. Los objetivos hechos se
  detectan por el texto del registro de misiones y el nombre del objetivo; si
  tu cliente no está en inglés pueden no coincidir y se mostrarán todos como
  pendientes.
- **Objetivos dentro de una mazmorra**: cuando los datos indican que el punto de un objetivo es la
  entrada exterior de una mazmorra (el objetivo está dentro), el destino se llama «Entrada de <mazmorra>
  (<objetivo>)» y el chat dice «Destino: Entrada de … (el objetivo está dentro)». En el mapa del mundo
  (marcas en «todo») y en el minimapa se pone un único símbolo de destino en la entrada, con el tooltip
  «Entrada de <mazmorra>: el objetivo está dentro», y no se dibuja malla de matar o recoger allí. El
  progreso de esos objetivos se cuenta igual. Hace falta la versión de los datos que trae esa marca; con
  datos anteriores se ven como cualquier otro objetivo.
- **Aspecto** (opciones, pestaña **Aspecto**, o `/smapas aspecto`): siete aspectos entre los que elige cada
  jugador, y se cambia en vivo sin recargar. Afecta al panel, a la lista de mapas y a la ventana de opciones
  (colores, marco y estructura de las misiones). **Clásico** es el de antes; los otros seis son diseños nuevos:
  *Bastión de Hierro y Bronce*, *Códice de Dalaran*, *Cuaderno de Expedición*, *Bitácora* (el que se usa por
  defecto), *Estandarte* y *Táctico*. Los colores salen exactamente de las maquetas de diseño
  (`generar_aspectos.py` los lee de ellas y escribe `Skins.lua`).
- **Cada aspecto tiene su propia estructura de misiones** (`Rows.lua` y `Rows_*.lua`), no solo otros colores:
  *Bastión de Hierro y Bronce*: barra lateral de color del estado, etiqueta del estado y caja de información
  hundida; *Códice de Dalaran*: columna fija de 58 px con el número y el estado; *Cuaderno de Expedición*: la
  primera misión como tarjeta destacada con barras de progreso de los objetivos y las demás en lista;
  *Bitácora*: carril de nodos numerados con una línea que los une; *Estandarte*: tarjetas con banda de color y la
  información como nota de pergamino con tinta oscura; *Táctico*: filas de tabla sin marco, con la columna de
  estado y la de nivel que aparecen al ensanchar el panel, y los objetivos como barras. En todos el texto se
  parte según el ancho (360 a 900 px) y la fila crece, sin pisarse. Diferencias conocidas con las maquetas: solo
  hay tipos de letra del juego (sin negrita ni espaciado de letras, y Táctico no usa Arial Narrow), no hay
  degradados ni sombras, las marcas «✓» y «·» de las maquetas son cuadraditos, y los anchos de etiquetas se
  calculan por número de caracteres.
- **Tamaño y diseño de la flecha** (opciones, pestaña **Flecha**): una barra de 24 a 128 píxeles y siete
  diseños con vista previa: **Blizzard** (la flecha del minimapa del juego) y seis imágenes nuevas hechas desde
  cero: **Lance** (por defecto), **Solar**, **Aether**, **Talon**, **Pulse** y **Plume**. Al cambiar algo
  aparece 4 segundos una flecha de muestra que gira. Las imágenes están en `Media/Arrow_*.tga` (128x128, 32
  bits); si el cliente no pudiera cargar una, se usa la de Blizzard. Los diseños antiguos (Punta, Flecha,
  Aguja) ya no existen: quien los tenía guardados pasa a Lance.
- **Ventana de opciones** (rueda del panel o `/smapas opciones`): una columna de pestañas a la izquierda y el
  contenido de la pestaña elegida a la derecha, sin barras de desplazamiento; cada opción está en su pestaña y
  la ventana recuerda la última que usaste. Se mueve arrastrando su título.
  - **Panel**: opacidad del fondo, tamaño original, misiones visibles (Una o Lista y su límite), información
    de las misiones (al pulsar o todas abiertas), **tamaño del texto** (Pequeño, Normal o Grande), **símbolos
    junto al estado** y los botones **Exportar configuración**, **Importar configuración** y **Diagnóstico**.
  - **Seguimiento**: *seguir la misión elegida* (flecha y destino; en No solo se marca con el botón Marcar
    destino), *cambiar de mapa solo al entrar en otro*, *ocultar misiones terminadas sin entregar*,
    *orden de la lista del panel* (Progresión, por defecto, o Cercanía), *entregar misiones automáticamente*
    (activada por defecto; Shift la pausa) y *sonido al completar un objetivo o la misión* (desactivado por defecto).
  - **Aspecto**: los siete aspectos con una muestra de sus colores.
  - **Flecha**: flecha propia o TomTom, tamaño, los siete diseños con vista previa y *girar al revés*.
  - **Mapa (M)**: destino marcado, símbolos (Solo «?», Todo o Ninguno), **intensidad del color**, *malla en la zona de los enemigos*,
    *línea de ruta con flechas al destino* y *«!» de misiones aún no disponibles (grises)*.
  - **Minimapa**: símbolos Sí/No y su tamaño (50 a 200 %).
  - **Filtros**: las 12 categorías de misión (Mostrar, Marcar u Ocultar) en dos columnas.
  - **Acciones**: botones para lo que antes solo se hacía escribiendo un comando (ver «Todo desde las opciones»).
- **Tamaño del texto**: Pequeño (90 %), Normal o Grande (115 %). Se consigue escalando el panel entero, así que
  letras, filas y botones crecen juntos y no se pisan; el panel se queda en su sitio. No cambia la ventana de
  opciones ni la flecha.
- **Sonido** (opcional): con el interruptor activado suena un aviso cuando se completa un objetivo de una misión
  de tu registro y otro cuando la misión queda lista para entregar. Usa los sonidos del juego por su nombre en
  `SOUNDKIT` (o el nombre antiguo si el cliente no lo tiene); no está comprobado en el cliente cuáles existen.
- **Diagnóstico**: si el addon registra errores aparece un discreto **[!]** rojo en la barra del panel, a la
  izquierda del botón de opciones. Al pulsarlo (o con el botón **Diagnóstico** de Opciones → Panel, o
  `/smapas diagnostico`) se abre una ventana con un texto que puedes seleccionar y copiar (Ctrl+A, Ctrl+C):
  versión, mapa activo y zona actual, el resultado de `/smapas api`, el de `/smapas test` y todos los errores
  completos (en el chat se cortan a 160 caracteres). `/smapas errores borrar` vacía la lista y quita el [!].
- **Exportar e importar la configuración** (Opciones → Panel): **Exportar** muestra un texto que empieza por
  `SM1;` con el aspecto, la flecha (diseño, tamaño, posición, giro), tamaño y posición del panel, opacidad,
  modo de las marcas, intensidad, tamaño del texto, interruptores y filtros. **No** incluye el progreso (misiones
  entregadas, saltadas, mapa activo ni misión elegida por mapa). Cópialo, pégalo en **Importar** en otro
  personaje y pulsa **Aplicar**. Los ajustes que nunca cambiaste en el personaje de origen no se exportan. La
  importación es todo o nada: si una sola parte no es válida (clave desconocida o repetida, valor fuera de rango,
  texto mal formado o de más de 4000 caracteres) no se cambia nada y el chat dice por qué.
- **Intensidad de las marcas**: Normal, **Intensa** (por defecto) o Máxima. Aviva los colores del halo (sin duplicar el
  icono, que lo desenfocaría) y la franja del destino pasa a azul
  intenso con bordes dorados. Afecta al mapa M y al minimapa.
- **Movimiento fluido**: el rumbo y la distancia se miden 10 veces por segundo, pero la flecha gira en
  **cada fotograma** con la orientación actual del personaje, y los símbolos del minimapa se recolocan
  también en cada fotograma (con el minimapa rotando se deslizan en vez de saltar).
- **Minimapa**: los mismos símbolos en grande: la estrella del destino (si se sale del alcance se queda
  en el borde señalando la dirección), sus otros puntos posibles y los «?» de las misiones terminadas
  de la zona donde estás (dentro del alcance). Usa el radio de vista del minimapa según su zoom y
  respeta la rotación del minimapa. Su tamaño se ajusta en las opciones. No hay símbolos en interiores ni
  instancias, donde el cliente no da posición. Si otro addon hace el minimapa cuadrado (función
  `GetMinimapShape` distinta de «ROUND»), los símbolos llegan hasta el borde cuadrado. Al pasar el ratón por un
  símbolo de misión se ve su nombre, el tipo (Entregar, Recoger, Objetivo) y el motivo; los clics siguen
  llegando al minimapa (no está comprobado en el cliente). Un símbolo que aparece durante un combate no
  responde al ratón hasta salir de él (así no se toca nada restringido en combate). Con los símbolos
  desactivados, o si el cliente no da el radio del minimapa, también se quita la línea de ruta.
- **Lista de mapas** (botón «Mapas»): cabeceras por franja de niveles y una de mazmorras, una banda de
  color por grupo (Reinos del Este dorado, Kalimdor verde, Islas Forever violeta, mazmorras rojo), filas
  alternas, el rango de nivel a la derecha, el mapa actual resaltado con «>», «(estás aquí)» en verde y
  debajo cuántas misiones tiene y cuántas llevas entregadas (o «sin abrir»). Al abrirla se desplaza al
  mapa actual.
- **Destino en el mapa del mundo** (tecla M): lo que marcas con **Marcar destino** (o lo que la
  flecha está siguiendo) se ve siempre en el mapa: una **estrella dorada grande con un halo que
  parpadea** y el nombre de la misión y del lugar debajo, **puntos dorados pequeños** en los otros
  sitios posibles del mismo objetivo, y una **franja negra arriba del mapa** con «Destino: …». Si el
  destino está en otro mapa, la franja dice en cuál y **al pulsarla abre ese mapa**. Al pulsar
  «Marcar destino» con el mapa abierto, el mapa salta al del destino. Funciona aunque tengas las
  demás marcas apagadas (`pines off`).
- **Marcas en el mapa del mundo** (tecla M): por defecto solo un «?» en quien entrega cada misión
  que tienes **terminada y sin entregar**. Nunca se marca dónde entregar una misión que no has
  terminado. `/smapas pines todo` añade «!» donde recoger misiones, y calaveras (matar) y rombos
  (recoger o usar) en los objetivos sin terminar de las misiones de tu registro. La malla de la zona de los
  objetivos es **roja** para matar y **azul** para recoger o usar, como sus iconos. Pasar el ratón da
  el detalle; pulsar una marca elige esa misión y marca la ruta con la flecha; pulsarla otra vez quita la ruta y deja libre el destino (la misión sigue elegida, pero el marcado automático no la vuelve a marcar hasta que cambie de estado o elijas otra). Las misiones que aún no puedes recoger
  (faltan previas o tu nivel es menor) conservan su «!» en quien las da, con el motivo y sus objetivos en el
  tooltip, pero nunca dibujan objetivos, malla ni monstruos en el mapa ni en el minimapa. Usa texturas base del juego
  y el lienzo de `WorldMapFrame`. Al abrir el mapa de una zona cuyo módulo no está cargado, se
  compila en ese momento (no en combate).
- **Marcado automático**: la misión elegida se marca sola; al cambiar de mapa,
  elegir otra misión, aceptar o entregar una, la flecha se actualiza.
- **Resumen**: el pie del panel muestra misiones entregadas y en curso del
  mapa (y cuántas están listas para entregar). Al entrar en un mapa se escribe
  en el chat su resumen; `/smapas resumen` lo detalla.

- **Selección automática**: al entrar en el mundo o cambiar de zona el addon
  identifica el mapa y carga su módulo. Al entrar al juego el cliente tarda en dar la posición del
  personaje, así que reintenta hasta 3 veces (a los 2, 4 y 6 s) antes de quedarse con el último mapa
  guardado. En combate espera a salir de él.
- **Misiones ya hechas**: se leen de la lista de misiones completadas del cliente
  (`C_QuestLog.GetAllCompletedQuestIDs`, la que usan los addons de Forever) y de las entregas que el
  addon vio con este personaje (se guardan por personaje). Aparecen como Entregadas y no se te
  vuelven a proponer. El botón **Actualizar** vuelve a leerlas.
- **Dónde te quedaste**: al actualizar, la misión elegida es la que tienes lista para entregar, o en
  curso, o la continuación de una cadena que ya empezaste (una misión disponible porque ya hiciste
  su previa) antes que cualquier otra misión nueva del mapa.
- **Flechas `<` `>`**: pasan a la misión anterior o siguiente **del mismo mapa** (botones
  del panel); la flecha de navegación y las marcas siguen a la misión elegida. No cambian de mapa.
  Siguen siempre el orden de progresión del mapa, también con el orden por cercanía.
- **Orden por cercanía** (opcional, desactivado por defecto; Opciones → Seguimiento o `/smapas orden cercania`): en
  modo **Lista**, la misión elegida sigue arriba y las demás se ordenan de la más cercana a la más lejana según su
  siguiente paso: dónde se recoge si aún no la tienes, el objetivo sin terminar más cercano si está en curso, o
  quien la entrega si ya está terminada (la misma distancia que usa la flecha). Las que no tienen coordenadas o
  están en otro continente van al final; a igual distancia se respeta el orden de progresión. El orden se
  calcula al actualizarse el panel (al cambiar el registro de misiones, al entrar en otra zona o con
  **Actualizar**), no mientras caminas, para que la lista no salte. En modo **Una** no cambia la misión elegida.
  Los números de cada fila siguen siendo su posición en el orden de progresión.
- **Cambiar de mapa a mano**: botón «Mapas» del panel, o
  `/smapas siguiente` · `/smapas anterior` (orden de progresión). El mapa elegido a mano **se mantiene
  hasta que cambies de zona**: mientras sigas en la misma zona no vuelve solo al mapa donde estás (el pie
  del panel lo indica); al entrar en otra zona el seguimiento automático decide otra vez. Con `auto off` el
  mapa elegido no cambia nunca al moverte.
- **Zonas sin misiones**: si los datos incluyen la lista de zonas sin misiones registradas
  (`ns.Index.missingMaps`, que genera `preparar_sendamapas.py`), al entrar en una de ellas el panel y
  `/smapas aqui` dicen «<Nombre>: zona sin misiones registradas en la base actual» en lugar de «No se reconoce
  el mapa actual». Sin esa lista se mantiene el mensaje de antes.
- **Cadenas entre mapas**: la información de una misión muestra el mapa de sus previas y siguientes sin
  cargar ese módulo (cada módulo guarda nombre y mapa de sus enlaces). El panel ya no tiene ventana de
  diario: se quitó a petición del autor.
- **Filtros** (Opciones > Filtros): para élite, grupo, mazmorra, banda, JcJ,
  repetibles, estacionales/eventos, profesión, otra clase, otra raza, otra
  facción y entregadas se elige Mostrar, Marcar (etiqueta) u Ocultar. Por
  defecto se ocultan las de otra clase, raza o facción (según el personaje) y
  las entregadas; el resto se marca. Las misiones `unimplementedStub` siempre
  se ocultan.
- **Estado de cada misión**, leído del registro de misiones y de la lista de completadas del juego:
  *sin coger* (Recoger), *por completar* (En curso: la tienes y falta completarla), *terminada sin
  entregar* (Entregar) y *entregada* (Entregada); además Faltan previas, Rama cerrada (excluyente ya
  hecha) y Comprobar. Solo la terminada sin entregar muestra dónde entregarla: una misión por
  completar muestra sus objetivos, no a su entregador.
- **Datos guardados por personaje** en `SendaMapasDB`: mapa activo, misión
  elegida por mapa, saltadas, filtros, seguir mapa, tamaño, posición y
  opacidad del panel y de las opciones, tamaño del texto, símbolos y sonido. Lleva un número de versión
  (`schema`) y al cargar se limpia: la lista de misiones abiertas vuelve a empezar si pasa de 200, y de las
  entregas vistas por el addon se quitan solo las que el propio juego ya da como completadas (ninguna entrega se
  pierde).

## Decisiones de diseño

- **Datos**: `preparar_sendamapas.py` convierte `guia-mapas-forever/mapas/*.json`
  en módulos Lua compactos, guardados como texto en `Data/` (id, nombre, nivel, nivel mínimo, PX, banderas en
  máscara de bits, bando, inicio/entrega con id, nombre y coordenadas por
  zona, texto y nombres de objetivos, previas/siguientes/excluyentes y enlaces
  a otros mapas, hub). El script es determinista: dos ejecuciones producen los
  mismos bytes.
- **Módulos**: decididos por el tamaño real del Lua generado (ver
  `MODULOS.md`). Un mapa de 35 000 bytes o más va solo; el resto se agrupa por
  continente (Reinos del Este, Kalimdor, Islas Forever, Mazmorras) en orden de
  progresión hasta unos 100 000 bytes. Resultado: 14 archivos `Data/*.lua` en
  lugar de 75 mapas sueltos. Cada archivo se lee al iniciar como una cadena de
  texto (barato) y se compila con `loadstring` solo al elegir uno de sus mapas;
  después se libera su texto. Una sola carpeta no puede usar `LoadOnDemand`
  (eso exige un addon por módulo), por eso se hace así. Los 8 mapas vacíos (MISSING) no tienen módulo.
- **Índice**: el addon principal solo lleva `Index.lua` (mapa → módulo, orden
  de progresión, rango de niveles de Wowhead, número de misiones).
- **Identificar el mapa**: los datos usan identificadores de zona (AreaTable),
  no `uiMapID`, y no se ha copiado ninguna tabla de equivalencias de terceros.
  El addon compara nombres: el nombre localizado de la zona
  (`C_Map.GetAreaInfo`) y el nombre inglés de los datos frente a
  `C_Map.GetBestMapForUnit` + `C_Map.GetMapInfo` (y sus mapas padre),
  `GetRealZoneText` y `GetZoneText`. Dentro de una instancia se prefieren las
  mazmorras.
- **Flecha**: el `uiMapID` de destino se obtiene del mapa actual o del árbol de
  mapas del cliente (`C_Map.GetMapChildrenInfo`), también por nombre.
- **Previas**: la fuente mezcla previas obligatorias y alternativas en una
  sola lista; para no ocultar alternativas válidas basta con una completada.
- **Orden de progresión**: el orden mundial combinado de `ORDEN_MAPAS.md`
  seguido de las mazmorras en su propio orden.

## Desarrollo y validación (fuera del paquete)

En la carpeta `ADDONWOW`:

- `python preparar_sendamapas.py`: regenera `SendaMapas/Index.lua`,
  `SendaMapas/MODULOS.md`, `SendaMapas/SendaMapas.toc`, los archivos
  `SendaMapas/Data/*.lua` y el ZIP. Lee `guia-mapas-forever/` sin modificarlo.
- `python validar_sendamapas_lua.py`: compila todos los `.lua` y ejecuta
  `tests_sendamapas/sendamapas_test.lua` con el Lua 5.1 incluido en VLC y
  dobles de la API de WoW (no es el cliente del juego).
- `python generar_aspectos.py`: regenera `SendaMapas/Skins.lua` a partir de las variables de color de las
  maquetas de `disenos/` (las seis maquetas y el aspecto clásico).
- `python tests_sendamapas/validar_paquete_sendamapas.py`: comprueba TOC,
  la carpeta única `Data`, el orden del TOC, tamaños y que el ZIP contiene exactamente los
  mismos archivos que las carpetas.

## Límites conocidos

- **No probado en el cliente**. No se ha comprobado en el juego la carga de
  módulos, la detección de mapas, la interfaz, la flecha propia (su sentido de giro no está comprobado), TomTom ni posibles problemas de
  *taint*.
- La detección automática depende de que los nombres del cliente coincidan
  con el nombre localizado del área o con el inglés de los datos. Si no
  coinciden (mapas con nombre distinto en la interfaz, nombres repetidos como
  los dos «City of Dalaran»), usa el selector manual.
- Las posiciones de los objetivos existen solo para parte de las misiones (alrededor del 76 %): con las demás, el
  addon avisa una vez de que no hay coordenadas y la flecha no se muestra; sigue el texto en el registro de misiones.
  Si el cliente no está en inglés, los objetivos se emparejan por posición cuando el número de objetivos coincide.
- El identificador de raza de los altos elfos en Forever no está confirmado;
  si el cliente devuelve otro, esas misiones se marcan con «(?)» en lugar de
  ocultarse.
- Las misiones fuera de los mapas capturados (p. ej. de clase o de otra
  facción) se muestran solo con nombre y etiqueta; no hay módulo que cargar.
- Los datos proceden de Wowhead Forever para uso local: revisa
  `THIRD_PARTY.md` antes de redistribuir.
