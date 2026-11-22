// Recettes paramétriques du mode Art (docs/mode_art_moteur.md, § 4, 13 et 14) : un meuble = des pièces
// dont les cotes sont des formules des paramètres, des liaisons entre chants nommés et un support.
// Une recette se pose sur une feuille : coupe à la guillotine, liaisons notées, puis « Usiner ».
import 'dart:convert';
import 'dart:math' as math;

import 'art.dart';
import 'art_relations.dart';
import 'i18n_hook.dart';

// ------------------------------------------------------------------ formules

/// Évalue une formule : nombres, variables, + − × /, parenthèses, comparaisons (1 ou 0), min, max, arrondi.
double evalFormula(String src, Map<String, double> vars) => _Formula(src, vars).run();

class _Formula {
  final String src, s;
  final Map<String, double> vars;
  int i = 0;
  _Formula(this.src, this.vars) : s = src.replaceAll(' ', '');

  Never fail(String why) => throw FormatException('Formule « $src » : $why');

  double run() {
    final v = expr();
    if (i != s.length) fail('caractère « ${s[i]} » inattendu');
    return v;
  }

  double expr() {
    final v = sum();
    for (final op in ['>=', '<=', '==', '>', '<']) {
      if (s.startsWith(op, i)) {
        i += op.length;
        final r = sum();
        return switch (op) { '>=' => v >= r, '<=' => v <= r, '>' => v > r, '<' => v < r, _ => (v - r).abs() < 1e-9 } ? 1 : 0;
      }
    }
    return v;
  }

  double sum() {
    var v = term();
    while (i < s.length && (s[i] == '+' || s[i] == '-')) {
      final op = s[i++];
      final r = term();
      v = op == '+' ? v + r : v - r;
    }
    return v;
  }

  double term() {
    var v = atom();
    while (i < s.length && (s[i] == '*' || s[i] == '/')) {
      final op = s[i++];
      final r = atom();
      v = op == '*' ? v * r : v / r;
    }
    return v;
  }

  double atom() {
    if (i >= s.length) fail('incomplète');
    final c = s[i];
    if (c == '(') {
      i++;
      final v = expr();
      if (i >= s.length || s[i] != ')') fail('parenthèse manquante');
      i++;
      return v;
    }
    if (c == '-') {
      i++;
      return -atom();
    }
    final num = RegExp(r'\d+(\.\d+)?').matchAsPrefix(s, i);
    if (num != null) {
      i = num.end;
      return double.parse(num.group(0)!);
    }
    final id = RegExp(r'[A-Za-z_][A-Za-z0-9_]*').matchAsPrefix(s, i);
    if (id == null) fail('caractère « $c » inattendu');
    i = id.end;
    final name = id.group(0)!;
    if (i < s.length && s[i] == '(') {
      i++;
      final args = <double>[expr()];
      while (i < s.length && s[i] == ',') {
        i++;
        args.add(expr());
      }
      if (i >= s.length || s[i] != ')') fail('parenthèse manquante');
      i++;
      return switch (name) {
        'min' => args.reduce(math.min),
        'max' => args.reduce(math.max),
        'arrondi' => args.length > 1 ? (args[0] / args[1]).round() * args[1] : args[0].roundToDouble(),
        _ => fail('fonction « $name » inconnue'),
      };
    }
    final v = vars[name];
    if (v == null) fail('variable « $name » inconnue');
    return v;
  }
}

double _f(Object? v, Map<String, double> vars) => v is num ? v.toDouble() : evalFormula('$v', vars);

// ------------------------------------------------------------------ modèle

class RecipeParam {
  final String id, name;
  final double value, min, max;
  const RecipeParam(this.id, this.name, this.value, this.min, this.max);
}

class ArtRecipe {
  final String id, name, family, description;
  final List<RecipeParam> params;
  final Map<String, dynamic> raw;
  const ArtRecipe(this.id, this.name, this.family, this.description, this.params, this.raw);

  factory ArtRecipe.fromJson(Map<String, dynamic> j) => ArtRecipe(
        j['id'] as String,
        j['nom'] as String,
        j['famille'] as String? ?? '',
        j['description'] as String? ?? '',
        [
          for (final p in (j['params'] as List).cast<Map<String, dynamic>>())
            RecipeParam(p['id'] as String, p['nom'] as String, (p['defaut'] as num).toDouble(), (p['min'] as num).toDouble(), (p['max'] as num).toDouble()),
        ],
        j,
      );

  Map<String, double> defaults() => {for (final p in params) p.id: p.value};
}

/// Pièce calculée d'une recette : longueur posée en X sur la feuille, largeur en Z (la largeur court le long
/// du chant de liaison), chants plaqués sur les longueurs et les largeurs.
class RecipePiece {
  final String id, name;
  final ArtRole role;
  final double lo, la;
  final int edgeLong, edgeShort;
  const RecipePiece(this.id, this.name, this.role, this.lo, this.la, this.edgeLong, this.edgeShort);
}

class RecipeLink {
  final String a, b, side, kind, align;
  final double offset, inset;
  final bool over;
  const RecipeLink(this.a, this.b, this.side, this.kind, this.align, this.offset, this.inset, this.over);
}

/// Recette évaluée pour des paramètres donnés.
class RecipeBuild {
  final ArtRecipe recipe;
  final Map<String, double> vars;
  final List<RecipePiece> pieces;
  final List<RecipeLink> links;
  final Map<String, dynamic>? support;
  const RecipeBuild(this.recipe, this.vars, this.pieces, this.links, this.support);
}

