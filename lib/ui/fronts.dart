// Dessin des façades (vue de face) : portes, poignées, tiroirs, niches, vitrines, appareils...
// Deux rendus avec la même géométrie :
// - trait (vignettes du menu, plans techniques) ;
// - réaliste (vue de face de l'éditeur et 3D) : texture, jeux entre portes, reliefs, poignées inox,
//   four / micro-ondes / réfrigérateur, intérieur des niches.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/engine.dart';
import 'finishes.dart';

/// Cases de façade d'un caisson posé : sa composition, ou celle reconstituée pour les appareils
/// en rendu réaliste (four, micro-ondes). null = dessin standard du modèle.
List<FrontCell>? frontCells(CabinetModel m, PlacedCabinet c, {bool realistic = false}) {
  final rows = rowsOf(m, c);
  if (rows != null) return cellsOf(rows, c.height);
  if (realistic && (m.id == 'base_cooktop_oven' || m.id == 'tall_oven_microwave')) return cellsOf(seedRows(m, c), c.height);
  return null;
}

/// Poignée en relief sur une façade : centre (mm depuis le coin haut gauche), longueur, taille, couleur.
class GripSpec {
  final String kind;
  final double x, y, len, size;
  final bool vertical;
  final Color color;
  const GripSpec(this.kind, this.x, this.y, this.vertical, this.len, this.size, this.color);
  Map<String, dynamic> toJson() => {'k': kind, 'x': x, 'y': y, 'v': vertical, 'len': len, 'size': size, 'c': color.toARGB32() & 0xFFFFFF};
}

