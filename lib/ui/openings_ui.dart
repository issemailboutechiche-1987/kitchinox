// Portes et fenêtres : choix dans le catalogue des menuiseries, et dessin selon le mécanisme d'ouverture
// (élévation pour les vues de face et les vignettes, symbole normalisé pour le plan).
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../engine/engine.dart';
import 'app_state.dart';
import 'theme.dart';
import 'i18n.dart';

const _glass = Color(0xFFCFE4F0);
const _glassLine = Color(0xFF7CA9C9);
const _ink = Color(0xFF55595F);

Paint _st(Color c, double w) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..color = c;

void _dashed(Canvas c, Offset a, Offset b, Paint p, {double dash = 6, double gap = 4}) {
  final d = b - a;
  final len = d.distance;
  if (len == 0) return;
  final u = d / len;
  for (var t = 0.0; t < len; t += dash + gap) {
    c.drawLine(a + u * t, a + u * math.min(len, t + dash), p);
  }
}

/// Teinte d'une porte d'après son modèle (bois, métal, laque…).
Color openingLeafColor(OpeningModel? m) {
  final id = m?.id ?? '';
  if (id.contains('solid_wood') || id.contains('barn')) return const Color(0xFFB98A5E);
  if (id.contains('security')) return const Color(0xFF8C8F93);
  if (id.contains('pivot')) return const Color(0xFF6F5A48);
  if (id.contains('aluminium')) return const Color(0xFF4A4E54);
  return const Color(0xFFF2F0EC);
}