/// Évalue [r] : paramètres bornés, épaisseur [t] de la feuille ; pièces sous condition (« si ») écartées.
RecipeBuild buildRecipe(ArtRecipe r, Map<String, double> params, double t) {
  final vars = <String, double>{'T': t};
  for (final p in r.params) {
    vars[p.id] = (params[p.id] ?? p.value).clamp(p.min, p.max).toDouble();
  }
  // variables dérivées, dans l'ordre (chacune peut utiliser les précédentes)
  for (final e in ((r.raw['variables'] as Map?) ?? const {}).entries) {
    vars['${e.key}'] = _f(e.value, vars);
  }
  final pieces = <RecipePiece>[];
  for (final p in (r.raw['pieces'] as List).cast<Map<String, dynamic>>()) {
    if (p['si'] != null && _f(p['si'], vars) == 0) continue;
    final ch = (p['chants'] as Map?)?.cast<String, dynamic>() ?? const {};
    final lo = _f(p['lo'], vars), la = _f(p['la'], vars);
    // chants donnés sur la longueur (lo) et la largeur (la) de la recette → chants longs et courts de la pièce
    final onLo = (ch['lo'] as num?)?.toInt() ?? 0, onLa = (ch['la'] as num?)?.toInt() ?? 0;
    pieces.add(RecipePiece(
      p['id'] as String,
      p['nom'] as String,
      ArtRole.values.firstWhere((x) => x.name == p['role'], orElse: () => ArtRole.decor),
      lo,
      la,
      lo >= la ? onLo : onLa,
      lo >= la ? onLa : onLo,
    ));
  }
  final ids = {for (final p in pieces) p.id};
  final links = <RecipeLink>[];
  for (final l in (r.raw['liens'] as List).cast<Map<String, dynamic>>()) {
    if (!ids.contains(l['a']) || !ids.contains(l['b'])) continue;
    final dir = parseDir(l['vers'] as String? ?? '+Y');
    links.add(RecipeLink(
      l['a'] as String,
      l['b'] as String,
      l['cote'] as String,
      l['type'] as String? ?? 'bout',
      switch (l['align']) { 'centre' => 'center', 'fin' => 'end', 'decale' => 'custom', _ => 'start' },
      l['decale'] == null ? 0 : _f(l['decale'], vars),
      l['retrait'] == null ? 0 : _f(l['retrait'], vars),
      (dir?.$2 ?? 1) > 0,
    ));
  }
  final sup = (r.raw['support'] as Map?)?.cast<String, dynamic>();
  return RecipeBuild(r, vars, pieces, links, sup);
}

/// Contrôles de la recette évaluée : pièces de taille impossible, plus grandes que la feuille.
List<String> recipeProblems(RecipeBuild b, ArtPanel sheet) => [
      for (final p in b.pieces)
        if (p.lo < 30 || p.la < 30)
          L('{0} : {1} × {2} mm, trop petit pour la scie', [L(p.name), p.lo.round(), p.la.round()])
        else if (p.lo > sheet.w || p.la > sheet.d)
          L('{0} : {1} × {2} mm, plus grand que la feuille', [L(p.name), p.lo.round(), p.la.round()]),
    ];

/// Pose la recette sur la feuille [sheet] : coupe à la guillotine, rôles et chants, liaisons notées et support.
/// Null si les pièces ne tiennent pas dans la feuille (rien n'est coupé).
List<ArtPanel>? cutRecipe(ArtProject art, ArtPanel sheet, RecipeBuild b, {double kerf = 4, bool moreSheets = true}) {
  // feuilles de plus si besoin : même format, posées à droite de la dernière
  ArtPanel extra() {
    final x = art.free.map((p) => p.right).reduce(math.max) + 300;
    final s = sheet.copy(id: art.newId())
      ..x = x
      ..z = sheet.z
      ..note = null;
    art.free.add(s);
    return s;
  }

  final cut = cutPiecesFromSheet(art, sheet, [for (final p in b.pieces) (p.name, p.lo, p.la)], kerf: kerf, extraSheet: moreSheets ? extra : null);
  if (cut == null) return null;
  final byId = <String, ArtPanel>{};
  for (var i = 0; i < b.pieces.length; i++) {
    final rp = b.pieces[i], panel = cut[i];
    panel
      ..role = rp.role
      ..edgeLong = rp.edgeLong
      ..edgeShort = rp.edgeShort;
    if (rp.role == ArtRole.porte) panel.hinge = 'left';
    byId[rp.id] = panel;
  }
  for (final l in b.links) {
    final a = byId[l.a]!, bb = byId[l.b]!;
    // la largeur de la pièce (en Z sur la feuille) court le long du chant de liaison : chant de normale X
    art.edgeLinks.add(EdgeLink(a.id, ArtProject.edgeWithNormal(a, 0, -1), bb.id, 0,
        kind: l.kind, bSide: l.side, align: l.align, offset: l.offset, inset: l.inset, over: l.over));
  }
  final s = b.support;
  if (s != null && byId[s['ancre']] != null) {
    art.support = ArtSupport(
      type: s['type'] as String? ?? 'pieds',
      anchor: byId[s['ancre']]!.id,
      height: s['hauteur'] == null ? 0 : _f(s['hauteur'], b.vars),
      plinth: byId[s['plinthe']]?.id,
      retreat: s['retrait'] == null ? 50 : _f(s['retrait'], b.vars),
    );
  }
  return cut;
}

// ------------------------------------------------------------------ catalogue

class ArtRecipes {
  static List<ArtRecipe> all = const [];
  static void parse(String text) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    all = [for (final r in (j['recettes'] as List).cast<Map<String, dynamic>>()) ArtRecipe.fromJson(r)];
  }

  static ArtRecipe? byId(String id) => all.where((r) => r.id == id).firstOrNull;
}
