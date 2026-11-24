#!/usr/bin/env python3
"""Maakt windows/Cyberpad/app.ico van de PNG's uit make-app-icon.swift (zelfde eendenicoon als op de Mac).
Gebruik: swift macos/scripts/make-app-icon.swift <map> && python3 macos/scripts/make-windows-ico.py <map>/AppIcon.iconset windows/Cyberpad/app.ico
"""
import struct, sys, os
src, out = sys.argv[1], sys.argv[2]
# 48 px bestaat niet als los bestand; Windows schaalt de 64 px-versie netjes. Dubbele vermijden:
files = [(16, 'icon_16x16.png'), (32, 'icon_32x32.png'), (64, 'icon_32x32@2x.png'), (128, 'icon_128x128.png'), (256, 'icon_256x256.png')]
blobs = [(s, open(os.path.join(src, f), 'rb').read()) for s, f in files]
head = struct.pack('<HHH', 0, 1, len(blobs))
offset = 6 + 16 * len(blobs)
entries, data = b'', b''
for s, b in blobs:
    entries += struct.pack('<BBBBHHII', s % 256, s % 256, 0, 0, 1, 32, len(b), offset + len(data))
    data += b
open(out, 'wb').write(head + entries + data)
print('ico klaar:', out, len(blobs), 'formaten')
