"""Fusionne translations*.json, signale les clés sans traduction, génère lib/ui/i18n_dict.dart."""
import glob, io, json, re, sys

SP = sys.argv[1]
R = 'D:/kitchinox/V2/'
tr = {}
for f in sorted(glob.glob(SP + '/translations*.json')):
    tr.update(json.load(io.open(f, encoding='utf-8')))
keys = json.load(io.open(SP + '/all_keys.json', encoding='utf-8'))
codes = {'a', 'exist:water', 'gas', 'luxe', 'n', 'plage', 'pce', 'w', 'I'}
trivial = lambda k: not re.search(r'[A-Za-zÀ-ÿ]{2,}', re.sub(r'\{\d+\}', '', k))
missing = [k for k in keys if k not in tr and k not in codes and not trivial(k)]
print('sans traduction :', len(missing), missing[:40])


def dq(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"').replace('$', '\\$').replace('\n', '\\n') + '"'


out = ["// Traductions de l'interface (clé = texte français). Généré depuis les fichiers de traduction ; à compléter au besoin.", '']
for i, name in enumerate(['enDict', 'arDict']):
    out.append('const Map<String, String> %s = {' % name)
    for k in sorted(tr):
        out.append('  %s: %s,' % (dq(k), dq(tr[k][i])))
    out.append('};')
    out.append('')
io.open(R + 'lib/ui/i18n_dict.dart', 'w', encoding='utf-8', newline='\n').write('\n'.join(out))
print(len(tr), 'traductions')
