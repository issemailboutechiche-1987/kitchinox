// Vue 3D (projection parallèle, rotation autour de la pièce) dessinée au CustomPainter.
// Projection orthographique : chaque face est un parallélogramme, donc les façades se dessinent
// avec la même fonction que la vue de face, à travers une transformation affine.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../engine/engine.dart';
import 'finishes.dart';
import 'fronts.dart';
import 'textures.dart';

class Camera3d {
  final double yaw, pitch, cx, cy, k, ox, oy;
  const Camera3d(this.yaw, this.pitch, this.cx, this.cy, this.k, this.ox, this.oy);

  /// Projection d'un point du monde (mm) vers l'écran.
  Offset p(double x, double y, double z) {
    final dx = x - cx, dy = y - cy;
    final xr = dx * math.cos(yaw) - dy * math.sin(yaw);
    final yr = dx * math.sin(yaw) + dy * math.cos(yaw);
    return Offset(ox + xr * k, oy + (yr * math.sin(pitch) - z * math.cos(pitch)) * k);
  }

  /// Projection d'un vecteur (sans translation).
  Offset v(double x, double y, double z) {
    final xr = x * math.cos(yaw) - y * math.sin(yaw);
    final yr = x * math.sin(yaw) + y * math.cos(yaw);
    return Offset(xr * k, (yr * math.sin(pitch) - z * math.cos(pitch)) * k);
  }

  /// Plus grand = plus proche de l'observateur.
  double depth(double x, double y, double z) {
    final dx = x - cx, dy = y - cy;
    final yr = dx * math.sin(yaw) + dy * math.cos(yaw);
    return yr * math.cos(pitch) + z * math.sin(pitch);
  }

  /// La face de normale (nx, ny, nz) est-elle tournée vers l'observateur ?
  bool faces(double nx, double ny, double nz) {
    final nyr = nx * math.sin(yaw) + ny * math.cos(yaw);
    return nyr * math.cos(pitch) + nz * math.sin(pitch) > 1e-6;
  }

  static Camera3d fit(Room room, double yaw, Size size, {double pitch = 0.62, double zoom = 1, double panX = 0, double panY = 0}) {
    final cx = room.width / 2, cy = room.depth / 2;
    final probe = Camera3d(yaw, pitch, cx, cy, 1, 0, 0);
    var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
    for (final x in [0.0, room.width]) {
      for (final y in [0.0, room.depth]) {
        for (final z in [0.0, room.height]) {
          final q = probe.p(x, y, z);
          minX = math.min(minX, q.dx);
          maxX = math.max(maxX, q.dx);
          minY = math.min(minY, q.dy);
          maxY = math.max(maxY, q.dy);
        }
      }
    }
    final k = math.min((size.width - 80) / (maxX - minX), (size.height - 80) / (maxY - minY)) * zoom;
    final ox = size.width / 2 - (minX + maxX) / 2 * k + panX;
    final oy = size.height / 2 - (minY + maxY) / 2 * k + panY;
    return Camera3d(yaw, pitch, cx, cy, k, ox, oy);
  }
}

/// Une face dessinée : sert aussi à la sélection au clic.
class HitFace {
  final Path path;
  final String uid;
  HitFace(this.path, this.uid);
}

class _Solid {
  final Box3 box;
  final Color color;
  final Finish? finish; // texture des faces (plan de travail, joues...)
  final String? uid;
  final PlacedCabinet? item;
  final CabinetModel? model;
  final Finish? front; // finition de la façade du caisson
  final Wall? wall; // mur de la façade
  final String? decor; // 'hob' | 'sink' | 'steel'
  _Solid(this.box, this.color, {this.finish, this.uid, this.item, this.model, this.front, this.wall, this.decor});
}

class Scene3dPainter {
  final LayoutEngine e;
  final Camera3d cam;
  final String? selected;
  final String? hover;
  final Color selectColor;
  final Color background;

  /// Ouverture animée des éléments (0 = fermé, 1 = ouvert), par identifiant.
  final Map<String, double> open;

  /// Catalogue des poignées (taille et finition de la poignée choisie).
  final HandleCatalog? handles;

  Scene3dPainter(
    this.e,
    this.cam, {
    this.selected,
    this.hover,
    required this.selectColor,
    required this.background,
    this.open = const {},
    this.handles,
  });

  Project get p => e.project;

  // lumière principale (vue de dessus) : vient de l'avant gauche de la pièce
  static const _lx = -0.45, _ly = 0.89;

  /// Assombrissement d'une face selon son orientation (0 = pleine lumière).
  double _dark(double nx, double ny, double nz) {
    if (nz > 0) return 0.0;
    final d = nx * _lx + ny * _ly; // -1..1
    return 0.06 + (1 - d) * 0.09;
  }

  /// Repère local d'une face : origine [o], axes unitaires [a] et [b] (mm) → écran.
  void _onPlane(Canvas canvas, (double, double, double) o, (double, double, double) a, (double, double, double) b, void Function() draw) {
    final q = cam.p(o.$1, o.$2, o.$3);
    final du = cam.v(a.$1, a.$2, a.$3), dv = cam.v(b.$1, b.$2, b.$3);
    canvas.save();
    canvas.transform(Float64List.fromList([du.dx, du.dy, 0, 0, dv.dx, dv.dy, 0, 0, 0, 0, 1, 0, q.dx, q.dy, 0, 1]));
    draw();
    canvas.restore();
  }

  Path _poly(List<(double, double, double)> pts) => Path()..addPolygon([for (final (x, y, z) in pts) cam.p(x, y, z)], true);