/// Élévation d'une ouverture dans le rectangle [r] (écran), vue depuis la pièce. [k] : px par mm.
void paintOpeningElevation(Canvas c, Rect r, OpeningModel? m, {required bool door, String hinge = 'left', double k = 0.2}) {
  final lw = math.max(1.0, k * 8);
  final ink = _st(_ink, lw);
  final thin = _st(_ink.withValues(alpha: 0.6), math.max(0.7, k * 5));
  final frameW = math.max(2.0, 45 * k);
  final mech = m?.mechanism ?? (door ? 'hinged_single' : 'casement_inward');
  final arch = m?.arch ?? false;
  Path shape(Rect x) {
    if (!arch) return Path()..addRect(x);
    final rad = x.width / 2;
    return Path()
      ..moveTo(x.left, x.bottom)
      ..lineTo(x.left, x.top + rad)
      ..arcToPoint(Offset(x.right, x.top + rad), radius: Radius.circular(rad))
      ..lineTo(x.right, x.bottom)
      ..close();
  }

  // dormant (cadre)
  c.drawPath(shape(r), Paint()..color = door ? const Color(0xFFE9DFD0) : Colors.white);
  final inner = r.deflate(frameW);
  if (door) {
    final leaf = Paint()..color = openingLeafColor(m);
    final glass = m?.glazed ?? false;
    void handle(Offset at, {bool bar = false}) {
      final hp = Paint()..color = const Color(0xFF6B6F75);
      if (bar) {
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: at, width: math.max(2, 25 * k), height: inner.height * 0.6), Radius.circular(4 * k)), hp);
      } else {
        c.drawCircle(at, math.max(1.5, 22 * k), hp);
      }
    }

    void leafAt(Rect lr, String side, {bool grid = false}) {
      c.drawRect(lr, glass ? (Paint()..color = _glass) : leaf);
      if (grid) {
        // petits bois : 2 x 4 carreaux
        for (var i = 1; i < 2; i++) {
          c.drawLine(Offset(lr.left + lr.width * i / 2, lr.top), Offset(lr.left + lr.width * i / 2, lr.bottom), _st(const Color(0xFF2B2B2B), math.max(1, k * 18)));
        }
        for (var i = 1; i < 4; i++) {
          c.drawLine(Offset(lr.left, lr.top + lr.height * i / 4), Offset(lr.right, lr.top + lr.height * i / 4), _st(const Color(0xFF2B2B2B), math.max(1, k * 18)));
        }
        c.drawRect(lr, _st(const Color(0xFF2B2B2B), math.max(1.5, k * 30)));
      } else if (m != null && m.id.contains('solid_wood')) {
        // portes à panneaux : 4 panneaux moulurés
        final p = lr.deflate(lr.width * 0.14);
        for (final (fx, fy, fw, fh) in [(0.0, 0.0, 0.46, 0.38), (0.54, 0.0, 0.46, 0.38), (0.0, 0.45, 0.46, 0.55), (0.54, 0.45, 0.46, 0.55)]) {
          c.drawRect(Rect.fromLTWH(p.left + p.width * fx, p.top + p.height * fy, p.width * fw, p.height * fh), thin);
        }
      } else if (m != null && m.id.contains('barn')) {
        for (var i = 1; i < 5; i++) {
          c.drawLine(Offset(lr.left + lr.width * i / 5, lr.top), Offset(lr.left + lr.width * i / 5, lr.bottom), thin);
        }
        c.drawLine(lr.topLeft, lr.bottomRight, thin);
      } else if (glass) {
        c.drawLine(Offset(lr.left + lr.width * 0.25, lr.bottom - lr.height * 0.1), Offset(lr.left + lr.width * 0.7, lr.top + lr.height * 0.1), _st(Colors.white, math.max(1, k * 20)));
      }
      c.drawRect(lr, ink);
      final hx = side == 'left' ? lr.right - 80 * k : lr.left + 80 * k;
      if (!(m?.flush ?? false)) handle(Offset(hx, lr.top + lr.height * 0.52), bar: m?.pivot ?? false);
    }

    if (m?.twoLeaves ?? false) {
      final half = Rect.fromLTRB(inner.left, inner.top, inner.center.dx, inner.bottom);
      leafAt(half, 'right', grid: glass && (m?.id.contains('french') ?? false));
      leafAt(Rect.fromLTRB(inner.center.dx, inner.top, inner.right, inner.bottom), 'left', grid: glass && (m?.id.contains('french') ?? false));
    } else if (m?.folding ?? false) {
      leafAt(inner, hinge);
      for (var i = 1; i < 4; i++) {
        c.drawLine(Offset(inner.left + inner.width * i / 4, inner.top), Offset(inner.left + inner.width * i / 4, inner.bottom), ink);
      }
    } else {
      leafAt(inner, hinge);
    }
    if (m?.sliding ?? false) {
      // flèche de coulissement, rail au-dessus (porte de grange en applique)
      final y = inner.top + inner.height * 0.3;
      final a = Offset(inner.center.dx - inner.width * 0.25, y), b = Offset(inner.center.dx + inner.width * 0.25, y);
      c.drawLine(a, b, ink);
      final tip = hinge == 'left' ? a : b;
      final dir = hinge == 'left' ? 1.0 : -1.0;
      c.drawLine(tip, tip + Offset(dir * 60 * k, -40 * k), ink);
      c.drawLine(tip, tip + Offset(dir * 60 * k, 40 * k), ink);
      if (m!.barn) c.drawLine(Offset(r.left - r.width * 0.9, r.top - 30 * k), Offset(r.right + 20 * k, r.top - 30 * k), _st(const Color(0xFF2B2B2B), math.max(2, k * 30)));
    }
  } else {
    // fenêtre : vitrage puis notation d'ouverture
    c.drawPath(shape(inner), Paint()..color = _glass);
    void triangle(Rect x, String apex) {
      final p = switch (apex) {
        'left' => [x.topRight, x.centerLeft, x.bottomRight],
        'right' => [x.topLeft, x.centerRight, x.bottomLeft],
        'top' => [x.bottomLeft, x.topCenter, x.bottomRight],
        _ => [x.topLeft, x.bottomCenter, x.topRight],
      };
      _dashed(c, p[0], p[1], thin, dash: math.max(3, 40 * k), gap: math.max(2, 25 * k));
      _dashed(c, p[1], p[2], thin, dash: math.max(3, 40 * k), gap: math.max(2, 25 * k));
    }

    switch (mech) {
      case 'casement_inward' || 'casement_inward_arch':
        if (inner.width >= 800 * k) {
          final l = Rect.fromLTRB(inner.left, inner.top, inner.center.dx, inner.bottom), rr = Rect.fromLTRB(inner.center.dx, inner.top, inner.right, inner.bottom);
          c.drawLine(inner.topCenter, inner.bottomCenter, ink);
          triangle(l, 'left');
          triangle(rr, 'right');
        } else {
          triangle(inner, hinge == 'left' ? 'left' : 'right');
        }
      case 'tilt_and_turn_inward':
        triangle(inner, hinge == 'left' ? 'left' : 'right');
        triangle(inner, 'bottom');
      case 'tilt_inward_bottom_hinged':
        triangle(inner, 'bottom');
      case 'sliding_horizontal':
        final n = inner.width > 2600 * k ? 3 : 2;
        for (var i = 1; i < n; i++) {
          c.drawLine(Offset(inner.left + inner.width * i / n, inner.top), Offset(inner.left + inner.width * i / n, inner.bottom), ink);
        }
        final y = inner.center.dy;
        c.drawLine(Offset(inner.left + inner.width * 0.15, y), Offset(inner.left + inner.width * 0.35, y), ink);
        c.drawLine(Offset(inner.left + inner.width * 0.35, y), Offset(inner.left + inner.width * 0.3, y - 30 * k), ink);
      case 'sliding_vertical':
        c.drawLine(inner.centerLeft, inner.centerRight, ink);
        c.drawLine(Offset(inner.center.dx, inner.center.dy + inner.height * 0.3), Offset(inner.center.dx, inner.center.dy + inner.height * 0.1), ink);
      case 'louver_pivoting':
        for (var i = 1; i < 10; i++) {
          c.drawLine(Offset(inner.left, inner.top + inner.height * i / 10), Offset(inner.right, inner.top + inner.height * i / 10), thin);
        }
      case 'pivot_center_horizontal':
        c.drawLine(inner.centerLeft, inner.centerRight, thin);
        c.drawCircle(inner.centerLeft, math.max(1.5, 20 * k), Paint()..color = _ink);
        c.drawCircle(inner.centerRight, math.max(1.5, 20 * k), Paint()..color = _ink);
      case 'mixed_casement_and_fixed':
        for (final f in [0.25, 0.75]) {
          c.drawLine(Offset(inner.left + inner.width * f, inner.top), Offset(inner.left + inner.width * f, inner.bottom), ink);
        }
        triangle(Rect.fromLTRB(inner.left, inner.top, inner.left + inner.width * 0.25, inner.bottom), 'left');
        triangle(Rect.fromLTRB(inner.left + inner.width * 0.75, inner.top, inner.right, inner.bottom), 'right');
      default: // fixe : reflet seul
        c.drawLine(Offset(inner.left + inner.width * 0.2, inner.bottom - inner.height * 0.15), Offset(inner.left + inner.width * 0.55, inner.top + inner.height * 0.15),
            _st(Colors.white, math.max(1, k * 25)));
    }
    c.drawPath(shape(inner), ink);
  }
  c.drawPath(shape(r), _st(const Color(0xFF8D9399), math.max(1, k * 6)));
}

