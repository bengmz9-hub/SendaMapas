# Senda Mapas 0.6.9-alpha

- Addon de guía de misiones **por mapa** para **WoW Forever** (`Interface 16001`), en español.
- Enfocado en **leveo (Alianza)**, en una sola carpeta y sin dependencias externas.
- Carga los datos de cada mapa bajo demanda al entrar en la zona.

## Instalación
- Cierra el juego y descomprime `SendaMapas-0.6.9-alpha.zip` en `World of Warcraft\_forever_\Interface\AddOns\`.
- Debe quedar una sola carpeta `AddOns\SendaMapas\` con `SendaMapas.toc` dentro.
- Activa **Senda Mapas** en la lista de addons.

## Acceso rápido
- `/smapas` — muestra u oculta el panel (el resto se gestiona desde el propio panel, el botón del minimapa o **Opciones**).

## Qué incluye
- **Panel de misiones**: órdenes *Ruta* (por defecto: recoge todas las misiones de un sitio, haz los objetivos por cercanía y entrégalas juntas, respetando las cadenas y sin misiones de profesión), *Paso a paso* (vista numerada), *Progresión* y *Cercanía*; se cambian con el botón de orden del panel, en **Opciones → Seguimiento** o con `/smapas orden ruta | pasos | progresion | cercania` (`/smapas ruta on|off` sigue siendo la línea de ruta del mapa). 8 aspectos, tamaño de texto, opacidad y filtros.
- **Ruta guiada**: incluida dentro de `SendaMapas` (`Rutas.lua`, una sola carpeta `AddOns\SendaMapas\`), el orden *Ruta* sigue rutas de leveo **Guía A** o **Guía B** elegidas por raza y nivel; añade pasos de viaje/entrenador/vendedor/nivel con detección automática y marcas a mano (`Mayús+clic`, clic derecho), consejos, misiones sin datos, paradas «Ve a <zona>», aviso de misiones sobrantes del registro y botón A/B en la cabecera (`/smapas guia [auto | siguiente | anterior | si | no | a | b | hecho [no] | mazmorras si|no | diag]`). Si se desactiva o sin rutas incluidas, *Ruta* funciona como siempre.
- **Flecha propia**: 10 diseños, distancia, tiempo estimado (ETA), sonido de rumbo, flecha al cadáver y rutas con transporte (barcos, portales, tranvía, dirigible y vuelos).
- **Mapa y minimapa**: marcas de recoger, objetivos, entrega y destino; malla de zona, línea de ruta, modo foco, coordenadas y soporte para mapas claros.
- **Cadenas y equipo**: cadenas destacadas (equipo verde/azul usable por clase y rol, llaves, monturas, mascotas, bolsas y mazmorras de 5), recompensa más valiosa y `Alt+clic` para saltar al inicio o siguiente paso.
- **Nivel y siguiente zona**: rango de nivel configurable (atenuar u ocultar), recomendación de siguiente zona y opción para olvidar misiones grises sin XP.
- **Piedra de hogar**: aviso para fijar la piedra en tu zona y sugerencia de uso en ruta cuando ahorra tiempo.
- **Comodidad**: entrega automática (pausable con `Shift`), avisos junto al panel sin escribir en el chat, exportar/importar ajustes y atajos de teclado.
