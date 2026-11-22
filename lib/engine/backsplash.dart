/// Crédence : les morceaux de mur entre le plan de travail et les hauts, découpés autour des portes et fenêtres.
/// Sert au rendu (vue de face, 3D) et au devis quand elle est dans la matière du plan de travail.
library;

import 'dart:math' as math;

import 'layout_engine.dart';
import 'project.dart';

/// Crédence dans la matière du plan de travail : jusqu'aux hauts, ou simple relevé de 10 cm.
const splashLikeTop = 'plan', splashUpstand = 'plan_10';
const upstandHeight = 100.0;

bool splashMatchesTop(KitchenStyle s) => s.splash == splashLikeTop || s.splash == splashUpstand;

typedef SplashSegment = ({String wall, double s0, double s1, double z0, double z1});

List<SplashSegment> splashSegments(LayoutEngine e) {
  final p = e.project;
  final room = p.room;
  final out = <SplashSegment>[];
  final zBottom = p.standards.worktopTop.toDouble();
  final low = p.style.splash == splashUpstand;
  void add(String wall, double s0, double s1, double z0, double z1) {
    if (low && z0 > zBottom + 0.5) return; // relevé : rien au-dessus des fenêtres
    final top = low ? math.min(z1, zBottom + upstandHeight) : z1;
    if (s1 > s0 + 0.5 && top > z0 + 0.5) out.add((wall: wall, s0: s0, s1: s1, z0: z0, z1: top));
  }

  for (final w in room.walls.where((w) => w.enabled)) {
    double topOver(double a, double b) {
      var z = zBottom + 600.0;
      for (final c in p.items.where((c) => c.wallId == w.id && e.modelOf(c).kind.isHigh && c.s < b && a < c.right)) {
        z = math.min(z, c.z);
      }
      return z;
    }

    for (final (a, b) in e.runs(w.id, (m) => e.kitchen && m.kind.isLow)) {
      final zTop = topOver(a, b);
      if (zTop <= zBottom) continue;
      final ops = p.openings.where((o) => o.wallId == w.id && o.right > a && o.s < b && o.z < zTop && o.z + o.height > zBottom).toList()
        ..sort((x, y) => x.s.compareTo(y.s));
      if (ops.isEmpty) {
        add(w.id, a, b, zBottom, zTop);
        continue;
      }
      var cur = a;
      for (final o in ops) {
        final s0 = math.max(a, o.s), s1 = math.min(b, o.right);
        if (s0 > cur + 1) add(w.id, cur, s0, zBottom, topOver(cur, s0));
        // allège sous la fenêtre, imposte au-dessus
        if (!o.isDoor && o.z > zBottom + 5) add(w.id, s0, s1, zBottom, math.min(zTop, o.z));
        if (!o.isDoor && o.z + o.height < zTop - 5) add(w.id, s0, s1, o.z + o.height, zTop);
        cur = math.max(cur, s1);
      }
      if (b > cur + 1) add(w.id, cur, b, zBottom, topOver(cur, b));
    }
  }
  return out;
}

/// Surface de crédence (m²).
double splashArea(LayoutEngine e) => splashSegments(e).fold<double>(0, (a, s) => a + (s.s1 - s.s0) * (s.z1 - s.z0)) / 1e6;