  List<HitFace> paint(Canvas canvas, Size size) {
    final hits = <HitFace>[];
    final room = p.room;
    final style = p.style;
    final top = worktopFinish(style, style.worktop);
    final carcass = finishById(carcasses, style.carcass);
    final lowFront = frontFinish(style, style.frontLower ?? style.front);
    final std = p.standards;

    // ---- sol : parquet en lames, ou carrelage / béton / texture importée
    final ff = floorFinish(style);
    final floor = _poly([for (final (x, y) in room.floorPolygon) (x, y, 0.0)]);
    canvas.drawPath(floor, Paint()..color = ff.color);
    // le parquet a ses lames dans la texture (haute définition)
    if (ff.textured) {
      _onPlane(canvas, (0, 0, 0), (1, 0, 0), (0, 1, 0), () {
        canvas.drawRect(Rect.fromLTWH(0, 0, room.width, room.depth), ff.paint());
      });
    }

    // ---- murs du fond (ceux tournés vers l'observateur), avec portes et fenêtres
    final wf = wallFinish(style), sf = splashFinish(style);
    final wallColor = wf.color;
    for (final w in room.walls) {
      if (!cam.faces(w.nx, w.ny, 0)) continue;
      final (ex, ey) = w.toPlan(w.length, 0);
      final path = _poly([(w.x0, w.y0, 0), (ex, ey, 0), (ex, ey, room.height), (w.x0, w.y0, room.height)]);
      // tous les murs du fond sont dessinés (un mur non équipé existe quand même)
      {
        final lo = cam.p(w.x0, w.y0, 0), hi = cam.p(w.x0, w.y0, room.height);
        canvas.drawPath(path, Paint()..color = wallColor);
        if (wf.textured) {
          _onPlane(canvas, (w.x0, w.y0, room.height), (w.dx, w.dy, 0), (0, 0, -1), () {
            canvas.drawRect(Rect.fromLTWH(0, 0, w.length, room.height), wf.paint());
          });
        }
        // crédence derrière les linéaires bas, jusqu'au bas des hauts (découpée autour des ouvertures)
        if (style.splash != null || sf != wf) {
          void drawSplash(double s0, double s1, double z0, double z1) {
            if (s1 <= s0 + 0.5 || z1 <= z0 + 0.5) return;
            final (sx, sy) = w.toPlan(s0, 1);
            _onPlane(canvas, (sx, sy, z1), (w.dx, w.dy, 0), (0, 0, -1), () {
              final r = Rect.fromLTWH(0, 0, s1 - s0, z1 - z0);
              canvas.drawRect(r, sf.paint());
              canvas.drawRect(Rect.fromLTWH(0, r.bottom - 4, r.width, 4), Paint()..color = Colors.black.withValues(alpha: 0.12));
            });
          }

          for (final (a, b) in e.runs(w.id, (m) => e.kitchen && m.kind.isLow)) {
            final zBottom = std.worktopTop.toDouble();
            var zTop = zBottom + 600.0;
            for (final c in p.items.where((c) => c.wallId == w.id && e.modelOf(c).kind.isHigh && c.s < b && a < c.right)) {
              zTop = math.min(zTop, c.z);
            }
            if (zTop <= zBottom) continue;

            final wallOps = p.openings
                .where((o) => o.wallId == w.id && o.right > a && o.s < b && o.z < zTop && o.z + o.height > zBottom)
                .toList()
              ..sort((x, y) => x.s.compareTo(y.s));

            if (wallOps.isEmpty) {
              drawSplash(a, b, zBottom, zTop);
            } else {
              var curS = a;
              for (final o in wallOps) {
                final os0 = math.max(a, o.s);
                final os1 = math.min(b, o.right);
                if (os0 > curS + 1.0) {
                  var segZ = zBottom + 600.0;
                  for (final c in p.items.where((c) => c.wallId == w.id && e.modelOf(c).kind.isHigh && c.s < os0 && curS < c.right)) {
                    segZ = math.min(segZ, c.z);
                  }
                  drawSplash(curS, os0, zBottom, segZ);
                }
                if (!o.isDoor && o.z > zBottom + 5.0) {
                  drawSplash(os0, os1, zBottom, math.min(zTop, o.z));
                }
                if (!o.isDoor && o.z + o.height < zTop - 5.0) {
                  drawSplash(os0, os1, o.z + o.height, zTop);
                }
                curS = math.max(curS, os1);
              }
              if (b > curS + 1.0) {
                var segZ = zBottom + 600.0;
                for (final c in p.items.where((c) => c.wallId == w.id && e.modelOf(c).kind.isHigh && c.s < b && curS < c.right)) {
                  segZ = math.min(segZ, c.z);
                }
                drawSplash(curS, b, zBottom, segZ);
              }
            }
          }
        }
        canvas.drawPath(
          path,
          Paint()
            ..shader = LinearGradient(
              colors: [
                Colors.black.withValues(alpha: 0.05 + _dark(w.nx, w.ny, 0) * 0.3),
                Colors.white.withValues(alpha: 0.03),
              ],
            ).createShader(Rect.fromPoints(lo, hi)),
        );
        // occlusion au pied du mur
        final (ax, ay) = w.toPlan(0, 0);
        final (bx, by) = w.toPlan(w.length, 160);
        final (cx2, cy2) = w.toPlan(0, 160);
        final occ = _poly([(ax, ay, 0), (ex, ey, 0), (bx, by, 0), (cx2, cy2, 0)]);
        canvas.drawPath(
          occ,
          Paint()
            ..shader = LinearGradient(
              colors: [Colors.black.withValues(alpha: 0.16), Colors.transparent],
            ).createShader(Rect.fromPoints(cam.p(ax, ay, 0), cam.p(bx, by, 0))),
        );
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = const Color(0xFFD6D3CC),
        );
      }
      for (final o in p.openings.where((o) => o.wallId == w.id)) {
        final (ax, ay) = w.toPlan(o.s, 1);
        final (bx, by) = w.toPlan(o.right, 1);
        final op = _poly([(ax, ay, o.z), (bx, by, o.z), (bx, by, o.z + o.height), (ax, ay, o.z + o.height)]);
        if (o.isDoor) {
          canvas.drawPath(op, Paint()..color = const Color(0xFFD9CBB5));
        } else {
          canvas.drawPath(
            op,
            Paint()
              ..shader = LinearGradient(
                colors: const [Color(0xFFDDEFF8), Color(0xFFA9CCE0)],
              ).createShader(Rect.fromPoints(cam.p(ax, ay, o.z + o.height), cam.p(bx, by, o.z))),
          );
        }
        canvas.drawPath(
          op,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(2, 50 * cam.k)
            ..color = const Color(0xFFFFFFFF),
        );
        if (!o.isDoor) {
          final mid1 = cam.p((ax + bx) / 2, (ay + by) / 2, o.z), mid2 = cam.p((ax + bx) / 2, (ay + by) / 2, o.z + o.height);
          canvas.drawLine(
            mid1,
            mid2,
            Paint()
              ..color = Colors.white
              ..strokeWidth = math.max(1.5, 35 * cam.k),
          );
        }
      }
    }

