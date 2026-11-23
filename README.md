# Claude Deck

App nativa de macOS para ver y manejar todas tus sesiones de [Claude Code](https://claude.com/claude-code) desde un solo lugar.

## Qué hace

- **Panel de sesiones:** muestra en tiempo real las sesiones activas y las recientes, con su estado: trabajando, esperando tu permiso, inactiva o cerrada. También muestra sus subagentes.
- **Terminal integrada:** las sesiones abiertas desde Claude Deck corren en tmux y se ven dentro de la app. Si cierras la ventana, siguen vivas.
- **Traer a Claude Deck:** pasa a la app una sesión que abriste en otra terminal.
- **Cerebro por sesión:** cada sesión abierta desde Claude Deck tiene su propio `BRAIN.md`, donde Claude guarda lo que vale la pena recordar. Al cerrarla puedes guardarlo como especialista con un nombre y usarlo de punto de partida en sesiones nuevas.
- **Liberar contexto:** primero le pide a Claude que actualice el cerebro de la sesión y, cuando termina, manda `/compact`. La sesión sigue siendo la misma, con un resumen corto y el cerebro recargado. Se activa cuando Claude no está trabajando ni esperando tu permiso, y se resalta en naranja pasados los 100k tokens.
- **Organización:** puedes renombrar sesiones, agruparlas y borrarlas por completo.
- **Lo que te necesita, a la vista:** cada sesión tiene un avatar de color con sus iniciales y su estado.
  - Las que esperan tu permiso se resaltan en naranja.
  - Las que están trabajando muestran una barra verde y una ruedita.
  - Las que respondieron o terminaron desde la última vez que las abriste llevan un punto azul y el texto "Respuesta nueva".
  - Con clic derecho → "Marcar como no vista" dejas una pendiente para después.
- **Apariencia de la terminal:** tema, letra, tamaño, zoom (⌘+, ⌘-, ⌘0 o pellizco), margen alrededor de la terminal y opacidad del fondo con el escritorio desenfocado detrás. Cada cambio puede aplicarse a una sola sesión o a todas.
- **Colores de Claude según el tema:** si Claude Code usa el tema `dark-ansi` (o `light-ansi`), toma los colores del tema de Claude Deck. Ese ajuste es de Claude y vale para todas tus terminales; con temas claros de Claude Deck conviene `light-ansi`.
- **Barra de estado propia:** al pie de Claude se muestra el nombre de la sesión, el modelo, el contexto usado (verde, amarillo o rojo) y la rama. Solo en las sesiones abiertas desde Claude Deck, y se desactiva en Ajustes → Apariencia. Se aplica al abrir o reanudar una sesión.
- **Apariencia de la lista:** en Ajustes → Lista eliges la letra y sus tamaños, qué muestra la línea de detalle (carpeta, rama, contexto, hace cuánto, último mensaje), la densidad, el color de acento, los colores de estado, el fondo y el estilo de íconos.
- **Avisos:** ventanitas flotantes cuando Claude pide permiso, termina su turno, se cierra una sesión o termina un subagente. Puedes elegir la posición, la pantalla, la duración, el sonido y el texto de cada evento.
- **Barra de menús:** un ícono indica cuántas sesiones esperan tu respuesta.

## Requisitos

- macOS 14 (Sonoma) o más nuevo
- Claude Code instalado y abierto al menos una vez, para que exista `~/.claude/settings.json`
- Command Line Tools de Apple (no hace falta Xcode)
- tmux, instalado con [Homebrew](https://brew.sh)

```sh
xcode-select --install
brew install tmux
```

## Instalación

```sh
git clone https://github.com/Willintong-dev/claude-deck.git ~/claude-deck
cd ~/claude-deck
./scripts/build-app.sh
python3 scripts/hooks.py install
open ~/Applications/ClaudeDeck.app
```

- `build-app.sh` compila la app y la deja en `~/Applications/ClaudeDeck.app`. También instala `~/.claude-deck/bin/deck-hook`. La primera vez tarda unos minutos porque descarga SwiftTerm.
- `hooks.py install` registra `deck-hook` en los hooks de `~/.claude/settings.json`. No toca los hooks que ya tengas y antes guarda una copia de respaldo (`settings.json.bak-claude-deck-<fecha>`).

Las sesiones de Claude Code que abras después aparecen en la app. Las que ya estaban abiertas se ven, pero su estado se actualiza recién con su siguiente evento.

## Actualizar

```sh
cd ~/claude-deck
git pull
./scripts/build-app.sh
```

Después cierra Claude Deck desde la barra de menús (Salir) y vuelve a abrirla. Las sesiones que corren en tmux siguen vivas mientras tanto.

## Desinstalar

```sh
cd ~/claude-deck
python3 scripts/hooks.py remove
rm -rf ~/Applications/ClaudeDeck.app ~/.claude-deck
```

Borrar `~/.claude-deck` elimina los nombres, grupos, cerebros guardados y ajustes de Claude Deck. Tus conversaciones de Claude Code en `~/.claude` no se tocan.

## Dónde guarda las cosas

| Archivo | Contenido |
| --- | --- |
| `~/.claude-deck/events.jsonl` | Eventos que reciben los hooks |
| `~/.claude-deck/catalog.json` | Nombres, grupos y sesiones borradas |
| `~/.claude-deck/appearance.json` | Apariencia de la terminal y de la lista |
| `~/.claude-deck/read.json` | Hasta dónde viste cada sesión |
| `~/.claude-deck/notifications.json` | Configuración de avisos |
| `~/.claude-deck/brains/` | Cerebros guardados y en uso |

## Problemas conocidos

- **`hooks.py` falla con "No such file":** `~/.claude/settings.json` todavía no existe. Abre Claude Code una vez y vuelve a correrlo.
- **macOS no deja abrir la app:** la app se firma solo en tu Mac, sin certificado de Apple. Si la compilas tú, no debería pasar. Si te pasaron el `.app` ya compilado, ábrelo con clic derecho → Abrir.
- **Sonido doble en los avisos:** otro hook de `settings.json` también reproduce sonidos. Quítalo o deja el sonido de Claude Deck en "Ninguno".
- **Los avisos no respetan "No molestar":** Claude Deck dibuja sus propios avisos, no usa las notificaciones de macOS. Los desactivas en Ajustes → Notificaciones.
- **Borrar una sesión no se puede deshacer:** elimina el transcript y los archivos de la sesión dentro de `~/.claude`.

## Desarrollo

```sh
./scripts/test.sh
swift build --package-path App
```

- La lógica vive en `Sources/DeckCore` y tiene tests en `Tests/DeckCoreTests`.
- La interfaz (SwiftUI + AppKit) está en `App/Sources/ClaudeDeck`.
- Sin Xcode, el plugin de macros de Swift Testing a veces no carga. `test.sh` reintenta solo y limpia `.build-tests` entre intentos.
- Sin Xcode tampoco funcionan las macros de SwiftUI como `@State`, así que el estado de las vistas vive en `DeckStore`.