/// Symbole d'une ouverture en plan. [at] : (position le long du mur, distance vers la pièce) → écran ;
/// [t] : épaisseur du mur (mm).
void paintOpeningPlan(Canvas c, Opening o, Offset Function(double s, double t) at, double t, {Color floor = const Color(0xFFE6D3B3), double scale = 0.1}) {
  final m = openingModelOf(o);
  final ink = _st(_ink, 1.6);
  final gap = Rect.fromPoints(at(o.s, -t), at(o.right, 0));
  if (!o.isDoor) {
    c.drawRect(gap, Paint()..color = Colors.white);
    c.drawRect(gap, ink);
    final glass = _st(_glassLine, 2);
    if (m?.sliding ?? false) {
      // deux vantaux décalés
      c.drawLine(at(o.s, -t * 0.62), at(o.s + o.width * 0.55, -t * 0.62), glass);
      c.drawLine(at(o.s + o.width * 0.45, -t * 0.38), at(o.right, -t * 0.38), glass);
    } else {
      c.drawLine(at(o.s, -t / 2), at(o.right, -t / 2), glass);
      if (m != null && (m.hinged)) {
        // ouvrants vers l'intérieur : arcs en pointillés
        final leaves = m.twoLeaves && o.width >= 800 ? 2 : 1;
        final lw = o.width / leaves;
        for (var i = 0; i < leaves; i++) {
          final left = leaves == 2 ? i == 0 : o.hinge == 'left';
          final hs = left ? o.s + i * lw : o.s + (i + 1) * lw;
          final path = Path();
          for (var a = 0; a <= 16; a++) {
            final ang = math.pi / 2 * a / 16;
            final q = at(hs + (left ? 1 : -1) * lw * math.cos(ang), lw * math.sin(ang));
            a == 0 ? path.moveTo(q.dx, q.dy) : path.lineTo(q.dx, q.dy);
          }
          final pm = path.computeMetrics();
          for (final mm in pm) {
            for (var d = 0.0; d < mm.length; d += 9) {
              c.drawPath(mm.extractPath(d, math.min(mm.length, d + 5)), _st(_ink.withValues(alpha: 0.5), 1));
            }
          }
        }
      }
    }
    return;
  }
  c.drawRect(gap, Paint()..color = floor);
  // montants (huisserie)
  for (final s in [o.s, o.right - 40]) {
    final jr = Rect.fromPoints(at(s, -t), at(s + 40, 0));
    c.drawRect(jr, Paint()..color = Colors.white);
    c.drawRect(jr, ink);
  }
  final leafPaint = _st(_ink, 2.2);
  void swing(double hingeS, double leaf, bool towardRight) {
    final h = at(hingeS, 0);
    final open = at(hingeS, leaf);
    c.drawLine(h, open, leafPaint);
    final arc = Path()..moveTo(open.dx, open.dy);
    for (var a = 1; a <= 24; a++) {
      final ang = math.pi / 2 * (1 - a / 24);
      final q = at(hingeS + (towardRight ? 1 : -1) * leaf * math.cos(ang), leaf * math.sin(ang));
      arc.lineTo(q.dx, q.dy);
    }
    c.drawPath(arc, ink);
  }

  final clear = o.width - 80;
  if (m == null || m.hinged && !m.twoLeaves) {
    o.hinge == 'left' ? swing(o.s + 40, clear, true) : swing(o.right - 40, clear, false);
  } else if (m.twoLeaves) {
    swing(o.s + 40, clear / 2, true);
    swing(o.right - 40, clear / 2, false);
  } else if (m.pivot) {
    final ps = o.s + 40 + clear * 0.2;
    c.drawLine(at(ps, -clear * 0.2), at(ps, clear * 0.8), leafPaint);
    c.drawCircle(at(ps, 0), 3, Paint()..color = _ink);
    swing(ps, clear * 0.8, true);
  } else if (m.pocket) {
    // vantail rentré dans la cloison (pointillés) + course
    _dashed(c, at(o.s - clear * 0.9, -t / 2), at(o.s + 40, -t / 2), _st(_ink, 2));
    c.drawLine(at(o.s + 40, -t / 2), at(o.s + 40 + clear * 0.15, -t / 2), leafPaint);
  } else if (m.barn) {
    // rail et vantail en applique côté pièce, décalé de l'ouverture
    c.drawLine(at(o.s - clear, 25), at(o.right, 25), _st(const Color(0xFF2B2B2B), 1.4));
    c.drawLine(at(o.s - clear * 0.85, 45), at(o.s + 40, 45), _st(_ink, 3));
  } else if (m.folding) {
    // vantaux pliés en accordéon
    final n = 4;
    final seg = clear / n;
    final pts = [for (var i = 0; i <= n; i++) at(o.s + 40 + seg * i * 0.35, i.isOdd ? seg * 0.9 : 0)];
    c.drawPoints(ui.PointMode.polygon, pts, leafPaint);
  } else {
    swing(o.s + 40, clear, true);
  }
}

