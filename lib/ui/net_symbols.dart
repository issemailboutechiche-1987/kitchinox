// Symboles des points de réseau (vue de face, plan, PDF) : couleur par réseau, abréviation au centre.

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

/// Dessine le symbole d'un point centré en [o], de rayon [r] (px).
void paintNetSymbol(Canvas c, Offset o, NetKind k, double r, {bool selected = false, bool behind = false}) {
  final col = netColor(k);
  final alpha = behind ? 0.75 : 1.0;
  final fillWhite = k.network == 'elec';
  final fill = Paint()..color = (fillWhite ? Colors.white : col).withValues(alpha: alpha);
  final stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = (r * 0.18).clamp(1.0, 3.0)
    ..color = col.withValues(alpha: alpha);
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
  switch (k) {
    case NetKind.switch_ || NetKind.switchDouble || NetKind.switchTriple:
      final rr = RRect.fromRectAndRadius(Rect.fromCircle(center: o, radius: r * 0.9), Radius.circular(r * 0.25));
      c.drawRRect(rr, fill);
      c.drawRRect(rr, stroke);
    case NetKind.light:
      c.drawCircle(o, r, fill);
      c.drawCircle(o, r, stroke);
      final d = r * 0.62;
      c.drawLine(o + Offset(-d, -d), o + Offset(d, d), stroke);
      c.drawLine(o + Offset(d, -d), o + Offset(-d, d), stroke);
      return;
    case NetKind.drain || NetKind.drainWc:
      final path = Path()
        ..moveTo(o.dx, o.dy + r * 1.05)
        ..lineTo(o.dx - r * 1.05, o.dy - r * 0.7)
        ..lineTo(o.dx + r * 1.05, o.dy - r * 0.7)
        ..close();
      c.drawPath(path, fill);
    default:
      c.drawCircle(o, r, fill);
      c.drawCircle(o, r, stroke);
  }
  final tag = k.tag;
  final tp = TextPainter(
    text: TextSpan(
        text: tag,
        style: TextStyle(
            fontSize: r * (tag.length >= 3 ? 0.62 : 0.85),
            fontWeight: FontWeight.w800,
            color: fillWhite ? col : Colors.white,
            fontFamily: 'Roboto',
            height: 1)),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, o - Offset(tp.width / 2, tp.height / 2 + (k == NetKind.drain ? r * 0.2 : 0)));
}
