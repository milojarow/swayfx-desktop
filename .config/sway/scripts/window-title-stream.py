#!/usr/bin/env python3
# feature: window-title
# role:    subscribe  (Method 3 — native-speed IPC stream + custom-name override)
"""
window-title-stream.py — fast window-title source for waybar (custom/window-title).

Replaces the old window-title.sh daemon. Talks to sway IPC over a persistent UNIX
socket (same engine as workspaces-subscribe.py): no swaymsg/jq subprocess per
event, no pstree/proc CWD inspection, no cache file, no signal-to-waybar round
trip. It emits the focused window's title as a JSON stream straight to waybar's
stdin (custom/window-title in stream mode).

Custom names: if NAMES_DIR/<window-id>.name exists, its text overrides the title.
window-title-rename.py writes/clears that file and sends SIGUSR1 to this process,
which re-emits the current focused window with the new label applied.
"""
import html
import json
import os
import signal
import socket
import struct
import sys

SWAYSOCK = os.environ.get("SWAYSOCK", "")
NAMES_DIR = "/tmp/waybar-window-names-{}".format(os.environ.get("USER", ""))
MAX_LEN = 70

_MAGIC = b"i3-ipc"
_MSG_GET_TREE = 4
_MSG_SUBSCRIBE = 2
_EVT_WINDOW = 0x80000003
_EVT_WORKSPACE = 0x80000000


# ── sway IPC over a persistent socket (no swaymsg/jq per event) ────────────────
def _connect():
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(SWAYSOCK)
    return s


def _recv(sock, n):
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise OSError("sway IPC socket closed")
        buf += chunk
    return buf


def _send(sock, mtype, payload=b""):
    sock.sendall(_MAGIC + struct.pack("=II", len(payload), mtype) + payload)


def _read(sock):
    hdr = _recv(sock, 14)
    length, mtype = struct.unpack("=II", hdr[6:14])
    return mtype, _recv(sock, length)


_query = None


def get_tree():
    """Query get_tree over a persistent socket; reconnect once if it died."""
    global _query
    for attempt in range(2):
        try:
            if _query is None:
                _query = _connect()
            _send(_query, _MSG_GET_TREE)
            _, data = _read(_query)
            return json.loads(data)
        except OSError:
            if _query is not None:
                try:
                    _query.close()
                except OSError:
                    pass
            _query = None
            if attempt == 1:
                raise
    return None


# ── helpers ────────────────────────────────────────────────────────────────────
def find_focused(node):
    if node.get("focused") and node.get("pid"):
        return node
    for c in node.get("nodes", []) + node.get("floating_nodes", []):
        r = find_focused(c)
        if r:
            return r
    return None


def app_of(node):
    return node.get("app_id") or (node.get("window_properties") or {}).get("class") or ""


def override_for(wid):
    try:
        with open(os.path.join(NAMES_DIR, "{}.name".format(wid))) as f:
            return f.read().strip()
    except OSError:
        return None


def css_class(app, has_override):
    al = app.lower()
    cls = "window-title"
    if any(t in al for t in ("foot", "term", "alacritty", "kitty", "ghostty")):
        cls += " terminal"
    elif any(t in al for t in ("firefox", "chrom", "brave", "librewolf")):
        cls += " browser"
    elif any(t in al for t in ("code", "vim", "helix", "kak")):
        cls += " editor"
    if has_override:
        cls += " custom-named"
    return cls


# ── emit ─────────────────────────────────────────────────────────────────────--
def emit(node):
    if not node:
        print(json.dumps({"text": "", "tooltip": "No focused window", "class": "empty"}),
              flush=True)
        return
    wid = node.get("id")
    name = node.get("name") or ""
    ov = override_for(wid)
    text = ov if ov is not None else name
    if len(text) > MAX_LEN:
        text = text[:MAX_LEN - 1] + "…"
    app = app_of(node)
    tooltip = "{}\n{}".format(app, name) if app else name
    print(json.dumps({
        "text": html.escape(text),
        "tooltip": html.escape(tooltip),
        "class": css_class(app, ov is not None),
    }, ensure_ascii=False), flush=True)


def emit_focused():
    tree = get_tree()
    emit(find_focused(tree) if tree else None)


# ── main ─────────────────────────────────────────────────────────────────────--
def main():
    if not SWAYSOCK:
        print(json.dumps({"text": "", "class": "empty"}), flush=True)
        sys.exit(1)

    # SIGUSR1 → re-emit current focused window (sent by the rename helper).
    signal.signal(signal.SIGUSR1, lambda *_: emit_focused())

    emit_focused()  # initial state

    sub = _connect()
    _send(sub, _MSG_SUBSCRIBE, b'["window","workspace"]')
    _read(sub)  # consume {"success": true}

    while True:
        try:
            mtype, raw = _read(sub)
        except OSError:
            try:
                sub.close()
            except OSError:
                pass
            sub = _connect()
            _send(sub, _MSG_SUBSCRIBE, b'["window","workspace"]')
            _read(sub)
            continue

        try:
            ev = json.loads(raw)
        except json.JSONDecodeError:
            continue

        change = ev.get("change", "")

        if mtype == _EVT_WINDOW:
            cont = ev.get("container", {}) or {}
            if change == "focus":
                # The event carries the new focused window — emit it directly,
                # no get_tree needed. This is the hot path on workspace switch.
                emit(cont if cont.get("pid") else None)
            elif change == "title" and cont.get("focused"):
                emit(cont)
            elif change == "close":
                cid = cont.get("id")
                if cid is not None:
                    try:
                        os.remove(os.path.join(NAMES_DIR, "{}.name".format(cid)))
                    except OSError:
                        pass
                if cont.get("focused"):
                    emit_focused()
        elif mtype == _EVT_WORKSPACE:
            # Covers switching to an EMPTY workspace (no window-focus event fires).
            if change == "focus":
                emit_focused()


if __name__ == "__main__":
    main()
