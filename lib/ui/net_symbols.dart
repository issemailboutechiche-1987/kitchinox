// Symboles des points de réseau (vue de face, plan, PDF) : symboles normalisés d'architecte (NF C 15-100 / NF EN 60617)
// pour l'électricité, couleur par réseau, et symboles des appareils raccordés (réfrigérateur, plaque, hotte…).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/engine.dart';

Color netColor(NetKind k) => switch (k.network) {
      'elec' => const Color(0xFFE8590C),
      'water' => k == NetKind.waterHot ? const Color(0xFFD62F2F) : const Color(0xFF1C7ED6),
      'drain' => const Color(0xFF6D4C41),
      'gas' => const Color(0xFFD9A400),
      'data' => const Color(0xFF7048E8),
      _ => const Color(0xFF6C757D),
    };

const netNetworkNames = {
  'elec': 'Électricité',
  'water': 'Eau',
  'drain': 'Évacuation',
  'gas': 'Gaz',
  'air': 'Ventilation',
  'data': 'Réseau et TV',
};

void _tag(Canvas c, Offset o, String t, double size, Color col) {
  final tp = TextPainter(
    text: TextSpan(text: t, style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, color: col, fontFamily: 'Roboto', height: 1)),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, o - Offset(tp.width / 2, tp.height / 2));
}

/// Nombre de socles / de commandes d'un point (prise double = 2…).
int netMultiple(NetKind k) => switch (k) {
      NetKind.socketDouble || NetKind.switchDouble => 2,
      NetKind.socketTriple || NetKind.switchTriple => 3,
      NetKind.socketQuad => 4,
      _ => 1,
    };

