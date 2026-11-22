// Export de la cuisine pour la vue WebGL (three.js) : géométrie en mm (repère du plan : x, y, z vers
// le haut), matériaux (couleur, texture, brillance) et images dessinées par le moteur Flutter
// (façades case par case, intérieurs, dessus de plaque et d'évier). Les images sont mises en cache :
// seules les nouvelles sont envoyées au navigateur.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../engine/engine.dart';
import 'app_state.dart';
import 'art_library.dart';
import 'art_page.dart' show artColor;
import 'finishes.dart';
import 'openings_ui.dart';
import 'fronts.dart';
import 'scene3d.dart';
import 'textures.dart';

/// Image prête pour le navigateur (pixels RGBA).
class SceneImage {
  final String key;
  final int width, height;
  final Uint8List rgba;
  const SceneImage(this.key, this.width, this.height, this.rgba);
}

/// Gorge Gola entre deux façades empilées : deux tiroirs d'un bas, ou deux façades ouvrantes d'une colonne.
bool golaBetween(CabinetModel m, FrontCell above, FrontCell below) {
  bool front(FrontCell c) => c.kind == CellKind.door || c.kind == CellKind.door2 || c.kind == CellKind.drawer;
  if (m.kind == CabinetKind.tall) return front(above) && front(below);
  return m.kind.isLow && above.kind == CellKind.drawer && below.kind == CellKind.drawer;
}

class SceneExporter {
  final Map<String, SceneImage> _images = {}; // déjà rendues
  final Set<String> _sent = {}; // déjà envoyées au navigateur

  /// Images rendues pendant la dernière construction et pas encore envoyées.
  List<SceneImage> takeNewImages() {
    final out = [for (final e in _images.entries) if (!_sent.contains(e.key)) e.value];
    _sent.addAll(out.map((x) => x.key));
    return out;
  }

  Future<SceneImage> _image(String key, double wMm, double hMm, void Function(Canvas c) draw, {double pxPerMm = 0.5, int maxPx = 512}) async {
    final hit = _images[key];
    if (hit != null) return hit;
    final k = math.min(pxPerMm, maxPx / math.max(wMm, hMm));
    final w = math.max(2, (wMm * k).round()), h = math.max(2, (hMm * k).round());
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.scale(w / wMm, h / hMm);
    draw(c);
    final img = await rec.endRecording().toImage(w, h);
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    img.dispose();
    final out = SceneImage(key, w, h, data!.buffer.asUint8List());
    _images[key] = out;
    return out;
  }

  Future<String?> _bank(String? tex) async {
    if (tex == null) return null;
    final img = TextureBank.instance[tex];
    if (img == null) return null;
    final key = 'bank:$tex';
    if (!_images.containsKey(key)) {
      final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      _images[key] = SceneImage(key, img.width, img.height, data.buffer.asUint8List());
    }
    return key;
  }

  static String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  /// Matériau : couleur, texture (clé), taille réelle du motif, rugosité, métal.
  Future<Map<String, dynamic>> _mat(Finish f, {double rough = 0.6, double metal = 0, bool vertical = false}) async => {
        'color': _hex(f.textured ? Colors.white : f.color),
        if (f.textured) 'map': await _bank(f.tex),
        'tile': f.tile,
        'rough': f.gloss ? 0.25 : rough,
        'metal': f.tex == 'steel' ? 0.35 : metal,
        if (vertical) 'vertical': true,
      };

  static Map<String, dynamic> _plain(Color c, {double rough = 0.7, double metal = 0}) => {'color': _hex(c), 'rough': rough, 'metal': metal};

  static Map<String, dynamic> _box(Box3 b) => {'x0': b.x0, 'y0': b.y0, 'z0': b.z0, 'x1': b.x1, 'y1': b.y1, 'z1': b.z1};

  static Map<String, dynamic> _frame(Wall w) => {'ox': w.x0, 'oy': w.y0, 'dx': w.dx, 'dy': w.dy, 'nx': w.nx, 'ny': w.ny};

