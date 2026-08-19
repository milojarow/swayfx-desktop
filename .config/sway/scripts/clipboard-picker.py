#!/usr/bin/env python3
# ── Clipboard Functionality ──────────────────────────────────────────────────
# Role:     GTK3 clipboard history picker over cliphist. Replaces the old rofi
#           picker (rofi can't do a per-row clickable pin nor fluid multi-select).
#             · click / shift+click / ctrl+click / shift+arrows  select (multi)
#             · Enter / double-click                             copy + close
#             · Delete                                           delete selected
#             · click the pin glyph on a row                     pin / unpin it
#             · type                                             live filter
#             · Escape                                           close
# Pins:     Live in PIN_DIR (content file "<hash>" + sidecar "<hash>.pv" preview),
#           OUTSIDE the cliphist DB, so they survive the bars' middle-click
#           `rm -f ~/.cache/cliphist/db`, `cliphist wipe`, and logout purge.
#           Pinned entries render in a "Fijados" section on top; history below.
# Window:   gtk-layer-shell OVERLAY, centered — so it needs no sway for_window rule.
# Backend:  cliphist list/decode/delete · wl-copy · waybar-signal · sha256sum(py)
# Launcher: clipboard-manager.sh execs this; bars/keybinds are unchanged.
# ─────────────────────────────────────────────────────────────────────────────

import hashlib
import subprocess
from pathlib import Path

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gtk, Gdk, GtkLayerShell, Pango  # noqa: E402

PIN_DIR = Path.home() / ".local/share/clipboard-pins"
# U+EB2B Nerd Font pin, written as a Python escape — the file stays pure ASCII,
# never the literal PUA glyph (which text tooling silently drops).
PIN_GLYPH = "\ueb2b"  # U+EB2B Nerd Font pin (ASCII escape, never literal PUA)
APP_ID = "com.milo.clipboard-picker"

CSS = b"""
window { background-color: transparent; }
.root {
    background-color: #2C1C0D;
    border: 3px solid #CD7F32;
    border-radius: 10px;
    padding: 12px;
}
entry {
    background-color: #4A3520;
    color: #F0E4D4;
    border: 0;
    border-radius: 6px;
    padding: 8px;
    margin-bottom: 8px;
}
list { background-color: transparent; }
row {
    color: #F0E4D4;
    padding: 2px;
    border-radius: 5px;
}
row:selected { background-color: #CD7F32; color: #2C1C0D; }
.section-header {
    color: #CD7F32;
    font-weight: bold;
    padding: 6px 4px 2px 4px;
}
.pin-btn {
    background: none;
    border: 0;
    box-shadow: none;
    color: #7D5A3C;
    font-family: "JetBrainsMono Nerd Font", "Symbols Nerd Font", monospace;
    font-size: 16px;
    padding: 0 6px;
    min-height: 0;
    min-width: 0;
}
.pin-btn:hover { color: #D4AF37; }
.pin-btn.active { color: #D4AF37; }
.entry-label { padding: 6px 4px; }
"""


# ── cliphist backend ─────────────────────────────────────────────────────────
def cliphist_list():
    """Yield (id, preview, raw_line) for each history entry ("<id>\\t<preview>")."""
    out = subprocess.run(["cliphist", "list"], capture_output=True, text=True).stdout
    items = []
    for line in out.splitlines():
        if not line:
            continue
        cid, _, preview = line.partition("\t")
        items.append((cid, preview or cid, line))
    return items


def cliphist_decode(raw_line):
    """Decode a history line back to its raw bytes (cliphist parses the leading id)."""
    return subprocess.run(
        ["cliphist", "decode"], input=(raw_line + "\n").encode(), capture_output=True
    ).stdout


def cliphist_delete(raw_line):
    subprocess.run(["cliphist", "delete"], input=(raw_line + "\n").encode())


def waybar_refresh():
    subprocess.run(["waybar-signal", "clipboard"], stderr=subprocess.DEVNULL)


# ── pin store ────────────────────────────────────────────────────────────────
def pv_path(content_file):
    """Sidecar preview path for a pin content file: '<hash>' -> '<hash>.pv'."""
    return Path(str(content_file) + ".pv")


def list_pin_files():
    """Pin content files (excluding .pv sidecars), newest first."""
    if not PIN_DIR.exists():
        return []
    files = [p for p in PIN_DIR.iterdir() if p.is_file() and p.suffix != ".pv"]
    files.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    return files


def pinned_previews():
    """Set of previews currently pinned — used to dedupe history against pins."""
    out = set()
    for pf in list_pin_files():
        pv = pv_path(pf)
        if pv.exists():
            out.add(pv.read_text())
    return out


def add_pin(raw_line, preview):
    PIN_DIR.mkdir(parents=True, exist_ok=True)
    content = cliphist_decode(raw_line)
    h = hashlib.sha256(content).hexdigest()[:16]  # dedupe: same content -> same file
    (PIN_DIR / h).write_bytes(content)
    pv_path(PIN_DIR / h).write_text(preview)


