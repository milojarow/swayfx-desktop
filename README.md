# swayfx-desktop

A complete SwayFX desktop — compositor config, keybindings, binding modes, waybar,
eww widgets, rofi, screenshots, screen recording, clipboard manager, emoji picker,
and a live palette-theming system that recolors everything at once.

Exported from a machine where this is the daily driver, so it is a working setup
rather than a starter kit. Everything personal to that machine was stripped;
`tools/check.py` is the gate that proves it.

---

## Requirements

**SwayFX, not vanilla sway.** The config uses `corner_radius`, `layer_effects` and
`animation_duration_ms`, which vanilla sway rejects when it loads the config. On
Arch/CachyOS the package is `swayfx` and it installs as `/usr/bin/sway`.

Reference machine: **SwayFX 0.6** (sway 1.12.0 base), CachyOS, `foot` as terminal,
JetBrains Mono Nerd Font. The bar and cheatsheet are full of Nerd Font glyphs — with
a plain font you get tofu boxes everywhere.

---

## Install

**1 — packages**

```bash
paru -S --needed $(grep -vE '^#|^$' dependencies.txt | tr '\n' ' ')
```

`dependencies-optional.txt` holds the rest; each entry says which feature it turns
on. Nothing in there is required.

**2 — build eww**

eww is not packaged. It has to be built with the Wayland feature (the default build
is X11 and will not produce a bar here). The exact revision this config runs:

```bash
cargo install --git https://github.com/elkowar/eww \
  --rev 2c6523a372c688d141373bd9b7ac26d84b458eda \
  --no-default-features --features=wayland --locked eww
```

Then put it behind the guard wrapper this repo ships:

```bash
mkdir -p ~/.local/lib/eww
mv ~/.cargo/bin/eww ~/.local/lib/eww/eww
ln -sf ~/.scripts/eww ~/.cargo/bin/eww
```

Why the shuffle: eww 0.6's **client** silently forks a second daemon whenever the
running one is slow to answer, and the fork steals the IPC socket — popups then get
stuck open forever with no way to close them. The wrapper injects `--no-daemonize`
into every call, which turns that fork into a clean error. Keep the real binary
*named* `eww` so `pkill -x eww` still finds it. Full story: `man eww-guard`.
Re-running `cargo install` overwrites the symlink and disables the guard — redo the
three lines above after every upgrade.

**3 — copy the dotfiles in**

```bash
cp -rT .config       ~/.config
cp -rT .local        ~/.local
cp -rT .scripts      ~/.scripts
```

Back up anything you care about first — this overwrites same-named files.

**4 — first run**

```bash
./tools/first-run.sh                  # or: ./tools/first-run.sh tokyo-night
```

It expands `__HOME__` in the three config formats that cannot use `$HOME`, makes the
scripts executable, bootstraps the theme, and enables the systemd user units. Safe
to re-run. Skipping it gets you a desktop with **no colors at all** — around twenty
eww stylesheets, waybar's `style.css` and rofi's `config.rasi` all `@import` files
that the theming system *generates*.

Then log out and pick the Sway session.

---

## Keys

`$mod` is **Super**. Inside sway, `$mod+slash` opens the full cheatsheet overlay and
`$mod+question` opens a searchable command finder.

### Windows

