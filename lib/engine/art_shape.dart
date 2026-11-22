/// Forme d'une pièce de l'atelier (rond, polygone, coins arrondis, contour libre) et cotes attachées aux pièces.
/// Une pièce reste une boîte (débit, nesting, assemblage) ; sa forme est un contour dans cette boîte, qui la suit
/// quand elle est déplacée, tournée ou montée : ses axes sont repérés par leur rang (long, court, épaisseur).
library;

import 'dart:math' as math;

import 'art.dart';

double _loOf(ArtPanel p, int k) => k == 0 ? p.x : (k == 1 ? p.y : p.z);
double _sizeOf(ArtPanel p, int k) => k == 0 ? p.w : (k == 1 ? p.h : p.d);

/// Axes de la pièce : le plus long, le moyen, l'épaisseur (à égalité, l'ordre x, y, z).
List<int> rankAxes(ArtPanel p) {
  final k = [0, 1, 2];
  int cmp(int a, int b) {
    final d = _sizeOf(p, b) - _sizeOf(p, a);
    return d.abs() < 0.01 ? a - b : (d > 0 ? 1 : -1);
  }

  for (var i = 1; i < 3; i++) {
    for (var j = i; j > 0 && cmp(k[j - 1], k[j]) > 0; j--) {
      final t = k[j];
      k[j] = k[j - 1];
      k[j - 1] = t;
    }
  }
  return k;
}

/// Contour de la pièce, en fractions (long, court) de sa boîte ; vide : rectangle plein.
List<(double, double)> outlineOf(ArtPanel p) {
  switch (p.shape) {
    case 'rond':
      return [for (var i = 0; i < 48; i++) (0.5 + 0.5 * math.cos(2 * math.pi * i / 48), 0.5 + 0.5 * math.sin(2 * math.pi * i / 48))];
    case 'arrondi':
      final ax = rankAxes(p);
      final l = _sizeOf(p, ax[0]), w = _sizeOf(p, ax[1]);
      final r = math.min(p.radius, math.min(l, w) / 2);
      if (r < 0.5) return const [];
      const n = 8;
      final out = <(double, double)>[];
      for (final (cx, cy, a0) in [(l - r, w - r, 0.0), (r, w - r, math.pi / 2), (r, r, math.pi), (l - r, r, 3 * math.pi / 2)]) {
        for (var i = 0; i <= n; i++) {
          final a = a0 + math.pi / 2 * i / n;
          out.add(((cx + r * math.cos(a)) / l, (cy + r * math.sin(a)) / w));
        }
      }
      return out;
    default:
      return p.outline ?? const [];
  }
}

bool isShaped(ArtPanel p) => p.shape != null && outlineOf(p).length >= 3;

/// Points du contour dans l'espace, sur la face basse ([hi] faux) ou haute de l'épaisseur.
List<List<double>> worldOutline(ArtPanel p, {bool hi = true}) {
  final ax = rankAxes(p);
  final t = _loOf(p, ax[2]) + (hi ? _sizeOf(p, ax[2]) : 0);
  return [
    for (final (u, v) in outlineOf(p))
      List<double>.filled(3, 0)
        ..[ax[0]] = _loOf(p, ax[0]) + u * _sizeOf(p, ax[0])
        ..[ax[1]] = _loOf(p, ax[1]) + v * _sizeOf(p, ax[1])
        ..[ax[2]] = t,
  ];
}

/// Longueur du contour (mm) : le chant à poser sur une pièce de forme.
double perimeterOf(ArtPanel p) {
  final pts = worldOutline(p);
  var s = 0.0;
  for (var i = 0; i < pts.length; i++) {
    final a = pts[i], b = pts[(i + 1) % pts.length];
    s += math.sqrt([0, 1, 2].fold<double>(0, (m, k) => m + (a[k] - b[k]) * (a[k] - b[k])));
  }
  return s;
}

/// Surface pleine de la forme (mm²).
double shapeArea(ArtPanel p) {
  final ax = rankAxes(p);
  final o = outlineOf(p);
  var s = 0.0;
  for (var i = 0; i < o.length; i++) {
    final a = o[i], b = o[(i + 1) % o.length];
    s += a.$1 * b.$2 - b.$1 * a.$2;
  }
  return s.abs() / 2 * _sizeOf(p, ax[0]) * _sizeOf(p, ax[1]);
}

/// Nom de la forme, à noter au débit (null : rectangle).
String? shapeLabel(ArtPanel p) {
  if (!isShaped(p)) return null;
  final ax = rankAxes(p);
  final l = _sizeOf(p, ax[0]).round(), w = _sizeOf(p, ax[1]).round();
  return switch (p.shape) {
    'rond' => l == w ? 'rond Ø $l' : 'ovale $l x $w',
    'arrondi' => 'coins R ${math.min(p.radius, w / 2).round()}',
    'polygone' => '${p.outline?.length ?? 6} côtés',
    _ => 'forme libre',
  };
}