def remove_pin(content_file):
    content_file.unlink(missing_ok=True)
    pv_path(content_file).unlink(missing_ok=True)


# ── UI ───────────────────────────────────────────────────────────────────────
class Picker(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID)
        self.win = None
        self.listbox = None
        self.search = None

    def do_activate(self):
        # Single instance: a second invocation toggles the picker off.
        if self.win is not None:
            self.win.destroy()
            self.win = None
            return
        self._build()

    def _build(self):
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        win = Gtk.Window()
        self.add_window(win)
        self.win = win
        win.set_size_request(720, 520)
        win.set_decorated(False)
        rgba = Gdk.Screen.get_default().get_rgba_visual()
        if rgba:
            win.set_visual(rgba)

        GtkLayerShell.init_for_window(win)
        GtkLayerShell.set_layer(win, GtkLayerShell.Layer.OVERLAY)
        # EXCLUSIVE so the picker grabs keyboard focus the instant it maps —
        # no extra click needed after opening from the bar. Sway still handles
        # its own keybindings first, so global shortcuts keep working.
        GtkLayerShell.set_keyboard_mode(win, GtkLayerShell.KeyboardMode.EXCLUSIVE)
        win.connect("key-press-event", self._on_key)
        win.connect("destroy", lambda *_: self._on_destroy())

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        root.get_style_context().add_class("root")
        win.add(root)

        self.search = Gtk.SearchEntry()
        self.search.set_placeholder_text("Buscar…")
        self.search.connect("search-changed", self._on_search_changed)
        # Down from the search box moves focus into the list.
        self.search.connect("key-press-event", self._search_key)
        # Enter inside the search box copies the first visible match — no need
        # to step into the list with Down first.
        self.search.connect("activate", self._on_search_activate)
        root.pack_start(self.search, False, False, 0)

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        root.pack_start(scroll, True, True, 0)

        self.listbox = Gtk.ListBox()
        self.listbox.set_selection_mode(Gtk.SelectionMode.MULTIPLE)
        self.listbox.set_activate_on_single_click(False)  # single click selects; dbl/Enter copies
        self.listbox.set_filter_func(self._filter)
        self.listbox.set_header_func(self._header)
        self.listbox.connect("row-activated", self._on_activate)
        scroll.add(self.listbox)

        # Focus the latest non-pinned row by default so arrow-nav works
        # immediately and pins don't grab attention. Printable keys forward to
        # the search entry via _on_key (type-to-search).
        self._populate(initial=True)
        win.show_all()

    # ── data → rows ──────────────────────────────────────────────────────────
    def _populate(self, initial=False, focus_index=None):
        for child in self.listbox.get_children():
            self.listbox.remove(child)

        for pf in list_pin_files():
            pv = pv_path(pf)
            preview = pv.read_text() if pv.exists() else pf.name
            self.listbox.add(self._make_row("pinned", pf, preview, True))

        skip = pinned_previews()
        for _cid, preview, raw in cliphist_list():
            if preview in skip:
                continue  # already shown in Fijados
            self.listbox.add(self._make_row("history", raw, preview, False))

        self.listbox.show_all()
        rows = self.listbox.get_children()
        if not rows:
            return
        # First open: land on the latest copied item (first row of "Historial",
        # since cliphist lists newest-first). Falls back to the first row if
        # there's no history (pins-only). Re-populates after pin/delete keep
        # the simpler "first row" behavior.
        if focus_index is not None:
            # After a delete: land on whatever row now occupies the slot the
            # user was working on (or the new last row if we cut the tail),
            # so the cursor never jumps back to the top. SELECTED, not just
            # focused — the CSS only paints row:selected, so a focus-only
            # cursor is invisible ("the selector vanished") and the next Del
            # is a dead key (_delete_selected returns early on an empty
            # selection). Safe for the same reason the initial path is: the
            # search paths unselect_all before re-selecting. Index over the
            # rows the filter actually SHOWS: a selection parked on a hidden
            # row is invisible again, and worse, it would feed the next Enter
            # content the user can't see.
            visible = [r for r in rows if self._filter(r)]
            if not visible:
                return
            target = visible[min(focus_index, len(visible) - 1)]
            self.listbox.select_row(target)
            target.grab_focus()
        elif initial:
            # Land on the latest non-pinned row, SELECTED, so Enter right after
            # opening copies the freshest item with zero keystrokes in between.
            # Selecting here used to leak into filtered Enters (the old
            # invisible-selection bug), but the search paths now unselect_all
            # before re-selecting (_on_search_changed / _search_key), so the
            # initial selection can no longer join a later batch unseen.
            target = next((r for r in rows if r.section == "history"), rows[0])
            self.listbox.select_row(target)
            target.grab_focus()
        else:
            self.listbox.select_row(rows[0])

    def _make_row(self, section, payload, preview, pinned):
        row = Gtk.ListBoxRow()
        row.section = section          # "pinned" | "history"
        row.payload = payload          # Path (pin) | raw cliphist line (history)
        row.preview = preview          # display + filter key

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        pin_btn = Gtk.Button(label=PIN_GLYPH)
        pin_btn.set_relief(Gtk.ReliefStyle.NONE)
        pin_btn.set_can_focus(False)
        ctx = pin_btn.get_style_context()
        ctx.add_class("pin-btn")
        if pinned:
            ctx.add_class("active")
        pin_btn.set_tooltip_text("Quitar fijado" if pinned else "Fijar")
        pin_btn.connect("clicked", self._on_pin, row)
        box.pack_start(pin_btn, False, False, 0)

        lbl = Gtk.Label(label=preview, xalign=0)
        lbl.set_ellipsize(Pango.EllipsizeMode.END)
        lbl.get_style_context().add_class("entry-label")
        box.pack_start(lbl, True, True, 0)

        row.add(box)
        return row

    def _header(self, row, before):
        if before is None or before.section != row.section:
            text = "Fijados" if row.section == "pinned" else "Historial"
            lbl = Gtk.Label(label=text, xalign=0)
            lbl.get_style_context().add_class("section-header")
            lbl.show()
            row.set_header(lbl)
        else:
            row.set_header(None)

    def _filter(self, row):
        q = self.search.get_text().lower()
        return q in row.preview.lower() if q else True

    # ── actions ────────────────────────────────────────────────────────────--
    def _row_content(self, row):
        if row.section == "pinned":
            return Path(row.payload).read_bytes()
        return cliphist_decode(row.payload)

    def _on_activate(self, _listbox, row):
        # With several rows selected, copy them as one payload joined by
        # newlines — a single Ctrl+V then pastes the whole batch in order.
        rows = self.listbox.get_selected_rows() or [row]
        if len(rows) == 1:
            payload = self._row_content(rows[0])
        else:
            payload = b"\n".join(self._row_content(r) for r in rows)
        subprocess.run(["wl-copy"], input=payload)
        self.win.destroy()

    def _on_pin(self, _btn, row):
        if row.section == "pinned":
            remove_pin(Path(row.payload))
        else:
            add_pin(row.payload, row.preview)
        self._populate()

    def _delete_selected(self):
        rows = self.listbox.get_selected_rows()
        if not rows:
            return
        # Snapshot the topmost deleted row's index *within the filtered view*
        # so the cursor lands on the row that takes its slot on screen — with
        # a query active, counting hidden rows aims at the wrong slot.
        visible = [r for r in self.listbox.get_children() if self._filter(r)]
        positions = [visible.index(r) for r in rows if r in visible]
        target_index = min(positions) if positions else 0
        for row in rows:
            if row.section == "pinned":
                remove_pin(Path(row.payload))
            else:
                cliphist_delete(row.payload)
        waybar_refresh()
        self._populate(focus_index=target_index)

    def _on_key(self, _win, event):
        if event.keyval == Gdk.KEY_Escape:
            self.win.destroy()
            return True
        if event.keyval == Gdk.KEY_Delete:
            self._delete_selected()
            return True
        # Type-to-search: when the focus is not on the search entry, hand the
        # event to SearchEntry.handle_event — it focuses itself and starts
        # filtering on printable keys, and returns False on non-printable ones
        # (arrows, Enter, …) so they fall through to the listbox.
        if not self.search.has_focus() and self.search.handle_event(event):
            return True
        return False

    def _on_search_changed(self, _entry):
        # Re-apply the filter, then highlight the first visible match so the
        # user can SEE which row Enter would copy. Clear the prior selection
        # first to avoid the multi-select bleed across query changes.
        self.listbox.unselect_all()
        self.listbox.invalidate_filter()
        if not self.search.get_text():
            return
        for r in self.listbox.get_children():
            if self._filter(r):
                self.listbox.select_row(r)
                return

    def _on_search_activate(self, _entry):
        # Enter inside the search entry: activate the first row that still
        # matches the current filter, so a query + Enter copies that match in
        # one go. Falls through silently if nothing matches.
        for r in self.listbox.get_children():
            if self._filter(r):
                self.listbox.emit("row-activated", r)
                return

    def _search_key(self, _entry, event):
        # Arrow-down out of the search box hands focus to the list.
        if event.keyval == Gdk.KEY_Down:
            rows = [r for r in self.listbox.get_children() if r.get_mapped()]
            if rows:
                # Drop any prior selection so jumping from the search box into
                # a filtered list always lands on a clean single row, never
                # bundled with whatever was previously highlighted.
                self.listbox.unselect_all()
                self.listbox.select_row(rows[0])
                rows[0].grab_focus()
            return True
        return False

    def _on_destroy(self):
        self.win = None
        waybar_refresh()


if __name__ == "__main__":
    Picker().run(None)
