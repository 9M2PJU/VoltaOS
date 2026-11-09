#!/usr/bin/env python3
"""Fills the i18n/volta_<lang>.ts files with the translations from i18n/dict.txt.
Usage (from the project folder):  python3 scripts/apply_translations.py
dict.txt: one line per text, "English§Italian§Spanish§French§Portuguese" (\\n = newline).
A key like "Home|shortcut" matches the string with that disambiguation comment.
The source language of the interface is English."""
import os, xml.etree.ElementTree as ET
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(root)
LANGS = ['it', 'es', 'fr', 'pt']
tr = {l: {} for l in LANGS}
for line in open('i18n/dict.txt', encoding='utf-8'):
    line = line.rstrip('\n')
    if not line or line.startswith('#'): continue
    p = line.split('§')
    if len(p) != 5: print('malformed line:', line[:60]); continue
    key = p[0].replace('\\n', '\n')
    src, _, com = key.partition('|')
    for k, l in enumerate(LANGS): tr[l][(src, com)] = p[k + 1].replace('\\n', '\n')
for l in LANGS:
    path = f'i18n/volta_{l}.ts'
    tree = ET.parse(path)
    n = done = 0
    for m in tree.iter('message'):
        n += 1
        s = m.find('source').text
        c = m.find('comment')
        com = (c.text or '') if c is not None else ''
        t = m.find('translation')
        v = tr[l].get((s, com))
        if v:
            t.text = v
            if 'type' in t.attrib: del t.attrib['type']
            done += 1
        else:
            t.text = None
            t.set('type', 'unfinished')
    tree.write(path, encoding='utf-8', xml_declaration=True)
    txt = open(path, encoding='utf-8').read()
    if '<!DOCTYPE TS>' not in txt:
        i = txt.index('\n') + 1
        open(path, 'w', encoding='utf-8').write(txt[:i] + '<!DOCTYPE TS>\n' + txt[i:])
    print(l, done, '/', n)
