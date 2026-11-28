// Miniatures dessinées des luminaires (menu Plafond) : le luminaire, sa lumière (couleur selon la
// température) et ce qu'il éclaire. Dessin vectoriel : net à toute taille, rien à charger.
import 'dart:math' as math;

import 'package:flutter/material.dart';

class LightThumb extends StatelessWidget {
  final String kind; // spot, darklight, track, magnetic, panel, ceiling, bulb, pendant, linear, strip, bar, cove, plinth, puck, dressing, none
  final int cct;
  final double width, height;
  const LightThumb({super.key, required this.kind, this.cct = 3000, this.width = 112, this.height = 72});

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size(width, height), painter: _ThumbPainter(kind, _lightColor(cct), Theme.of(context).brightness == Brightness.dark));
}

Color _lightColor(int k) => Color(k <= 2200
    ? 0xFFFF9E44
    : k <= 2700
        ? 0xFFFFC98A
        : k <= 3000
            ? 0xFFFFDDB0
            : k <= 4000
                ? 0xFFFFF0DC
                : 0xFFF0F6FF);

class _ThumbPainter extends CustomPainter {
  final String kind;
  final Color light;
  final bool dark;
  _ThumbPainter(this.kind, this.light, this.dark);

  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    final r = RRect.fromRectAndRadius(Offset.zero & s, const Radius.circular(10));
    c.save();
    c.clipRRect(r);
    // pièce dans la pénombre : la lumière du luminaire se lit bien
    c.drawRect(Offset.zero & s,
        Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [const Color(0xFF2B2E33), const Color(0xFF3A3D42)]).createShader(Offset.zero & s));
    final ceil = h * 0.16;
    final floor = h * 0.9;
    final ceiling = Paint()..color = const Color(0xFF4A4E54);
    final metal = Paint()..color = const Color(0xFF1C1E21);
    final white = Paint()..color = const Color(0xFFEDEDEB);
    final glow = Paint()..color = light;
    void cone(Offset from, double spread, {double to = 0}) {
      final bottom = to == 0 ? floor : to;
      final path = Path()
        ..moveTo(from.dx - 3, from.dy)
        ..lineTo(from.dx + 3, from.dy)
        ..lineTo(from.dx + spread, bottom)
        ..lineTo(from.dx - spread, bottom)
        ..close();
      c.drawPath(
          path,
          Paint()
            ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [light.withValues(alpha: 0.85), light.withValues(alpha: 0.05)])
                .createShader(Rect.fromLTRB(from.dx - spread, from.dy, from.dx + spread, bottom)));
      c.drawOval(Rect.fromCenter(center: Offset(from.dx, bottom), width: spread * 2.2, height: h * 0.1), Paint()..color = light.withValues(alpha: 0.35));
    }

    void halo(Offset at, double radius) => c.drawCircle(
        at,
        radius,
        Paint()
          ..shader = RadialGradient(colors: [light.withValues(alpha: 0.9), light.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: at, radius: radius)));
    void ceilingBand() => c.drawRect(Rect.fromLTRB(0, 0, w, ceil), ceiling);
    void floorLine() => c.drawRect(Rect.fromLTRB(0, floor, w, h), Paint()..color = const Color(0xFF55585E));

    switch (kind) {
      case 'spot':
      case 'darklight':
        ceilingBand();
        floorLine();
        for (final x in [w * 0.3, w * 0.7]) {
          cone(Offset(x, ceil), kind == 'darklight' ? w * 0.13 : w * 0.18);
          if (kind == 'darklight') {
            c.drawRect(Rect.fromCenter(center: Offset(x, ceil - 2), width: 14, height: 5), metal);
            c.drawRect(Rect.fromCenter(center: Offset(x, ceil - 1), width: 5, height: 2), glow);
          } else {
            c.drawRect(Rect.fromCenter(center: Offset(x, ceil + 1), width: 14, height: 3), white);
          }
        }
      case 'track':
      case 'magnetic':
        ceilingBand();
        floorLine();
        c.drawRect(Rect.fromLTRB(w * 0.12, ceil, w * 0.88, ceil + 4), metal);
        for (final (x, a) in [(w * 0.3, -0.35), (w * 0.62, 0.25)]) {
          c.save();
          c.translate(x, ceil + 4);
          c.rotate(a);
          cone(Offset(0, 10), w * (kind == 'track' ? 0.1 : 0.14));
          c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-5, 0, 10, kind == 'track' ? 13 : 9), const Radius.circular(2)), metal);
          c.restore();
        }
      case 'panel':
        ceilingBand();
        floorLine();
        cone(Offset(w / 2, ceil), w * 0.42);
        c.drawRect(Rect.fromCenter(center: Offset(w / 2, ceil + 1.5), width: w * 0.46, height: 4), glow);
      case 'ceiling':
        ceilingBand();
        floorLine();
        halo(Offset(w / 2, ceil + 6), w * 0.42);
        c.drawArc(Rect.fromCenter(center: Offset(w / 2, ceil), width: w * 0.34, height: 18), 0, math.pi, true, white);
      case 'bulb':
        ceilingBand();
        floorLine();
        c.drawLine(Offset(w / 2, ceil), Offset(w / 2, h * 0.42), Paint()
          ..color = const Color(0xFF1C1E21)
          ..strokeWidth = 1.2);
        halo(Offset(w / 2, h * 0.48), w * 0.32);
        c.drawCircle(Offset(w / 2, h * 0.48), 6, glow);
      case 'pendant':
        ceilingBand();
        floorLine();
        for (final x in [w * 0.28, w * 0.5, w * 0.72]) {
          c.drawLine(Offset(x, ceil), Offset(x, h * 0.4), Paint()
            ..color = const Color(0xFF8A8F96)
            ..strokeWidth = 1);
          cone(Offset(x, h * 0.48), w * 0.08, to: h * 0.74);
          c.drawPath(
              Path()
                ..moveTo(x - 3, h * 0.4)
                ..lineTo(x + 3, h * 0.4)
                ..lineTo(x + 9, h * 0.49)
                ..lineTo(x - 9, h * 0.49)
                ..close(),
              metal);
        }
        c.drawRect(Rect.fromLTRB(w * 0.14, h * 0.74, w * 0.86, h * 0.8), white); // îlot
      case 'linear':
        ceilingBand();
        floorLine();
        for (final x in [w * 0.26, w * 0.74]) {
          c.drawLine(Offset(x, ceil), Offset(x, h * 0.42), Paint()
            ..color = const Color(0xFF8A8F96)
            ..strokeWidth = 1);
        }
        cone(Offset(w / 2, h * 0.46), w * 0.36, to: h * 0.74);
        c.drawRect(Rect.fromLTRB(w * 0.2, h * 0.42, w * 0.8, h * 0.47), metal);
        c.drawRect(Rect.fromLTRB(w * 0.14, h * 0.74, w * 0.86, h * 0.8), white);
      case 'strip':
      case 'bar':
        // meuble haut, sa lumière sur le plan de travail
        c.drawRect(Rect.fromLTRB(0, h * 0.1, w, h * 0.42), Paint()..color = const Color(0xFF6B6F75));
        final y = h * 0.42;
        final glowRect = kind == 'strip' ? Rect.fromLTRB(w * 0.04, y, w * 0.96, y + 3) : Rect.fromLTRB(w * 0.18, y, w * 0.82, y + 4);
        c.drawRect(glowRect, glow);
        c.drawRect(
            Rect.fromLTRB(glowRect.left, y, glowRect.right, h * 0.72),
            Paint()
              ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [light.withValues(alpha: 0.7), light.withValues(alpha: 0.1)])
                  .createShader(Rect.fromLTRB(0, y, w, h * 0.72)));
        c.drawRect(Rect.fromLTRB(0, h * 0.72, w, h * 0.78), white); // plan de travail
        c.drawRect(Rect.fromLTRB(0, h * 0.78, w, h), Paint()..color = const Color(0xFF6B6F75));
      case 'cove':
        c.drawRect(Rect.fromLTRB(0, 0, w, ceil * 0.7), ceiling);
        c.drawRect(Rect.fromLTRB(0, ceil * 0.7, w * 0.3, ceil * 1.6), ceiling);
        c.drawRect(Rect.fromLTRB(w * 0.7, ceil * 0.7, w, ceil * 1.6), ceiling);
        halo(Offset(w * 0.3, ceil * 0.75), w * 0.25);
        halo(Offset(w * 0.7, ceil * 0.75), w * 0.25);
        floorLine();
      case 'plinth':
        c.drawRect(Rect.fromLTRB(w * 0.1, h * 0.3, w * 0.9, h * 0.76), Paint()..color = const Color(0xFF6B6F75));
        c.drawRect(Rect.fromLTRB(w * 0.1, h * 0.27, w * 0.9, h * 0.3), white);
        c.drawRect(Rect.fromLTRB(w * 0.14, h * 0.76, w * 0.86, h * 0.78), glow);
        c.drawRect(
            Rect.fromLTRB(0, h * 0.78, w, h),
            Paint()
              ..shader = RadialGradient(center: Alignment.topCenter, radius: 1.2, colors: [light.withValues(alpha: 0.8), light.withValues(alpha: 0)])
                  .createShader(Rect.fromLTRB(0, h * 0.78, w, h * 1.3)));
      case 'puck':
        final box = Rect.fromLTRB(w * 0.2, h * 0.12, w * 0.8, h * 0.88);
        c.drawRect(box, Paint()..color = const Color(0xFF4F5359));
        cone(Offset(w / 2, h * 0.16), w * 0.2, to: h * 0.5);
        c.drawRect(Rect.fromLTRB(box.left, h * 0.5, box.right, h * 0.53), Paint()..color = const Color(0x99D8E4EA)); // étagère verre
        cone(Offset(w / 2, h * 0.53), w * 0.2, to: h * 0.86);
        c.drawRect(box, Paint()
          ..color = const Color(0xFFBFC4C8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
      case 'dressing':
        final box = Rect.fromLTRB(w * 0.15, h * 0.1, w * 0.85, h * 0.92);
        c.drawRect(box, Paint()..color = const Color(0xFF4F5359));
        c.drawRect(Rect.fromLTRB(box.left + 4, h * 0.24, box.right - 4, h * 0.27), glow);
        c.drawRect(
            Rect.fromLTRB(box.left, h * 0.27, box.right, h * 0.7),
            Paint()
              ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [light.withValues(alpha: 0.6), light.withValues(alpha: 0)])
                  .createShader(Rect.fromLTRB(0, h * 0.27, w, h * 0.7)));
        for (final x in [w * 0.32, w * 0.45, w * 0.58]) {
          c.drawRect(Rect.fromLTRB(x, h * 0.3, x + 8, h * 0.66), Paint()..color = const Color(0xFF8A7E72));
        }
      default: // aucun
        ceilingBand();
        floorLine();
        c.drawLine(Offset(w * 0.38, h * 0.36), Offset(w * 0.62, h * 0.68), Paint()
          ..color = const Color(0xFF8A8F96)
          ..strokeWidth = 2);
        c.drawLine(Offset(w * 0.62, h * 0.36), Offset(w * 0.38, h * 0.68), Paint()
          ..color = const Color(0xFF8A8F96)
          ..strokeWidth = 2);
    }
    c.restore();
  }

  @override
  bool shouldRepaint(covariant _ThumbPainter o) => o.kind != kind || o.light != light || o.dark != dark;
}