/// Le point (x, y, z) est-il dans le contour ?
bool insideOutline(ArtPanel p, List<double> pt) {
  final ax = rankAxes(p);
  final u = (pt[ax[0]] - _loOf(p, ax[0])) / _sizeOf(p, ax[0]), v = (pt[ax[1]] - _loOf(p, ax[1])) / _sizeOf(p, ax[1]);
  final o = outlineOf(p);
  var inside = false;
  for (var i = 0, j = o.length - 1; i < o.length; j = i++) {
    final (ui, vi) = o[i];
    final (uj, vj) = o[j];
    if ((vi > v) != (vj > v) && u < (uj - ui) * (v - vi) / (vj - vi) + ui) inside = !inside;
  }
  return inside;
}

/// Donne à [p] (déjà à la taille du contour) la forme du contour [pts] (points de l'espace).
void setOutline(ArtPanel p, List<List<double>> pts, {String shape = 'libre'}) {
  final ax = rankAxes(p);
  p
    ..shape = shape
    ..outline = [
      for (final q in pts)
        (
          ((q[ax[0]] - _loOf(p, ax[0])) / _sizeOf(p, ax[0])).clamp(0.0, 1.0).toDouble(),
          ((q[ax[1]] - _loOf(p, ax[1])) / _sizeOf(p, ax[1])).clamp(0.0, 1.0).toDouble(),
        ),
    ];
}

/// Retourne la forme le long de l'axe du monde [axis] (miroir).
void flipOutline(ArtPanel p, int axis) {
  final o = p.outline;
  if (o == null) return;
  final ax = rankAxes(p);
  p.outline = [for (final (u, v) in o) (ax[0] == axis ? 1 - u : u, ax[1] == axis ? 1 - v : v)];
}

/// Contour [pts] coupé par le plan « axe = at » : garde le côté des valeurs ≤ ([below]) ou ≥.
List<List<double>> clipOutline(List<List<double>> pts, int axis, double at, {required bool below}) {
  bool keep(List<double> q) => below ? q[axis] <= at + 1e-6 : q[axis] >= at - 1e-6;
  final out = <List<double>>[];
  for (var i = 0; i < pts.length; i++) {
    final a = pts[i], b = pts[(i + 1) % pts.length];
    if (keep(a)) out.add([...a]);
    if (keep(a) != keep(b)) {
      final t = (at - a[axis]) / (b[axis] - a[axis]);
      out.add([for (var k = 0; k < 3; k++) a[k] + (b[k] - a[k]) * t]);
    }
  }
  return out;
}

/// Pièce coupée : sa forme est celle du morceau de contour [pts], sa boîte se resserre dessus.
void fitToOutline(ArtPanel p, List<List<double>> pts) {
  final ax = rankAxes(p);
  for (final k in ax.take(2)) {
    final lo = pts.map((q) => q[k]).reduce(math.min), hi = pts.map((q) => q[k]).reduce(math.max);
    switch (k) {
      case 0:
        p
          ..x = lo
          ..w = hi - lo;
      case 1:
        p
          ..y = lo
          ..h = hi - lo;
      default:
        p
          ..z = lo
          ..d = hi - lo;
    }
  }
  setOutline(p, pts);
}

/// Simplifie un tracé à main levée : points à moins de [tol] mm de la corde retirés, puis courbe adoucie.
List<List<double>> smoothStroke(List<List<double>> pts, {double tol = 8}) {
  if (pts.length < 4) return pts;
  double dist(List<double> q, List<double> a, List<double> b) {
    final ab = [for (var k = 0; k < 3; k++) b[k] - a[k]], aq = [for (var k = 0; k < 3; k++) q[k] - a[k]];
    final l2 = ab.fold<double>(0, (s, x) => s + x * x);
    final t = l2 == 0 ? 0.0 : ((ab[0] * aq[0] + ab[1] * aq[1] + ab[2] * aq[2]) / l2).clamp(0.0, 1.0);
    return math.sqrt([0, 1, 2].fold<double>(0, (s, k) => s + math.pow(aq[k] - ab[k] * t, 2)));
  }

  List<List<double>> dp(List<List<double>> l) {
    if (l.length < 3) return l;
    var best = 0.0, at = 0;
    for (var i = 1; i < l.length - 1; i++) {
      final d = dist(l[i], l.first, l.last);
      if (d > best) {
        best = d;
        at = i;
      }
    }
    if (best <= tol) return [l.first, l.last];
    return [...dp(l.sublist(0, at + 1)), ...dp(l.sublist(at)).skip(1)];
  }

  // deux moitiés : le contour est fermé, sa corde serait nulle
  final half = pts.length ~/ 2;
  final ring = [...dp(pts.sublist(0, half + 1)), ...dp([...pts.sublist(half), pts.first]).skip(1)]..removeLast();
  if (ring.length < 3) return pts;
  var out = ring;
  for (var n = 0; n < 2; n++) {
    out = [
      for (var i = 0; i < out.length; i++) ...[
        [for (var k = 0; k < 3; k++) out[i][k] * 0.75 + out[(i + 1) % out.length][k] * 0.25],
        [for (var k = 0; k < 3; k++) out[i][k] * 0.25 + out[(i + 1) % out.length][k] * 0.75],
      ],
    ];
  }
  return out;
}

