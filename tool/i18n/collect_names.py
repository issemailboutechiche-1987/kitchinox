"""Noms et descriptions des catalogues (JSON) et des listes Dart (finitions, sanitaires, palettes, modèles)."""
import glob, io, json, os, re, sys

R = 'D:/kitchinox/kitchen_planner/'
out = set()


def walk(o):
    if isinstance(o, dict):
        for k, v in o.items():
            if k in ('name', 'label', 'title', 'description', 'note') and isinstance(v, str) and re.search(r'[A-Za-zÀ-ÿ]', v):
                out.add(v)
            walk(v)
    elif isinstance(o, list):
        for v in o:
            walk(v)


for f in glob.glob(R + 'assets/**/*.json', recursive=True):
    walk(json.load(io.open(f, encoding='utf-8')))

LIT = r"'((?:[^'\\]|\\.)*)'"
dart = {
    'lib/ui/finishes.dart': [r"Finish\(\s*" + LIT + r"\s*,\s*" + LIT],
    'lib/engine/room_objects.dart': [r"FixtureType\(\s*" + LIT + r"\s*,\s*" + LIT, r"FixtureType\([^\n]*?\],\s*\d+,\s*\d+,\s*\d+,\s*\[[^\]]*\],\s*\n?\s*" + LIT],
    'lib/engine/universe_templates.dart': [r"Palette\(\s*" + LIT, r"UniverseTemplate\(\s*" + LIT + r"\s*,\s*" + LIT + r"\s*,\s*" + LIT + r"\s*,\s*" + LIT],
    'lib/engine/proposals.dart': [r"\(\s*'[a-z_]+[^']*'\s*,\s*'[^']*'\s*,\s*[^,]+,\s*(?:true|false)\s*,\s*'[^']*'\s*,\s*" + LIT + r"\)"],
}
for f, pats in dart.items():
    s = io.open(R + f, encoding='utf-8').read()
    for p in pats:
        for m in re.finditer(p, s):
            for g in m.groups():
                if g and re.search(r'[A-Za-zÀ-ÿ]', g) and (' ' in g or g[0].isupper()) and not re.match(r'^[a-z_0-9]+$', g):
                    out.add(g.replace("\\'", "'"))
# noms des murs
s = io.open(R + 'lib/engine/project.dart', encoding='utf-8').read()
m = re.search(r"static const wallNames = \{(.*?)\};", s, re.S)
for v in re.findall(r":\s*" + LIT, m.group(1)):
    out.add(v)
json.dump(sorted(out), io.open(sys.argv[1], 'w', encoding='utf-8'), ensure_ascii=False, indent=0)
print(len(out))
