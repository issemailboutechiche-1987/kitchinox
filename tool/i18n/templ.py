"""Transforme les textes affichés (y compris avec valeurs $x / ${expr}) en appels de traduction :
  'Évier à ${d} m de ${m.name}'  →  FN('Évier à {0} m de {1}', [d, NAME(m.name)])
Dans une région donnée (argument d'un Text, d'un message, d'un Issue...), chaque suite de chaînes adjacentes
contenant des lettres est remplacée. Usage : python templ.py <mode ui|engine|pdf> <keys_out.json> fichiers..."""
import io, json, re, sys

MODE = sys.argv[1]
KEYS_OUT = sys.argv[2]
FILES = sys.argv[3:]
FN = {'ui': 'trp', 'engine': 'L', 'pdf': 'trp'}[MODE]
NAME = {'ui': 'tr', 'engine': 'L', 'pdf': 'tr'}[MODE]
keys = set()
IDENT = re.compile(r'[A-Za-z_][A-Za-z0-9_]*')


def scan_expr_end(s, i):
    """i : juste après '${' ; renvoie l'index de la '}' fermante."""
    depth = 0
    while i < len(s):
        c = s[i]
        if c in '\'"':
            i = skip_literal(s, i)
            continue
        if c == '{':
            depth += 1
        elif c == '}':
            if depth == 0:
                return i
            depth -= 1
        i += 1
    raise ValueError('expr non fermée')


def skip_literal(s, i):
    """Saute une chaîne Dart simple commençant en i (quote) ; renvoie l'index après."""
    q = s[i]
    if s[i:i + 3] == q * 3:
        e = s.find(q * 3, i + 3)
        return e + 3
    i += 1
    while i < len(s):
        c = s[i]
        if c == '\\':
            i += 2
            continue
        if c == '$' and i + 1 < len(s) and s[i + 1] == '{':
            i = scan_expr_end(s, i + 2) + 1
            continue
        if c == q:
            return i + 1
        if c == '\n':
            raise ValueError('chaîne non fermée')
        i += 1
    raise ValueError('fin de fichier')


def parse_literal(s, i):
    """Chaîne en i (éventuellement r'...') → (fin, morceaux) ; morceaux : ('t', texte) / ('e', code). None si non gérée."""
    raw = False
    if s[i] == 'r' and i + 1 < len(s) and s[i + 1] in '\'"':
        raw = True
        i += 1
    q = s[i]
    if s[i:i + 3] == q * 3:
        return None
    i += 1
    parts = []
    buf = ''
    while i < len(s):
        c = s[i]
        if c == q:
            if buf:
                parts.append(('t', buf))
            return i + 1, parts
        if c == '\n':
            return None
        if c == '\\' and not raw:
            n = s[i + 1]
            buf += {'n': '\n', 't': '\t', '\\': '\\', "'": "'", '"': '"', '$': '$'}.get(n, n)
            i += 2
            continue
        if c == '$' and not raw:
            if s[i + 1] == '{':
                e = scan_expr_end(s, i + 2)
                if buf:
                    parts.append(('t', buf))
                    buf = ''
                parts.append(('e', s[i + 2:e].strip()))
                i = e + 1
                continue
            m = IDENT.match(s, i + 1)
            if m:
                if buf:
                    parts.append(('t', buf))
                    buf = ''
                parts.append(('e', m.group(0)))
                i = m.end()
                continue
        buf += c
        i += 1
    return None


def parse_sequence(s, i):
    """Suite de chaînes adjacentes à partir de i → (fin, morceaux) ou None."""
    parts = []
    end = i
    first = True
    while True:
        j = end
        while j < len(s) and s[j] in ' \t\r\n':
            j += 1
        if j < len(s) and (s[j] in '\'"' or (s[j] == 'r' and j + 1 < len(s) and s[j + 1] in '\'"')):
            r = parse_literal(s, j)
            if r is None:
                return None
            end, p = r
            parts += p
            first = False
        else:
            break
    return (end, parts) if not first else None


def dart_q(t):
    return "'" + t.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$').replace('\n', '\\n') + "'"


REQ_SPACE = [False]


def build(parts):
    text = ''
    args = []
    for k, v in parts:
        if k == 't':
            if '{' in v or '}' in v:
                return None
            text += v
        else:
            text += '{%d}' % len(args)
            if re.search(r'(^|\.)(name|label)$', v) and not v.startswith(NAME + '('):
                v = '%s(%s)' % (NAME, v)
            args.append(v)
    if not re.search(r'[A-Za-zÀ-ÿ]', re.sub(r'\{\d+\}', '', text)):
        return None
    if REQ_SPACE[0] and ' ' not in text.strip():
        return None
    keys.add(text)
    if not args:
        return '%s(%s)' % (NAME if MODE != 'engine' else 'L', dart_q(text))
    return '%s(%s, [%s])' % (FN, dart_q(text), ', '.join(args))