void paintFront(
  Canvas canvas,
  Rect r,
  CabinetModel m, {
  required Color fill,
  required Color stroke,
  required Color line,
  String? opening,
  String? variant,
  double strokeWidth = 1.2,
  String handle = 'bar',
  Paint? fillPaint,
  List<FrontCell>? cells,
  bool realistic = false,
  double? pxPerMm,
  List<String> appliances = const [],
  Color carcass = const Color(0xFFF2F1EE),
  bool gloss = false,
  double handleSize = 160, // entraxe, longueur ou diamètre de la poignée (mm)
  Color handleColor = const Color(0xFFB4B9BF),
  bool tallXxl = false, // barres XXL sur les portes de colonne
  bool? handleTop, // force la position de la poignée (haut ou bas de porte)
  HandleSet? handles, // poignées des portes et des tiroirs (remplace handle, handleSize, handleColor)
  void Function(GripSpec g)? onGrip, // poignées en relief (3D) : signalées au lieu d'être peintes
  String profile = 'lisse', // modèle de façade (voir frontProfiles)
  bool golaProfile = true, // faux : façade seule (porte ouverte en 3D), le profil Gola reste sur le caisson
}) {
  var orient = 'auto', place = 'auto';
  var pair = false;
  if (handles != null) {
    handle = handles.door.kind;
    handleSize = handles.door.size;
    handleColor = handles.door.color;
    orient = handles.door.orient;
    place = handles.door.pos;
    pair = handles.door.pair;
  }
  final u = pxPerMm ?? r.height / math.max(1, m.defaultHeight); // pixels par mm
  final body = fillPaint ?? (Paint()..color = fill);
  final edge = Paint()
    ..color = stroke
    ..style = PaintingStyle.stroke
    ..strokeWidth = strokeWidth;
  final ln = Paint()
    ..color = line
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(0.8, strokeWidth * 0.8);
  canvas.drawRect(r, body);
  if (!realistic) canvas.drawRect(r, edge);
  if (r.width < 6 || r.height < 6) return;

  final inset = realistic ? 1.5 * u : math.min(r.shortestSide * 0.06, 6.0);
  final f = r.deflate(inset);
  final hl = math.max(4.0, math.min(f.height, f.width) * 0.18); // longueur de poignée (trait)
  final isHigh = m.kind.isHigh;

  // ---------------------------------------------------------------- poignées
  final steel = Paint()..color = handleColor;
  final steelHi = Paint()..color = Color.lerp(handleColor, Colors.white, 0.7)!;
  final drop = Paint()..color = Colors.black.withValues(alpha: 0.22);
  final hole = Paint()..color = Color.lerp(handleColor, Colors.black, 0.75)!;
  const edgeTypes = {'edge', 'edgeFull', 'jProfile', 'groove', 'chamfer'};

  /// Passe à la poignée des portes ou des tiroirs.
  void use(HandleLook? l) {
    if (l == null) return;
    handle = l.kind;
    handleSize = l.size;
    handleColor = l.color;
    orient = l.orient;
    place = l.pos;
    pair = l.pair;
    steel.color = handleColor;
    steelHi.color = Color.lerp(handleColor, Colors.white, 0.7)!;
    hole.color = Color.lerp(handleColor, Colors.black, 0.75)!;
  }

  bool relief(String kind, Offset c, bool vertical, double len, double size) {
    if (onGrip == null || !const {'bar', 'xxl', 'knob', 'cup', 'leather', 'edge', 'edgeFull', 'jProfile'}.contains(kind)) return false;
    onGrip(GripSpec(kind, (c.dx - r.left) / u, (c.dy - r.top) / u, vertical, len / u, size, handleColor));
    return true;
  }

  void barReal(Offset c, bool vertical, double maxLen, {double? lengthMm, double thickMm = 12, bool appliance = false}) {
    final len = math.min((lengthMm ?? (handleSize > 60 ? handleSize + 30 : 160)) * u, maxLen * 0.8);
    final th = math.max(1.6, thickMm * u);
    final rr = RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: vertical ? th : len, height: vertical ? len : th), Radius.circular(th / 2));
    canvas.drawRRect(rr.shift(Offset(th * 0.25, th * 0.35)), drop);
    canvas.drawRRect(rr, appliance ? (Paint()..color = const Color(0xFFB4B9BF)) : steel);
    final hi = vertical
        ? Rect.fromLTWH(rr.left + th * 0.2, rr.top + th * 0.3, th * 0.25, len - th * 0.6)
        : Rect.fromLTWH(rr.left + th * 0.3, rr.top + th * 0.2, len - th * 0.6, th * 0.25);
    canvas.drawRect(hi, appliance ? (Paint()..color = const Color(0xFFF2F4F6)) : steelHi);
  }

  void knobReal(Offset c) {
    final rad = math.max(1.6, (handleSize > 10 && handleSize < 60 ? handleSize / 2 : 15) * u);
    canvas.drawCircle(c + Offset(rad * 0.2, rad * 0.3), rad, drop);
    canvas.drawCircle(c, rad, steel);
    canvas.drawCircle(c - Offset(rad * 0.3, rad * 0.3), rad * 0.35, steelHi);
  }

  /// Poignée ponctuelle (barre, bouton, coquille, cuir, cuvette...) centrée en [c].
  void pointGrip(Offset c, bool vertical, double maxLen, {String? as}) {
    final kind = as ?? handle;
    if (kind == 'push' || kind == 'gola') return;
    final shown = const {'bar', 'xxl', 'knob', 'cup', 'leather', 'recess', 'recessRound', 'pocket'}.contains(kind) ? kind : 'bar';
    final barLen = math.min((kind == 'xxl' ? handleSize + 100 : (handleSize > 60 ? handleSize + 30 : 160)) * u, (kind == 'xxl' ? maxLen * 1.6 : maxLen) * 0.8);
    if (relief(shown, c, vertical, shown == 'bar' || shown == 'xxl' ? barLen : 0, handleSize)) return;
    switch (kind) {
      case 'knob':
        knobReal(c);
      case 'xxl':
        barReal(c, true, maxLen * 1.6, lengthMm: handleSize + 100, thickMm: 18);
      case 'cup':
        final r0 = Rect.fromCenter(center: c, width: 95 * u, height: 40 * u);
        canvas.drawRRect(RRect.fromRectAndRadius(r0.shift(Offset(0, 2 * u)), Radius.circular(20 * u)), drop);
        canvas.drawRRect(RRect.fromRectAndCorners(r0, bottomLeft: Radius.circular(40 * u), bottomRight: Radius.circular(40 * u), topLeft: Radius.circular(6 * u), topRight: Radius.circular(6 * u)), steel);
        canvas.drawRect(Rect.fromLTWH(r0.left + 8 * u, r0.top + 6 * u, r0.width - 16 * u, 8 * u), hole);
      case 'leather':
        final r0 = Rect.fromCenter(center: c + Offset(0, 22 * u), width: 25 * u, height: 70 * u);
        canvas.drawRRect(RRect.fromRectAndRadius(r0.shift(Offset(2 * u, 3 * u)), Radius.circular(10 * u)), drop);
        canvas.drawRRect(RRect.fromRectAndRadius(r0, Radius.circular(10 * u)), steel);
        canvas.drawCircle(Offset(c.dx, r0.top + 10 * u), 4 * u, Paint()..color = const Color(0xFFC9A54C));
      case 'recess':
        final r0 = Rect.fromCenter(center: c, width: (vertical ? 40 : 120) * u, height: (vertical ? 120 : 40) * u);
        canvas.drawRRect(RRect.fromRectAndRadius(r0, Radius.circular(4 * u)), steel);
        canvas.drawRRect(RRect.fromRectAndRadius(r0.deflate(4 * u), Radius.circular(3 * u)), hole);
      case 'recessRound':
        canvas.drawCircle(c, 25 * u, steel);
        canvas.drawCircle(c, 20 * u, hole);
      case 'pocket':
        final r0 = Rect.fromCenter(center: c, width: (vertical ? 30 : 120) * u, height: (vertical ? 120 : 30) * u);
        canvas.drawRRect(RRect.fromRectAndRadius(r0, Radius.circular(15 * u)), Paint()..color = Colors.black.withValues(alpha: 0.45));
      default:
        barReal(c, vertical, maxLen);
    }
  }

  /// Poignée sur le chant (profil, gorge usinée, biseau) le long du bord haut ou bas de [d].
  void edgeGrip(Rect d, bool top, {bool? hingeLeft}) {
    final full = handle != 'edge';
    final len = full ? d.width : math.min(handleSize * u, d.width - 24 * u);
    final th = switch (handle) { 'groove' => 28.0, 'chamfer' => 12.0, 'jProfile' => 18.0, _ => 12.0 } * u;
    final double x0;
    if (full) {
      x0 = d.left;
    } else if (hingeLeft != null) {
      // Sur une porte battante, la poignée individuelle est placée du côté ouverture (opposé aux charnières)
      x0 = hingeLeft ? d.right - len - 16 * u : d.left + 16 * u;
    } else {
      // Sur un tiroir ou abattant, la poignée est centrée
      x0 = d.center.dx - len / 2;
    }
    final r0 = Rect.fromLTWH(x0, top ? d.top : d.bottom - th, len, th);
    if (relief(handle, r0.center, false, len, handleSize)) return;
    if (!realistic) {
      canvas.drawRect(r0, ln);
      return;
    }
    if (handle == 'groove' || handle == 'chamfer') {
      canvas.drawRect(
          r0,
          Paint()
            ..shader = LinearGradient(
              begin: top ? Alignment.topCenter : Alignment.bottomCenter,
              end: top ? Alignment.bottomCenter : Alignment.topCenter,
              colors: [Colors.black.withValues(alpha: handle == 'groove' ? 0.55 : 0.35), Colors.black.withValues(alpha: 0.05)],
            ).createShader(r0));
    } else {
      canvas.drawRect(r0, steel);
      canvas.drawRect(Rect.fromLTWH(r0.left, top ? r0.bottom - 1.2 * u : r0.top, r0.width, 1.2 * u), steelHi);
    }
  }

  final knob = Paint()..color = line;
  void handleV(double x, double cy, double maxLen) {
    if (handle == 'gola' || handle == 'push') return;
    if (realistic) {
      pointGrip(Offset(x, cy), true, maxLen);
      return;
    }
    if (handle == 'knob' || handle == 'recessRound') {
      canvas.drawCircle(Offset(x, cy), math.max(1.2, hl * 0.12), knob);
    } else {
      canvas.drawLine(Offset(x, cy - hl / 2), Offset(x, cy + hl / 2), ln);
    }
  }

  void handleH(double cx, double y, double maxLen) {
    if (handle == 'gola' || handle == 'push') return;
    if (realistic) {
      pointGrip(Offset(cx, y), false, maxLen);
      return;
    }
    if (handle == 'knob' || handle == 'recessRound') {
      canvas.drawCircle(Offset(cx, y), math.max(1.2, hl * 0.12), knob);
    } else {
      canvas.drawLine(Offset(cx - hl / 2, y), Offset(cx + hl / 2, y), ln);
    }
  }

  // sans poignée : gorge (rainure profilée) Gola
  if (handle == 'gola' && golaProfile && !m.kind.isFiller && m.isCarcass) {
    if (realistic) {
      final gh = math.max(2.0, 24 * u);
      final golaPaint = Paint()..color = Color.lerp(handleColor, Colors.black, 0.25)!;
      final golaHi = Paint()..color = Colors.white30;
      if (m.kind == CabinetKind.tall) {
        // Colonne haute : gorge horizontale au niveau du plan de travail (séparation des portes)
        final gy = r.bottom - 1300 * u;
        if (gy > r.top && gy < r.bottom) {
          final g = Rect.fromLTWH(r.left, gy - gh / 2, r.width, gh);
          canvas.drawRect(g, golaPaint);
          canvas.drawRect(Rect.fromLTWH(g.left, g.top, g.width, 1), golaHi);
        }
      } else {
        // Meuble bas (gorge en haut sous le plan) ou meuble haut (gorge en bas)
        final g = isHigh ? Rect.fromLTWH(r.left, r.bottom - gh, r.width, gh) : Rect.fromLTWH(r.left, r.top, r.width, gh);
        canvas.drawRect(g, golaPaint);
        canvas.drawRect(Rect.fromLTWH(g.left, isHigh ? g.top : g.bottom - 1, g.width, 1), golaHi);
      }
    } else {
      final gy = isHigh ? r.bottom - inset : r.top + inset;
      canvas.drawLine(Offset(r.left, gy), Offset(r.right, gy), ln);
    }
  }

  // ---------------------------------------------------------------- panneaux (porte, tiroir)
  final gapPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(0.8, 3 * u)
    ..color = Color.lerp(fill, Colors.black, 0.55)!.withValues(alpha: 0.75);
  final bevelLight = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(0.5, 1.4 * u)
    ..color = Colors.white.withValues(alpha: 0.35);
  final bevelDark = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(0.5, 1.4 * u)
    ..color = Colors.black.withValues(alpha: 0.16);

  /// Cadre, moulure ou cannelures de la façade [d].
  void molding(Rect d) {
    if (profile == 'lisse') return;
    final w = d.width / u, h = d.height / u;
    if (profile == 'cannelee') {
      if (h < 100) return;
      final step = 24 * u;
      if (!realistic) {
        for (var x = d.left + step * 2; x < d.right; x += step * 3) {
          canvas.drawLine(Offset(x, d.top), Offset(x, d.bottom), ln);
        }
        return;
      }
      canvas.save();
      canvas.clipRect(d.deflate(2 * u));
      for (var x = d.left; x < d.right; x += step) {
        final r0 = Rect.fromLTWH(x, d.top, step, d.height);
        canvas.drawRect(
            r0,
            Paint()
              ..shader = LinearGradient(colors: [Colors.black.withValues(alpha: 0.20), Colors.white.withValues(alpha: 0.16), Colors.white.withValues(alpha: 0.0), Colors.black.withValues(alpha: 0.12)], stops: const [0, 0.3, 0.65, 1])
                  .createShader(r0));
      }
      canvas.restore();
      return;
    }
    final fw = profileFrame(profile, w, h);
    if (fw == 0) return;
    final inner = d.deflate(fw * u);
    if (!realistic) {
      canvas.drawRect(inner, ln);
      return;
    }
    void bevel(Rect q, double deep) {
      final dark = Paint()
        ..color = Colors.black.withValues(alpha: 0.22 * deep)
        ..strokeWidth = math.max(1, 5 * u);
      final light = Paint()
        ..color = Colors.white.withValues(alpha: 0.4 * deep)
        ..strokeWidth = math.max(1, 4 * u);
      canvas.drawLine(q.topLeft, q.topRight, dark);
      canvas.drawLine(q.topLeft, q.bottomLeft, dark);
      canvas.drawLine(q.bottomLeft, q.bottomRight, light);
      canvas.drawLine(q.topRight, q.bottomRight, light);
    }

    canvas.drawRect(inner, Paint()..color = Colors.black.withValues(alpha: 0.035));
    bevel(inner, 1);
    if (profile == 'mouluree' && inner.shortestSide / u > 120) {
      bevel(inner.deflate(14 * u), 0.6);
      final raised = inner.deflate(40 * u);
      if (raised.width > 20 * u && raised.height > 20 * u) {
        canvas.drawRect(raised, Paint()..color = Colors.white.withValues(alpha: 0.04));
        final p1 = Paint()
          ..color = Colors.white.withValues(alpha: 0.35)
          ..strokeWidth = math.max(1, 3 * u);
        final p2 = Paint()
          ..color = Colors.black.withValues(alpha: 0.16)
          ..strokeWidth = math.max(1, 3 * u);
        canvas.drawLine(raised.topLeft, raised.topRight, p1);
        canvas.drawLine(raised.topLeft, raised.bottomLeft, p1);
        canvas.drawLine(raised.bottomLeft, raised.bottomRight, p2);
        canvas.drawLine(raised.topRight, raised.bottomRight, p2);
      }
    }
  }

  void panel(Rect d) {
    if (!realistic) {
      canvas.drawRect(d, ln);
      molding(d);
      return;
    }
    molding(d);
    canvas.drawRect(d, gapPaint);
    final i = d.deflate(gapPaint.strokeWidth / 2 + bevelLight.strokeWidth / 2);
    canvas.drawLine(i.topLeft, i.topRight, bevelLight);
    canvas.drawLine(i.topLeft, i.bottomLeft, bevelLight);
    canvas.drawLine(i.bottomLeft, i.bottomRight, bevelDark);
    canvas.drawLine(i.topRight, i.bottomRight, bevelDark);
    if (gloss) {
      canvas.save();
      canvas.clipRect(i);
      canvas.drawRect(
          i,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white.withValues(alpha: 0.0), Colors.white.withValues(alpha: 0.22), Colors.white.withValues(alpha: 0.0)],
              stops: const [0.25, 0.42, 0.6],
            ).createShader(i));
      canvas.restore();
    }
  }

  void door(Rect d, {required bool hingeLeft, bool handleTop = false}) {
    final dReal = (handle == 'gola' && golaProfile && !isHigh && m.kind != CabinetKind.tall)
        ? Rect.fromLTRB(d.left, d.top + 30 * u, d.right, d.bottom)
        : d;
    panel(dReal);
    if (handle == 'gola' || handle == 'push') return; // sans poignée : rien sur la porte
    if (tallXxl && realistic && m.kind == CabinetKind.tall && dReal.height / u > 1200) {
      final x = hingeLeft ? dReal.right - math.min(50 * u, dReal.width * 0.15) : dReal.left + math.min(50 * u, dReal.width * 0.15);
      pointGrip(Offset(x, dReal.bottom - 950 * u), true, dReal.height, as: 'xxl');
      return;
    }
    if (edgeTypes.contains(handle)) {
      if (m.kind == CabinetKind.tall && dReal.height / u > 1200) {
        // Sur grande colonne, poignée sur chant verticale à hauteur ergonomique de main (1050 mm)
        final x = hingeLeft ? dReal.right - 14 * u : dReal.left;
        final hlen = math.min(handleSize * u, 240 * u);
        final rGrip = Rect.fromLTWH(x, dReal.bottom - 1050 * u - hlen / 2, 14 * u, hlen);
        if (relief(handle, rGrip.center, true, hlen, handleSize)) return;
        canvas.drawRect(rGrip, steel);
        canvas.drawRect(Rect.fromLTWH(hingeLeft ? rGrip.left : rGrip.right - 1.2 * u, rGrip.top, 1.2 * u, rGrip.height), steelHi);
      } else {
        edgeGrip(dReal, handleTop, hingeLeft: hingeLeft);
      }
      return;
    }
    // Marge minimale latérale pour éviter que les coquilles ou boutons ne débordent de la façade
    final margin = (handle == 'cup' ? 58.0 : 45.0) * u;
    final x = realistic
        ? (hingeLeft
            ? dReal.right - math.max(margin, math.min(75 * u, dReal.width * 0.16))
            : dReal.left + math.max(margin, math.min(75 * u, dReal.width * 0.16)))
        : (hingeLeft ? dReal.right - dReal.width * 0.12 : dReal.left + dReal.width * 0.12);
    final off = realistic ? math.min(130 * u, dReal.height * 0.3) : dReal.height * 0.15;
    var cy = handleTop ? dReal.top + off : dReal.bottom - off;
    // porte de grande hauteur : poignée à hauteur de main (≈ 1050 mm du sol)
    if (dReal.height / u > 1200 && m.kind == CabinetKind.tall) cy = math.max(dReal.top + off, dReal.bottom - 950 * u);
    if (place == 'centre' && dReal.height / u <= 1200) cy = dReal.center.dy;
    final alongTop = orient == 'h' && const {'bar', 'cup', 'recess', 'pocket', 'xxl'}.contains(handle);
    if (alongTop || handle == 'cup') {
      // poignée horizontale : centrée sur la porte, à 60 mm du bord haut (bas) ou 50 mm du bas (haut)
      final edge = realistic ? math.min(60 * u, dReal.height * 0.2) : dReal.height * 0.12;
      final tallDoor = dReal.height / u > 1200 && m.kind == CabinetKind.tall;
      final y = place == 'centre' && !tallDoor ? dReal.center.dy : (tallDoor ? cy : (handleTop ? dReal.top + edge : dReal.bottom - edge));
      handleH(place == 'centre' || orient == 'h' ? dReal.center.dx : x, y, dReal.width);
      return;
    }
    handleV(x, cy, math.min(dReal.height, 900 * u));
  }

  void drawers(Rect d, List<double> ratios) {
    use(handles?.drawer);
    var y = d.top;
    final total = ratios.fold<double>(0, (a, b) => a + b);
    for (var idx = 0; idx < ratios.length; idx++) {
      final k = ratios[idx];
      final h = d.height * k / total;
      final isGola = handle == 'gola';
      final dr = Rect.fromLTWH(d.left, y + (isGola && idx > 0 ? 12 * u : 0), d.width, h - (isGola && idx > 0 ? 12 * u : 0)).deflate(realistic ? 0 : 1);
      panel(dr);
      if (isGola) {
        if (realistic && golaProfile && idx > 0) {
          // Gorge intermédiaire Gola (profil C) entre tiroirs
          final gh = math.max(2.0, 14 * u);
          final gola = Rect.fromLTWH(d.left, y - gh / 2, d.width, gh);
          canvas.drawRect(gola, Paint()..color = Color.lerp(handleColor, Colors.black, 0.25)!);
          canvas.drawRect(Rect.fromLTWH(gola.left, gola.bottom - 1, gola.width, 1), Paint()..color = Colors.white24);
        }
        y += h;
        continue;
      }
      if (edgeTypes.contains(handle)) {
        edgeGrip(dr, true);
        y += h;
        continue;
      }
      // tiroir à cadre : coquille et bouton au milieu de la traverse haute
      final rail = profileFrame(profile, dr.width / u, dr.height / u);
      final hy = place == 'centre' ? dr.center.dy : realistic && rail > 40 && const {'cup', 'knob'}.contains(handle) ? dr.top + rail * u * 0.5 : (realistic ? dr.top + math.min(55 * u, dr.height * 0.3) : dr.top + math.min(dr.height * 0.25, 10));
      if (pair && dr.width / u >= 780) {
        handleH(dr.left + dr.width * 0.25, hy, dr.width / 2);
        handleH(dr.left + dr.width * 0.75, hy, dr.width / 2);
      } else {
        handleH(dr.center.dx, hy, dr.width);
      }
      y += h;
    }
    use(handles?.door);
  }

  // ---------------------------------------------------------------- niches, vitrines, appareils
  void openNiche(Rect d, {bool wine = false}) {
    if (!realistic) {
      canvas.drawRect(d, ln);
      final shelves = (d.height / u / 350).floor();
      for (var k = 1; k <= shelves; k++) {
        final y = d.top + d.height * k / (shelves + 1);
        canvas.drawLine(Offset(d.left, y), Offset(d.right, y), ln);
      }
      return;
    }
    final t = 18 * u; // épaisseur des côtés visibles
    canvas.drawRect(d, Paint()..color = carcass);
    final inner = Rect.fromLTRB(d.left + t, d.top + t, d.right - t, d.bottom - t);
    if (inner.width <= 0 || inner.height <= 0) return;
    canvas.drawRect(inner, Paint()..color = Color.lerp(carcass, Colors.black, 0.22)!);
    // ombre portée en haut et sur la gauche de l'intérieur
    canvas.drawRect(
        inner,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withValues(alpha: 0.32), Colors.transparent],
            stops: const [0, 0.35],
          ).createShader(inner));
    if (wine) {
      final lat = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, 10 * u)
        ..color = carcass;
      canvas.save();
      canvas.clipRect(inner);
      final step = 110 * u;
      for (var x = inner.left - inner.height; x < inner.right; x += step) {
        canvas.drawLine(Offset(x, inner.bottom), Offset(x + inner.height, inner.top), lat);
        canvas.drawLine(Offset(x, inner.top), Offset(x + inner.height, inner.bottom), lat);
      }
      canvas.restore();
      return;
    }
    final shelves = (inner.height / u / 350).floor();
    for (var k = 1; k <= shelves; k++) {
      final y = inner.top + inner.height * k / (shelves + 1);
      final sh = Rect.fromLTWH(inner.left, y, inner.width, t);
      canvas.drawRect(sh.shift(Offset(0, t)), Paint()..color = Colors.black.withValues(alpha: 0.18));
      canvas.drawRect(sh, Paint()..color = carcass);
    }
  }

  void glassDoor(Rect d, {required bool hingeLeft, bool handleTop = false}) {
    panel(d);
    final fw = math.max(2.0, 60 * u);
    final g = d.deflate(fw);
    if (g.width <= 0 || g.height <= 0) {
      door(d, hingeLeft: hingeLeft, handleTop: handleTop);
      return;
    }
    if (realistic) {
      canvas.drawRect(g, Paint()..color = Color.lerp(carcass, Colors.black, 0.18)!);
      final shelves = (g.height / u / 330).floor();
      for (var k = 1; k <= shelves; k++) {
        final y = g.top + g.height * k / (shelves + 1);
        canvas.drawRect(Rect.fromLTWH(g.left, y, g.width, 6 * u), Paint()..color = carcass.withValues(alpha: 0.85));
      }
      canvas.drawRect(g, Paint()..color = const Color(0xFFB7CCD6).withValues(alpha: 0.42));
      canvas.drawRect(
          g,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white.withValues(alpha: 0.05), Colors.white.withValues(alpha: 0.38), Colors.white.withValues(alpha: 0.05)],
              stops: const [0.2, 0.45, 0.7],
            ).createShader(g));
      canvas.drawRect(g, bevelDark);
      if (profile == 'shaker' || profile == 'mouluree') {
        final bar = Paint()..color = fill;
        final nx = g.width / u > 300 ? 2 : 1, ny = (g.height / u / 280).round().clamp(1, 6);
        for (var k = 1; k < nx; k++) {
          canvas.drawRect(Rect.fromLTWH(g.left + g.width * k / nx - 9 * u, g.top, 18 * u, g.height), bar);
        }
        for (var k = 1; k < ny; k++) {
          canvas.drawRect(Rect.fromLTWH(g.left, g.top + g.height * k / ny - 9 * u, g.width, 18 * u), bar);
        }
      }
    } else {
      canvas.drawRect(g, ln);
      canvas.drawLine(g.topLeft + Offset(g.width * 0.2, g.height * 0.15), g.topLeft + Offset(g.width * 0.45, g.height * 0.05), ln);
      canvas.drawLine(g.topLeft + Offset(g.width * 0.2, g.height * 0.3), g.topLeft + Offset(g.width * 0.65, g.height * 0.1), ln);
    }
    final x = hingeLeft ? d.right - fw / 2 : d.left + fw / 2;
    final off = realistic ? math.min(130 * u, d.height * 0.3) : d.height * 0.15;
    handleV(x, handleTop ? d.top + off : d.bottom - off, d.height);
  }


  final glassBlack = Paint()..color = const Color(0xFF17191C);
  void reflection(Rect g) {
    canvas.drawRect(
        g,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white.withValues(alpha: 0.0), Colors.white.withValues(alpha: 0.16), Colors.white.withValues(alpha: 0.0)],
            stops: const [0.2, 0.4, 0.62],
          ).createShader(g));
  }

  void washer(Rect d) {
    // carrosserie blanche, bandeau de commande, hublot
    final body = d.deflate(4 * u);
    canvas.drawRRect(RRect.fromRectAndRadius(body, Radius.circular(10 * u)), Paint()..color = const Color(0xFFF4F5F6));
    canvas.drawRRect(RRect.fromRectAndRadius(body, Radius.circular(10 * u)), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, 2 * u)
      ..color = const Color(0xFFB8BDC2));
    final band = Rect.fromLTWH(body.left, body.top, body.width, math.min(body.height * 0.16, 110 * u));
    canvas.drawLine(band.bottomLeft, band.bottomRight, Paint()
      ..color = const Color(0xFFC9CDD1)
      ..strokeWidth = math.max(1, 2 * u));
    canvas.drawRect(Rect.fromLTWH(band.left + 20 * u, band.top + band.height * 0.3, band.width * 0.35, band.height * 0.4), Paint()..color = const Color(0xFFDDE1E5));
    canvas.drawCircle(Offset(band.right - band.width * 0.22, band.center.dy), band.height * 0.28, Paint()..color = const Color(0xFFB0B5BA));
    final rest = Rect.fromLTRB(body.left, band.bottom, body.right, body.bottom);
    final rad = math.min(rest.width, rest.height) * 0.36;
    final cen = Offset(rest.center.dx, rest.top + rest.height * 0.47);
    canvas.drawCircle(cen, rad, Paint()..color = const Color(0xFFAEB4BA));
    canvas.drawCircle(cen, rad * 0.8, Paint()..color = const Color(0xFF3A4048));
    canvas.drawCircle(cen.translate(-rad * 0.25, -rad * 0.25), rad * 0.22, Paint()..color = const Color(0x33FFFFFF));
  }

  void oven(Rect d) {
    canvas.drawRect(d, Paint()..color = const Color(0xFF2A2D31));
    final band = Rect.fromLTWH(d.left, d.top, d.width, math.min(d.height * 0.16, 90 * u));
    canvas.drawRect(band, Paint()..color = const Color(0xFFBFC4C9));
    for (final k in [0.18, 0.82]) {
      canvas.drawCircle(Offset(band.left + band.width * k, band.center.dy), band.height * 0.28, Paint()..color = const Color(0xFF6E7378));
    }
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: band.center, width: band.width * 0.22, height: band.height * 0.42), Radius.circular(2 * u)),
        Paint()..color = const Color(0xFF101214));
    final g = Rect.fromLTRB(d.left + d.width * 0.08, band.bottom + d.height * 0.14, d.right - d.width * 0.08, d.bottom - d.height * 0.08);
    canvas.drawRect(g, glassBlack);
    reflection(g);
    barReal(Offset(d.center.dx, band.bottom + d.height * 0.07), false, d.width * 1.4, lengthMm: d.width / u * 0.75, appliance: true);
  }

  void microwave(Rect d) {
    canvas.drawRect(d, Paint()..color = const Color(0xFF2A2D31));
    final g = Rect.fromLTRB(d.left + d.width * 0.05, d.top + d.height * 0.1, d.left + d.width * 0.72, d.bottom - d.height * 0.1);
    canvas.drawRect(g, glassBlack);
    reflection(g);
    final pnl = Rect.fromLTRB(d.left + d.width * 0.76, d.top + d.height * 0.1, d.right - d.width * 0.04, d.bottom - d.height * 0.1);
    canvas.drawRect(pnl, Paint()..color = const Color(0xFFBFC4C9));
    canvas.drawRect(Rect.fromLTWH(pnl.left + pnl.width * 0.15, pnl.top + pnl.height * 0.1, pnl.width * 0.7, pnl.height * 0.16), glassBlack);
    for (var k = 0; k < 3; k++) {
      canvas.drawCircle(Offset(pnl.center.dx, pnl.top + pnl.height * (0.45 + k * 0.17)), pnl.width * 0.14, Paint()..color = const Color(0xFF7B8085));
    }
  }

  void fridge(Rect d) {
    final split = d.top + d.height * 0.62;
    final st = Paint()
      ..shader = LinearGradient(colors: const [Color(0xFFD3D7DB), Color(0xFFAEB3B8), Color(0xFFCDD1D5)], stops: const [0, 0.55, 1])
          .createShader(d);
    for (final dd in [Rect.fromLTRB(d.left, d.top, d.right, split), Rect.fromLTRB(d.left, split, d.right, d.bottom)]) {
      final x = dd.deflate(2 * u);
      canvas.drawRect(x, st);
      canvas.drawRect(x, bevelDark);
      final hx = x.left + math.min(60 * u, x.width * 0.12);
      final hr = dd.top == d.top ? Rect.fromLTWH(hx, x.bottom - x.height * 0.45, 14 * u, x.height * 0.35) : Rect.fromLTWH(hx, x.top + 40 * u, 14 * u, x.height * 0.35);
      canvas.drawRRect(RRect.fromRectAndRadius(hr, Radius.circular(7 * u)), Paint()..color = const Color(0xFF8A8F95));
    }
  }

  void appliance(Rect d, double hMm) {
    if (appliances.any((a) => a.startsWith('washing') || a.contains('linge'))) {
      washer(d);
    } else if (hMm > 1000 && appliances.any((a) => a.contains('fridge') || a.contains('froid'))) {
      openNiche(d);
      fridge(d.deflate(25 * u));
    } else if (hMm < 470) {
      microwave(d);
    } else {
      oven(d);
    }
  }

  // ---------------------------------------------------------------- composition par cases
  if (cells != null && cells.isNotEmpty) {
    final total = cells.last.y + cells.last.h;
    final k = f.height / (total <= 0 ? 1 : total);
    for (final c in cells) {
      final d = Rect.fromLTWH(f.left, f.top + c.y * k, f.width, c.h * k);
      final cellRect = realistic ? d : d.deflate(1);
      final hingeLeft = opening == 'hinged_left' || (opening != 'hinged_right' && c.hinge != 'right');
      final lowerHalf = handleTop ?? (m.kind == CabinetKind.tall ? c.y > total * 0.45 : !isHigh);
      switch (c.kind) {
        case CellKind.door:
          door(cellRect, hingeLeft: hingeLeft, handleTop: lowerHalf);
        case CellKind.door2:
          final half = cellRect.width / 2;
          door(Rect.fromLTWH(cellRect.left, cellRect.top, half, cellRect.height), hingeLeft: true, handleTop: lowerHalf);
          door(Rect.fromLTWH(cellRect.left + half, cellRect.top, half, cellRect.height), hingeLeft: false, handleTop: lowerHalf);
        case CellKind.glass:
          if (cellRect.width / u >= 790) {
            final half = cellRect.width / 2;
            glassDoor(Rect.fromLTWH(cellRect.left, cellRect.top, half, cellRect.height), hingeLeft: true, handleTop: lowerHalf);
            glassDoor(Rect.fromLTWH(cellRect.left + half, cellRect.top, half, cellRect.height), hingeLeft: false, handleTop: lowerHalf);
          } else {
            glassDoor(cellRect, hingeLeft: hingeLeft, handleTop: lowerHalf);
          }
        case CellKind.drawer:
          drawers(cellRect, const [1]);
        case CellKind.flap:
          panel(cellRect);
          final off = realistic ? math.min(50 * u, cellRect.height * 0.25) : cellRect.height * 0.12;
          handleH(cellRect.center.dx, isHigh ? cellRect.bottom - off : cellRect.top + off, cellRect.width);
        case CellKind.panel:
          panel(cellRect);
        case CellKind.niche:
          openNiche(realistic ? d.inflate(inset) : cellRect, wine: m.id == 'base_wine_rack');
          if (m.id.startsWith('laundry_washer_dryer') && realistic) {
            final duo = m.id.endsWith('side_by_side');
            final n = cellRect.deflate(20 * u);
            for (var k = 0; k < 2; k++) {
              washer(duo ? Rect.fromLTWH(n.left + n.width / 2 * k, n.top, n.width / 2, n.height) : Rect.fromLTWH(n.left, n.top + n.height / 2 * k, n.width, n.height / 2));
            }
          }
        case CellKind.appliance:
          appliance(cellRect, c.h);
      }
    }
    return;
  }

  // ---------------------------------------------------------------- modèles standard
  switch (m.id) {
    case 'base_drawers_multi':
      switch (variant) {
        case '2_deep_drawers':
          drawers(f, [1, 1]);
        case '1_low_2_deep':
          drawers(f, [0.6, 1.2, 1.2]);
        case '4_drawers':
          drawers(f, [1, 1, 1, 1]);
        default:
          drawers(f, [1, 1, 1]);
      }
      return;
    case 'base_pullout_spice':
      panel(f);
      handleH(f.center.dx, f.top + (realistic ? math.min(55 * u, f.height * 0.2) : f.height * 0.08), f.width);
      return;
    case 'base_sink_drawers':
      drawers(f, [1, 1]);
      return;
    case 'base_cooktop_oven':
      oven(Rect.fromLTWH(f.left, f.top, f.width, f.height * 0.72).deflate(1));
      drawers(Rect.fromLTWH(f.left, f.top + f.height * 0.72, f.width, f.height * 0.28), [1]);
      return;
    case 'base_integrated_dishwasher_door':
      panel(f);
      handleH(f.center.dx, f.top + (realistic ? math.min(55 * u, f.height * 0.2) : f.height * 0.08), f.width);
      return;
    case 'wall_lift_up':
      panel(f);
      handleH(f.center.dx, f.bottom - (realistic ? math.min(50 * u, f.height * 0.2) : f.height * 0.12), f.width);
      return;
    case 'wall_open_shelf':
      if (realistic) {
        openNiche(r);
        return;
      }
      canvas.drawRect(f, ln);
      for (var k = 1; k < 3; k++) {
        final y = f.top + f.height * k / 3;
        canvas.drawLine(Offset(f.left, y), Offset(f.right, y), ln);
      }
      return;
    case 'wall_integrated_hood':
      door(Rect.fromLTWH(f.left, f.top, f.width, f.height * 0.8).deflate(realistic ? 0 : 1), hingeLeft: true, handleTop: false);
      final band = Rect.fromLTWH(f.left, f.top + f.height * 0.82, f.width, f.height * 0.18).deflate(realistic ? 0 : 1);
      if (realistic) {
        canvas.drawRect(band, Paint()..color = const Color(0xFFB4B9BF));
        canvas.drawRect(Rect.fromLTWH(band.left, band.bottom - 4 * u, band.width, 4 * u), Paint()..color = Colors.black26);
      } else {
        canvas.drawRect(band, ln);
      }
      return;
    case 'tall_oven_microwave':
      final h = f.height;
      door(Rect.fromLTWH(f.left, f.top, f.width, h * 0.2).deflate(1), hingeLeft: true, handleTop: false);
      microwave(Rect.fromLTWH(f.left, f.top + h * 0.2, f.width, h * 0.17).deflate(1));
      oven(Rect.fromLTWH(f.left, f.top + h * 0.37, f.width, h * 0.27).deflate(1));
      drawers(Rect.fromLTWH(f.left, f.top + h * 0.64, f.width, h * 0.36), [1, 1]);
      return;
    case 'tall_integrated_fridge':
      final split = variant == '50_50' ? 0.5 : variant == 'single_door' ? 1.0 : 0.62;
      door(Rect.fromLTWH(f.left, f.top, f.width, f.height * split).deflate(realistic ? 0 : 1), hingeLeft: opening == 'hinged_left', handleTop: false);
      if (split < 1) {
        door(Rect.fromLTWH(f.left, f.top + f.height * split, f.width, f.height * (1 - split)).deflate(realistic ? 0 : 1),
            hingeLeft: opening == 'hinged_left', handleTop: true);
      }
      return;
  }

  switch (m.kind) {
    case CabinetKind.fillerBase:
    case CabinetKind.fillerWall:
    case CabinetKind.coverPanel:
    case CabinetKind.islandPanel:
      if (realistic) {
        panel(r.deflate(0.5));
        return;
      }
      // panneau plein : rayures fines
      canvas.save();
      canvas.clipRect(r);
      final step = math.max(6.0, r.shortestSide / 3);
      for (var x = r.left - r.height; x < r.right; x += step) {
        canvas.drawLine(Offset(x, r.bottom), Offset(x + r.height, r.top), ln..color = line.withValues(alpha: 0.35));
      }
      ln.color = line;
      canvas.restore();
      return;
    default:
      break;
  }

  // portes : une ou deux selon l'ouverture / la largeur
  final double2 = opening == 'double_hinged' ||
      m.id.contains('double_door') ||
      m.doorType == 'bifold_corner_door' ||
      (m.id == 'base_sink' && r.width / r.height > 0.9);
  final top = isHigh; // poignée en bas pour les hauts, en haut pour les bas
  final dd = realistic ? 0.0 : 1.0;
  // colonne haute : deux portes superposées (comme au débit), poignées vers le milieu
  if (m.kind == CabinetKind.tall && r.height / u > 1800) {
    final hTop = f.height / 2;
    final two = double2 || r.width / u >= 790;
    for (final (y, hh, handleTopDoor) in [(f.top, hTop, false), (f.top + hTop, f.height - hTop, true)]) {
      final d = Rect.fromLTWH(f.left, y, f.width, hh);
      if (two) {
        door(Rect.fromLTWH(d.left, d.top, d.width / 2, d.height).deflate(dd), hingeLeft: true, handleTop: handleTopDoor);
        door(Rect.fromLTWH(d.left + d.width / 2, d.top, d.width / 2, d.height).deflate(dd), hingeLeft: false, handleTop: handleTopDoor);
      } else {
        door(d.deflate(dd), hingeLeft: opening != 'hinged_right', handleTop: handleTopDoor);
      }
    }
    return;
  }
  if (double2) {
    final half = f.width / 2;
    door(Rect.fromLTWH(f.left, f.top, half, f.height).deflate(dd), hingeLeft: true, handleTop: !top);
    door(Rect.fromLTWH(f.left + half, f.top, half, f.height).deflate(dd), hingeLeft: false, handleTop: !top);
  } else {
    door(f, hingeLeft: opening != 'hinged_right', handleTop: !top);
  }
}

