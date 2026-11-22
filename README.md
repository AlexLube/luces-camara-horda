# Luces, Cámara, Horda (Godot 4)

*Lights, Camera, Horde!* en inglés. Antes se llamaba «Reel Survivors» (nombre de trabajo).

Survivor-like de cine de Macacaweke Studio. Este proyecto es la **base técnica** (fases P0.5 y B1–B15 del plan de desarrollo): todo el juego funciona de principio a fin con los 5 platós que ya tienen arte, y el resto del catálogo (54 armas, 26 objetos, 96 personajes, 34 platós, 22 cláusulas, 134 premios) está cargado como datos.

- Motor: **Godot 4.3**, renderizador *Compatibility* (funciona en PC, Mac, móvil y web).
- Abrir: Godot 4.3 → *Importar* → `project.godot` → F5.
- Pruebas: `godot --headless --path . res://tests/tests.tscn` (añade `-- --quick` para saltar la partida simulada de 30 min).

## Estructura

| Carpeta | Qué hay |
|---|---|
| `data/` | Contenido en JSON, generado desde el catálogo de diseño con `tools/data/build_data.py`. |
| `i18n/ui.json` | Textos de interfaz en español e inglés. |
| `scripts/autoload/` | `Data` (contenido), `Save` (perfil y opciones), `Controls` (teclado, mando y táctil), `Loc` (idioma), `Sfx` (sonido) y `Achievements` (premios, preparado para Steam). |
| `scripts/run/` | La partida: `run.gd` (jugador, recogidas, dibujo), `enemies.gd` (horda en arrays con rejilla espacial), `weapons.gd` (11 arquetipos de arma), `director.gd` (oleadas y calendario), `upgrades.gd` (subida de nivel, latas, evoluciones y uniones) y `stats.gd`. |
| `scripts/ui/` | `hud.gd` (HUD y paneles de partida) y `ui_kit.gd` (estilo común). |
| `scripts/main.gd` | Menús: título, casting, platós, Cláusulas, Premios, opciones y créditos. |
| `tools/art/sprite_tools.py` | Pipeline de arte: imagen de Gemini → recorte de croma → tira de frames anclada. |
| `tools/shots.sh` | Capturas de todas las pantallas para revisar cambios. |
| `tests/` | Pruebas automáticas. |

## Cómo está hecho cada punto del plan

- **B1 Proyecto y migración**: el prototipo HTML pasa a escenas y scripts de Godot; el arte de los 5 platós se reutiliza tal cual (`data/art_sets.json`).
- **B2 Bucle de 30 min**: `director.gd` lleva el calendario (min 5 Estrella Invitada, 10 jefe débil, 15 oleada especial, 20 jefe, 25 dos invitadas, 28 jefe final, 30 El Productor Ejecutivo). Los platós bonus duran 20 min.
- **B3 1000+ enemigos a 60 fps**: no hay un nodo por enemigo; viven en arrays empaquetados con una rejilla espacial y se dibujan en una sola pasada ordenada por profundidad. Con 1200 enemigos la lógica tarda unos 4 ms por fotograma.
- **B4 Armas por datos, 8 niveles**: cada arma es uno de 11 arquetipos con sus números en `weapons.json`.
- **B5 Evoluciones y uniones**: arma a nivel 8 + su objeto + minuto 10 → la siguiente lata la evoluciona. Las 8 uniones funden sus armas en una nueva.
- **B6 26 objetos pasivos y estadísticas**: `stats.gd` suma base + personaje + cláusulas + objetos.
- **B7 Subida de nivel**: 3 opciones (4 con suerte), con Otra toma, Descarte y Cortar escena.
- **B8 Latas de película**: dan 1, 3 o 5 premios; los jefes siempre dan 3 o más.
- **B9 Taquilla y 22 Cláusulas**: precio creciente, devolución total y desactivar las que estén al máximo.
- **B10 Desbloqueos**: los premios desbloquean personajes y platós; los personajes se contratan con taquilla.
- **B11 Guardado**: `user://save.json` con copia de seguridad.
- **B12 Menús**: título, casting, platós, pausa, opciones (idioma ES/EN, volumen, pantalla completa, temblor, destellos, números de daño, teclas) y créditos.
- **B13 Controles**: teclado reasignable, mando y stick táctil.
- **B14 Herramientas de arte**: `tools/art/sprite_tools.py` (`sheet`, `props`, `ground`, `check`).
- **B15 Logros para Steam**: `Achievements` llama a `Steam.setAchievement` si el plugin GodotSteam está instalado; los IDs ya son estables.

## Pendiente para fases siguientes

- Arte de los 29 platós restantes (usan el bosque de forma provisional), iconos de las 54 armas y animaciones de jefes.
- Música (fase 5), reliquias, guiones y modificadores (fase 3), equilibrado fino (Q).
- Exportar: las plantillas de exportación se instalan desde el editor (*Editor → Gestionar plantillas*); los presets de Windows, Mac, Linux y Web ya están en `export_presets.cfg`.
