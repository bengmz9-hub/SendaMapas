# Módulos de SendaMapas 0.2.0-alpha

Generado por `preparar_sendamapas.py`. Tamaños reales en bytes de `Data/<módulo>.lua`.

Regla: un mapa cuyo bloque Lua compacto alcanza 35000 bytes va solo; el resto se agrupa por grupo (Reinos del Este, Kalimdor, Islas Forever, Mazmorras) en orden de progresión hasta 100000 bytes.

Mapas sin misiones (MISSING, sin módulo): Ragefire Chasm (2437), Half-Pint Tavern (16632), The Shaper's Terrace (Instance) (16667), Ruins of Gilneas (16756), Whelgar's Excavation Site (16876), Gilneas (17065), Shark-Infested Waters (17066), Hyjal Crater (17852).

| Módulo | Bytes | Mapas (zoneId: bytes, misiones) |
| --- | ---: | --- |
| SendaMapas_EK01 | 87041 | Elwynn Forest (12: 30080, 79); Dun Morogh (1: 24207, 68); Stormwind City (1519: 32541, 92) |
| SendaMapas_KAL01 | 95730 | Teldrassil (141: 25484, 66); Darnassus (1657: 12420, 31); Thousand Needles (400: 13586, 42); The Barrens (17: 8126, 23); Darkshore (148: 30938, 80); Moonglade (493: 4962, 11) |
| SendaMapas_ISLA01 | 59985 | Zephras Isle (16593: 59770, 120) |
| SendaMapas_EK02 | 47094 | Ironforge (1537: 46881, 101) |
| SendaMapas_EK03 | 98746 | Westfall (40: 23699, 53); Deeprun Tram (2257: 697, 2); Loch Modan (38: 21278, 50); Redridge Mountains (44: 16606, 42); Wetlands (11: 27926, 69); Hillsbrad Foothills (267: 8327, 18) |
| SendaMapas_EK04 | 37695 | Duskwood (10: 37482, 96) |
| SendaMapas_KAL02 | 85569 | Stonetalon Mountains (406: 11115, 27); Ashenvale (331: 20000, 53); Desolace (405: 26692, 67); Shen'dralas (16651: 14249, 34); Dustwallow Marsh (15: 13299, 47) |
| SendaMapas_EK05 | 97945 | Alterac Mountains (36: 9021, 23); Arathi Highlands (45: 14582, 35); Swamp of Sorrows (8: 6656, 17); Badlands (3: 14698, 36); The Hinterlands (47: 7969, 19); Searing Gorge (51: 15540, 33); Western Plaguelands (28: 29266, 62) |
| SendaMapas_EK06 | 44248 | Stranglethorn Vale (33: 44035, 114) |
| SendaMapas_EK07 | 42759 | Riverglades (16591: 42546, 111) |
| SendaMapas_KAL03 | 38464 | Tanaris (440: 38250, 93) |
| SendaMapas_KAL04 | 96459 | Feralas (357: 19900, 53); Azshara (16: 25710, 73); Felwood (361: 25493, 73); Blackmaw Hold (Timbermaw Open World) (1216: 3457, 7); Un'Goro Crater (490: 21284, 51); Elderwild (16848: 401, 1) |
| SendaMapas_EK08 | 38785 | Blasted Lands (4: 17810, 35); Burning Steppes (46: 12558, 23); Deadwind Pass (41: 449, 1); Blackrock Mountain (25: 7755, 13) |
| SendaMapas_EK09 | 46450 | Eastern Plaguelands (139: 46237, 102) |
| SendaMapas_KAL05 | 51443 | Silithus (1377: 51229, 109) |
| SendaMapas_KAL06 | 48264 | Mount Hyjal (616: 48050, 140) |
| SendaMapas_KAL07 | 24997 | Winterspring (618: 23992, 53); The Shaper's Terrace (16985: 791, 3) |
| SendaMapas_MAZ01 | 86347 | The Deadmines (1581: 2779, 6); Wailing Caverns (718: 2815, 8); Shadowfang Keep (209: 175, 2); Blackfathom Deeps (719: 2292, 6); The Stockade (717: 2826, 6); Gnomeregan (721: 9453, 25); Scarlet Monastery (796: 1761, 3); Razorfen Kraul (491: 2225, 4); Razorfen Downs (722: 2941, 6); Maraudon (2100: 4307, 9); Uldaman (1337: 8870, 19); Dire Maul (2557: 16641, 36); Zul'Farrak (1176: 4231, 10); Stratholme (2017: 8740, 16); The Temple of Atal'Hakkar (1477: 2912, 8); Blackrock Depths (1584: 13165, 28) |
| SendaMapas_MAZ02 | 42374 | Blackrock Spire (1583: 15007, 27); Scholomance (2057: 7633, 12); Alcaz Prison (16620: 2141, 8); Blackmaw Hold (16554: 2251, 9); City of Dalaran (16544: 2306, 4); City of Dalaran (16560: 1757, 4); Excavation Site: Wetlands (16732: 2824, 9); Krol'dok Stronghold (16842: 2801, 9); Ruins of Lordaeron (16611: 1616, 4); The Drowned City (16550: 1970, 5); The Hall of Thanes (16919: 1854, 4) |

Total módulos: 19. Bytes de datos: 1170395. Misiones: 2838 (63 marcadas como stub, siempre ocultas).

Enlaces de cadena a otros mapas con módulo: 574. Enlaces con etiqueta de captura: 175. Enlaces con etiqueta recuperada de QuestieDB local: 113 (nombres recuperados: 72). Enlaces sin mapa conocido: 0 (anónimos: 0). Discrepancias zona índice/crossMapLinks: 0. Objetivos con entrada exterior de mazmorra (`e`): 272.

Copia fijada de QuestieDB usada: `reutilizacion/20261117-snapshot-questiedb/QuestieDB` (huella combinada SHA-256: `616e84da5d99b80dc335eb954feb9c3fa747266df4870ed9abf280f56ffe5bad`).
| Archivo de entrada (`QuestieDB`) | SHA-256 |
| --- | --- |
| `QuestieDB_Forever.toc` | `02020e6789efdcdcd032d9388ff2fe14586363ea94a5fca847db9360f2015d49` |
| `src/corrections/enum/quests.lua` | `eb15f94f58be894772786706bb9c3db56756df1985d7ab93fc180d7567103ede` |
| `src/meta/questMeta.lua` | `d124338dbbc345503efb1f8cd50f7dd2d39a34760d445872f6b106af64441ee4` |
| `support/Forever/Zones/areaIdToUiMapId.lua` | `805544d9e6234876c6cc1047fc0fbde1c034a46bb418d5f5b19384b8f615206b` |
| `support/Forever/Zones/dungeons.lua` | `e2291c9f55d366957ca47cc4e7e744a7d1ab84ce421bc116417848b14039b5c9` |