/// Dessine le symbole d'un point centré en [o], de rayon [r] (px).
void paintNetSymbol(Canvas c, Offset o, NetKind k, double r, {bool selected = false, bool behind = false}) {
  final col = netColor(k);
  final alpha = behind ? 0.75 : 1.0;
  final fillWhite = k.network == 'elec' || k.network == 'data';
  final ink = col.withValues(alpha: alpha);
  final fill = Paint()..color = (fillWhite ? Colors.white : col).withValues(alpha: alpha);
  final sw = (r * 0.16).clamp(1.0, 3.0);
  final stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = sw
    ..strokeCap = StrokeCap.round
    ..color = ink;
  final dot = Paint()..color = ink;
  if (selected) {
    c.drawCircle(o, r * 1.55, Paint()..color = col.withValues(alpha: 0.22));
    c.drawCircle(
        o,
        r * 1.55,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = col);
  }
  c.drawCircle(o + Offset(r * 0.12, r * 0.18), r, Paint()..color = Colors.black.withValues(alpha: 0.18));
  void disc() {
    c.drawCircle(o, r, fill);
    c.drawCircle(o, r, stroke);
  }

  // petit chiffre « ×n » en exposant pour les socles et commandes multiples
  void multiple() {
    final n = netMultiple(k);
    if (n < 2) return;
    final b = o + Offset(r * 0.95, -r * 0.95);
    c.drawCircle(b, r * 0.48, Paint()..color = ink);
    _tag(c, b, '$n', r * 0.62, Colors.white);
  }

  switch (k) {
    // prise de courant 2P+T : cercle, deux broches et la terre
    case NetKind.socket || NetKind.socketDouble || NetKind.socketTriple || NetKind.socketQuad || NetKind.usb:
      disc();
      final d = r * 0.42;
      c.drawCircle(o + Offset(-d, r * 0.12), r * 0.14, dot);
      c.drawCircle(o + Offset(d, r * 0.12), r * 0.14, dot);
      c.drawCircle(o + Offset(0, -r * 0.42), r * 0.14, dot);
      if (k == NetKind.usb) _tag(c, o + Offset(0, r * 0.55), 'USB', r * 0.36, ink);
      multiple();
    // prise spécialisée 20 A / sortie 32 A : même prise, calibre inscrit
    case NetKind.socket20 || NetKind.out32:
      disc();
      final d = r * 0.42;
      c.drawCircle(o + Offset(-d, -r * 0.2), r * 0.13, dot);
      c.drawCircle(o + Offset(d, -r * 0.2), r * 0.13, dot);
      c.drawCircle(o + Offset(0, -r * 0.6), r * 0.13, dot);
      _tag(c, o + Offset(0, r * 0.38), k == NetKind.socket20 ? '20A' : '32A', r * 0.46, ink);
    // interrupteur : cercle et levier oblique, un trait par commande
    case NetKind.switch_ || NetKind.switchDouble || NetKind.switchTriple:
      disc();
      c.drawCircle(o, r * 0.2, dot);
      final n = netMultiple(k);
      for (var i = 0; i < n; i++) {
        final a = -math.pi / 4 - (i - (n - 1) / 2) * 0.42;
        final p0 = o + Offset(math.cos(a), math.sin(a)) * (r * 0.2);
        final p1 = o + Offset(math.cos(a), math.sin(a)) * (r * 1.7);
        c.drawLine(p0, p1, stroke);
        final t = Offset(math.cos(a + math.pi / 2), math.sin(a + math.pi / 2)) * (r * 0.38);
        c.drawLine(p1, p1 + t, stroke);
      }
    // point lumineux (DCL) : cercle barré d'une croix
    case NetKind.light:
      disc();
      final d = r * 0.7;
      c.drawLine(o + Offset(-d, -d), o + Offset(d, d), stroke);
      c.drawLine(o + Offset(d, -d), o + Offset(-d, d), stroke);
    // alimentation LED : réglette (tube fluorescent / ruban)
    case NetKind.led:
      final rr = Rect.fromCenter(center: o, width: r * 2.3, height: r * 0.9);
      c.drawRect(rr, fill);
      c.drawRect(rr, stroke);
      c.drawLine(rr.centerLeft + Offset(-r * 0.3, -r * 0.45), rr.centerLeft + Offset(-r * 0.3, r * 0.45), stroke);
      c.drawLine(rr.centerRight + Offset(r * 0.3, -r * 0.45), rr.centerRight + Offset(r * 0.3, r * 0.45), stroke);
      _tag(c, o, 'LED', r * 0.5, ink);
    // sortie de câble : cercle et câble sortant fléché
    case NetKind.cable:
      disc();
      c.drawLine(o + Offset(-r * 0.55, 0), o + Offset(r * 0.55, 0), stroke);
      c.drawLine(o + Offset(r * 0.55, 0), o + Offset(r * 0.2, -r * 0.32), stroke);
      c.drawLine(o + Offset(r * 0.55, 0), o + Offset(r * 0.2, r * 0.32), stroke);
      c.drawCircle(o + Offset(-r * 0.55, 0), r * 0.13, dot);
    // prises courant faible : TV / RJ45 inscrits
    case NetKind.tvSat || NetKind.rj45:
      disc();
      _tag(c, o, k == NetKind.tvSat ? 'TV' : 'RJ45', r * (k == NetKind.tvSat ? 0.72 : 0.5), ink);
    case NetKind.drain || NetKind.drainWc:
      final path = Path()
        ..moveTo(o.dx, o.dy + r * 1.05)
        ..lineTo(o.dx - r * 1.05, o.dy - r * 0.7)
        ..lineTo(o.dx + r * 1.05, o.dy - r * 0.7)
        ..close();
      c.drawPath(path, fill);
      _tag(c, o - Offset(0, r * 0.2), k.tag, r * 0.7, Colors.white);
    default:
      disc();
      final tag = k.tag;
      _tag(c, o, tag, r * (tag.length >= 3 ? 0.62 : 0.85), fillWhite ? ink : Colors.white);
  }
}

/// Appareils raccordés : symbole d'architecte du plan d'installation (carré avec signe).
const applianceUses = {NetUse.fridge, NetUse.hob, NetUse.hood, NetUse.dishwasher, NetUse.microwave, NetUse.oven, NetUse.washer};

