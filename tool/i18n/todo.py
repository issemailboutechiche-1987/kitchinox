"""Toutes les clés de traduction du code (tr, trf, trp, L) + noms des catalogues → celles qui n'ont pas de traduction."""
import io, json, os, re, sys

SP = sys.argv[1]
R = 'D:/kitchinox/kitchen_planner/'
LIT = re.compile(r"""\s*(?:'((?:[^'\\\n]|\\.)*)'|"((?:[^"\\\n]|\\.)*)")""")


def unesc(t):
    return re.sub(r"\\(.)", lambda m: {'n': '\n', 't': '\t'}.get(m.group(1), m.group(1)), t)


keys = set()
files = [R + 'lib/main.dart'] + [R + 'lib/ui/' + f for f in os.listdir(R + 'lib/ui') if f.endswith('.dart')] + \
        [R + 'lib/engine/' + f for f in os.listdir(R + 'lib/engine') if f.endswith('.dart')]
for f in files:
    s = io.open(f, encoding='utf-8').read()
    for m in re.finditer(r"\b(?:tr|trf|trp|L)\(", s):
        pos = m.end()
        parts = []
        while True:
            lm = LIT.match(s, pos)
            if not lm:
                break
            parts.append(unesc(lm.group(1) if lm.group(1) is not None else lm.group(2)))
            pos = lm.end()
        if parts and re.match(r"\s*[,)]", s[pos:]):
            keys.add(''.join(parts))
for extra in ['keys_names.json', 'enum_keys.json']:
    keys |= set(json.load(io.open(SP + '/' + extra, encoding='utf-8')))
skip = {'.sct', 'kitchinox', 'PD', 'PE', 'English', 'Français', 'العربية'}
keys = {k for k in keys if k not in skip and re.search(r'[A-Za-zÀ-ÿ]', re.sub(r'\{\w+\}', '', k))}
json.dump(sorted(keys), io.open(SP + '/all_keys.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=0)
tr = json.load(io.open(SP + '/translations.json', encoding='utf-8'))
todo = sorted(k for k in keys if k not in tr)
json.dump(todo, io.open(SP + '/todo.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=0)
print(len(keys), 'clés,', len(todo), 'à traduire,', sum(len(k) for k in todo), 'caractères')
