![Scale Slider bar widget](docs/bar-widget.png)

A display-scale slider for the Omarchy bar. The bar shows the current Hyprland
scale; clicking it opens a popup with a 1.00×–2.00× slider and an editable
value field, and every settled change commits through the same CLI the
standalone app uses.

## Bar widget plugin

```sh
./bin/build            # builds the CLI the widget shells out to
./plugin/install.sh    # installs into ~/.config/omarchy/plugins/
```

`plugin/install.sh` copies the plugin into `~/.config/omarchy/plugins/`
(the shell hot-reloads it), symlinks `build/scale-slider` into `~/.local/bin`
when the CLI is not yet on PATH, and prints the one manual step: adding
`{"id": "admin.scale-slider"}` to any `bar.layout` section of
`~/.config/omarchy/shell.json`, e.g. beside the audio widget in `right`.
If an edit ever looks stale, `omarchy-shell shell rescanPlugins` or
`omarchy restart shell` clears it.

Behavior:

- The bar readout is live: `scale-slider check --json` runs at shell startup
  and whenever the panel opens, so a scale changed anywhere — including by the
  standalone app or by hand in `monitors.lua` — is what the bar shows.
  The screenshot above is that readout with the panel open.
- Left click opens the popup; dragging is preview-only and applies on release,
  so repeated config reloads can never yank the panel out from under the
  cursor mid-drag. Mouse wheel anywhere steps the scale one notch.
- The value field is editable: click to select, Enter or focus-out applies,
  Escape backs out, invalid input snaps back. Dot and comma decimals both work.
- Right click on the bar icon opens the standalone app; the popup carries
  h/l adjust and Esc/q close, and the widget honors Omarchy's theme, language
  (English and Danish catalogs included) and bar styling, mirroring in
  right-to-left locales.
- `min`, `max`, `step` and `binPath` are per-widget settings in the widget's
  `shell.json` entry; `min`/`max` default to the app's 1.00–2.00 range and
  `step` to 0.01.

### Open problem: panels do not survive a scale change

Applying a scale runs `hyprctl reload`, and changing an output's scale makes
Hyprland tear down and re-map the layer-shell surfaces on that output — the
bar's included. When a layer surface dies, Qt Quick frees its whole scene
graph (`Bar.qml` in omarchy-shell: unmapping "frees the layer surface and the
whole scene graph"), so **every bar widget instance is destroyed and
re-created**, and an open panel simply does not exist afterwards: fresh
instance, `open` state lost, popup gone.

This was verified by instrumenting widget instance creation (timestamps land
at the exact moment of the reload) and by a toggle probe after a change: one
toggle re-opens the panel, meaning the controller state itself was reset, not
merely the surface. Omarchy's own panels collapse the same way — the volume
panel, for example, closes identically across a scale change. It is therefore
a property of the bar widget lifecycle, not of this plugin.

The panel is anchored to a bar icon and is part of the bar's scene graph, so
"stays put while the world re-lays out" is not reachable from here: the panel
would need its own independent layer surface (the way the OSD and
notifications live), or the shell would need to migrate panel state across
widget remounts. Both are internal changes to omarchy-shell. As of this
writing the popup closes on commit — the shift-around is Hyprland doing its
job; the panel dying is the shell's scene graph going down with it.

## Standalone app

A small Omarchy desktop app for adjusting display scale from 1.00× to 2.00×.
Drag the slider, scroll over it, or type an exact value into the scale field.
Press Enter or leave the field to apply a typed value; Escape cancels editing.
Values use steps of 0.01. Closing keeps the last applied scale.

```sh
./bin/build
./build/scale-slider open
```

`./bin/install` builds and installs the Arch package and launcher entry.
Build requirements: Qt 6 base and declarative, qmake6, make and a C++17 compiler.
The app uses Hyprland's Lua configuration and `hyprctl`.

Each update atomically saves `~/.config/hypr/monitors.lua`, ensures
`debug.disable_scale_checks = true`, and runs `hyprctl reload` followed by
`hyprctl configerrors`. The first update in a session saves a timestamped
backup alongside the file. Rejected updates restore the previous contents.
Updates are throttled to 120 ms while dragging and flushed on release.
The app reads the latest contents before each write, preserving unrelated edits.
Earlier duplicate scale assignments are commented out; one active declaration
remains. The variable must be a simple top-level assignment used by your monitor
rule. Explicit monitor rules with independent scales are not changed.
Block comments and long strings require manual review rather than guessed edits.

| Key | Action |
|---|---|
| Left / Right | Adjust focused slider by 0.01 |
| Scroll over slider | Adjust by 0.01 |
| Enter in scale field | Apply typed scale |
| Escape in scale field | Cancel editing |
| Space | Focus slider |
| Ctrl+Z / Ctrl+Shift+Z | Undo / redo applied changes |
| ? | Show shortcuts |
| Q | Close |

Headless commands:

```sh
scale-slider check --json
scale-slider set 1.45 --json
scale-slider skill install
```

`--config PATH` and `--hyprctl PATH` support isolated testing. `check` inspects
whether the file is editable; it does not change it. `set` validates and applies
one scale. Commands return 0 for success and 1 for errors.

Run `./bin/test` for file preservation, backups, rollback, duplicate declarations,
input validation, and actual QML keyboard, wheel and text-field interaction tests.
Tests use temporary files and a fake compositor command.

Theme and language helpers are adapted from the Omarchy app templates, based on
Omacut by David Heinemeier Hansson (MIT).