/// Vignette d'un modèle pour le menu.
class FrontThumb extends StatelessWidget {
  final CabinetModel model;
  final Color fill, stroke, line;
  const FrontThumb({super.key, required this.model, required this.fill, required this.stroke, required this.line});

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _ThumbPainter(model, fill, stroke, line),
        size: Size.infinite,
      );
}

class _ThumbPainter extends CustomPainter {
  final CabinetModel m;
  final Color fill, stroke, line;
  _ThumbPainter(this.m, this.fill, this.stroke, this.line);

  @override
  void paint(Canvas canvas, Size size) {
    if (m.kind.isCorner) {
      _corner(canvas, size);
      return;
    }
    final w = m.shape == CabinetShape.lShape || m.shape == CabinetShape.diagonal
        ? m.defaultWidth + (m.widthRight ?? 0) - m.depth
        : m.defaultWidth;
    final h = m.defaultHeight;
    final k = math.min(size.width / w, size.height / h) * 0.9;
    final rect = Rect.fromCenter(center: size.center(Offset.zero), width: w * k, height: h * k);
    final apps = <String>[
      if (m.requiresAppliance != null) m.requiresAppliance!,
      if (m.id.contains('wash') || m.id.contains('linge')) 'washing_machine',
      if (m.id.contains('oven') || m.id.contains('four') || m.id.contains('cooktop')) 'oven',
      if (m.id.contains('micro')) 'microwave',
      if (m.id.contains('fridge') || m.id.contains('refrigerateur')) 'fridge',
    ];
    paintFront(canvas, rect, m,
        fill: fill,
        stroke: stroke,
        line: line,
        realistic: true,
        appliances: apps,
        opening: m.openingOptions.isEmpty ? null : m.openingOptions.first,
        variant: m.variants.isEmpty ? null : m.variants.first,
        cells: m.frontLayout == null ? null : cellsOf(m.frontLayout!, h));
  }

