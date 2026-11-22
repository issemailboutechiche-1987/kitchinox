// Caméra et géométrie de l'atelier Art : vue 3D en perspective ou orthogonale, orbite, panoramique, zoom,
// vues standard ; rayons depuis l'écran, intersection avec des plans, faces des panneaux (pavés) pointées.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/art.dart';

/// Vecteur 3D (mm) : x à droite (axe rouge), y vers le haut (axe bleu), z vers l'arrière (axe vert).
class V3 {
  final double x, y, z;
  const V3(this.x, this.y, this.z);
  V3 operator +(V3 o) => V3(x + o.x, y + o.y, z + o.z);
  V3 operator -(V3 o) => V3(x - o.x, y - o.y, z - o.z);
  V3 operator *(double k) => V3(x * k, y * k, z * k);
  double dot(V3 o) => x * o.x + y * o.y + z * o.z;
  V3 cross(V3 o) => V3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(dot(this));
  V3 get unit => this * (1 / (length == 0 ? 1 : length));
  double operator [](int i) => i == 0 ? x : (i == 1 ? y : z);
  V3 withAxis(int i, double v) => i == 0 ? V3(v, y, z) : (i == 1 ? V3(x, v, z) : V3(x, y, v));
  static const zero = V3(0, 0, 0);
}

/// Une face d'un panneau : axe de la normale (0 x, 1 y, 2 z) et sens (+1 / -1).
class Face {
  final ArtPanel panel;
  final int axis;
  final int sign;
  const Face(this.panel, this.axis, this.sign);

  V3 get normal => V3(axis == 0 ? sign.toDouble() : 0, axis == 1 ? sign.toDouble() : 0, axis == 2 ? sign.toDouble() : 0);

  /// Coordonnée du plan de la face sur son axe.
  double get plane {
    final p = panel;
    return switch (axis) {
      0 => sign > 0 ? p.right : p.x,
      1 => sign > 0 ? p.top : p.y,
      _ => sign > 0 ? p.back : p.z,
    };
  }

  List<V3> get corners {
    final p = panel;
    final xs = [p.x, p.right], ys = [p.y, p.top], zs = [p.z, p.back];
    final c = plane;
    return switch (axis) {
      0 => [V3(c, ys[0], zs[0]), V3(c, ys[1], zs[0]), V3(c, ys[1], zs[1]), V3(c, ys[0], zs[1])],
      1 => [V3(xs[0], c, zs[0]), V3(xs[1], c, zs[0]), V3(xs[1], c, zs[1]), V3(xs[0], c, zs[1])],
      _ => [V3(xs[0], ys[0], c), V3(xs[1], ys[0], c), V3(xs[1], ys[1], c), V3(xs[0], ys[1], c)],
    };
  }

  V3 get center {
    final cs = corners;
    return (cs[0] + cs[2]) * 0.5;
  }
}

List<V3> boxCorners(ArtPanel p) => [
      for (final x in [p.x, p.right])
        for (final y in [p.y, p.top])
          for (final z in [p.z, p.back]) V3(x, y, z),
    ];

List<Face> facesOf(ArtPanel p) => [for (var a = 0; a < 3; a++) for (final s in const [-1, 1]) Face(p, a, s)];

class ArtCamera extends ChangeNotifier {
  V3 target;
  double yaw, pitch, dist;
  bool ortho;
  double fov = 35 * math.pi / 180;
  Size size = const Size(800, 600);
  ArtCamera({this.target = const V3(1000, 700, 200), this.yaw = -0.65, this.pitch = 0.42, this.dist = 5200, this.ortho = false});

  /// Sens du regard : yaw 0 et pitch 0 = vue de face (l'œil devant le meuble, côté z négatif, regarde vers le mur).
  V3 get forward => V3(-math.sin(yaw) * math.cos(pitch), -math.sin(pitch), math.cos(yaw) * math.cos(pitch));
  V3 get eye => target - forward * dist;
  V3 get right {
    final r = const V3(0, 1, 0).cross(forward);
    return r.length < 1e-6 ? V3(math.cos(yaw), 0, math.sin(yaw)) : r.unit;
  }

  V3 get up => forward.cross(right).unit;
  double get focal => size.height / 2 / math.tan(fov / 2);
  double get orthoScale => focal / dist; // px par mm au niveau de la cible
  Offset get center => Offset(size.width / 2, size.height / 2);

  /// Point écran et profondeur (distance le long du regard).
  (Offset, double) project(V3 p) {
    final d = p - eye;
    final depth = d.dot(forward);
    final s = ortho ? orthoScale : focal / math.max(depth, 1);
    return (center + Offset(d.dot(right) * s, -d.dot(up) * s), depth);
  }

