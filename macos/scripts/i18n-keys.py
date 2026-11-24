#!/usr/bin/env python3
"""Verzamelt alle te vertalen teksten (Nederlands = sleutel) en controleert shared/i18n/<taal>.json.

Gebruik: python3 macos/scripts/i18n-keys.py            → overzicht van ontbrekende en overbodige sleutels
         python3 macos/scripts/i18n-keys.py --list     → alle sleutels (JSON-lijst)
"""
import json, re, sys, glob, os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
def rd(p): return open(os.path.join(ROOT, p), encoding='utf-8').read()

def js_calls(src):
    out = []
    for m in re.finditer(r"\bT\('((?:[^'\\]|\\.)*)'", src):
        out.append(m.group(1).replace("\\'", "'").replace('\\n', '\n').replace('\\"', '"'))
    return out

def swift_calls(src):
    out = []
    for m in re.finditer(r'\bL\("((?:[^"\\]|\\.)*)"', src):
        out.append(m.group(1).replace('\\n', '\n').replace('\\"', '"'))
    return out

def html_marks(src):
    out = []
    for m in re.finditer(r'<(\w+)[^>]*\bdata-t(?![-\w])[^>]*>([^<]*)<', src):
        if m.group(2).strip(): out.append(m.group(2).strip())
    for m in re.finditer(r'<\w+[^>]*\btitle="([^"]*)"[^>]*\bdata-t-title\b', src):
        out.append(m.group(1))
    return out

keys = []
for p in ['shared/pad/pad.js', 'shared/editor/editor.js']:
    keys += js_calls(rd(p))
for p in ['shared/pad/index.html', 'shared/editor/index.html']:
    keys += html_marks(rd(p))
for p in glob.glob(os.path.join(ROOT, 'macos/Sources/Cyberpad/**/*.swift'), recursive=True):
    keys += swift_calls(open(p, encoding='utf-8').read())
# Windows (C#): zelfde L("…")-aanroepen.
for p in glob.glob(os.path.join(ROOT, 'windows/Cyberpad/**/*.cs'), recursive=True):
    keys += swift_calls(open(p, encoding='utf-8').read())
# Dynamische teksten: schema, sneltoetsen, thema's, groepen in de editor, knoppen van de terminal.
schema = json.loads(rd('shared/editor/schema.json'))
def walk(o):
    if isinstance(o, dict):
        for k, v in o.items():
            if k in ('name', 'label', 'placeholder', 'group') and isinstance(v, str): keys.append(v)
            else: walk(v)
    elif isinstance(o, list):
        for v in o: walk(v)
walk({k: v for k, v in schema.items() if k != 'fieldTypes'})
for app in json.loads(rd('shared/catalog/shortcuts.json'))['apps']:
    for sc in app.get('shortcuts', []): keys.append(sc['label'])
for p in sorted(glob.glob(os.path.join(ROOT, 'shared/themes/*.json'))):
    t = json.load(open(p, encoding='utf-8'))
    keys += [t['name'], t.get('description', '')]
ed = rd('shared/editor/editor.js')
m = re.search(r'PALETTE_GROUPS = \[([^\]]*)\]', ed)
keys += re.findall(r"'([^']+)'", m.group(1)) + ['Basis']
keys += ['START', 'STOP']

seen, uniq = set(), []
for k in keys:
    if k and k not in seen and re.search(r'[A-Za-zÀ-ÿ]', k):
        seen.add(k); uniq.append(k)

if '--list' in sys.argv:
    print(json.dumps(uniq, ensure_ascii=False, indent=1)); sys.exit()

bad = False
for lang in ('en', 'es'):
    path = os.path.join(ROOT, 'shared/i18n', lang + '.json')
    d = json.load(open(path, encoding='utf-8')) if os.path.exists(path) else {}
    missing = [k for k in uniq if k not in d]
    extra = [k for k in d if not k.startswith('_') and k not in seen]
    ph = [k for k in uniq if k in d and sorted(re.findall(r'\{\d\}', k)) != sorted(re.findall(r'\{\d\}', d[k]))]
    print(f'{lang}: {len(uniq)} sleutels, {len(missing)} ontbreken, {len(extra)} overbodig, {len(ph)} met verkeerde {{0}}')
    for k in missing[:40]: print('  ontbreekt:', repr(k))
    for k in extra[:40]: print('  overbodig:', repr(k))
    for k in ph: print('  plaatshouder:', repr(k))
    bad = bad or missing or ph
sys.exit(1 if bad else 0)
