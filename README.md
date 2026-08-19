# swayfx-desktop

A complete SwayFX desktop — compositor config, keybindings, binding modes, waybar
exactly as it is configured on the source machine, rofi, screenshots, screen
recording, clipboard manager, emoji picker, and a live palette-theming system that
recolors everything at once.

eww ships as **plumbing, not as a widget collection**: only the three widgets that
sway and waybar actually call survive — the `$mod+slash` cheatsheet, the screenshot
capture-mode indicator, and the wifi popup that waybar's network module opens. The
personal desktop widgets (floating clock, notes, timers, gauges, USB and bluetooth
panels, disk meter) were left behind. The framework is wired up and working, so
build your own.

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
to re-run. Skipping it gets you a desktop with **no colors at all**: sway's own
config `include`s a `theme.conf` that defines every colour and font variable the
rest of it uses, and waybar's `style.css`, rofi's `config.rasi`, foot's theme and two
eww stylesheets each `@import` a file by name. The theming system *generates* all of
them; none is in the repo.

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
so it is instant. Twelve palettes ship: catppuccin ×4 (frappe, latte, macchiato,
mocha), matcha ×4 (blue, green, leaf, red), dracula, gruvbox-dark, nordic-bluish-accent
and tokyo-night. Each carries a `theme.conf` and a `foot-theme.ini`.

`theme.conf` stores colours indirectly — `$accent-color` points at `$cyan`, which
points at a hex value — so opening the file does not hand you the palette. Resolve
them with `python3 tools/palettes.py` (add `--md` for markdown, or a theme name for
every variable of that one). The table below is that script's output:

| theme | bg | text | accent | selection | mode |
|---|---|---|---|---|---|
| catppuccin-frappe | `#303446` | `#c6d0f5` | `#00ecec` | `#51576d` | prefer-dark |
| catppuccin-latte | `#eff1f5` | `#4c4f69` | `#1e66f5` | `#bcc0cc` | prefer-light |
| catppuccin-macchiato | `#24273a` | `#cad3f5` | `#f5a97f` | `#494d64` | prefer-dark |
| catppuccin-mocha | `#1e1e2e` | `#cdd6f4` | `#94e2d5` | `#45475a` | prefer-dark |
| dracula | `#141a1b` | `#f8f8f2` | `#bd93f9` | `#282a2b` | prefer-dark |
| gruvbox-dark | `#1d2021` | `#ebdbb2` | `#fabd2f` | `#3c3836` | prefer-dark |
| matcha-blue | `#14161b` | `#eeeeee` | `#3498db` | `#282a2b` | prefer-dark |
| matcha-green | `#141a1b` | `#eeeeee` | `#16a085` | `#282a2b` | prefer-dark |
| matcha-leaf | `#141a1b` | `#eeeeee` | `#88ad62` | `#282a2b` | prefer-dark |
| matcha-red | `#222222` | `#eeeeee` | `#e44138` | `#282a2b` | prefer-dark |
| nordic-bluish-accent | `#2E3440` | `#E5E9F0` | `#81A1C1` | `#3B4252` | prefer-dark |
| tokyo-night | `#1a1b26` | `#c0caf5` | `#7aa2f7` | `#292e42` | prefer-dark |

**The palettes are complete; the GTK/Qt/cursor themes they point at are not in this
repo.** Every `theme.conf` names a GTK theme, an icon theme, a cursor theme and a
Kvantum theme, and those are separate packages. What the repo generates — sway
borders, foot, waybar, rofi, wofi, eww — recolors regardless; the GTK, Qt and cursor
side silently falls back to defaults until those packages are installed. Each theme
directory has a `packages` file naming them (Arch/AUR names; on other distros expect
to hunt). Between them the twelve want:

- `papirus-icon-theme` — the icon theme for 8 of the 12
- the catppuccin GTK, cursor and Kvantum themes — 4 palettes
- Dracula, Gruvbox, Nordic/Nordzy, Tokyonight, Matcha/Matchama GTK sets — one each
- `breeze-cursor-theme` for the four matcha palettes. It comes from KDE, so if you
  are stripping a KDE install off this machine, keep that one package.

Adding your own: drop a directory under `.config/sway/themes/<name>/` with a
`theme.conf` and a `foot-theme.ini`, then run `theme-cache-regen.sh <name>`.
Full documentation: `man palette-theming`.

---

## Documentation

21 man pages ship with the config and install to `~/.local/share/man`.
After copying, run `mandb ~/.local/share/man` once, then:

```
man screenshots · man recording · man swap · man resize · man scratchpad
man shutdown · man lock-screen · man idle-inhibitor · man lid-handling
man clipboard-functionality · man clipardo · man emoji-picker · man peek
man palette-theming · man gamma-correction · man do-not-disturb
man cheatsheet · man usb-management · man window-title
man screensharing · man eww-guard
```

---

## What is deliberately not here

This was carved out of a personal dotfiles repo. Removed on the way out:

- **the git history** — this repo starts at commit one; nothing from the original
  bare repo travels with it
- **26 of the 32 eww features** — the whole personal widget collection (clock,
  battery, notes, timer, sysmonitor and CPU gauges, temps, disk meter, USB and
  bluetooth panels, wallpaper cycler, activate-linux) plus the legacy scripts left
  over from before the bar moved to waybar, plus three widgets tied to a specific
  VPS (remote disk usage, SSH tunnel toggle, remote tmux sessions) and the host
  config they read. `man notes` went with them
- **two keybindings** that called scripts belonging to a business workflow
  (`$mod+Shift+v`, `$mod+o` — both free again)
- **shell, editor, browser and file-manager configs**, MIME defaults, and every
  service unrelated to the desktop session
- **the Arch logo** — waybar's leftmost button (`custom/menu`, opens the launcher)
  used the Arch glyph `U+F303`; it is a distro-neutral menu glyph now

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