  /// Meuble d'angle vu de dessus : emprise en L, pan coupé ou angle mort, murs et façades.
  void _corner(Canvas canvas, Size size) {
    final wl = m.defaultWidth.toDouble(), d = m.depth.toDouble();
    final wr = (m.widthRight ?? (m.shape == CabinetShape.blind ? m.depth : m.defaultWidth)).toDouble();
    final blind = m.shape == CabinetShape.blind;
    final spanX = wl, spanY = blind ? d : wr;
    final k = math.min((size.width - 16) / spanX, (size.height - 16) / spanY);
    final o = Offset((size.width - spanX * k) / 2, (size.height - spanY * k) / 2);
    Offset p(double x, double y) => o + Offset(x * k, y * k);
    final body = Paint()..color = fill;
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = stroke;
    final front = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..color = line;
    final wall = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = const Color(0xFF5A5F66);
    Path poly(List<Offset> pts) => Path()..addPolygon(pts, true);
    switch (m.shape) {
      case CabinetShape.lShape:
        final shape = poly([p(0, 0), p(wl, 0), p(wl, wr), p(wl - d, wr), p(wl - d, d), p(0, d)]);
        canvas.drawPath(shape, body);
        canvas.drawPath(shape, edge);
        canvas.drawLine(p(0, d), p(wl - d, d), front);
        canvas.drawLine(p(wl - d, d), p(wl - d, wr), front);
        // porte pliante d'angle : deux vantaux articulés au coin
        final arc = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = line.withValues(alpha: 0.6);
        canvas.drawArc(Rect.fromCircle(center: p(wl - d, d), radius: (wl - d) * k * 0.55), math.pi / 2, math.pi / 2, false, arc);
        // tourniquet (angle bas seulement)
        if (m.kind == CabinetKind.cornerBase) canvas.drawCircle(p(wl - d * 0.55, d * 0.55), d * k * 0.35, arc);
      case CabinetShape.diagonal:
        final shape = poly([p(0, 0), p(wl, 0), p(wl, wr), p(wl - d, wr), p(0, d)]);
        canvas.drawPath(shape, body);
        canvas.drawPath(shape, edge);
        canvas.drawLine(p(0, d), p(wl - d, wr), front);
      default:
        // angle avec fileur : partie accessible (porte) et partie aveugle sous le meuble voisin
        final r = Rect.fromPoints(p(0, 0), p(wl, d));
        canvas.drawRect(r, body);
        final overlap = (m.blindOverlap ?? 600).toDouble();
        final hidden = Rect.fromPoints(p(wl - overlap, 0), p(wl, d));
        canvas.save();
        canvas.clipRect(hidden);
        final hatch = Paint()
          ..strokeWidth = 1
          ..color = line.withValues(alpha: 0.45);
        for (var x = hidden.left - hidden.height; x < hidden.right; x += 6) {
          canvas.drawLine(Offset(x, hidden.bottom), Offset(x + hidden.height, hidden.top), hatch);
        }
        canvas.restore();
        canvas.drawRect(r, edge);
        canvas.drawLine(p(0, d), p(wl - overlap, d), front);
    }
    // murs de l'angle
    canvas.drawLine(p(0, 0), p(spanX, 0), wall);
    canvas.drawLine(p(spanX, 0), p(spanX, blind ? d : wr), wall);
  }