/// Vignette d'un modèle (choix dans le catalogue).
class OpeningThumb extends CustomPainter {
  final OpeningModel m;
  OpeningThumb(this.m);
  @override
  void paint(Canvas c, Size s) {
    final w = m.defaultWidth.toDouble(), h = m.defaultHeight.toDouble();
    final k = math.min(s.width * 0.82 / w, s.height * 0.86 / h);
    final r = Rect.fromCenter(center: s.center(Offset.zero), width: w * k, height: h * k);
    paintOpeningElevation(c, r, m, door: m.door, k: k);
  }

  @override
  bool shouldRepaint(OpeningThumb o) => o.m != m;
}

/// Catalogue des portes et fenêtres : un clic pose le modèle sur un espace libre du mur affiché
/// (ou remplace le modèle de l'ouverture [replace]).
Future<void> showOpeningPicker(BuildContext context, AppState state, void Function(String) onMessage, {Opening? replace}) {
  final t = Theme.of(context).textTheme;
  return showDialog<void>(
    context: context,
    builder: (ctx) => DefaultTabController(
      length: 2,
      initialIndex: replace != null && !replace.isDoor ? 1 : 0,
      child: Dialog(
        insetPadding: const EdgeInsets.all(Tokens.s5),
        child: SizedBox(
          width: 900,
          height: 640,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s4, Tokens.s3, 0),
              child: Row(children: [
                Expanded(child: Text(replace == null ? tr('Portes et fenêtres') : tr('Changer de modèle'), style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                IconButton(tooltip: tr('Fermer'), onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
              ]),
            ),
            if (replace == null)
              const TabBar(tabs: [Tab(text: 'Portes'), Tab(text: 'Fenêtres')])
            else
              const SizedBox(height: Tokens.s2),
            Expanded(
              child: TabBarView(
                physics: replace == null ? null : const NeverScrollableScrollPhysics(),
                children: [
                  for (final door in [true, false])
                    GridView.extent(
                      padding: const EdgeInsets.all(Tokens.s4),
                      maxCrossAxisExtent: 210,
                      childAspectRatio: 0.78,
                      mainAxisSpacing: Tokens.s3,
                      crossAxisSpacing: Tokens.s3,
                      children: [
                        for (final m in OpeningModel.byId.values.where((x) => x.door == door && (replace == null || x.door == replace.isDoor)))
                          Card(
                            margin: EdgeInsets.zero,
                            child: InkWell(
                              onTap: () {
                                Navigator.pop(ctx);
                                if (replace != null) {
                                  state.setOpeningModel(replace.uid, m.id);
                                  onMessage(trp('{0} : {1} x {2} mm', [tr(m.name), replace.width.round(), replace.height.round()]));
                                } else {
                                  final err = state.addOpening(door ? 'door' : 'window', model: m.id);
                                  onMessage(err ?? trp('{0} posée sur {1}', [tr(m.name), Room.wallNames[state.selectedOpeningObj?.wallId]?.toLowerCase()]));
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(Tokens.s2),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Expanded(child: CustomPaint(painter: OpeningThumb(m), size: Size.infinite)),
                                  const SizedBox(height: 4),
                                  Text(tr(m.name), maxLines: 2, overflow: TextOverflow.ellipsis, style: t.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                                  Text(m.mechanismLabel, style: t.labelSmall),
                                  Text(trp('{0} mm', [m.widths.join(' · ')]), maxLines: 1, overflow: TextOverflow.ellipsis, style: t.labelSmall),
                                ]),
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ]),
        ),
      ),
    ),
  );
}