| Key | |
|---|---|
| `$mod+Return` | terminal (in the focused window's cwd, with `swaycwd`) |
| `$mod+Shift+q` | close window |
| `$mod+Ctrl+Shift+q` | close every window of the app |
| `$mod+←↓↑→` | move focus |
| `$mod+Shift+←↓↑→` | move window |
| `$mod+b` / `$mod+v` | split horizontal / vertical |
| `$mod+s` / `$mod+w` / `$mod+e` | stacking / tabbed / tiling |
| `$mod+f` / `$mod+Shift+f` | fullscreen / global fullscreen |
| `$mod+Shift+space` | toggle floating |
| `$mod+space` | jump between tiling and floating |
| `$mod+a` | focus parent |
| `$mod+p` | window switcher (MRU) |
| `Alt+Tab` | last used window |

### Workspaces

| Key | |
|---|---|
| `$mod+1..9` | switch |
| `$mod+Shift+1..9` | move window there |
| `$mod+Tab` | last used workspace |
| `$mod+n` | first empty workspace |
| `$mod+Shift+n` / `$mod+Shift+m` | move window to a new one / move and follow |
| `$mod+Alt+←→` | move the whole workspace to another output |

### Modes

| Key | Mode |
|---|---|
| `$mod+r` | resize |
| `$mod+Ctrl+w` | swap two windows keeping size and layout |
| `Print` | screenshot (two capture modes, toggled from the bar) |
| `$mod+Shift+r` | screen recording — mute, mic, or system audio |
| `$mod+Shift+e` | power menu |

### Tools

| Key | |
|---|---|
| `$mod+d` / `$mod+Shift+d` | launcher / launcher in a new workspace |
| `$mod+Shift+p` | clipboard history |
| `$mod+period` | emoji picker |
| `$mod+i` | paste an image path, see the image |
| `$mod+t` | theme picker |
| `$mod+slash` | cheatsheet |
| `$mod+Shift+b` | toggle the bar |
| `$mod+Shift+c` | reload sway |
| `Ctrl+Alt+Delete` | task manager |

Two bindings expect apps that are not part of any of this: `$mod+m` opens `nchat`
(a WhatsApp TUI that lives in the scratchpad) and `Ctrl+$mod+space` opens Claude
Desktop. Without those installed the keys are no-ops — install them or drop the
lines from `.config/sway/modes/default`.

---

## Theming

`$mod+t` swaps the palette across sway borders, foot, waybar, rofi, wofi, eww, GTK,
Qt and the cursor in one shot — it is a symlink swap against a pre-generated cache,
so it is instant. Twelve palettes ship (catppuccin ×4, dracula, gruvbox, tokyo-night,
nordic, matcha ×5).

Adding your own: drop a directory under `.config/sway/themes/<name>/` with a
`theme.conf` and a `foot-theme.ini`, then run `theme-cache-regen.sh <name>`.
Full documentation: `man palette-theming`.

---

## Documentation

Around twenty man pages ship with the config and install to `~/.local/share/man`.
After copying, run `mandb ~/.local/share/man` once, then:

```
man screenshots · man recording · man swap · man resize · man scratchpad
man palette-theming · man clipboard-functionality · man emoji-picker
man cheatsheet · man notes · man lock-screen · man idle-inhibitor
man usb-management · man window-title · man screensharing · man eww-guard
man gamma-correction · man do-not-disturb · man lid-handling · man peek
```

---

## What is deliberately not here

This was carved out of a personal dotfiles repo. Removed on the way out:

- **the git history** — this repo starts at commit one; nothing from the original
  bare repo travels with it
- **three eww widgets** tied to a specific VPS (remote disk usage, SSH tunnel
  toggle, remote tmux sessions) and the host config they read
- **two keybindings** that called scripts belonging to a business workflow
  (`$mod+Shift+v`, `$mod+o` — both free again)
- **shell, editor, browser and file-manager configs**, MIME defaults, and every
  service unrelated to the desktop session

Also absent by nature: monitor layout and input tuning. `.config/sway/inputs/`
holds generic `type:keyboard` / `type:touchpad` blocks, and there are no `output`
lines at all — configure your own displays in `.config/sway/definitions.d/`, which
is where local overrides belong and is read before everything else.

---

## Checking it

```bash
python3 tools/check.py
```

Parses every shell and python script, fails on any absolute `/home/<user>/` path or
leftover identifier from the source machine, and verifies that every `~/…` path any
config names is actually shipped. Run it after changing anything. Two runs on an
unchanged tree must print the same thing — if they disagree, distrust the checker
before the tree.

---

## Not on Arch?

The configs are distro-agnostic; the package names are not. `swayfx` is the only
hard one — most distros do not carry it, so it means building from source
(https://github.com/wlrfx/swayfx). If you would rather stay on vanilla sway, delete
the four SwayFX directives (`corner_radius` ×2, `layer_effects`,
`animation_duration_ms`) from `.config/sway/config.d/` and you lose the rounded
corners and animations but nothing else.