/// Arc de cercle passant par [a], [m] et [b] dans le plan des axes [u], [v] ; null si les points sont alignés.
List<List<double>>? arcThrough(List<double> a, List<double> m, List<double> b, int u, int v, {int segments = 32}) {
  final ax = a[u], ay = a[v], bx = b[u], by = b[v], cx = m[u], cy = m[v];
  final d = 2 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by));
  if (d.abs() < 1) return null;
  final ux = ((ax * ax + ay * ay) * (by - cy) + (bx * bx + by * by) * (cy - ay) + (cx * cx + cy * cy) * (ay - by)) / d;
  final uy = ((ax * ax + ay * ay) * (cx - bx) + (bx * bx + by * by) * (ax - cx) + (cx * cx + cy * cy) * (bx - ax)) / d;
  final r = math.sqrt((ax - ux) * (ax - ux) + (ay - uy) * (ay - uy));
  double ang(double x, double y) => math.atan2(y - uy, x - ux);
  double norm(double t) => (t % (2 * math.pi) + 2 * math.pi) % (2 * math.pi);
  final a0 = ang(ax, ay);
  final am = norm(ang(cx, cy) - a0), a1 = norm(ang(bx, by) - a0);
  final sweep = am <= a1 ? a1 : a1 - 2 * math.pi; // passe par le point du milieu
  return [
    for (var i = 0; i <= segments; i++)
      [...a]
        ..[u] = ux + r * math.cos(a0 + sweep * i / segments)
        ..[v] = uy + r * math.sin(a0 + sweep * i / segments),
  ];
}

// ------------------------------------------------------------------ cotes attachées

/// Attache d'un point de cote à une pièce : sa position en fractions (long, court, épaisseur) de la boîte.
class DimAnchor {
  final String panel;
  final List<double> f;
  const DimAnchor(this.panel, this.f);
  Map<String, dynamic> toJson() => {'p': panel, 'f': f};
  static DimAnchor? parse(Object? j) => j is Map ? DimAnchor('${j['p']}', [for (final x in j['f'] as List) (x as num).toDouble()]) : null;

  /// Position dans l'espace, la pièce ayant pu bouger ou tourner.
  List<double> at(ArtPanel p) {
    final ax = rankAxes(p);
    final out = List<double>.filled(3, 0);
    for (var i = 0; i < 3; i++) {
      out[ax[i]] = _loOf(p, ax[i]) + f[i] * _sizeOf(p, ax[i]);
    }
    return out;
  }
}

/// La pièce (de préférence [prefer]) que touche le point [q], et l'attache correspondante.
DimAnchor? anchorAt(List<ArtPanel> panels, List<double> q, {String? prefer}) {
  DimAnchor? best;
  for (final p in panels) {
    var inside = true, onFace = false;
    for (var k = 0; k < 3; k++) {
      final lo = _loOf(p, k), hi = lo + _sizeOf(p, k);
      if (q[k] < lo - 1.5 || q[k] > hi + 1.5) inside = false;
      if ((q[k] - lo).abs() < 1.5 || (q[k] - hi).abs() < 1.5) onFace = true;
    }
    if (!inside || !onFace) continue;
    final ax = rankAxes(p);
    final a = DimAnchor(p.id, [for (var i = 0; i < 3; i++) ((q[ax[i]] - _loOf(p, ax[i])) / math.max(0.001, _sizeOf(p, ax[i]))).clamp(0.0, 1.0).toDouble()]);
    if (p.id == prefer) return a;
    best ??= a;
  }
  return best;
}

/// Décalage de la ligne de cote, rapporté aux axes de la pièce (et retour).
List<double> offsetToRank(ArtPanel p, List<double> off) => [for (final k in rankAxes(p)) off[k]];
List<double> offsetFromRank(ArtPanel p, List<double> r) {
  final ax = rankAxes(p);
  final out = List<double>.filled(3, 0);
  for (var i = 0; i < 3; i++) {
    out[ax[i]] = r[i];
  }
  return out;
}
