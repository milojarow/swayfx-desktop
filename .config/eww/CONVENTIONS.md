# eww Config Conventions

This config has dozens of yuck/scss/scripts files. Without an explicit
convention, knowing which files work together for any given feature
becomes archaeology. These rules keep that discoverable.

## Feature, not widget

Each file declares which **feature** it serves. A feature is a user-facing
capability — wifi, battery, gamma, usb-widget, etc. A feature can
manifest as:

- A standalone window (`defwindow`) — e.g. `wifi-popup`, `temps-window`
- A module inside the bar (`defwidget` consumed by `bar.yuck`) — e.g. `bar-wifi`, `bar-gamma`
- Both at once — e.g. `battery` shows up in the bar AND as a desktop widget
- Just supporting scripts/styles with no UI of its own

The same `feature:` tag groups all of those. The `role:` tag distinguishes them.

## Header format

Every file under `widgets/`, `scripts/`, `styles/` starts with a header
comment in this shape:

```
; feature: <name>
; role:    <vocabulary entry>
; deps:    <comma-separated paths, optional>
```

Comment syntax depends on the language:

| Extension | Prefix |
|---|---|
| `.yuck` | `;` |
| `.scss` | `//` |
| `.sh` `.py` | `#` |

The shebang stays on line 1 if present; the header goes immediately after.

### `role:` vocabulary

Use one of these exact words. Anything outside the list is a smell.

| Role | Meaning |
|---|---|
| `window` | Defines a `defwindow` (a standalone surface) |
| `module` | Defines a `defwidget` consumed inline by `bar.yuck` (used inside the bar's centerbox) |
| `container` | Hosts multiple modules from different features (today only `bar.yuck`) |
| `style` | SCSS for a feature |
| `subscribe` | `deflisten` script — long-lived, emits state changes |
| `action` | One-shot script invoked from `:onclick`, `:onhover`, etc. |
| `helper` | Internal utility called by other scripts (not eww directly) |
| `shared` | Used by every feature (`theme.scss`, `_open-windows.sh`, etc.) |

### Example — feature with several files

```
; widgets/wifi-popup.yuck
; feature: wifi
; role:    window
; deps:    scripts/wifi-{toggle,close,rescan,connect,disconnect,forget}.sh,
;          scripts/wifi-{scan,subscribe}.py, styles/wifi.scss
```

```
# scripts/wifi-subscribe.py
# feature: wifi
# role:    subscribe
```

```
// styles/wifi.scss
// feature: wifi
// role:    style
```

### Example — `bar.yuck` as container

`bar.yuck` defines many `defwidget`s belonging to different features. One
`feature:` tag can't capture that. The header gets a TOC of modules, each
mapping to its real feature:

```
; widgets/bar.yuck
; feature: bar
; role:    container
; modules:
;   - bar-battery       (feature: battery)
;   - bar-mem-pressure  (feature: mem-pressure)
;   - bar-clipboard     (feature: clipboard)
;   - bar-wifi          (feature: wifi)
;   - bar-gamma         (feature: gamma)
;   - bar-volume        (feature: volume)
;   - bar-dnd           (feature: dnd)
;   - bar-date          (feature: date)
;   - bar-workspaces    (feature: workspaces)
```

The `_manifest.sh` parser reads this TOC and emits cross-references in
the generated `MANIFEST.md`.

### Example — feature in two surfaces

`battery` lives in the bar (as `bar-battery` module) AND as `battery-window`
on the desktop. Same feature tag, different roles.

```
; widgets/battery.yuck
; feature: battery
; role:    window
```

```
# scripts/battery-subscribe.sh
# feature: battery
# role:    subscribe          (used by both surfaces)
```

`bar-battery` itself is documented in `bar.yuck`'s TOC; no extra file.

## Naming convention

Files belonging to feature `X` are named `X[.-]*.<ext>`:

- `wifi-popup.yuck`, `wifi-toggle-popup.sh`, `wifi.scss` → all feature wifi
- `gamma-subscribe.sh`, `gamma.scss` → all feature gamma

Shared utilities used by many features get the prefix `_`:

- `_open-windows.sh`, `_manifest.sh`

Existing files that don't follow this convention are not renamed if the
header tag is unambiguous. Going forward, prefer the convention.

## Tooling

- `scripts/_manifest.sh` — regenerates `MANIFEST.md`. Run after adding/
  modifying files. Also reports orphans (no header), ghosts (header
  references a feature with no other files), and name/header dissonances.
- `MANIFEST.md` — auto-generated index of all files grouped by feature.
  Don't edit by hand.