    // ---- ombres : au sol sous les éléments posés, sur le mur sous les éléments hauts
    final blur = MaskFilter.blur(BlurStyle.normal, math.max(1.5, 45 * cam.k));
    final floorShadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.22)
      ..maskFilter = blur;
    for (final c in p.items) {
      final m = e.modelOf(c);
      for (final tb in e.boxesOf(c)) {
        final b = tb.box;
        if (b.z0 < 5 || m.floorSupport) {
          canvas.drawPath(
            _poly([(b.x0 - 20, b.y0 - 20, 0), (b.x1 + 20, b.y0 - 20, 0), (b.x1 + 20, b.y1 + 20, 0), (b.x0 - 20, b.y1 + 20, 0)]),
            floorShadow,
          );
        } else if (m.kind.isHigh) {
          final w = room.wall(tb.wallId);
          if (!cam.faces(w.nx, w.ny, 0)) continue;
          final (s0, s1, _, _) = w.boxToWall(b);
          final (ax, ay) = w.toPlan(s0 - 20, 1);
          final (bx, by) = w.toPlan(s1 + 20, 1);
          final hz = math.max(0.0, b.z0 - 260);
          canvas.drawPath(
            _poly([(ax, ay, b.z0), (bx, by, b.z0), (bx, by, hz), (ax, ay, hz)]),
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withValues(alpha: 0.28), Colors.transparent],
              ).createShader(Rect.fromPoints(cam.p(ax, ay, b.z0), cam.p(ax, ay, hz))),
          );
        }
      }
    }

    // ---- solides : caissons, plans de travail, plinthes
    final solids = <_Solid>[];
    for (final c in p.items) {
      final m = e.modelOf(c);
      final fr = frontOfItem(style, c, m);
      final isPanel = m.kind.isFiller || m.kind == CabinetKind.coverPanel || m.kind == CabinetKind.islandPanel;
      for (final tb in e.boxesOf(c)) {
        solids.add(
          _Solid(
            tb.box,
            isPanel ? fr.color : carcass.color,
            finish: isPanel ? fr : carcass,
            uid: c.uid,
            item: c,
            model: m,
            front: fr,
            wall: room.wall(tb.wallId),
          ),
        );
      }
    }
    // Collecter les réservations / trous dans le plan de travail (évier, plaque de cuisson)
    final cutoutsByWall = <String, List<({double s0, double s1, double t0, double t1})>>{};
    const wd = worktopDepth * 1.0;
    for (final c in p.items) {
      final m = e.modelOf(c);
      if (!m.kind.isLow || !m.isCarcass || m.kind.isCorner) continue;
      final isCook = m.id == 'base_cooktop_oven' || m.id == 'base_oven_built_in' || (e.isCooking(m) && m.kind.isLow) || m.id.contains('cooktop') || (c.appliances?.any((a) => a.contains('cooktop')) ?? false);
      final isSink = m.id.startsWith('base_sink') || m.id.contains('sink') || m.id.contains('evier') || e.isWashing(m) || (c.appliances?.any((a) => a.contains('sink')) ?? false);

      if (isSink) {
        final sk = KitchenFixtures.sink(p.style.sink);
        final bw = math.min(c.width - 60.0, sk.length.toDouble());
        final sd = math.min(sk.depth.toDouble(), wd - 80.0);
        final s0 = c.s + (c.width - bw) / 2;
        final t0 = (wd - sd) / 2;
        cutoutsByWall.putIfAbsent(c.wallId, () => []).add((s0: s0, s1: s0 + bw, t0: t0, t1: t0 + sd));
      } else if (isCook && !m.id.contains('sans_plaque')) {
        final hd = c.width >= 750 ? 520.0 : 510.0;
        final s0 = c.s + 30.0;
        final t0 = (wd - hd) / 2;
        cutoutsByWall.putIfAbsent(c.wallId, () => []).add((s0: s0, s1: s0 + (c.width - 60.0), t0: t0, t1: t0 + hd));
      }
    }

    for (final w in room.walls.where((w) => w.enabled)) {
      final cuts = (cutoutsByWall[w.id] ?? [])..sort((a, b) => a.s0.compareTo(b.s0));
      for (final (a, b) in e.runs(w.id, (m) => e.kitchen && m.kind.isLow)) {
        final inRun = cuts.where((x) => x.s0 < b - 20 && x.s1 > a + 20).toList();
        if (inRun.isEmpty) {
          solids.add(
            _Solid(w.strip(a, b - a, worktopDepth.toDouble(), std.baseTop.toDouble(), std.worktopThickness.toDouble()), top.color, finish: top),
          );
        } else {
          var curS = a;
          for (final cut in inRun) {
            final cs0 = math.max(a, cut.s0);
            final cs1 = math.min(b, cut.s1);
            if (cs0 > curS + 5) {
              solids.add(_Solid(w.stripRange(curS, cs0 - curS, 0, wd, std.baseTop.toDouble(), std.worktopThickness.toDouble()), top.color, finish: top));
            }
            if (cut.t0 > 5) {
              solids.add(_Solid(w.stripRange(cs0, cs1 - cs0, 0, cut.t0, std.baseTop.toDouble(), std.worktopThickness.toDouble()), top.color, finish: top));
            }
            if (wd - cut.t1 > 5) {
              solids.add(_Solid(w.stripRange(cs0, cs1 - cs0, cut.t1, wd, std.baseTop.toDouble(), std.worktopThickness.toDouble()), top.color, finish: top));
            }
            curS = cs1;
          }
          if (b > curS + 5) {
            solids.add(_Solid(w.stripRange(curS, b - curS, 0, wd, std.baseTop.toDouble(), std.worktopThickness.toDouble()), top.color, finish: top));
          }
        }
      }
      for (final (a, b) in e.runs(w.id, (m) => m.floorSupport)) {
        solids.add(_Solid(w.strip(a, b - a, 540, 0, std.plinthHeight.toDouble()), shade(lowFront.color, -0.12)));
      }
    }
    final isl = room.island;
    if (isl != null) {
      final w = room.wall('I');
      Box3 box(double s0, double s1, double t0, double t1, double z0, double z1) {
        final (ax, ay) = w.toPlan(s0, t0);
        final (bx, by) = w.toPlan(s1, t1);
        return Box3(math.min(ax, bx), math.min(ay, by), z0, math.max(ax, bx), math.max(ay, by), z1);
      }

      for (final (a, b) in e.runs('I', (m) => e.kitchen && m.kind.isLow)) {
        // plan de travail : 20 mm devant, débord repas à l'arrière
        solids.add(_Solid(box(a, b, -isl.overhang, Island.depth + 20, std.baseTop.toDouble(), std.worktopTop.toDouble()), top.color, finish: top));
        // habillage arrière sous le débord
        solids.add(_Solid(box(a, b, -18, 0, 0, std.baseTop.toDouble()), lowFront.color, finish: lowFront));
      }
      for (final (a, b) in e.runs('I', (m) => m.floorSupport)) {
        solids.add(_Solid(box(a, b, 0, 540, 0, std.plinthHeight.toDouble()), shade(lowFront.color, -0.12)));
      }
    }

    // appareils visibles : plaque et évier posés sur le plan de travail, hotte sous son élément haut
    for (final c in p.items) {
      final m = e.modelOf(c);
      final w = room.wall(c.wallId);
      final topZ = std.worktopTop.toDouble();
      // plaque centrée dans la profondeur du plan ; évier vers l'avant, robinet derrière la cuve
      Box3 at(double s0, double width, double t0, double t1, double z, double h) {
        final (ax, ay) = w.toPlan(s0, t0);
        final (bx, by) = w.toPlan(s0 + width, t1);
        return Box3(math.min(ax, bx), math.min(ay, by), z, math.max(ax, bx), math.max(ay, by), z + h);
      }

      const wd = worktopDepth * 1.0;
      final isCook = m.id == 'base_cooktop_oven' || m.id == 'base_oven_built_in' || (e.isCooking(m) && m.kind.isLow) || m.id.contains('cooktop') || (c.appliances?.any((a) => a.contains('cooktop')) ?? false);
      final isSink = m.id.startsWith('base_sink') || m.id.contains('sink') || m.id.contains('evier') || e.isWashing(m) || (c.appliances?.any((a) => a.contains('sink')) ?? false);
      final isHood = m.id == 'wall_integrated_hood' || m.id.contains('hood') || m.id.contains('hotte');

      if (isCook && !m.id.contains('sans_plaque')) {
        final hd = c.width >= 750 ? 520.0 : 510.0;
        final t0 = (wd - hd) / 2;
        solids.add(_Solid(at(c.s + 30, c.width - 60.0, t0, t0 + hd, topZ + 1.0, 8), const Color(0xFF1F2124), decor: 'hob'));
      } else if (isSink) {
        final sk = KitchenFixtures.sink(p.style.sink);
        final fc = KitchenFixtures.faucet(p.style.faucet);
        final bw = math.min(c.width - 60.0, sk.length.toDouble());
        final sd = math.min(sk.depth.toDouble(), wd - 80.0);
        final t0 = (wd - sd) / 2;
        final sinkColor = p.style.sinkFinish == 'noir_quartz' ? const Color(0xFF222528) : (p.style.sinkFinish == 'blanc_ceramique' ? const Color(0xFFF0F1F2) : const Color(0xFFBFC5CA));
        solids.add(_Solid(at(c.s + (c.width - bw) / 2, bw, t0, t0 + sd, topZ + 1.0, 6), sinkColor, decor: 'sink:${sk.layout}'));
        final mid = sk.layout == 'drainer' ? c.s + (c.width - bw) / 2 + bw * 0.28 : c.s + c.width / 2;
        final fColor = p.style.faucetFinish == 'noir_mat' ? const Color(0xFF222426) : (p.style.faucetFinish == 'or_brosse' ? const Color(0xFFD4AF37) : const Color(0xFFA9AFB5));
        final fh = fc.height.toDouble().clamp(280.0, 440.0);
        solids.add(_Solid(at(mid - 16, 32, t0 - 55, t0 - 25, topZ + 2.0, fh - 20), fColor, decor: 'steel'));
        solids.add(_Solid(at(mid - 14, 28, t0 - 55, t0 + (fc.spring ? 180 : 150), topZ + fh - 40, 26), fColor, decor: 'steel'));
        if (fc.pullout || fc.spring) solids.add(_Solid(at(mid - 20, 40, t0 + 100, t0 + 155, topZ + fh - 130, 90), fColor, decor: 'steel'));
      } else if (isHood) {
        solids.add(_Solid(w.strip(c.s + 40, c.width - 80.0, 480, c.z - 70, 70), const Color(0xFFA9AFB5), decor: 'steel'));
      }
    }

    // objets de la pièce (vignettes, vue simplifiée) : volumes simples aux cotes réelles
    for (final o in p.objects) {
      final (x0, y0, x1, y1) = o.footprint;
      final f = o.fixture;
      final z0 = o.z, z1 = o.z + o.h;
      const white = Color(0xFFF7F7F5);
      switch (f?.id) {
        case 'wc_suspendu' || 'bidet':
          solids.add(_Solid(Box3(x0, y0, z1 - 280, x1, y1, z1), white));
        case 'douche' || 'douche_italienne':
          solids.add(_Solid(Box3(x0, y0, 0, x1, y1, f!.id == 'douche' ? 40 : 10), white));
          // paroi vitrée le long de la face avant
          final (fx, fy) = o.front;
          final g = fx > 0
              ? Box3(x1 - 8, y0, 40, x1, y1, z1)
              : fx < 0
                  ? Box3(x0, y0, 40, x0 + 8, y1, z1)
                  : fy > 0
                      ? Box3(x0, y1 - 8, 40, x1, y1, z1)
                      : Box3(x0, y0, 40, x1, y0 + 8, z1);
          solids.add(_Solid(g, const Color(0xFFCFE3EC)));
        case null:
          final tv = o.ref.contains('television') || o.ref.contains('computerScreen');
          final rug = o.h <= 20;
          solids.add(_Solid(Box3(x0, y0, z0, x1, y1, math.max(z1, z0 + 6)),
              tv ? const Color(0xFF2A2C30) : (rug ? const Color(0xFFC9B8A6) : const Color(0xFFD8CFC4))));
        default:
          solids.add(_Solid(Box3(x0, y0, z0, x1, y1, z1), white));
      }
    }

    final ordered = _depthOrder(solids);
    // 1. Dessiner d'abord tous les solides de base (caissons, plinthes, murs, plan de travail...)
    // sauf les équipements de surface (plaque, évier, robinet) qui doivent impérativement
    // se peindre au-dessus du plan de travail pour ne jamais être recouverts.
    final surfaceAppliances = <_Solid>[];
    for (final s in ordered) {
      if (s.decor == 'hob' || (s.decor?.startsWith('sink') ?? false) || (s.box.z0 >= std.baseTop && s.model == null && s.finish == null && s.decor == 'steel')) {
        surfaceAppliances.add(s);
      } else {
        _paintSolid(canvas, s, hits, carcass.color);
      }
    }
    // 2. Dessiner les équipements de surface (évier, cuves, mitigeur, plaque) au premier plan
    for (final s in surfaceAppliances) {
      _paintSolid(canvas, s, hits, carcass.color);
    }
    _paintOpenParts(canvas, carcass.color);
    return hits;
  }

  // ------------------------------------------------------------------ ouverture

  /// Cases qui s'ouvrent : composition du caisson, ou celle reconstituée pour les modèles standard.
  List<FrontCell> _openCells(CabinetModel m, PlacedCabinet c) {
    if (m.kind.isCorner || m.kind.isFiller || !m.isCarcass && m.id != 'base_integrated_dishwasher_door') return const [];
    if (m.id == 'base_integrated_dishwasher_door') return [FrontCell(CellKind.flap, 0, c.height.toDouble(), null, -1)];
    final rows = rowsOf(m, c) ?? seedRows(m, c);
    return cellsOf(rows, c.height);
  }

  static bool _moves(CellKind k) => k == CellKind.door || k == CellKind.door2 || k == CellKind.glass || k == CellKind.flap || k == CellKind.drawer;

  /// Intérieur visible derrière les portes ouvertes (dans le repère de la façade, mm) :
  /// cuve et paniers du lave-vaisselle, siphon sous l'évier, clayettes du réfrigérateur,
  /// moteur de la hotte, sinon étagères selon la hauteur.
  void _paintInterior(Canvas canvas, Rect face, List<FrontCell> cells, double total, Color carcass, CabinetModel m, PlacedCabinet item) =>
      paintCabinetInterior(e, canvas, face, cells, total, carcass, m, item);

  /// Portes qui pivotent, abattants qui se relèvent (ou s'abaissent), tiroirs qui coulissent.
  void _paintOpenParts(Canvas canvas, Color carcass) {
    final parts = <(double, void Function())>[];
    for (final c in p.items) {
      // ouverture arrêtée au contact d'un mur ou d'un meuble
      final pr = math.min(open[c.uid] ?? 0, openLimit(e, c).$1);
      if (pr <= 0.001) continue;
      final m = e.modelOf(c);
      final cells = _openCells(m, c);
      if (cells.isEmpty) continue;
      final tb = e.boxesOf(c).first;
      final w = p.room.wall(tb.wallId);
      if (!cam.faces(w.nx, w.ny, 0)) continue; // façade tournée dos à la vue : les parties ouvertes sont cachées
      final b = tb.box;
      final (s0, s1, _, t1) = w.boxToWall(b);
      final total = cells.last.y + cells.last.h;
      final kz = (b.z1 - b.z0) / (total <= 0 ? 1 : total);
      final fr = frontOfItem(p.style, c, m);
      final ease = Curves.easeInOut.transform(pr.clamp(0.0, 1.0));
      (double, double, double) at(double s, double t, double z) {
        final (x, y) = w.toPlan(s, t);
        return (x, y, z);
      }

      final wdir = (w.dx, w.dy, 0.0), n = (w.nx, w.ny, 0.0);
      (double, double, double) mix((double, double, double) a, double ka, (double, double, double) bb, double kb) =>
          (a.$1 * ka + bb.$1 * kb, a.$2 * ka + bb.$2 * kb, a.$3 * ka + bb.$3 * kb);
      (double, double, double) add3((double, double, double) a, (double, double, double) bb, double k) =>
          (a.$1 + bb.$1 * k, a.$2 + bb.$2 * k, a.$3 + bb.$3 * k);
      const down = (0.0, 0.0, -1.0), up = (0.0, 0.0, 1.0);

      void panel(
        (double, double, double) origin,
        (double, double, double) u,
        (double, double, double) v,
        double lu,
        double lv,
        FrontCell cell,
        double shadeK,
      ) {
        final (cx, cy, cz) = add3(add3(origin, u, lu / 2), v, lv / 2);
        // normale de la face avant (vers l'extérieur du meuble) et épaisseur du panneau
        final nrm = (u.$2 * v.$3 - u.$3 * v.$2, u.$3 * v.$1 - u.$1 * v.$3, u.$1 * v.$2 - u.$2 * v.$1);
        const th = 18.0;
        final off = (-nrm.$1 * th, -nrm.$2 * th, -nrm.$3 * th);
        final frontVisible = cam.faces(nrm.$1, nrm.$2, nrm.$3);
        final dishwasherDoor = m.id == 'base_integrated_dishwasher_door';
        parts.add((
          cam.depth(cx, cy, cz),
          () {
            final c0 = origin, c1 = add3(origin, u, lu), c2 = add3(c1, v, lv), c3 = add3(origin, v, lv);
            final edgePaint = Paint()..color = shade(fr.color, -0.12);
            final edgeLine = Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.8
              ..color = shade(fr.color, -0.35);
            for (final (pa, pb) in [(c0, c1), (c1, c2), (c2, c3), (c3, c0)]) {
              final q = _poly([pa, pb, add3(pb, off, 1), add3(pa, off, 1)]);
              canvas.drawPath(q, edgePaint);
              canvas.drawPath(q, edgeLine);
            }
            if (!frontVisible) {
              // on voit l'intérieur de la porte : contre-porte inox du lave-vaisselle, sinon le dos du panneau
              _onPlane(canvas, add3(origin, off, 1), u, v, () {
                final r = Rect.fromLTWH(0, 0, lu, lv);
                if (dishwasherDoor) {
                  canvas.drawRect(
                    r,
                    Paint()..shader = const LinearGradient(colors: [Color(0xFFA9AFB5), Color(0xFFDDE1E4), Color(0xFFB0B5BA)]).createShader(r),
                  );
                  canvas.drawRect(Rect.fromLTWH(40, 40, lu - 80, 120), Paint()..color = const Color(0xFF8A9096));
                } else {
                  canvas.drawRect(r, Paint()..color = shade(carcass, -0.04));
                }
                canvas.drawRect(r, edgeLine);
              });
              return;
            }
            _onPlane(canvas, origin, u, v, () {
              final r = Rect.fromLTWH(0, 0, lu, lv);
              paintFront(
                canvas,
                r,
                m,
                fill: fr.color,
                stroke: shade(fr.color, -0.3),
                line: lineOn(fr.color),
                handle: p.style.handle,
                handleSize: handleLook(p.style, handles).$2,
                handleColor: handleLook(p.style, handles).$3,

                tallXxl: p.style.tallXxl,
                fillPaint: fr.paint(vertical: true),
                cells: [FrontCell(cell.kind, 0, lv, cell.hinge, -1)],
                realistic: true,
                pxPerMm: 1,
                carcass: carcass,
                gloss: fr.gloss,
              );
              // chant de la porte et ombre selon l'angle
              canvas.drawRect(
                r,
                Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 4
                  ..color = shade(fr.color, -0.25),
              );
              if (shadeK > 0) canvas.drawRect(r, Paint()..color = Colors.black.withValues(alpha: shadeK));
            });
          },
        ));
      }

      final width = s1 - s0;
      for (final cell in cells.where((x) => _moves(x.kind))) {
        final zTop = b.z1 - cell.y * kz, h = cell.h * kz;
        final zBot = zTop - h;
        switch (cell.kind) {
          case CellKind.door:
          case CellKind.glass:
          case CellKind.door2:
            final a = ease * 100 * math.pi / 180;
            final halves = cell.kind == CellKind.door2 || (cell.kind == CellKind.glass && width >= 790)
                ? [(s0, width / 2, true), (s0 + width / 2, width / 2, false)]
                : [(s0, width, c.opening == 'hinged_left' || (c.opening != 'hinged_right' && cell.hinge != 'right'))];
            for (final (ls, lw, hingeLeft) in halves) {
              final kind = cell.kind == CellKind.door2 ? CellKind.door : cell.kind;
              final one = FrontCell(kind, 0, h, hingeLeft ? 'left' : 'right', -1);
              if (hingeLeft) {
                final u = mix(wdir, math.cos(a), n, math.sin(a));
                panel(at(ls, t1, zTop), u, down, lw, h, one, 0.15 * math.sin(a));
              } else {
                final u = mix(wdir, math.cos(a), n, -math.sin(a));
                final hinge = at(ls + lw, t1, zTop);
                panel(add3(hinge, u, -lw), u, down, lw, h, one, 0.15 * math.sin(a));
              }
            }
          case CellKind.flap:
            if (m.kind.isHigh) {
              // abattant relevable : pivote autour du bord haut
              final a = ease * 100 * math.pi / 180;
              final v = mix(down, math.cos(a), n, math.sin(a));
              panel(at(s0, t1, zTop), wdir, v, width, h, cell, 0.12 * math.sin(a));
            } else {
              // porte basculante (lave-vaisselle, four) : pivote autour du bord bas
              final a = ease * 85 * math.pi / 180;
              final vUp = mix(up, math.cos(a), n, math.sin(a));
              final origin = add3(at(s0, t1, zBot), vUp, h);
              panel(origin, wdir, (-vUp.$1, -vUp.$2, -vUp.$3), width, h, cell, 0.05);
            }
          case CellKind.drawer:
            final d = ease * math.min(450.0, c.depth - 120.0);
            // caisson du tiroir : côtés et fond visibles, puis la façade avancée
            final boxIn = <(double, double, double)>[
              at(s0 + 25, t1, zTop - 30),
              at(s1 - 25, t1, zTop - 30),
              at(s1 - 25, t1 + d, zTop - 30),
              at(s0 + 25, t1 + d, zTop - 30),
            ];
            final (cx, cy, cz) = at((s0 + s1) / 2, t1 + d, zTop - h / 2);
            parts.add((
              cam.depth(cx, cy, cz) - 1,
              () {
                final floorPts = [for (final (x, y, _) in boxIn) (x, y, zBot + 20)];
                canvas.drawPath(_poly(floorPts), Paint()..color = Color.lerp(carcass, Colors.black, 0.35)!);
                for (final side in [s0 + 25, s1 - 25]) {
                  final q = [at(side, t1, zBot + 20), at(side, t1 + d, zBot + 20), at(side, t1 + d, zTop - 30), at(side, t1, zTop - 30)];
                  canvas.drawPath(_poly(q), Paint()..color = shade(carcass, -0.08));
                  canvas.drawPath(
                    _poly(q),
                    Paint()
                      ..style = PaintingStyle.stroke
                      ..strokeWidth = 0.7
                      ..color = Colors.black26,
                  );
                }
              },
            ));
            panel(at(s0, t1 + d, zTop), wdir, down, width, h, cell, 0);
          default:
            break;
        }
      }
    }
    parts.sort((a, b) => a.$1.compareTo(b.$1));
    for (final (_, draw) in parts) {
      draw();
    }
  }

  /// Ordre de dessin du plus loin au plus proche. Pour deux boîtes séparées le long d'un axe,
  /// celle qui est du côté opposé à l'observateur passe avant (exact pour des boîtes alignées
  /// sur les axes qui ne s'interpénètrent pas) ; sinon on départage par la profondeur du centre.
  List<_Solid> _depthOrder(List<_Solid> list) {
    // direction vers l'observateur dans le repère du monde
    final gx = math.sin(cam.yaw) * math.cos(cam.pitch), gy = math.cos(cam.yaw) * math.cos(cam.pitch), gz = math.sin(cam.pitch);
    double center(Box3 b) => cam.depth((b.x0 + b.x1) / 2, (b.y0 + b.y1) / 2, (b.z0 + b.z1) / 2);

    /// -1 : a derrière b ; 1 : a devant b ; 0 : indéterminé.
    int cmp(Box3 a, Box3 b) {
      const e = 0.5;
      final votes = <int>{};
      void axis(double a0, double a1, double b0, double b1, double g) {
        if (g.abs() < 1e-9) return;
        if (a1 <= b0 + e) votes.add(g > 0 ? -1 : 1);
        if (b1 <= a0 + e) votes.add(g > 0 ? 1 : -1);
      }

      axis(a.x0, a.x1, b.x0, b.x1, gx);
      axis(a.y0, a.y1, b.y0, b.y1, gy);
      axis(a.z0, a.z1, b.z0, b.z1, gz);
      // plusieurs axes séparateurs en désaccord : les projections ne se recouvrent pas vraiment
      return votes.length == 1 ? votes.first : 0;
    }

    final n = list.length;
    final before = List.generate(n, (_) => <int>[]); // before[j] : indices à dessiner avant j
    final indeg = List.filled(n, 0);
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        // seules les boîtes dont les projections se recouvrent ont besoin d'un ordre
        if (!_screenOverlap(list[i].box, list[j].box)) continue;
        final c = cmp(list[i].box, list[j].box);
        if (c < 0) {
          before[j].add(i);
          indeg[j]++;
        } else if (c > 0) {
          before[i].add(j);
          indeg[i]++;
        }
      }
    }
    final after = List.generate(n, (_) => <int>[]);
    for (var j = 0; j < n; j++) {
      for (final i in before[j]) {
        after[i].add(j);
      }
    }
    final depth = [for (final s in list) center(s.box)];
    final ready = [
      for (var i = 0; i < n; i++)
        if (indeg[i] == 0) i,
    ];
    final out = <_Solid>[];
    final done = List.filled(n, false);
    while (out.length < n) {
      if (ready.isEmpty) {
        // cycle (rare) : on débloque la boîte restante la plus lointaine
        var k = -1;
        for (var i = 0; i < n; i++) {
          if (!done[i] && (k < 0 || depth[i] < depth[k])) k = i;
        }
        ready.add(k);
        indeg[k] = 0;
      }
      ready.sort((a, b) => depth[b].compareTo(depth[a]));
      final i = ready.removeLast();
      if (done[i]) continue;
      done[i] = true;
      out.add(list[i]);
      for (final j in after[i]) {
        if (--indeg[j] == 0 && !done[j]) ready.add(j);
      }
    }
    return out;
  }

  bool _screenOverlap(Box3 a, Box3 b) {
    Rect proj(Box3 x) {
      var r = Rect.fromLTWH(cam.p(x.x0, x.y0, x.z0).dx, cam.p(x.x0, x.y0, x.z0).dy, 0, 0);
      for (final px in [x.x0, x.x1]) {
        for (final py in [x.y0, x.y1]) {
          for (final pz in [x.z0, x.z1]) {
            final q = cam.p(px, py, pz);
            r = r.expandToInclude(Rect.fromLTWH(q.dx, q.dy, 0, 0));
          }
        }
      }
      return r;
    }

    return proj(a).overlaps(proj(b));
  }

  void _paintSolid(Canvas canvas, _Solid s, List<HitFace> hits, Color carcassColor) {
    final b = s.box;
    // 5 faces possibles (pas le dessous) : normale, coins (p0 → p1 : axe a, p0 → p3 : axe b)
    final faces = <((double, double, double), List<(double, double, double)>)>[
      ((0, 0, 1), [(b.x0, b.y0, b.z1), (b.x1, b.y0, b.z1), (b.x1, b.y1, b.z1), (b.x0, b.y1, b.z1)]),
      ((0, -1, 0), [(b.x0, b.y0, b.z0), (b.x1, b.y0, b.z0), (b.x1, b.y0, b.z1), (b.x0, b.y0, b.z1)]),
      ((0, 1, 0), [(b.x0, b.y1, b.z0), (b.x1, b.y1, b.z0), (b.x1, b.y1, b.z1), (b.x0, b.y1, b.z1)]),
      ((-1, 0, 0), [(b.x0, b.y0, b.z0), (b.x0, b.y1, b.z0), (b.x0, b.y1, b.z1), (b.x0, b.y0, b.z1)]),
      ((1, 0, 0), [(b.x1, b.y0, b.z0), (b.x1, b.y1, b.z0), (b.x1, b.y1, b.z1), (b.x1, b.y0, b.z1)]),
    ];
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = shade(s.color, -0.3).withValues(alpha: 0.45);
    for (final ((nx, ny, nz), pts) in faces) {
      if (!cam.faces(nx, ny, nz)) continue;
      final path = _poly(pts);
      final w = s.wall;
      final isFront = s.model != null && w != null && (nx - w.nx).abs() < 1e-6 && (ny - w.ny).abs() < 1e-6;
      final (x0, y0, z0) = pts[0];
      final (x1, y1, z1) = pts[1];
      final (x3, y3, z3) = pts[3];
      final la = math.sqrt(math.pow(x1 - x0, 2) + math.pow(y1 - y0, 2) + math.pow(z1 - z0, 2));
      final lb = math.sqrt(math.pow(x3 - x0, 2) + math.pow(y3 - y0, 2) + math.pow(z3 - z0, 2));
      if (la < 0.1 || lb < 0.1) continue;
      final a = ((x1 - x0) / la, (y1 - y0) / la, (z1 - z0) / la);
      final bb = ((x3 - x0) / lb, (y3 - y0) / lb, (z3 - z0) / lb);

      if (isFront) {
        _paintFront(canvas, s, carcassColor);
      } else if (s.finish != null && s.finish!.textured) {
        // fil dans le sens de la plus grande longueur (plan de travail le long du mur)
        _onPlane(canvas, pts[0], a, bb, () {
          canvas.drawRect(Rect.fromLTWH(0, 0, la, lb), s.finish!.paint(vertical: lb > la));
        });
      } else {
        canvas.drawPath(path, Paint()..color = s.color);
      }
      if (nz > 0 && s.decor != null) _decor(canvas, s, pts[0], a, bb, la, lb);
      final dk = _dark(nx, ny, nz);
      if (dk > 0) canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: dk));
      // chant éclairé du plan de travail
      if (nz > 0 && s.finish != null && s.model == null) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = Colors.white.withValues(alpha: 0.35),
        );
      } else {
        canvas.drawPath(path, edge);
      }
      if (s.uid != null) hits.add(HitFace(path, s.uid!));
      if (s.uid != null && (s.uid == selected || s.uid == hover)) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = s.uid == selected ? 2.5 : 1.5
            ..color = s.uid == selected ? selectColor : selectColor.withValues(alpha: 0.6),
        );
      }
    }
  }

  /// Détails sur le dessus : feux de la plaque, cuve de l'évier, reflets de l'inox.
  void _decor(Canvas canvas, _Solid s, (double, double, double) o, (double, double, double) a, (double, double, double) b, double la, double lb) {
    _onPlane(canvas, o, a, b, () => paintTopDecor(canvas, Rect.fromLTWH(0, 0, la, lb), s.decor!, s.color));
  }

  /// Dessine la façade (portes, tiroirs, poignées) sur la face avant du solide.
  void _paintFront(Canvas canvas, _Solid s, Color carcassColor) {
    final w = s.wall!, c = s.item!, m = s.model!;
    final fr = s.front!;
    final b = s.box;
    final (s0, s1, _, t1) = w.boxToWall(b);
    final (fx, fy) = w.toPlan(s0, t1);
    final o = cam.p(fx, fy, b.z1);
    final du = cam.v(w.dx, w.dy, 0);
    final dv = cam.v(0, 0, -1);
    final mat = Float64List.fromList([du.dx, du.dy, 0, 0, dv.dx, dv.dy, 0, 0, 0, 0, 1, 0, o.dx, o.dy, 0, 1]);
    canvas.save();
    canvas.transform(mat);
    final scale = math.max(0.0001, du.distance);
    final r = Rect.fromLTWH(0, 0, s1 - s0, b.z1 - b.z0);
    final pr = open[c.uid] ?? 0;
    final openCells = pr > 0.001 ? _openCells(m, c) : const <FrontCell>[];
    if (openCells.isNotEmpty) {
      // façade ouverte : on dessine l'intérieur, les parties mobiles viennent par-dessus
      final total = openCells.last.y + openCells.last.h;
      paintFront(
        canvas,
        r,
        m,
        fill: fr.color,
        stroke: shade(fr.color, -0.3),
        line: lineOn(fr.color),
        handle: p.style.handle,
        handleSize: handleLook(p.style, handles).$2,
        handleColor: handleLook(p.style, handles).$3,

        tallXxl: p.style.tallXxl,
        fillPaint: fr.paint(vertical: true, origin: Offset(-s0, 0)),
        cells: frontCells(m, c, realistic: true),
        realistic: true,
        pxPerMm: 1,
        appliances: appliancesOf(m, c),
        carcass: carcassColor,
        gloss: fr.gloss,
      );
      _paintInterior(canvas, r, openCells, total, carcassColor, m, c);
      canvas.restore();
      return;
    }
    paintFront(
      canvas,
      r,
      m,
      fill: fr.color,
      stroke: shade(fr.color, -0.3),
      line: lineOn(fr.color),
      opening: c.opening,
      variant: c.variant,
      strokeWidth: 1.1 / scale,
      handle: p.style.handle,
      handleSize: handleLook(p.style, handles).$2,
      handleColor: handleLook(p.style, handles).$3,

      tallXxl: p.style.tallXxl,
      fillPaint: fr.paint(vertical: true, origin: Offset(-s0, 0)),
      cells: frontCells(m, c, realistic: true),
      realistic: true,
      pxPerMm: 1,
      appliances: appliancesOf(m, c),
      carcass: carcassColor,
      gloss: fr.gloss,
    );
    // ombre du plan de travail sur le haut des façades basses
    if (m.kind.isLow && b.z1 > p.standards.baseTop - 5) {
      final band = Rect.fromLTWH(0, 0, r.width, 70);
      canvas.drawRect(
        band,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withValues(alpha: 0.22), Colors.transparent],
          ).createShader(band),
      );
    }
    canvas.restore();
  }
}