  /// Rayon (origine, direction) passant par un point de l'écran.
  (V3, V3) ray(Offset px) {
    final dx = px.dx - center.dx, dy = px.dy - center.dy;
    if (ortho) {
      final s = orthoScale;
      return (eye + right * (dx / s) + up * (-dy / s), forward);
    }
    return (eye, (forward * focal + right * dx + up * (-dy)).unit);
  }

  /// Intersection du rayon avec le plan « coordonnée [axis] = [value] ».
  V3? hitPlane(Offset px, int axis, double value) {
    final (o, d) = ray(px);
    final dn = d[axis];
    if (dn.abs() < 1e-9) return null;
    final t = (value - o[axis]) / dn;
    if (t < 0) return null;
    return o + d * t;
  }

  /// Longueur à l'écran d'un déplacement de 100 mm le long de [dir] partant de [at] (pour Pousser/Tirer).
  Offset screenDir(V3 at, V3 dir) => project(at + dir * 100).$1 - project(at).$1;

  void orbit(Offset delta) {
    yaw -= delta.dx * 0.012;
    pitch = (pitch + delta.dy * 0.009).clamp(-1.45, 1.45);
    notifyListeners();
  }

  void pan(Offset delta) {
    final s = ortho ? orthoScale : focal / dist;
    target = target - right * (delta.dx / s) + up * (delta.dy / s);
    notifyListeners();
  }

  void zoomAt(double factor) {
    dist = (dist * factor).clamp(300.0, 60000.0);
    notifyListeners();
  }

  /// Cadre tout le modèle (Zoom étendu).
  void fit(List<ArtPanel> panels) {
    if (panels.isEmpty) {
      target = const V3(1000, 700, 200);
      dist = 5200;
      notifyListeners();
      return;
    }
    var lo = const V3(1e9, 1e9, 1e9), hi = const V3(-1e9, -1e9, -1e9);
    for (final p in panels) {
      lo = V3(math.min(lo.x, p.x), math.min(lo.y, p.y), math.min(lo.z, p.z));
      hi = V3(math.max(hi.x, p.right), math.max(hi.y, p.top), math.max(hi.z, p.back));
    }
    target = (lo + hi) * 0.5;
    final r = (hi - lo).length / 2;
    // vue étroite (écran partagé, tablette debout) : c'est la largeur qui limite
    final aspect = size.width > 0 && size.height > 0 ? math.min(1.0, size.width / size.height) : 1.0;
    dist = math.max(800, r / math.sin(fov / 2) * 1.15 / aspect);
    notifyListeners();
  }

  /// Vues standard.
  void view(String v) {
    switch (v) {
      case 'iso':
        yaw = -0.65;
        pitch = 0.42;
        ortho = false;
      case 'dessus':
        yaw = 0;
        pitch = 1.45;
        ortho = true;
      case 'face':
        yaw = 0;
        pitch = 0;
        ortho = true;
      case 'droite':
        yaw = math.pi / 2;
        pitch = 0;
        ortho = true;
      case 'gauche':
        yaw = -math.pi / 2;
        pitch = 0;
        ortho = true;
      case 'arriere':
        yaw = math.pi;
        pitch = 0;
        ortho = true;
    }
    notifyListeners();
  }
}

/// Face visible sous un point de l'écran (la plus proche), ou null.
Face? pickFace(ArtCamera cam, List<ArtPanel> panels, Offset px) {
  Face? best;
  var bestDepth = double.infinity;
  final (o, d) = cam.ray(px);
  for (final p in panels) {
    for (final f in facesOf(p)) {
      final n = f.normal;
      if (n.dot(d) >= 0) continue; // face vue de dos
      final dn = d[f.axis];
      if (dn.abs() < 1e-9) continue;
      final t = (f.plane - o[f.axis]) / dn;
      if (t <= 0 || t >= bestDepth) continue;
      final hit = o + d * t;
      bool inside(int a, double lo, double hi) => hit[a] >= lo - 0.5 && hit[a] <= hi + 0.5;
      final ok = switch (f.axis) {
        0 => inside(1, p.y, p.top) && inside(2, p.z, p.back),
        1 => inside(0, p.x, p.right) && inside(2, p.z, p.back),
        _ => inside(0, p.x, p.right) && inside(1, p.y, p.top),
      };
      if (ok) {
        best = f;
        bestDepth = t;
      }
    }
  }
  return best;
}
