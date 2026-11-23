#!/usr/bin/env python3
"""Voorbeeldplugin: is een server bereikbaar, en hoe snel? Werkt op macOS en Windows."""
import json
import socket
import sys
import time

history = {}


def send(msg):
    sys.stdout.write(json.dumps(msg, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def measure(tile, params):
    host, port = str(params.get("host", "1.1.1.1")), int(params.get("port", 443))
    start = time.monotonic()
    try:
        with socket.create_connection((host, port), timeout=3):
            ms = (time.monotonic() - start) * 1000
    except OSError as e:
        ms = None
        reason = e.strerror or str(e)
    h = history.setdefault(tile, [])
    h.append(ms)
    del h[:-20]
    ok = [x for x in h if x is not None]
    data = {"icon": "📡", "title": host, "sub": "poort " + str(port)}
    if ms is None:
        data.update({"value": "onbereikbaar", "active": False, "sub": reason[:80]})
    else:
        data.update({"value": str(round(ms)), "unit": "ms", "active": True})
    data["lines"] = [
        {"label": "GEM", "value": (str(round(sum(ok) / len(ok))) + " ms") if ok else "—"},
        {"label": "OK", "value": str(len(ok)) + " / " + str(len(h))},
    ]
    return data


for line in sys.stdin:
    try:
        msg = json.loads(line)
    except ValueError:
        continue
    if msg.get("type") == "widget":
        send({"type": "result", "id": msg["id"], "ok": True, "data": measure(msg["tile"], msg.get("params") or {})})
    elif msg.get("id") is not None:
        send({"type": "result", "id": msg["id"], "ok": False, "error": "niet ondersteund"})
