// Dessins techniques pour le plan d'exécution : vue de dessus et plans de face, en traits noirs,
// avec chaînes de cotes (mm), repères numérotés et symboles d'appareils.
// Les mêmes fonctions servent à l'écran et au PDF (rendu en image haute définition).

import 'i18n.dart';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../engine/engine.dart';
import 'finishes.dart';
import 'openings_ui.dart';
import 'fronts.dart';
import 'net_symbols.dart';
import 'scene3d.dart';

const _ink = Color(0xFF1A1A1A);
const _grey = Color(0xFF6B6B6B);
const _light = Color(0xFFE6E6E6);
const _repere = Color(0xFFD9480F);
const _wallFill = Color(0xFF9A9A9A);
const wallThickness = 120.0;

/// Numérotation des éléments (repères) : mur par mur dans l'ordre A, B, D, C, puis de gauche à droite,
/// les éléments bas avant les hauts.
Map<String, int> repereNumbers(LayoutEngine e) {
  // tri stable : même numérotation sur tablette (navigateur) et ailleurs
  final items = [...e.project.items]..stableSort((a, b) {
      final w = e.project.room.order.indexOf(a.wallId).compareTo(e.project.room.order.indexOf(b.wallId));
      if (w != 0) return w;
      final ha = e.modelOf(a).kind.isHigh ? 1 : 0, hb = e.modelOf(b).kind.isHigh ? 1 : 0;
      if (ha != hb) return ha.compareTo(hb);
      final c = a.s.compareTo(b.s);
      return c != 0 ? c : a.z.compareTo(b.z);
    });
  return {for (var i = 0; i < items.length; i++) items[i].uid: i + 1};
}

class TechDrawer {
  final LayoutEngine e;
  final Map<String, int> reperes;
  TechDrawer(this.e) : reperes = repereNumbers(e);

  Project get p => e.project;

  // ---------------------------------------------------------------- outils de tracé

  late double u; // unité graphique (px) proportionnelle à la taille du dessin

  Paint _line(double w, [Color c = _ink]) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w * u
    ..strokeCap = StrokeCap.butt;