  /// Construit la scène complète (JSON) ; les images nouvelles sont ensuite prises par [takeNewImages].
  Future<Map<String, dynamic>> build(AppState st) async {
    final e = st.engine;
    final p = st.project;
    final room = p.room;
    final style = p.style;
    final std = p.standards;
    final carcass = finishById(carcasses, style.carcass);
    final top = worktopFinish(style, style.worktop);
    final lowFront = frontFinish(style, style.frontLower ?? style.front);
    final (_, hSize, hColor) = handleLook(style, st.db?.handles);

    // ---- pièce : murs (avec ouvertures), sol, crédence
    final walls = <Map<String, dynamic>>[];
    for (final w in room.walls) {
      if (!w.straight) {
        // arc : découpé en pans droits (sans ouverture), masqués avec l'arc
        final pts = w.points(16);
        for (var i = 0; i + 1 < pts.length; i++) {
          final (ax, ay) = pts[i];
          final (bx, by) = pts[i + 1];
          final len = math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
          final dx = (bx - ax) / len, dy = (by - ay) / len;
          walls.add({'id': '${w.id}~$i', 'ox': ax, 'oy': ay, 'dx': dx, 'dy': dy, 'nx': -dy, 'ny': dx, 'len': len + 2, 'openings': const []});
        }
        continue;
      }
      walls.add({
        'id': w.id,
        ..._frame(w),
        'len': w.length,
        'openings': [
          for (final o in p.openings.where((o) => o.wallId == w.id))
            () {
              final m = openingModelOf(o);
              return {
                's': o.s, 'w': o.width, 'z': o.z, 'h': o.height, 'door': o.isDoor,
                'mech': m?.mechanism ?? (o.isDoor ? 'hinged_single' : 'casement_inward'),
                'glazed': m?.glazed ?? !o.isDoor,
                'leaf': openingLeafColor(m).toARGB32() & 0xFFFFFF,
                'hinge': o.hinge,
              };
            }(),
        ],
      });
    }
    final splash = <Map<String, dynamic>>[];
    for (final w in room.walls.where((w) => w.enabled)) {
      for (final (a, b) in e.runs(w.id, (m) => e.kitchen && m.kind.isLow)) {
        final zBottom = std.worktopTop.toDouble();
        var zTop = zBottom + 600.0;
        for (final c in p.items.where((c) => c.wallId == w.id && e.modelOf(c).kind.isHigh && c.s < b && a < c.right)) {
          zTop = math.min(zTop, c.z);
        }
        if (zTop <= zBottom) continue;

        // Découpe précise de la crédence autour des ouvertures (fenêtres et portes)
        final wallOps = p.openings
            .where((o) => o.wallId == w.id && o.right > a && o.s < b && o.z < zTop && o.z + o.height > zBottom)
            .toList()
          ..sort((x, y) => x.s.compareTo(y.s));

        if (wallOps.isEmpty) {
          splash.add({'wall': w.id, 's0': a, 's1': b, 'z0': zBottom, 'z1': zTop});
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
              if (segZ > zBottom) {
                splash.add({'wall': w.id, 's0': curS, 's1': os0, 'z0': zBottom, 'z1': segZ});
              }
            }
            // Allège sous la fenêtre si le dormant est au-dessus du plan de travail
            if (!o.isDoor && o.z > zBottom + 5.0) {
              final sillTop = math.min(zTop, o.z);
              splash.add({'wall': w.id, 's0': os0, 's1': os1, 'z0': zBottom, 'z1': sillTop});
            }
            // Au-dessus de la fenêtre si l'imposte est sous zTop
            if (!o.isDoor && o.z + o.height < zTop - 5.0) {
              splash.add({'wall': w.id, 's0': os0, 's1': os1, 'z0': o.z + o.height, 'z1': zTop});
            }
            curS = math.max(curS, os1);
          }
          if (b > curS + 1.0) {
            var segZ = zBottom + 600.0;
            for (final c in p.items.where((c) => c.wallId == w.id && e.modelOf(c).kind.isHigh && c.s < b && curS < c.right)) {
              segZ = math.min(segZ, c.z);
            }
            if (segZ > zBottom) {
              splash.add({'wall': w.id, 's0': curS, 's1': b, 'z0': zBottom, 'z1': segZ});
            }
          }
        }
      }
    }

    // ---- solides : caissons, plans de travail, plinthes, îlot, appareils
    final solids = <Map<String, dynamic>>[];
    final tops = <Map<String, dynamic>>[];
    final fronts = <Map<String, dynamic>>[];
    final items = <Map<String, dynamic>>[];
    final carcassMat = await _mat(carcass, rough: 0.7);

    for (final c in p.items) {
      final m = e.modelOf(c);
      final fr = frontOfItem(style, c, m);
      final isPanel = m.kind.isFiller || m.kind == CabinetKind.coverPanel || m.kind == CabinetKind.islandPanel;
      final frMat = await _mat(fr, rough: 0.5, vertical: true);
      final boxes = e.boxesOf(c);
      final corner = m.kind.isCorner && m.isCarcass;
      final opens = openableCells(m, c).isNotEmpty || corner;
      for (var bi = 0; bi < boxes.length; bi++) {
        final b = boxes[bi].box;
        if (opens && (bi == 0 || corner)) {
          // caisson creux (côtés, dessus, dessous, dos de 18 mm) : l'intérieur se voit quand on ouvre ;
          // la façade (18 mm + tampon) est un volume à part devant
          final w = room.wall(boxes[bi].wallId);
          final (s0, s1, t0, t1) = w.boxToWall(b);
          final tf = t1 - 20; // face avant du caisson
          Box3 at(double sa, double sb, double ta, double tb, double za, double zb) {
            final (ax, ay) = w.toPlan(sa, ta);
            final (bx, by) = w.toPlan(sb, tb);
            return Box3(math.min(ax, bx), math.min(ay, by), za, math.max(ax, bx), math.max(ay, by), zb);
          }

          final topPanels = m.kind.isLow
              ? [
                  at(s0 + 18, s1 - 18, t0, t0 + 70, b.z1 - 18, b.z1), // traverse arrière
                  if (style.handle != 'gola') at(s0 + 18, s1 - 18, tf - 70, tf, b.z1 - 18, b.z1), // traverse avant (remplacée par le profil Gola)
                ]
              : [
                  at(s0 + 18, s1 - 18, t0, tf, b.z1 - 18, b.z1), // dessus plein (hauts et colonnes)
                ];

          // profil Gola (sans poignée) : gorge en aluminium fixée dans le caisson, sous le plan de travail
          // (et entre deux tiroirs) ; les façades s'arrêtent dessous, en dégageant la prise de main
          if (style.handle == 'gola' && !m.kind.isFiller && !m.isHoodUnit) {
            final golaMat = _plain(const Color(0xFFB9BDC2), rough: 0.35, metal: 0.6);
            // gorge de 26 mm de profondeur et 33 mm de haut : fond, lèvre basse, rebord haut
            void channel(double zTop) {
              solids.add({..._box(at(s0, s1, tf - 26, tf - 23, zTop - 33, zTop)), 'mat': golaMat, 'uid': c.uid});
              solids.add({..._box(at(s0, s1, tf - 26, tf, zTop - 33, zTop - 30)), 'mat': golaMat, 'uid': c.uid});
              solids.add({..._box(at(s0, s1, tf - 26, tf, zTop - 3, zTop)), 'mat': golaMat, 'uid': c.uid});
            }
            if (m.kind.isLow) channel(b.z1);
            if (m.kind.isHigh) channel(b.z0 + 33); // meuble haut : gorge en bas
            final rows = cellsOf(rowsOf(m, c) ?? seedRows(m, c), c.height);
            final total = rows.isEmpty ? (b.z1 - b.z0) : rows.last.y + rows.last.h;
            final kz = (b.z1 - b.z0) / (total <= 0 ? 1 : total);
            for (var i = 1; i < rows.length; i++) {
              if (golaBetween(m, rows[i - 1], rows[i])) channel(b.z1 - rows[i].y * kz); // entre tiroirs, entre portes de colonne
            }
          }
          // Détection des côtés gauche et droit exposés (ex: côté visible d'une colonne à côté d'un plan de travail)
          // (un voisin ne cache le côté que s'il monte et descend autant : un haut ne cache pas le côté d'un bas)
          bool hides(PlacedCabinet o) => o.z <= c.z + 50 && o.top >= c.top - 50 && o.depth >= c.depth - 50;
          final beside = p.items.where((o) => o != c && o.wallId == c.wallId && !e.modelOf(o).isFreeHood);
          final leftExposed = !beside.any((o) => (o.s + o.width - c.s).abs() < 15 && hides(o));
          final rightExposed = !beside.any((o) => (c.s + c.width - o.s).abs() < 15 && hides(o));

          // Finition de façade pour les côtés / joues visibles (choix personnalisé ou accordé aux bas/hauts)
          final epf = style.endPanelFinish;
          final sideFinish = epf != null
              ? frontFinish(style, epf)
              : (m.kind.isHigh
                  ? frontFinish(style, style.frontUpper ?? style.front)
                  : frontFinish(style, style.frontLower ?? style.front));
          final sideMat = await _mat(sideFinish, rough: 0.5, vertical: true);

          final leftSideMat = (leftExposed && (c.s > 10 || style.endPanels)) ? sideMat : carcassMat;
          final rightSideMat = (rightExposed && (c.s + c.width < w.length - 10 || style.endPanels)) ? sideMat : carcassMat;

          for (final (bx, mat) in [
            (at(s0, s0 + 18, t0, tf, b.z0, b.z1), leftSideMat), // côté gauche
            (at(s1 - 18, s1, t0, tf, b.z0, b.z1), rightSideMat), // côté droit
            (at(s0 + 18, s1 - 18, t0, tf, b.z0, b.z0 + 18), carcassMat), // dessous
            for (final pan in topPanels) (pan, carcassMat),
            (at(s0 + 18, s1 - 18, t0, t0 + 18, b.z0 + 18, b.z1 - 18), carcassMat), // dos
          ]) {
            solids.add({..._box(bx), 'mat': mat, 'uid': c.uid});
          }
          // étagères réelles dans les cases à porte sans appareil
          final apps = appliancesOf(m, c);
          if (apps.isEmpty && !e.isWashing(m)) {
            final inner = b.z1 - b.z0 - 36;
            final n = m.kind == CabinetKind.tall ? 4 : (inner > 600 ? 2 : (inner > 330 ? 1 : 0));
            final drawers = openableCells(m, c).where((x) => x.kind == CellKind.drawer).fold<double>(0, (a, x) => a + x.h);
            final top = b.z1 - 18, bottom = b.z0 + 18 + (drawers > 0 && m.kind.isLow ? drawers : 0);
            for (var k = 1; k <= n; k++) {
              final z = bottom + (top - bottom) * k / (n + 1);
              if (z < bottom + 120 || z > top - 120) continue;
              solids.add({..._box(at(s0 + 18, s1 - 18, t0 + 18, tf - 30, z - 9, z + 9)), 'mat': carcassMat, 'uid': c.uid});
            }
          }
        } else if (!m.isFreeHood) {
          solids.add({..._box(b), 'mat': isPanel ? frMat : carcassMat, 'uid': c.uid});
        }
      }
      final w0 = room.wall(boxes.first.wallId);
      items.add({'uid': c.uid, ..._frame(w0), 's': c.s, 'z': c.z, 'canZ': e.canMoveVertically(m), 'depth': c.depth});

      // façades
      final cells = openableCells(m, c);
      final all = cellsOf(rowsOf(m, c) ?? seedRows(m, c), c.height);
      final apps = appliancesOf(m, c);
      Future<String> frontImg(String what, double wMm, double hMm, List<FrontCell>? cs, {String? opening, bool? handleTop}) async {
        final key = 'front|${m.id}|$what|${wMm.round()}x${hMm.round()}|${fr.id}|${style.handle}|${style.handleId}|${style.handleSize}|'
            '${style.handleFinish}|${style.tallXxl}|${opening ?? c.opening}|${c.variant}|${apps.join(',')}|${carcass.id}|${fr.textured}|$handleTop';
        final img = await _image(key, wMm, hMm, (cv) {
          paintFront(cv, Rect.fromLTWH(0, 0, wMm, hMm), m,
              fill: fr.color,
              stroke: shade(fr.color, -0.3),
              line: lineOn(fr.color),
              opening: opening ?? c.opening,
              variant: c.variant,
              handle: style.handle,
              handleSize: hSize,
              handleColor: hColor,
              tallXxl: style.tallXxl,
              fillPaint: fr.paint(vertical: true),
              cells: cs,
              realistic: true,
              pxPerMm: 1,
              appliances: apps,
              carcass: carcass.color,
              gloss: fr.gloss,
              handleTop: handleTop,
              golaProfile: false); // la gorge est une pièce du caisson, pas un dessin sur la porte
        });
        return img.key;
      }

      Future<String> interiorImg(FrontCell cell, double wMm, double hMm) async {
        final key = 'inside|${m.id}|${cell.kind.name}|${wMm.round()}x${hMm.round()}|${carcass.id}|${apps.join(',')}';
        final img = await _image(key, wMm, hMm, (cv) {
          paintCabinetInterior(e, cv, Rect.fromLTWH(0, 0, wMm, hMm), [FrontCell(cell.kind, 0, hMm, cell.hinge, -1)], hMm, carcass.color, m, c);
        }, pxPerMm: 0.35);
        return img.key;
      }

      for (var bi = 0; bi < boxes.length; bi++) {
        final tb = boxes[bi];
        final w = room.wall(tb.wallId);
        final b = tb.box;
        final (s0, s1, _, t1) = w.boxToWall(b);
        final width = s1 - s0, height = b.z1 - b.z0;
        final parts = <Map<String, dynamic>>[];
        if (bi == 0 && cells.isNotEmpty) {
          final total = all.isEmpty ? height : all.last.y + all.last.h;
          final kz = height / (total <= 0 ? 1 : total);
          for (final cell in all) {
            final zTop = b.z1 - cell.y * kz, h = cell.h * kz;
            final moving = cells.any((x) => x.y == cell.y && x.kind == cell.kind);
            final kind = !moving
                ? 'static'
                : switch (cell.kind) {
                    CellKind.drawer => 'drawer',
                    CellKind.flap => m.kind.isHigh ? 'flapUp' : 'flapDown',
                    _ => 'door',
                  };
            final halves = kind == 'door' && (cell.kind == CellKind.door2 || (cell.kind == CellKind.glass && width >= 790))
                ? [(s0, width / 2, 'left'), (s0 + width / 2, width / 2, 'right')]
                : [
                    (
                      s0,
                      width,
                      (c.opening == 'hinged_left' || (c.opening != 'hinged_right' && cell.hinge != 'right')) ? 'left' : 'right',
                    ),
                  ];
            final gola = style.handle == 'gola' && m.isCarcass && !m.kind.isFiller;
            var fz0 = zTop - h, fz1 = zTop;
            if (gola && ((m.kind.isLow && cell.y < 0.5) || (all.indexOf(cell) > 0 && golaBetween(m, all[all.indexOf(cell) - 1], cell)))) {
              fz1 -= 30; // sous le profil : on passe les doigts dans la gorge
            } else if (gola && m.kind.isHigh && cell.y + cell.h >= total - 0.5) {
              fz0 += 30; // meuble haut : gorge en bas
            }
            for (final (ls, lw, hinge) in halves) {
              final single = FrontCell(cell.kind == CellKind.door2 ? CellKind.door : cell.kind, 0, fz1 - fz0, hinge, cell.index);
              final m2 = m.id == 'base_integrated_dishwasher_door' ? null : [single];
              // Hauteur de poignée ergonomique :
              // - Sur meuble haut : poignée en bas (handleTop = false)
              // - Sur meuble bas : poignée en haut (handleTop = true)
              // - Sur colonne (tall) :
              //   * Porte du haut (au-dessus de 1100 mm) : poignée en bas de cette porte (handleTop = false)
              //   * Porte du bas (en dessous de 1100 mm) : poignée en haut de cette porte (handleTop = true)
              //   * Porte unique pleine hauteur : poignée à hauteur ergonomique 1050 mm
              final isLower = m.kind == CabinetKind.tall ? (cell.y + cell.h / 2 > height * 0.45) : !m.kind.isHigh;
              parts.add({
                'kind': kind,
                'hinge': hinge,
                's0': ls,
                's1': ls + lw,
                'z0': fz0,
                'z1': fz1,
                'img': await frontImg('${cell.kind.name}-$hinge', lw, fz1 - fz0, m2, opening: hinge == 'left' ? 'hinged_left' : 'hinged_right', handleTop: isLower),
                if (kind != 'static') 'inside': await interiorImg(cell, lw, fz1 - fz0),
                if (kind != 'static') 'insideT': 19.0,
              });
            }
          }
        } else if (corner) {
          // angle en L / pan coupé : une porte par bras, articulée côté extérieur ; borgne : porte d'accès + panneau fixe
          final door = FrontCell(CellKind.door, 0, height, null, -1);
          Future<void> addDoor(double a, double bb, String hinge) async {
            if (bb - a < 60) return;
            parts.add({
              'kind': 'door',
              'hinge': hinge,
              's0': a,
              's1': bb,
              'z0': b.z0,
              'z1': b.z1,
              'img': await frontImg('corner-$bi-$hinge-${(bb - a).round()}', bb - a, height, [door],
                  opening: hinge == 'left' ? 'hinged_left' : 'hinged_right'),
              'insideT': 19.0,
            });
          }

          if (m.shape == CabinetShape.blind) {
            final wl = room.wall(c.wallId);
            final blindAtEnd = c.right >= wl.length - 60 || c.s > 60;
            final dw = blindDoorWidth(m, c).clamp(200.0, width);
            final (da, db) = blindAtEnd ? (s0, s0 + dw) : (s1 - dw, s1);
            await addDoor(da, db, blindAtEnd ? 'left' : 'right');
            final (pa, pb) = blindAtEnd ? (db, s1) : (s0, da);
            parts.add({'kind': 'static', 's0': pa, 's1': pb, 'z0': b.z0, 'z1': b.z1, 'img': await frontImg('blind$bi-${(pb - pa).round()}', pb - pa, height, const [])});
          } else if (bi == 0) {
            // bras le long du mur : de l'extrémité jusqu'au retour
            await addDoor(s0, math.min(s1, room.wall(c.wallId).length - c.depth), 'left');
          } else {
            await addDoor(math.max(s0, c.depth.toDouble()), s1, 'right');
          }
        } else {
          parts.add({'kind': 'static', 's0': s0, 's1': s1, 'z0': b.z0, 'z1': b.z1, 'img': await frontImg('box$bi', width, height, frontCells(m, c, realistic: true))});
        }
        fronts.add({'uid': c.uid, ..._frame(w), 't': t1, 'depth': c.depth, 'parts': parts, if (m.id.contains('mirror')) 'mirror': true});
      }
    }

    // Détection automatique et robuste du caisson évier et du caisson plaque dans la cuisine
    PlacedCabinet? designatedSink;
    PlacedCabinet? designatedHob;
    if (e.kitchen) {
      designatedSink = p.items.where((c) {
        final m = e.modelOf(c);
        return m.id.contains('sink') || m.id.contains('evier') || e.isWashing(m) ||
            (c.appliances?.any((a) => a.contains('sink')) ?? false);
      }).firstOrNull;
      designatedSink ??= p.items.where((c) {
        final m = e.modelOf(c);
        final isCook = m.id == 'base_cooktop_oven' || m.id == 'base_oven_built_in' || e.isCooking(m) || m.id.contains('cooktop');
        return m.kind.isLow && m.isCarcass && !m.kind.isCorner && !isCook && c.width >= 600;
      }).firstOrNull;

      designatedHob = p.items.where((c) {
        final m = e.modelOf(c);
        return m.id == 'base_cooktop_oven' || (c.appliances?.any((a) => a.contains('cooktop')) ?? false);
      }).firstOrNull;
      designatedHob ??= p.items.where((c) {
        final m = e.modelOf(c);
        return (m.id == 'base_oven_built_in' || m.id.contains('oven')) && m.kind.isLow;
      }).firstOrNull;
    }

    // Réservations / découpes précises du plan de travail pour l'évier et la plaque (vrais trous)
    final cutoutsByWall = <String, List<({double s0, double s1, double t0, double t1})>>{};
    const wd = worktopDepth * 1.0;
    for (final c in p.items) {
      final m = e.modelOf(c);
      if (!m.kind.isLow || !m.isCarcass || m.kind.isCorner) continue;
      final isCook = (c == designatedHob) || m.id == 'base_cooktop_oven' || m.id == 'base_oven_built_in' || (e.isCooking(m) && m.kind.isLow) || m.id.contains('cooktop') || (c.appliances?.any((a) => a.contains('cooktop')) ?? false);
      final isSink = (c == designatedSink) || m.id == 'base_sink' || e.isWashing(m) || m.id.contains('sink') || m.id.contains('evier') || (c.appliances?.any((a) => a.contains('sink')) ?? false);

      if (isSink) {
        final sk = KitchenFixtures.sink(style.sink);
        final bw = math.min(c.width - 40.0, sk.length.toDouble());
        final sd = math.min(sk.depth.toDouble(), wd - 80.0);
        final s0 = c.s + (c.width - bw) / 2;
        final t0 = (wd - sd) / 2;
        cutoutsByWall.putIfAbsent(c.wallId, () => []).add((s0: s0, s1: s0 + bw, t0: t0, t1: t0 + sd));
      } else if (isCook && !m.id.contains('sans_plaque')) {
        final hw = style.hobWidth > 0
            ? style.hobWidth.toDouble() * 10
            : (c.width >= 800 ? (c.width >= 900 ? 880.0 : 770.0) : 590.0);
        final hd = 515.0;
        final s0 = c.s + (c.width - hw) / 2;
        final t0 = (wd - hd) / 2;
        cutoutsByWall.putIfAbsent(c.wallId, () => []).add((s0: s0, s1: s0 + hw, t0: t0, t1: t0 + hd));
      }
    }

    // plans de travail et plinthes (avec découpes réelles autour des appareils)
    final topMat = await _mat(top, rough: top.tex?.startsWith('marble') ?? false ? 0.3 : 0.55);
    final plinthMat = _plain(shade(lowFront.color, -0.12), rough: 0.6);
    for (final w in room.walls.where((w) => w.enabled)) {
      final cuts = (cutoutsByWall[w.id] ?? [])..sort((a, b) => a.s0.compareTo(b.s0));
      for (final (a, b) in e.runs(w.id, (m) => e.kitchen && m.kind.isLow)) {
        final inRun = cuts.where((x) => x.s0 < b - 20 && x.s1 > a + 20).toList();
        if (inRun.isEmpty) {
          solids.add({..._box(w.strip(a, b - a, worktopDepth.toDouble(), std.baseTop.toDouble(), std.worktopThickness.toDouble())), 'mat': topMat, 'top': true});
        } else {
          var curS = a;
          for (final cut in inRun) {
            final cs0 = math.max(a, cut.s0);
            final cs1 = math.min(b, cut.s1);
            if (cs0 > curS + 0.5) {
              solids.add({..._box(w.stripRange(curS, cs0 - curS, 0, wd, std.baseTop.toDouble(), std.worktopThickness.toDouble())), 'mat': topMat, 'top': true});
            }
            // Bande arrière de plan (crédence / dosseret de robinetterie)
            if (cut.t0 > 0.5) {
              solids.add({..._box(w.stripRange(cs0, cs1 - cs0, 0, cut.t0, std.baseTop.toDouble(), std.worktopThickness.toDouble())), 'mat': topMat, 'top': true});
            }
            // Bande avant de plan (nez de marche / chant avant)
            if (wd - cut.t1 > 0.5) {
              solids.add({..._box(w.stripRange(cs0, cs1 - cs0, cut.t1, wd, std.baseTop.toDouble(), std.worktopThickness.toDouble())), 'mat': topMat, 'top': true});
            }
            // Entre cut.t0 et cut.t1 : le trou d'encastrement reste ouvert et creux !
            curS = cs1;
          }
          if (b > curS + 0.5) {
            solids.add({..._box(w.stripRange(curS, b - curS, 0, wd, std.baseTop.toDouble(), std.worktopThickness.toDouble())), 'mat': topMat, 'top': true});
          }
        }
      }
      for (final (a, b) in e.runs(w.id, (m) => m.floorSupport)) {
        solids.add({..._box(w.strip(a, b - a, 540, 0, std.plinthHeight.toDouble())), 'mat': plinthMat});
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
        solids.add({..._box(box(a, b, -isl.overhang, Island.depth + 20, std.baseTop.toDouble(), std.worktopTop.toDouble())), 'mat': topMat, 'top': true});
        solids.add({..._box(box(a, b, -18, 0, 0, std.baseTop.toDouble())), 'mat': await _mat(lowFront, vertical: true)});
      }
      for (final (a, b) in e.runs('I', (m) => m.floorSupport)) {
        solids.add({..._box(box(a, b, 0, 540, 0, std.plinthHeight.toDouble())), 'mat': plinthMat});
      }
    }

    final steel = _plain(const Color(0xFFC4C8CC), rough: 0.35, metal: 0.35);
    final kitchenFixtures = <Map<String, dynamic>>[];
    for (final c in p.items) {
      final m = e.modelOf(c);
      final w = room.wall(c.wallId);
      final topZ = std.worktopTop.toDouble();
      final isCookBase = (c == designatedHob) || m.id == 'base_cooktop_oven' || m.id == 'base_oven_built_in' || (e.isCooking(m) && m.kind.isLow) || m.id.contains('cooktop') || (c.appliances?.any((a) => a.contains('cooktop')) ?? false);
      final isSinkBase = (c == designatedSink) || m.id == 'base_sink' || e.isWashing(m) || m.id.contains('sink') || m.id.contains('evier') || (c.appliances?.any((a) => a.contains('sink')) ?? false);
      final isHoodUnit = m.id == 'wall_integrated_hood' || m.id.contains('hood') || m.id.contains('hotte');

      if (isCookBase) {
        final hasHob = !m.id.contains('sans_plaque');
        if (hasHob) {
          final hw = style.hobWidth > 0
              ? style.hobWidth.toDouble() * 10
              : (c.width >= 800 ? (c.width >= 900 ? 880.0 : 770.0) : 590.0);
          final hd = 515.0;
          final (cx, cy) = w.toPlan(c.s + c.width / 2, wd / 2);
          kitchenFixtures.add({
            'uid': 'hob:${c.uid}',
            'pick': 'item:${c.uid}',
            'kind': 'fixture',
            'type': 'kitchen_hob',
            'x': cx, 'y': cy, 'z': topZ,
            'rot': w.rot,
            'w': hw, 'd': hd, 'h': 40.0,
            'hobType': style.hobType,
          });
        }
        // Four encastrable parfaitement aligné dans le caisson (non saillant)
        const ovenD = 550.0;
        final (ox, oy) = w.toPlan(c.s + c.width / 2, c.depth - ovenD / 2);
        kitchenFixtures.add({
          'uid': 'oven:${c.uid}',
          'pick': 'item:${c.uid}',
          'kind': 'fixture',
          'type': 'kitchen_oven',
          'x': ox, 'y': oy, 'z': std.plinthHeight.toDouble() + math.max(120.0, c.height - 595.0 - 20.0),
          'rot': w.rot,
          'w': c.width.toDouble() - 4, 'd': ovenD, 'h': 595.0,
          'finish': style.ovenFinish,
          'handle': style.ovenHandle,
        });
      } else if (m.kind == CabinetKind.tall && (m.id.contains('oven') || (c.appliances?.any((a) => a.contains('oven')) ?? false))) {
        // Four dans colonne haute (hauteur ergonomique)
        const ovenD = 550.0;
        final (ox, oy) = w.toPlan(c.s + c.width / 2, c.depth - ovenD / 2);
        kitchenFixtures.add({
          'uid': 'oven:${c.uid}',
          'pick': 'item:${c.uid}',
          'kind': 'fixture',
          'type': 'kitchen_oven',
          'x': ox, 'y': oy, 'z': std.plinthHeight.toDouble() + 750.0,
          'rot': w.rot,
          'w': c.width.toDouble() - 4, 'd': ovenD, 'h': 595.0,
          'finish': style.ovenFinish,
          'handle': style.ovenHandle,
        });
      } else if (isSinkBase) {
        final sk = KitchenFixtures.sink(style.sink), fc = KitchenFixtures.faucet(style.faucet);
        final bw = math.min(c.width - 40.0, sk.length.toDouble());
        final sd = math.min(sk.depth.toDouble(), wd - 80);
        final (cx, cy) = w.toPlan(c.s + c.width / 2, wd / 2);
        kitchenFixtures.add({
          'uid': 'sink:${c.uid}',
          'pick': 'item:${c.uid}',
          'kind': 'fixture',
          'type': 'kitchen_sink',
          'x': cx, 'y': cy, 'z': topZ,
          'rot': w.rot,
          'w': bw, 'd': sd, 'h': 200.0,
          'mount': style.sinkMount,
          'layout': sk.layout,
          'sinkFinish': style.sinkFinish,
          'faucet': fc.id,
          'faucetFinish': style.faucetFinish,
          'faucetLever': style.faucetLever,
          'faucetHeight': fc.height.toDouble(),
          'spring': fc.spring,
          'pullout': fc.pullout,
          'swan': fc.swan,
          'square': fc.square,
        });
      } else if (m.isFreeHood) {
        // hotte posée librement : dessinée entière (hotte + cheminée jusqu'au plafond)
        final (hx, hy) = w.toPlan(c.s + c.width / 2, c.depth / 2);
        kitchenFixtures.add({
          'uid': 'hood:${c.uid}',
          'pick': 'item:${c.uid}',
          'kind': 'fixture',
          'type': 'kitchen_hood_free',
          'hoodStyle': m.id.replaceFirst('hood_free_', ''),
          'x': hx, 'y': hy, 'z': c.z.toDouble(),
          'rot': w.rot,
          'w': c.width.toDouble(), 'd': c.depth.toDouble(), 'h': (room.height - c.z).toDouble(),
        });
      } else if (isHoodUnit) {
        // visière à fleur, sous le caisson (elle ne dépasse plus des façades voisines)
        solids.add({..._box(w.strip(c.s + 15, c.width - 30.0, math.min(350.0, c.depth.toDouble()), c.z - 35, 35)), 'mat': steel});
        final (hx, hy) = w.toPlan(c.s + c.width / 2, c.depth / 2);
        kitchenFixtures.add({
          'uid': 'hood:${c.uid}',
          'pick': 'item:${c.uid}',
          'kind': 'fixture',
          'type': 'kitchen_hood',
          'x': hx, 'y': hy, 'z': c.z.toDouble(),
          'rot': w.rot,
          'w': c.width.toDouble(), 'd': c.depth.toDouble(), 'h': c.height.toDouble(),
        });
      }
    }

    // joues de finition automatiques
    if (style.endPanels) {
      for (final j in endPanels(e)) {
        final w = room.wall(j.wallId);
        final finishId = style.endPanelFinish ?? (j.high ? (style.frontUpper ?? style.front) : (style.frontLower ?? style.front));
        final f = frontFinish(style, finishId);
        solids.add({..._box(w.strip(j.s, EndPanel.thickness, j.depth, j.z0, j.height)), 'mat': await _mat(f, rough: 0.5, vertical: true)});
      }
    }

    // éclairage : rubans LED sous les hauts (et dans les plinthes)
    final lights = <Map<String, dynamic>>[];
    if (style.lighting != 'aucun') {
      for (final c in p.items) {
        final m = e.modelOf(c);
        if (!m.kind.isHigh || m.isHoodUnit || m.isFreeHood) continue;
        final w = room.wall(c.wallId);
        final b = w.strip(c.s + 25, c.width - 50.0, c.depth - 70.0, c.z - 6, 6);
        final (cx, cy) = w.toPlan(c.s + c.width / 2, c.depth - 60.0);
        lights.add({..._box(b), 'px': cx, 'py': cy, 'pz': c.z - 20, 'spot': true});
      }
      if (style.lighting == 'led_hauts_plinthes') {
        for (final w in room.walls.where((w) => w.enabled)) {
          for (final (a, b) in e.runs(w.id, (m) => m.floorSupport)) {
            lights.add({..._box(w.strip(a + 20, b - a - 40, 545, 8, 6)), 'spot': false});
          }
        }
      }
    }

    return {
      'room': {'w': room.width, 'd': room.depth, 'h': room.height},
      if (room.outline != null) 'floorPoly': [for (final (x, y) in room.floorPolygon) [x, y]],
      'lights': lights,
      'walls': walls,
      // sol : béton ciré et carrelages plus satinés que le parquet
      'floor': await _mat(floorFinish(style), rough: (floorFinish(style).tex ?? '').startsWith('parquet') ? 0.6 : 0.35),
      'wall': await _mat(wallFinish(style), rough: 0.9),
      'splashMat': style.splash == null ? null : await _mat(splashFinish(style), rough: 0.35),
      'splash': style.splash == null ? const [] : splash,
      'solids': solids,
      'tops': tops,
      'fronts': fronts,
      'items': items,
      // objets de la pièce : sanitaires (volumes générés) et modèles glTF du catalogue libre, chargés à la demande
      'objects': [
        for (final ob in p.objects)
          {
            'uid': ob.uid,
            'kind': ob.isFixture ? 'fixture' : 'model',
            'type': ob.isFixture ? ob.ref.substring(8) : ob.ref,
            'file': ob.isFixture ? null : st.objectCatalog.where((c) => c.id == ob.ref).firstOrNull?.file,
            'yaw': ob.isFixture ? 0 : st.objectCatalog.where((c) => c.id == ob.ref).firstOrNull?.yaw ?? 0,
            'x': ob.x, 'y': ob.y, 'z': ob.z, 'rot': ob.rot, 'w': ob.w, 'h': ob.h, 'd': ob.d,
            if (ob.ref.startsWith('lib:')) 'panels': ArtLibrary.instance.panelsFor(ob, artColor),
          }
      ],
      // vasques en céramique posées sur les meubles vasque (le toucher choisit le meuble)
      'basins': [
        for (final c in p.items)
          if (c.modelId.contains('vanity') && c.wallId != 'I')
            () {
              final w = room.wall(c.wallId);
              final (x, y) = w.toPlan(c.s + c.width / 2, c.depth / 2);
              return {
                'uid': 'vasque-${c.uid}',
                'pick': c.uid,
                'kind': 'fixture',
                'type': c.modelId.contains('double') && c.width >= 1000 ? 'vasque_double' : 'lavabo',
                'x': x, 'y': y, 'z': c.z + c.height - 110, 'rot': room.wall(c.wallId).rot,
                'w': c.width, 'h': 150, 'd': c.depth,
              };
            }(),
      ],
      'kitchenFixtures': kitchenFixtures,
      'socketFinish': style.socketFinish,
      // points de réseau (prises, interrupteurs, sorties, arrivées d'eau…) : plaques et appareils sur les murs
      'netPoints': !p.networks
          ? const []
          : [
              for (final x in visiblePoints(p))
                if (!_hiddenIn3d(p, x))
                if (x.onCeiling)
                  {'uid': x.uid, 'kind': x.kind.name, 'x': x.s, 'y': x.z, 'z': room.height, 'dx': 1.0, 'dy': 0.0, 'nx': 0.0, 'ny': 0.0, 'ceiling': true}
                else if (x.wallId == 'I' ? room.island != null : room.order.contains(x.wallId))
                  () {
                    final w = room.wall(x.wallId);
                    // îlot : sur l'habillage côté repas (face arrière)
                    final (px, py) = x.wallId == 'I' ? w.toPlan(x.s, -2) : w.toPlan(x.s, 0);
                    final sign = x.wallId == 'I' ? -1.0 : 1.0;
                    return {
                      'uid': x.uid, 'kind': x.kind.name, 'x': px, 'y': py, 'z': x.z,
                      'dx': w.dx * sign, 'dy': w.dy * sign, 'nx': w.nx * sign, 'ny': w.ny * sign, 'wall': x.wallId,
                    };
                  }(),
            ],
      'selectedObject': st.selectedObject,
      'selected': st.selected,
      'open': {
        for (final u in st.openTargets)
          if (p.byUid(u) != null) u: openLimit(e, p.byUid(u)!).$1,
      },
      'yaw': st.yaw,
      'zoom': st.zoom,
      'cam': st.camera3d,
      'editable': !st.lockMoves && (st.step == PlanStep.layout || st.step == PlanStep.style), // verrou : la 3D navigue seulement
    };
  }
}

/// Point de réseau absent de la vue 3D : attente noyée dans le bâti-support d'un WC suspendu,
/// ou arrivée / évacuation existante une fois les appareils raccordés (le réseau généré la remplace).
bool _hiddenIn3d(Project p, NetPoint x) {
  if (x.onCeiling || x.wallId == 'I') return false;
  if (x.use == existingUse) return p.points.any((y) => y.auto && y.kind.network == x.kind.network && y.forUid != null);
  return x.kind.network != 'elec' && x.kind.network != 'data' && concealedInFrame(p.room, p.objects, x.wallId, x.s, x.z);
}