/// Intérieur visible derrière des portes ouvertes (repère de la façade, mm) : partagé par la vue 3D
/// dessinée et la vue WebGL.
void paintCabinetInterior(
  LayoutEngine e,
  Canvas canvas,
  Rect face,
  List<FrontCell> cells,
  double total,
  Color carcass,
  CabinetModel m,
  PlacedCabinet item,
) {
  final k = face.height / (total <= 0 ? 1 : total);
  final apps = appliancesOf(m, item);
  final dishwasher = m.id == 'base_integrated_dishwasher_door' || apps.any((a) => a.startsWith('dishwasher'));
  final sink = e.isWashing(m);
  final fridge = e.isCooling(m) || apps.any((a) => a.startsWith('fridge'));
  final hood = m.id == 'wall_integrated_hood';
  final steelGrad = Paint();
  for (final c in cells.where((c) => Scene3dPainter._moves(c.kind))) {
    final r = Rect.fromLTWH(face.left, face.top + c.y * k, face.width, c.h * k);
    if (dishwasher) {
      // cuve inox, panier haut et panier bas
      steelGrad.shader = const LinearGradient(colors: [Color(0xFF9EA4AA), Color(0xFFD7DBDF), Color(0xFFA9AEB4)]).createShader(r);
      canvas.drawRect(r, steelGrad);
      final wire = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = const Color(0xFF6E757C);
      for (final (y0, y1) in [(0.12, 0.42), (0.55, 0.92)]) {
        final bk = Rect.fromLTRB(r.left + 25, r.top + r.height * y0, r.right - 25, r.top + r.height * y1);
        canvas.drawRRect(RRect.fromRectAndRadius(bk, const Radius.circular(10)), wire);
        for (var x = bk.left + 40; x < bk.right - 20; x += 45) {
          canvas.drawLine(Offset(x, bk.top + bk.height * 0.35), Offset(x, bk.bottom - 6), wire..strokeWidth = 3);
        }
        wire.strokeWidth = 4;
        // assiettes dans le panier bas, verres dans le haut
        if (y0 > 0.5) {
          for (var x = bk.left + 50; x < bk.right - 40; x += 70) {
            canvas.drawOval(
              Rect.fromCenter(center: Offset(x, bk.center.dy), width: 18, height: bk.height * 0.8),
              Paint()..color = const Color(0xFFF7F7F5),
            );
          }
        } else {
          for (var x = bk.left + 45; x < bk.right - 30; x += 75) {
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromCenter(center: Offset(x, bk.center.dy + 10), width: 50, height: bk.height * 0.6),
                const Radius.circular(12),
              ),
              Paint()..color = const Color(0xCCE3F0F6),
            );
          }
        }
      }
      continue;
    }
    canvas.drawRect(r, Paint()..color = carcass);
    final inner = r.deflate(18);
    if (inner.width <= 0 || inner.height <= 0) continue;
    final interiorColor = fridge && c.kind != CellKind.drawer
        ? const Color(0xFFF3F6F8)
        : Color.lerp(carcass, Colors.black, c.kind == CellKind.drawer ? 0.55 : 0.2)!;
    canvas.drawRect(inner, Paint()..color = interiorColor);
    canvas.drawRect(
      inner,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: fridge ? 0.12 : 0.35),
            Colors.transparent,
          ],
          stops: const [0, 0.4],
        ).createShader(inner),
    );
    if (c.kind == CellKind.drawer) continue;
    if (sink) {
      // siphon, arrivées d'eau froide / chaude et poubelle
      final pipe = Paint()
        ..color = const Color(0xFFDADDE0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 40
        ..strokeCap = StrokeCap.round;
      final cx = inner.center.dx;
      final trapY = inner.top + inner.height * 0.45;
      final path = Path()
        ..moveTo(cx, inner.top)
        ..lineTo(cx, trapY)
        ..quadraticBezierTo(cx, trapY + 90, cx + 90, trapY + 90)
        ..quadraticBezierTo(cx + 180, trapY + 90, cx + 180, trapY)
        ..lineTo(cx + 180, trapY - 40);
      canvas.drawPath(path, pipe);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.black26,
      );
      for (final (dx, col) in [(-150.0, const Color(0xFF1C7ED6)), (150.0, const Color(0xFFD62F2F))]) {
        canvas.drawLine(
          Offset(cx + dx, inner.top + 40),
          Offset(cx + dx, inner.top + inner.height * 0.3),
          Paint()
            ..color = const Color(0xFFB8BCC0)
            ..strokeWidth = 14,
        );
        canvas.drawCircle(Offset(cx + dx, inner.top + inner.height * 0.3), 22, Paint()..color = col);
      }
      final bin = Rect.fromLTWH(inner.left + 30, inner.bottom - inner.height * 0.42, math.min(260, inner.width * 0.35), inner.height * 0.4);
      canvas.drawRRect(RRect.fromRectAndRadius(bin, const Radius.circular(18)), Paint()..color = const Color(0xFF7D8A80));
      continue;
    }
    if (fridge) {
      // clayettes en verre, bacs à légumes en bas
      final n = math.max(2, (inner.height / 300).floor() - 1);
      for (var i = 1; i <= n; i++) {
        final y = inner.top + inner.height * 0.75 * i / (n + 1);
        canvas.drawRect(Rect.fromLTWH(inner.left, y, inner.width, 8), Paint()..color = const Color(0xAAB9D8E6));
      }
      if (inner.height > 900) {
        for (var i = 0; i < 2; i++) {
          final bx = Rect.fromLTWH(
            inner.left + 10 + i * inner.width / 2,
            inner.bottom - inner.height * 0.2,
            inner.width / 2 - 20,
            inner.height * 0.18,
          );
          canvas.drawRRect(RRect.fromRectAndRadius(bx, const Radius.circular(8)), Paint()..color = const Color(0x88D5E9F1));
        }
      }
      continue;
    }
    if (hood) {
      final box = Rect.fromLTWH(inner.left + 30, inner.bottom - 160, inner.width - 60, 150);
      canvas.drawRect(box, Paint()..color = const Color(0xFF5A5F65));
      canvas.drawRect(Rect.fromLTWH(inner.center.dx - 70, inner.top, 140, box.top - inner.top), Paint()..color = const Color(0xFFC8CCD0));
      continue;
    }
    // étagères : 1 dans un bas, selon la hauteur dans un haut ou une colonne
    final hMm = inner.height;
    final n = m.kind.isLow
        ? (hMm > 450 ? 1 : 0)
        : m.kind.isHigh
        ? math.max(1, (hMm / 400).floor() - 0) - (hMm < 700 ? 1 : 0)
        : (hMm / 380).floor();
    for (var i = 1; i <= n; i++) {
      final y = inner.top + inner.height * i / (n + 1);
      canvas.drawRect(Rect.fromLTWH(inner.left, y, inner.width, 18), Paint()..color = carcass);
      canvas.drawRect(Rect.fromLTWH(inner.left, y + 18, inner.width, 10), Paint()..color = Colors.black.withValues(alpha: 0.2));
    }
  }
}