  @override
  bool shouldRepaint(covariant _ThumbPainter o) => o.m != m || o.fill != fill;
}

/// Profil Gola (gorge en aluminium) fixé sur le caisson : en haut d'un meuble bas, en bas d'un meuble haut,
/// à 1300 mm du bas sur une colonne, et entre les tiroirs. Dessiné à part quand les façades sont ouvertes :
/// il ne bouge pas avec les portes (seule une poignée intégrée suit la porte).
void paintGolaProfile(Canvas canvas, Rect r, CabinetModel m, {List<FrontCell>? cells, double u = 1, Color color = const Color(0xFF222426)}) {
  if (m.kind.isFiller || !m.isCarcass) return;
  final gh = math.max(2.0, 24 * u);
  final golaPaint = Paint()..color = color;
  final golaHi = Paint()..color = Colors.white30;
  if (m.kind == CabinetKind.tall) {
    final gy = r.bottom - 1300 * u;
    if (gy > r.top && gy < r.bottom) {
      final g = Rect.fromLTWH(r.left, gy - gh / 2, r.width, gh);
      canvas.drawRect(g, golaPaint);
      canvas.drawRect(Rect.fromLTWH(g.left, g.top, g.width, 1), golaHi);
    }
  } else {
    final isHigh = m.kind.isHigh;
    final g = isHigh ? Rect.fromLTWH(r.left, r.bottom - gh, r.width, gh) : Rect.fromLTWH(r.left, r.top, r.width, gh);
    canvas.drawRect(g, golaPaint);
    canvas.drawRect(Rect.fromLTWH(g.left, isHigh ? g.top : g.bottom - 1, g.width, 1), golaHi);
  }
  // gorges intermédiaires entre deux tiroirs
  final cs = cells ?? const <FrontCell>[];
  for (var i = 1; i < cs.length; i++) {
    if (cs[i].kind != CellKind.drawer || cs[i - 1].kind != CellKind.drawer) continue;
    final y = r.top + cs[i].y * u;
    final h2 = math.max(2.0, 14 * u);
    final g = Rect.fromLTWH(r.left, y - h2 / 2, r.width, h2);
    canvas.drawRect(g, golaPaint);
    canvas.drawRect(Rect.fromLTWH(g.left, g.bottom - 1, g.width, 1), Paint()..color = Colors.white24);
  }
}