def region_end(s, i):
    """Fin de l'argument commençant en i : virgule ou parenthèse/crochet fermant au niveau 0."""
    depth = 0
    while i < len(s):
        c = s[i]
        if c in '\'"' or (c == 'r' and i + 1 < len(s) and s[i + 1] in '\'"' and not (s[i - 1].isalnum() or s[i - 1] == '_')):
            if c == 'r':
                i += 1
            i = skip_literal(s, i)
            continue
        if c in '([{':
            depth += 1
        elif c in ')]}':
            if depth == 0:
                return i
            depth -= 1
        elif c == ',' and depth == 0:
            return i
        elif c == ';' and depth == 0:
            return i
        i += 1
    return i


ALREADY = re.compile(r'(?:\btr|\btrf|\btrp|\bL)\(\s*$' if MODE == 'pdf' else r'(?:\btr|\btrf|\btrp|\bL|_t)\(\s*$')


def transform_region(s, a, b):
    out = []
    i = a
    while i < b:
        c = s[i]
        is_lit = c in '\'"' or (c == 'r' and i + 1 < b and s[i + 1] in '\'"' and not (s[i - 1].isalnum() or s[i - 1] == '_'))
        if is_lit:
            prev = s[max(0, i - 8):i]
            r = parse_sequence(s, i)
            if r is None:
                e = skip_literal(s, i + (1 if c == 'r' else 0))
                out.append(s[i:e])
                i = e
                continue
            e, parts = r
            # déjà traduit, ou argument d'une méthode (replaceAll, join...) : on laisse
            before = ''.join(out)[-12:] + ''
            if ALREADY.search(''.join(out)[-8:]) or re.search(r'\.\w+\(\s*$', ''.join(out)[-30:]):
                out.append(s[i:e])
            else:
                rep = build(parts)
                out.append(rep if rep is not None else s[i:e])
            i = e
            continue
        out.append(c)
        i += 1
    return ''.join(out)


CTX = {
    'pdf': [r'\b_text\(\s*c\s*,\s*',r'\b_t\(\s*', r'\bpw\.Text\(\s*', r'\btx\(\s*', r'\bnote\(\s*', r'\b_kv\(\s*', r'\b_cell\(\s*', r'\btitle\(\s*',
            r'\bpw\.Bullet\(\s*text:\s*', r'\bstep\([^,]+,\s*', r'\bonProgress\?\.call\([^,]+,\s*', r"\b_kv\(\s*'[^']*'\s*,\s*", r"\b_cell\(\s*'[^']*'\s*,\s*"],
    'ui': [r'\bText\(\s*', r'\b_msg\(\s*', r'\bonMessage\(\s*', r'\bsay\(\s*', r'\blabel:\s*', r'\btooltip:\s*',
           r'\bsubtitle:\s*', r'\bhelperText:\s*', r'\blabelText:\s*', r'\bhintText:\s*', r'\bmessage:\s*', r'\berrorText:\s*',
           r'\breturn\s+', r'\berror\s*=\s*', r'\brunBusy\(\s*context,\s*', r'\brunBusy\(\s*ctx,\s*', r"\bprogress\.set\([^,]+,\s*"],
    'engine': [r'\bIssue\(\s*(?:Severity\.\w+|\w+(?:\s*\?\s*Severity\.\w+\s*:\s*Severity\.\w+)?)\s*,\s*\'[a-z_0-9]+\'\s*,\s*',
               r'\bPlacementException\(\s*', r'\bIssueFix\(\s*', r'\blabel:\s*'],
}


def process(path):
    s = io.open(path, encoding='utf-8').read()
    ctx = CTX[MODE]
    # positions des débuts d'argument
    starts = set()
    for c in ctx:
        for m in re.finditer(c, s):
            if MODE != 'engine' and c == r'\breturn\s+' and 'app_state' not in path and 'fixes' not in path:
                continue
            starts.add(m.end())
    if not starts:
        return 0
    res = []
    last = 0
    n = 0
    for a in sorted(starts):
        if a < last:
            continue
        try:
            b = region_end(s, a)
        except ValueError:
            continue
        REQ_SPACE[0] = bool(re.search(r'(return\s+|error\s*=\s*)$', s[max(0, a - 12):a]))
        seg = transform_region(s, a, b)
        if seg != s[a:b]:
            n += 1
        res.append(s[last:a])
        res.append(seg)
        last = b
    res.append(s[last:])
    out = ''.join(res)
    if out != s:
        io.open(path, 'w', encoding='utf-8', newline='\n').write(out)
    return n


total = 0
for f in FILES:
    total += process(f)
old = []
try:
    old = json.load(io.open(KEYS_OUT, encoding='utf-8'))
except Exception:
    pass
json.dump(sorted(set(old) | keys), io.open(KEYS_OUT, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print(total, 'régions modifiées,', len(keys), 'textes')