/// Dessus d'un appareil (repère mm) : plaque gaz, évier inox, inox brossé.
void paintTopDecor(Canvas canvas, Rect r, String decor, Color color) {
  final la = r.width, lb = r.height;
  switch (decor) {
    case 'hob':
      canvas.drawRect(r, Paint()..color = const Color(0xFF17181A));
      final n = la > 700 || lb > 700 ? 5 : 4;
      final long = la >= lb;
      final ls = long ? la : lb, sh = long ? lb : la;
      final pts = <Offset>[
        Offset(ls * 0.27, sh * 0.28),
        Offset(ls * 0.73, sh * 0.28),
        Offset(ls * 0.27, sh * 0.72),
        Offset(ls * 0.73, sh * 0.72),
        if (n == 5) Offset(ls * 0.5, sh * 0.5),
      ];
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..color = const Color(0xFF5B5E63);
      final grid = Paint()
        ..strokeWidth = 10
        ..color = const Color(0xFF0B0B0C);
      for (var i = 0; i < pts.length; i++) {
        final q = long ? pts[i] : Offset(pts[i].dy, pts[i].dx);
        final rad = (i == 4 ? 0.2 : 0.14) * math.min(ls, sh * 2);
        canvas.drawCircle(q, rad * 0.55, Paint()..color = const Color(0xFF3A3C40));
        canvas.drawCircle(q, rad * 0.55, ring);
        canvas.drawCircle(q, rad * 0.25, Paint()..color = const Color(0xFF8D9096));
        for (var k = 0; k < 4; k++) {
          final ang = k * math.pi / 2 + math.pi / 4;
          canvas.drawLine(q + Offset(math.cos(ang), math.sin(ang)) * rad * 0.35, q + Offset(math.cos(ang), math.sin(ang)) * rad, grid);
        }
      }
    case 'sink' || 'sink:compact' || 'sink:drainer' || 'sink:2' || 'sink:2_drainer':
      canvas.drawRect(r, texturePaint('steel', const Color(0xFFC6CACE), 500));
      // Bordure périphérique inox
      canvas.drawRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = const Color(0xFF7A8188),
      );
      final m = math.min(la, lb) * 0.1;
      void basin(Rect b) {
        canvas.drawRRect(RRect.fromRectAndRadius(b, const Radius.circular(40)), Paint()..color = const Color(0xFF8E959C));
        canvas.drawRRect(
          RRect.fromRectAndRadius(b.deflate(12), const Radius.circular(34)),
          Paint()..shader = const LinearGradient(colors: [Color(0xFF737980), Color(0xFFB4BAC0)]).createShader(b),
        );
        canvas.drawCircle(b.center, 28, Paint()..color = const Color(0xFF4A4F55));
        canvas.drawCircle(b.center, 14, Paint()..color = const Color(0xFFC8CDD2));
      }

      final inner = r.deflate(m);
      if (decor == 'sink:drainer') {
        // bac à gauche, égouttoir rainuré à droite
        basin(Rect.fromLTRB(inner.left, inner.top, inner.left + inner.width * 0.55, inner.bottom));
        final dr = Rect.fromLTRB(inner.left + inner.width * 0.6, inner.top, inner.right, inner.bottom);
        for (var i = 1; i < 8; i++) {
          final x = dr.left + dr.width * i / 8;
          canvas.drawLine(Offset(x, dr.top + 20), Offset(x, dr.bottom - 20), Paint()
            ..color = const Color(0xFF9AA0A6)
            ..strokeWidth = 6);
        }
      } else if (decor == 'sink:2' || decor == 'sink:2_drainer') {
        basin(Rect.fromLTRB(inner.left, inner.top, inner.left + inner.width * 0.48, inner.bottom));
        basin(Rect.fromLTRB(inner.left + inner.width * 0.52, inner.top, inner.right, inner.bottom));
      } else {
        basin(inner);
      }
    case 'steel':
      canvas.drawRect(r, texturePaint('steel', color, 400));
  }
}