  void _text(Canvas c, String s, Offset center,
      {double size = 9, Color color = _ink, FontWeight weight = FontWeight.w500, double angle = 0, Color? bg}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: size * u, color: color, fontWeight: weight, fontFamily: 'Roboto')),
      textDirection: TextDirection.ltr,
    )..layout();
    c.save();
    c.translate(center.dx, center.dy);
    if (angle != 0) c.rotate(angle);
    final o = Offset(-tp.width / 2, -tp.height / 2);
    if (bg != null) c.drawRect(Rect.fromLTWH(o.dx - 2 * u, o.dy, tp.width + 4 * u, tp.height), Paint()..color = bg);
    tp.paint(c, o);
    c.restore();
  }

  void _dashed(Canvas c, Offset a, Offset b, Paint p, {double dash = 6, double gap = 4}) {
    final d = b - a, len = d.distance;
    if (len == 0) return;
    final v = d / len;
    for (var t = 0.0; t < len; t += (dash + gap) * u) {
      c.drawLine(a + v * t, a + v * math.min(len, t + dash * u), p);
    }
  }

  /// Chaîne de cotes le long d'un segment écran [a]→[b] représentant [0, total] mm.
  /// [ticks] : positions (mm) des repères. Texte au-dessus du trait (côté [side]).
  void _chain(Canvas c, Offset a, Offset b, double total, Iterable<double> ticks, {Offset? side}) {
    final ts = {...ticks.map((t) => t.clamp(0.0, total))}.toList()..sort();
    if (ts.length < 2) return;
    final dir = (b - a) / (b - a).distance;
    final nrm = side ?? Offset(dir.dy, -dir.dx); // côté du texte
    final angle = math.atan2(dir.dy, dir.dx);
    final readable = (angle > math.pi / 2 || angle <= -math.pi / 2) ? angle + math.pi : angle;
    Offset at(double mm) => a + (b - a) * (mm / total);
    c.drawLine(at(ts.first), at(ts.last), _line(0.9));
    final slash = Offset(dir.dx + nrm.dx, dir.dy + nrm.dy) * (5 * u / math.sqrt2);
    for (final t in ts) {
      final q = at(t);
      c.drawLine(q - slash, q + slash, _line(1.6));
      c.drawLine(q - nrm * 8 * u, q + nrm * 3 * u, _line(0.5, _grey));
    }
    var lift = 0;
    for (var i = 0; i + 1 < ts.length; i++) {
      final seg = ts[i + 1] - ts[i];
      if (seg < 0.5) continue;
      final px = (at(ts[i + 1]) - at(ts[i])).distance;
      final label = '${seg.round()}';
      // segment trop court : texte décalé en quinconce
      final tooShort = px < (label.length * 7.2 + 8) * u;
      lift = tooShort ? (lift == 1 ? 2 : 1) : 0;
      final mid = (at(ts[i]) + at(ts[i + 1])) / 2 + nrm * (9 + lift * 13) * u;
      _text(c, label, mid, size: 10.5, weight: FontWeight.w600, angle: readable);
    }
  }

  void _repereTag(Canvas c, String uid, Offset at, {double size = 12}) {
    final n = reperes[uid];
    if (n == null) return;
    final r = size * 0.95 * u;
    c.drawCircle(at, r, Paint()..color = Colors.white);
    c.drawCircle(at, r, _line(1.4, _repere));
    _text(c, '$n', at, size: size * 0.9, color: _repere, weight: FontWeight.w800);
  }

  // ---------------------------------------------------------------- plan de dessus

  void paintPlan(Canvas c, Size size) {
    u = size.width / 1400;
    final room = p.room;
    const t = wallThickness;
    final margin = 175 * u; // place pour 3 chaînes de cotes
    final k = math.min((size.width - 2 * margin) / (room.width + 2 * t), (size.height - 2 * margin) / (room.depth + 2 * t));
    final ox = (size.width - room.width * k) / 2, oy = (size.height - room.depth * k) / 2;
    Offset s(double x, double y) => Offset(ox + x * k, oy + y * k);

    // murs (épaisseur pleine) puis sol
    if (room.outline == null) {
      c.drawRect(Rect.fromPoints(s(-t, -t), s(room.width + t, room.depth + t)), Paint()..color = _wallFill);
      c.drawRect(Rect.fromPoints(s(0, 0), s(room.width, room.depth)), Paint()..color = Colors.white);
      c.drawRect(Rect.fromPoints(s(-t, -t), s(room.width + t, room.depth + t)), _line(1.2));
      c.drawRect(Rect.fromPoints(s(0, 0), s(room.width, room.depth)), _line(1.2));
    } else {
      // contour libre : mur épais le long des traits et des arcs
      final path = Path()..addPolygon([for (final (x, y) in room.floorPolygon) s(x, y)], true);
      c.drawPath(path, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * t * k
        ..strokeJoin = StrokeJoin.miter
        ..color = _wallFill);
      c.drawPath(path, Paint()..color = Colors.white);
      c.drawPath(path, _line(1.2));
    }

    // ouvertures : on « coupe » le mur
    for (final o in p.openings) {
      final w = room.wall(o.wallId);
      final a = w.toPlan(o.s, -t), b = w.toPlan(o.right, 0);
      final r = Rect.fromPoints(s(a.$1, a.$2), s(b.$1, b.$2));
      c.drawRect(r, Paint()..color = Colors.white);
      c.drawRect(r, _line(0.8));
      paintOpeningPlan(c, o, (ss, tt) {
        final q = w.toPlan(ss, tt);
        return s(q.$1, q.$2);
      }, t, floor: Colors.white);
    }

    // îlot : plan de travail avec débord repas
    final isl = room.island;
    if (isl != null) {
      final ir = Rect.fromPoints(s(isl.x0, isl.y0), s(isl.x0 + isl.length, isl.y0 + Island.depth + isl.overhang));
      c.drawRect(ir, Paint()..color = _light);
      c.drawRect(ir, _line(1.2));
      _text(c, trp('ÎLOT  {0} x {1}', [isl.length.round(), (Island.depth + isl.overhang).round()]),
          Offset(ir.center.dx, s(0, isl.y0 + Island.depth + isl.overhang / 2).dy), size: 10, weight: FontWeight.w800, color: _grey);
      // cotes de position de l'îlot
      _chain(c, s(isl.x0, isl.y0) + Offset(0, -18 * u), s(isl.x0 + isl.length, isl.y0) + Offset(0, -18 * u), isl.length, [0, isl.length],
          side: const Offset(0, -1));
      _chain(c, s(0, isl.y0 + 300) , s(isl.x0, isl.y0 + 300), isl.x0, [0, isl.x0], side: const Offset(0, -1));
    }

    // caissons : bas et colonnes pleins, hauts en pointillés par-dessus
    final shapes = e.planView();
    for (final sh in shapes.where((x) => !x.model.kind.isHigh)) {
      final path = Path()..addPolygon([for (final (x, y) in sh.points) s(x, y)], true);
      c.drawPath(path, Paint()..color = Colors.white);
      c.drawPath(path, _line(1.3));
      _symbols(c, sh, s, k);
    }
    for (final sh in shapes.where((x) => x.model.kind.isHigh)) {
      final pts = [for (final (x, y) in sh.points) s(x, y)];
      for (var i = 0; i < pts.length; i++) {
        _dashed(c, pts[i], pts[(i + 1) % pts.length], _line(0.7, _grey), dash: 5, gap: 3);
      }
    }
    // repères : bas au centre, hauts vers le mur
    for (final sh in shapes) {
      final it = p.byUid(sh.uid)!;
      final w = room.wall(it.wallId);
      Offset at;
      if (sh.model.shape == CabinetShape.rect || sh.model.shape == CabinetShape.blind) {
        final q = w.toPlan(it.s + it.width / 2, it.depth * (sh.model.kind.isHigh ? 0.25 : 0.62));
        at = s(q.$1, q.$2);
      } else {
        final b = (Path()..addPolygon([for (final (x, y) in sh.points) s(x, y)], true)).getBounds();
        at = b.center;
      }
      _repereTag(c, sh.uid, at);
    }

    // chaînes de cotes à l'extérieur de chaque mur
    for (final w in room.walls) {
      final out = Offset(-w.nx, -w.ny);
      Offset sp(double sMm, double off) {
        final q = w.toPlan(sMm, -t);
        return s(q.$1, q.$2) + out * off;
      }

      final elev = e.elevation(w.id);
      final lowTicks = <double>{0, w.length};
      for (final r in elev.where((r) => !r.model.kind.isHigh)) {
        lowTicks
          ..add(r.s0)
          ..add(r.s1);
      }
      final openTicks = <double>{0, w.length};
      for (final o in p.openings.where((o) => o.wallId == w.id)) {
        openTicks
          ..add(o.s)
          ..add(o.right);
      }
      var off = 40 * u;
      if (lowTicks.length > 2) {
        _chain(c, sp(0, off), sp(w.length, off), w.length, lowTicks, side: out);
        off += 44 * u;
      }
      if (openTicks.length > 2) {
        _chain(c, sp(0, off), sp(w.length, off), w.length, openTicks, side: out);
        off += 44 * u;
      }
      _chain(c, sp(0, off), sp(w.length, off), w.length, [0, w.length], side: out);
      // nom du mur
      final mid = sp(w.length / 2, off + 36 * u);
      final ang = w.dx == 0 ? (w.nx < 0 ? math.pi / 2 : -math.pi / 2) : 0.0;
      _text(c, trp('MUR {0}{1}', [w.id, w.enabled ? '' : tr(' (sans caissons)')]), mid, size: 11, weight: FontWeight.w800, angle: ang, color: _grey);
    }

    // sanitaires et objets posés : contour, symbole, nom ; mobilier du client en pointillés
    for (final o in p.objects) {
      final (x0, y0, x1, y1) = o.footprint;
      final rr = Rect.fromPoints(s(x0, y0), s(x1, y1));
      final f = o.fixture;
      if (f == null) {
        _dashedPath(c, Path()..addRect(rr), _line(0.8, _grey));
      } else {
        c.drawRect(rr, Paint()..color = Colors.white);
        c.drawRect(rr, _line(1.1));
        switch (f.id) {
          case 'wc_suspendu' || 'wc_sol' || 'bidet':
            c.drawOval(rr.deflate(rr.shortestSide * 0.12), _line(1.0));
          case 'lavabo' || 'vasque_double' || 'baignoire':
            c.drawRRect(RRect.fromRectAndRadius(rr.deflate(rr.shortestSide * 0.14), Radius.circular(rr.shortestSide * 0.3)), _line(0.9));
          case 'douche' || 'douche_italienne':
            c.drawLine(rr.topLeft, rr.bottomRight, _line(0.6, _grey));
            c.drawLine(rr.topRight, rr.bottomLeft, _line(0.6, _grey));
          default:
            break;
        }
      }
      _text(c, objectName(o), rr.center, size: 8.5, color: f == null ? _grey : _ink, weight: FontWeight.w700, bg: Colors.white);
    }

    // surface
    _text(c, trp('Cuisine  {0} m²', [(room.width * room.depth / 1e6).toStringAsFixed(1).replaceAll('.', ',')]),
        s(room.width / 2, room.island == null ? room.depth / 2 : room.depth - 500),
        size: 13, color: _grey);
  }

  void _dashedPath(Canvas c, Path path, Paint paint) {
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 9 * u) {
        c.drawPath(m.extractPath(d, math.min(m.length, d + 5 * u)), paint);
      }
    }
  }

  /// Évier, plaque de cuisson, lave-vaisselle : symboles normalisés en vue de dessus.
  void _symbols(Canvas c, PlanShape sh, Offset Function(double, double) s, double k) {
    final it = p.byUid(sh.uid)!;
    final w = p.room.wall(it.wallId);
    Offset at(double ss, double tt) {
      final q = w.toPlan(ss, tt);
      return s(q.$1, q.$2);
    }

    switch (sh.model.id) {
      case 'base_sink':
        final bw = math.min(it.width - 140.0, 760.0);
        final s0 = it.s + (it.width - bw) / 2;
        final r = Rect.fromPoints(at(s0, 90), at(s0 + bw, 480));
        c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(40 * k)), _line(0.9));
        c.drawCircle(r.center, 22 * k, _line(0.8));
        c.drawCircle(at(it.s + it.width / 2, 50), 15 * k, _line(0.8));
      case 'base_cooktop_oven':
        final r = Rect.fromPoints(at(it.s + 40, 60), at(it.right - 40, 540));
        c.drawRect(r, _line(0.9));
        for (final (fs, ft, rad) in [(0.28, 0.3, 95.0), (0.72, 0.3, 75.0), (0.28, 0.72, 75.0), (0.72, 0.72, 95.0)]) {
          c.drawCircle(Offset(r.left + r.width * fs, r.top + r.height * ft), rad * k, _line(0.7));
        }
      case 'base_integrated_dishwasher_door':
        _text(c, tr('LV'), (at(it.s, 0) + at(it.right, it.depth.toDouble())) / 2 + const Offset(0, 0), size: 7, color: _grey);
      case 'tall_integrated_fridge':
        _snowflake(c, (at(it.s, 0) + at(it.right, it.depth.toDouble())) / 2, 9 * u);
    }
  }

  void _snowflake(Canvas c, Offset center, double r) {
    for (var i = 0; i < 3; i++) {
      final a = math.pi / 3 * i;
      final d = Offset(math.cos(a), math.sin(a)) * r;
      c.drawLine(center - d, center + d, _line(0.8));
    }
  }

  // ---------------------------------------------------------------- plan de face

  void paintElevation(Canvas c, Size size, String wallId) {
    u = size.width / 1400;
    final room = p.room;
    final std = p.standards;
    final w = room.wall(wallId);
    final len = w.length, h = room.height;
    final ml = 130 * u, mr = 110 * u, mt = 90 * u, mb = 150 * u;
    final k = math.min((size.width - ml - mr) / len, (size.height - mt - mb) / h);
    final ox = ml + ((size.width - ml - mr) - len * k) / 2;
    final oy = mt + ((size.height - mt - mb) + h * k) / 2; // y écran du sol
    Offset s(double a, double z) => Offset(ox + a * k, oy - z * k);
    Rect r(double a0, double z0, double a1, double z1) => Rect.fromPoints(s(a0, z0), s(a1, z1));

    // mur, plafond, sol
    c.drawRect(r(0, 0, len, h), _line(0.6, _grey));
    _dashed(c, s(-200, h), s(len + 200, h), _line(0.6, _grey));
    c.drawLine(s(-250, 0), s(len + 250, 0), _line(2.2));

    // ouvertures
    for (final o in p.openings.where((o) => o.wallId == wallId)) {
      final rr = r(o.s, o.z, o.right, o.z + o.height);
      c.drawRect(rr, Paint()..color = Colors.white);
      paintOpeningElevation(c, rr, openingModelOf(o), door: o.isDoor, hinge: o.hinge, k: k);
      _text(c, openingName(o), Offset(rr.center.dx, rr.top - 12 * u), size: 8.5, color: _grey, bg: Colors.white);
    }

    final rects = e.elevation(wallId);

    // éléments des murs voisins vus de profil : hachurés
    for (final x in rects.where((x) => !x.onThisWall)) {
      final rr = r(x.s0, x.z0, x.s1, x.z1);
      c.save();
      c.clipRect(rr);
      for (var d = -rr.height; d < rr.width; d += 10 * u) {
        c.drawLine(Offset(rr.left + d, rr.bottom), Offset(rr.left + d + rr.height, rr.top), _line(0.4, _grey));
      }
      c.restore();
      c.drawRect(rr, _line(0.8, _grey));
    }

    final mine = rects.where((x) => x.onThisWall).toList();

    // plinthes et plan de travail
    for (final x in mine.where((x) => x.model.floorSupport && x.z0 > 0)) {
      final rr = r(x.s0, 0, x.s1, x.z0);
      c.drawRect(rr, Paint()..color = _light);
      c.drawRect(rr, _line(0.6));
    }
    for (final (a, b) in e.runs(wallId, (m) => e.kitchen && m.kind.isLow)) {
      final rr = r(a, std.baseTop.toDouble(), b, std.worktopTop.toDouble());
      c.drawRect(rr, Paint()..color = _light);
      c.drawRect(rr, _line(1.0));
    }

    // caissons avec façades
    for (final x in mine) {
      final it = p.byUid(x.uid)!;
      final rr = r(x.s0, x.z0, x.s1, x.z1);
      paintFront(c, rr, x.model,
          fill: Colors.white,
          stroke: _ink,
          line: _grey,
          opening: it.opening,
          variant: it.variant,
          strokeWidth: 1.5 * u,
          handle: p.style.handle);
      _frontSymbols(c, x, rr, k);
    }
    // vides à combler : hachures orange et largeur
    for (final g in e.gaps().where((g) => g.wallId == wallId)) {
      final (z0, z1) = g.band == Band.low
          ? (std.plinthHeight.toDouble(), std.baseTop.toDouble())
          : (std.wallBottomDefault.toDouble(), std.wallBottomDefault + 700.0);
      final rr = r(g.s0, z0, g.s1, z1);
      c.save();
      c.clipRect(rr);
      for (var d = -rr.height; d < rr.width + rr.height; d += 7 * u) {
        c.drawLine(Offset(rr.left + d, rr.bottom), Offset(rr.left + d + rr.height, rr.top), _line(0.6, _repere));
      }
      c.restore();
      c.drawRect(rr, _line(1.0, _repere));
      if (g.fillable) {
        _text(c, trp('fileur {0}', [g.width.round()]), Offset(rr.center.dx, rr.top - 12 * u),
            size: 9.5, color: _repere, weight: FontWeight.w700, bg: Colors.white);
      }
    }
    for (final x in mine) {
      final rr = r(x.s0, x.z0, x.s1, x.z1);
      _repereTag(c, x.uid, rr.center + Offset(0, rr.height > 60 * u ? -rr.height * 0.18 : 0), size: 10);
    }
    // sanitaires et objets dos à ce mur : contour, nom, cote d'axe depuis le départ du mur
    for (final o in p.objects) {
      final (wid, a, b) = objectOnWall(room, o);
      if (wid != wallId) continue;
      final rr = r(a, o.z, b, o.z + o.h);
      final f = o.fixture;
      if (f == null) {
        _dashedPath(c, Path()..addRect(rr), _line(0.8, _grey));
      } else {
        c.drawRect(rr, Paint()..color = Colors.white);
        c.drawRect(rr, _line(1.1));
      }
      _text(c, objectName(o), rr.center, size: 8.5, color: f == null ? _grey : _ink, weight: FontWeight.w700, bg: Colors.white);
      if (f != null) {
        final axis = (a + b) / 2;
        _text(c, trp('axe {0}', [axis.round()]), Offset(s(axis, 0).dx, s(axis, 0).dy - 10 * u), size: 8, color: _repere, bg: Colors.white);
      }
    }

    // ---- chaînes de cotes
    final low = <double>{0, len};
    for (final x in rects.where((x) => !x.model.kind.isHigh)) {
      low
        ..add(x.s0)
        ..add(x.s1);
    }
    final high = <double>{0, len};
    for (final x in rects.where((x) => x.model.kind.isHigh)) {
      high
        ..add(x.s0)
        ..add(x.s1);
    }
    for (final o in p.openings.where((o) => o.wallId == wallId)) {
      high
        ..add(o.s)
        ..add(o.right);
    }
    const down = Offset(0, 1), up = Offset(0, -1);
    _chain(c, s(0, 0) + Offset(0, 44 * u), s(len, 0) + Offset(0, 44 * u), len, low, side: down);
    _chain(c, s(0, 0) + Offset(0, 92 * u), s(len, 0) + Offset(0, 92 * u), len, [0, len], side: down);
    _text(c, trp('{0}  ·  {1} mm', [w.id == 'I' ? tr('ÎLOT') : trp('MUR {0}', [w.id]), len.round()]), s(len / 2, 0) + Offset(0, 122 * u), size: 12, weight: FontWeight.w800, color: _grey);
    if (high.length > 2) _chain(c, s(0, h) + Offset(0, -40 * u), s(len, h) + Offset(0, -40 * u), len, high, side: up);

    // hauteurs à gauche : sol, plinthe, caisson, plan de travail, bas et haut des meubles hauts, plafond
    final zs = <double>{0, h};
    if (mine.any((x) => x.model.kind.isLow)) {
      zs.addAll([std.plinthHeight.toDouble(), std.baseTop.toDouble(), std.worktopTop.toDouble()]);
    }
    for (final x in mine.where((x) => x.model.kind.isHigh)) {
      zs
        ..add(x.z0)
        ..add(x.z1);
    }
    _chain(c, s(0, 0) + Offset(-44 * u, 0), s(0, h) + Offset(-44 * u, 0), h, zs, side: const Offset(-1, 0));
    _chain(c, s(0, 0) + Offset(-92 * u, 0), s(0, h) + Offset(-92 * u, 0), h, [0, h], side: const Offset(-1, 0));

    // à droite : colonnes et ouvertures
    final zr = <double>{0, h};
    for (final x in mine.where((x) => x.model.kind == CabinetKind.tall)) {
      zr.add(x.z1);
    }
    for (final o in p.openings.where((o) => o.wallId == wallId)) {
      zr
        ..add(o.z)
        ..add(o.z + o.height);
    }
    if (zr.length > 2) {
      _chain(c, s(len, 0) + Offset(44 * u, 0), s(len, h) + Offset(44 * u, 0), h, zr, side: const Offset(1, 0));
    }
  }

  /// Symboles en vue de face : frigo, plaque et robinet sur le plan de travail, lave-vaisselle, hotte.
  void _frontSymbols(Canvas c, ElevationRect x, Rect rr, double k) {
    final std = p.standards;
    final topY = rr.top - std.worktopThickness * k; // dessus du plan de travail
    switch (x.model.id) {
      case 'tall_integrated_fridge':
        _snowflake(c, Offset(rr.center.dx, rr.top + rr.height * 0.18), 16 * u);
      case 'base_cooktop_oven':
        c.drawRect(Rect.fromLTWH(rr.left + 40 * k, topY - 8 * k, rr.width - 80 * k, 8 * k), Paint()..color = _ink);
        for (var i = 0; i < 4; i++) {
          c.drawCircle(Offset(rr.left + rr.width * (0.2 + i * 0.2), rr.top + 35 * k), 12 * k, _line(0.8));
        }
      case 'base_sink':
        final cx = rr.center.dx;
        final path = Path()
          ..moveTo(cx, topY)
          ..lineTo(cx, topY - 300 * k)
          ..quadraticBezierTo(cx, topY - 360 * k, cx + 70 * k, topY - 360 * k)
          ..lineTo(cx + 120 * k, topY - 330 * k);
        c.drawPath(path, _line(1.6));
      case 'base_integrated_dishwasher_door':
        _text(c, tr('LV'), rr.center, size: 13, color: _grey, weight: FontWeight.w800);
      case 'wall_integrated_hood':
        final hood = Path()
          ..moveTo(rr.left + 30 * k, rr.bottom)
          ..lineTo(rr.right - 30 * k, rr.bottom)
          ..lineTo(rr.right - 60 * k, rr.bottom + 60 * k)
          ..lineTo(rr.left + 60 * k, rr.bottom + 60 * k)
          ..close();
        c.drawPath(hood, Paint()..color = _light);
        c.drawPath(hood, _line(1.0));
    }
  }

  // ---------------------------------------------------------------- vue 3D (couverture)

  /// Plan de face des réseaux : le mur (estompé) et ses points cotés (position et hauteur).
  void paintNetworks(Canvas c, Size size, String wallId) {
    paintElevation(c, size, wallId);
    c.drawRect(Offset.zero & size, Paint()..color = Colors.white.withValues(alpha: 0.62));
    u = size.width / 1400;
    final room = p.room;
    final len = wallId == 'I' ? (room.island?.length ?? 0) : room.wall(wallId).length;
    final h = room.height;
    final ml = 130 * u, mr = 110 * u, mt = 90 * u, mb = 150 * u;
    final k = math.min((size.width - ml - mr) / len, (size.height - mt - mb) / h);
    final ox = ml + ((size.width - ml - mr) - len * k) / 2;
    final oy = mt + ((size.height - mt - mb) + h * k) / 2;
    Offset s(double a, double z) => Offset(ox + a * k, oy - z * k);
    final pts = visiblePoints(p).where((x) => x.wallId == wallId).toList()..sort((a, b) => a.s.compareTo(b.s));
    if (pts.isEmpty) return;
    final r = 15 * u;
    // repères verticaux discrets jusqu'au sol
    for (final x in pts) {
      _dashed(c, s(x.s, 0), s(x.s, x.z), _line(0.5, netColor(x.kind).withValues(alpha: 0.6)));
    }
    for (final x in pts) {
      paintNetSymbol(c, s(x.s, x.z), x.kind, r);
      _text(c, trp('h {0}', [x.z.round()]), s(x.s, x.z) + Offset(0, r + 9 * u), size: 8.5, color: netColor(x.kind), weight: FontWeight.w800, bg: Colors.white);
    }
    // chaîne de cotes des positions, au-dessus du mur
    _chain(c, s(0, h) + Offset(0, -62 * u), s(len, h) + Offset(0, -62 * u), len, [0, len, ...pts.map((x) => x.s)], side: const Offset(0, -1));
  }

  void paint3d(Canvas c, Size size, double yaw) {
    final cam = Camera3d.fit(p.room, yaw, size);
    Scene3dPainter(e, cam, selectColor: _repere, background: Colors.white).paint(c, size);
  }
}

/// Rend un dessin en PNG (fond blanc) à la taille donnée.
Future<Uint8List> renderPng(Size size, void Function(Canvas c, Size s) draw) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(Offset.zero & size, Paint()..color = Colors.white);
  draw(c, size);
  final img = await rec.endRecording().toImage(size.width.round(), size.height.round());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return data!.buffer.asUint8List();
}

/// Murs à dessiner en plan de face : ceux qui portent au moins un élément ou une ouverture.
List<String> wallsToDraw(LayoutEngine e) => [
      for (final id in e.project.room.runIds)
        if (e.project.items.any((c) => e.boxesOf(c).any((b) => b.wallId == id)) ||
            e.project.openings.any((o) => o.wallId == id))
          id
    ];

/// Teinte de façade (pour la légende du PDF).
String finishSummary(Project p) =>
    'Façades ${frontFinish(p.style, p.style.front).name.toLowerCase()} · plan de travail ${worktopFinish(p.style, p.style.worktop).name.toLowerCase()} · '
    '${handleName(p.style).toLowerCase()}';
