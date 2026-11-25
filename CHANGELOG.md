# Historial de cambios

## 0.7.1 (2026-11-25)

Estado: alpha; el aviso del instructor, el diagnóstico de API ampliado y el medidor de rendimiento aún sin ver en el juego. Validación en Lua 5.1 con dobles: pasan `285 + 14` comprobaciones.

### Instructor de clase
- **Aviso para ir al instructor** (`Instructor.lua`; `/smapas instructor [si | no | ir | hecho]`): al llegar a un nivel par del 4 al 60 sale un aviso junto al panel con los botones «Ir» (la flecha apunta al instructor de tu clase más cercano que conocen las guías, como marca manual) y «Hecho». Espera si estás en combate, en taxi, muerto o dentro de una instancia, y vuelve una vez al entrar en una zona con instructor de tu clase mientras la visita siga pendiente.
- **Lo que dice el propio instructor**: al abrir la ventana del instructor de clase el addon lee qué hechizos quedan y a qué nivel; desde entonces el aviso dice cuántos hay, cuánto cuestan y si te alcanza el dinero, también en un nivel que la regla par no da. La visita se da por hecha al cerrar la ventana sin nada pendiente. Sin tabla de hechizos incluida: si el cliente no deja leer la ventana, queda el aviso por nivel par. Sin probar en el cliente 16001: `GetNumTrainerServices`, `GetTrainerServiceInfo`, `GetTrainerServiceLevelReq`, `GetTrainerServiceCost`, `UnitGUID`, `GetMoney` y `TRAINER_UPDATE`.
- `/smapas avisos no` quita también este aviso; el interruptor propio se guarda en `trainerNotice`.

### Diagnóstico
- **Inventario completo de la API** (`Diagnostico.lua`): `/smapas api` y la ventana de diagnóstico añaden al final «API ausente» y «Eventos no válidos», con todas las funciones, tablas y eventos del juego que usa el addon (128 nombres y 34 eventos). Solo comprueba si existen; no llama a ninguna. El resultado se guarda en `SendaMapasDB.apiDiag` cada vez que se consulta y, sin escribir nada, unos segundos después de entrar al mundo.
- **Medidor de rendimiento** (`Rendimiento.lua`; `/smapas rendimiento [si | no | ver | borrar]`): mientras está activo mide las llamadas, el tiempo total, el tiempo por llamada y el máximo de 30 funciones principales (refresco, panel, flecha, ruta guiada, marcas del mapa y del minimapa), además de los fotogramas y el más largo. Informe en una ventana copiable y en `SendaMapasDB.perfReport`. Apagado no cuesta nada (se devuelven las funciones originales) y siempre arranca apagado. Los tiempos son inclusivos. Necesita `debugprofilestop` o `GetTimePreciseSec`; si el cliente no tiene ninguno, lo dice y no mide.