String applianceName(String use) => switch (use) {
      NetUse.fridge => 'Réfrigérateur',
      NetUse.hob => 'Plaque de cuisson',
      NetUse.hood => 'Hotte',
      NetUse.dishwasher => 'Lave-vaisselle',
      NetUse.microwave => 'Micro-ondes',
      NetUse.oven => 'Four',
      NetUse.washer => 'Lave-linge',
      _ => use,
    };

/// Dessine le symbole d'appareil [use] dans un carré de demi-côté [r] centré en [o].
void paintApplianceSymbol(Canvas c, Offset o, String use, double r, {Color color = const Color(0xFF263238)}) {
  final box = Rect.fromCircle(center: o, radius: r);
  final sw = (r * 0.12).clamp(0.8, 2.4);
  final st = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = sw
    ..strokeCap = StrokeCap.round
    ..color = color;
  final dot = Paint()..color = color;
  c.drawRect(box, Paint()..color = Colors.white);
  c.drawRect(box, st);
  switch (use) {
    case NetUse.fridge:
      // étoile de froid
      for (var i = 0; i < 3; i++) {
        final a = i * math.pi / 3;
        final d = Offset(math.cos(a), math.sin(a)) * (r * 0.62);
        c.drawLine(o - d, o + d, st);
      }
    case NetUse.hob:
      // quatre foyers
      for (final d in [const Offset(-1, -1), const Offset(1, -1), const Offset(-1, 1), const Offset(1, 1)]) {
        c.drawCircle(o + d * (r * 0.45), r * 0.22, st);
        c.drawCircle(o + d * (r * 0.45), r * 0.07, dot);
      }
    case NetUse.hood:
      // signe infini (extraction)
      final path = Path();
      for (var i = 0; i <= 48; i++) {
        final t = i / 48 * 2 * math.pi;
        final den = 1 + math.pow(math.sin(t), 2);
        final p = o + Offset(r * 0.72 * math.cos(t) / den, r * 0.72 * math.sin(t) * math.cos(t) / den);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      c.drawPath(path, st);
    case NetUse.dishwasher:
      // bras d'aspersion et jets
      c.drawLine(o + Offset(-r * 0.6, r * 0.3), o + Offset(r * 0.6, r * 0.3), st);
      for (var i = -2; i <= 2; i++) {
        c.drawLine(o + Offset(i * r * 0.28, r * 0.1), o + Offset(i * r * 0.36, -r * 0.55), st);
      }
    case NetUse.microwave:
      // ondes
      for (var j = 0; j < 3; j++) {
        final y = o.dy + (j - 1) * r * 0.45;
        final path = Path()..moveTo(o.dx - r * 0.65, y);
        for (var i = 1; i <= 24; i++) {
          final x = -0.65 + 1.3 * i / 24;
          path.lineTo(o.dx + x * r, y + math.sin(x * math.pi * 2.3) * r * 0.13);
        }
        c.drawPath(path, st);
      }
    case NetUse.oven:
      // enceinte et résistances haute / basse
      final inner = Rect.fromCircle(center: o, radius: r * 0.62);
      c.drawRect(inner, st);
      c.drawLine(inner.topLeft + Offset(r * 0.15, r * 0.2), inner.topRight + Offset(-r * 0.15, r * 0.2), st);
      c.drawLine(inner.bottomLeft + Offset(r * 0.15, -r * 0.2), inner.bottomRight + Offset(-r * 0.15, -r * 0.2), st);
    case NetUse.washer:
      // hublot
      c.drawCircle(o, r * 0.62, st);
      c.drawCircle(o, r * 0.14, dot);
    default:
      _tag(c, o, '?', r, color);
  }
}

/// Point qui alimente un appareil (prise spécialisée, sortie de câble…) : son appareil, sinon null.
String? applianceOf(NetPoint x) => applianceUses.contains(x.use) && x.kind.network == 'elec' ? x.use : null;
