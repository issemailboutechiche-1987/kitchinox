"""Retire les « const » qui englobent un tr(...) : boucle analyseur → correction, jusqu'à zéro erreur de const."""
import io, re, subprocess, sys

R = 'D:/kitchinox/kitchen_planner/'
CODES = ('const_with_non_constant_argument', 'non_constant_list_element', 'invalid_constant',
         'const_initialized_with_non_constant_value', 'non_constant_map_element', 'non_constant_default_value',
         'const_constructor_param_type_mismatch', 'non_constant_set_element', 'const_eval_method_invocation')
for it in range(30):
    out = subprocess.run('flutter analyze --no-pub lib', shell=True, cwd=R, capture_output=True, text=True, encoding='utf-8', errors='replace').stdout
    errs = []
    for line in out.splitlines():
        m = re.search(r'error - .* - (lib[\\/][^:]+):(\d+):(\d+) - (\w+)', line)
        if m and m.group(4) in CODES:
            errs.append((m.group(1).replace('\\', '/'), int(m.group(2)), int(m.group(3))))
    other = [l for l in out.splitlines() if 'error -' in l and not any(c in l for c in CODES)]
    print('passe', it, ':', len(errs), 'const,', len(other), 'autres')
    if not errs:
        for l in other[:20]:
            print(l)
        break
    byfile = {}
    for f, ln, col in errs:
        byfile.setdefault(f, []).append((ln, col))
    for f, locs in byfile.items():
        s = io.open(R + f, encoding='utf-8').read()
        lines = s.split('\n')
        offs = [0]
        for l in lines:
            offs.append(offs[-1] + len(l) + 1)
        removed = set()
        # du plus loin au plus proche du début : les positions restent valables
        for ln, col in sorted(set(locs), reverse=True):
            pos = offs[ln - 1] + col - 1
            # « const » le plus proche avant l'erreur
            k = s.rfind('const ', 0, pos + 1)
            while k > 0 and (s[k - 1].isalnum() or s[k - 1] == '_'):
                k = s.rfind('const ', 0, k)
            if k < 0 or k in removed:
                continue
            removed.add(k)
            s = s[:k] + s[k + 6:]
        io.open(R + f, 'w', encoding='utf-8', newline='\n').write(s)
