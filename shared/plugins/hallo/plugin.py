#!/usr/bin/env python3
"""Voorbeeldplugin voor Cyberpad (macOS en Windows).

Protocol: één JSON-bericht per regel via stdin/stdout. Zie docs/PLUGINS.md.
Alleen de standaardbibliotheek van Python, zodat er niets geïnstalleerd hoeft te worden.
"""
import json
import os
import sys

DATA = os.path.join(os.environ.get("CYBERPAD_DATA_DIR", "."), "teller.json")


def send(msg):
    sys.stdout.write(json.dumps(msg, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def load():
    try:
        with open(DATA, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save(state):
    with open(DATA, "w", encoding="utf-8") as f:
        json.dump(state, f)


def teller(tile, params):
    n = load().get(tile, 0)
    return {
        "icon": "🔢",
        "value": n,
        "sub": "stap " + str(params.get("stap", 1)),
        "buttons": [{"id": "plus", "label": "+" + str(params.get("stap", 1))}, {"id": "reset", "label": "0"}],
        "active": n >= 10,
    }


for line in sys.stdin:
    try:
        msg = json.loads(line)
    except ValueError:
        continue
    kind, mid = msg.get("type"), msg.get("id")
    params = msg.get("params") or {}

    if kind == "hello":
        send({"type": "log", "text": "hallo-plugin gestart op " + msg.get("platform", "?")})

    elif kind == "invoke" and msg.get("action") == "groet":
        send({"type": "toast", "text": "Hallo, " + str(params.get("naam", "wereld")) + "!"})
        send({"type": "result", "id": mid, "ok": True})

    elif kind == "widget" and msg.get("widget") == "teller":
        send({"type": "result", "id": mid, "ok": True, "data": teller(msg["tile"], params)})

    elif kind == "widgetAction" and msg.get("widget") == "teller":
        state, tile = load(), msg["tile"]
        if msg.get("action") == "plus":
            state[tile] = state.get(tile, 0) + int(params.get("stap", 1))
        elif msg.get("action") == "reset":
            state[tile] = 0
        else:
            send({"type": "result", "id": mid, "ok": False, "error": "onbekende knop"})
            continue
        save(state)
        send({"type": "result", "id": mid, "ok": True, "data": teller(tile, params)})

    elif mid is not None:
        send({"type": "result", "id": mid, "ok": False, "error": "onbekend bericht: " + str(kind)})
