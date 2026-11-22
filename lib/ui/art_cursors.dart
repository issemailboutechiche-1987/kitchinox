// Curseurs et icônes des outils de l'atelier, dessinés pour kitchinox : lame de scie (couper), perceuse (percer),
// rouleau de chant (plaquer un chant), panneau rainuré (rainure). Le même dessin sert au curseur et à la palette.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/art_cad.dart';

/// Outils qui ont leur dessin.
bool hasToolGlyph(CadTool t) => const {CadTool.cut, CadTool.drill, CadTool.edgeBand, CadTool.groove}.contains(t);

/// Dessine l'outil dans un carré de 40 unités. [turn] : rotation de la lame.
void paintToolGlyph(Canvas c, CadTool tool, Color ink, Color paper, {double turn = 0}) {
  final fill = Paint()
    ..color = ink
    ..isAntiAlias = true;
  final line = Paint()
    ..color = ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.4
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final cut = Paint()
    ..color = paper
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;
  switch (tool) {
    case CadTool.cut:
      // lame : dents en crochet, cercle de coupe, alésage
      const o = Offset(20, 20), n = 16, rOut = 18.5, rIn = 14.2;
      final p = Path();
      for (var i = 0; i < n; i++) {
        Offset at(double k, double r) {
          final a = turn + 2 * math.pi * (i + k) / n;
          return o + Offset(math.cos(a), math.sin(a)) * r;
        }

        final g = at(0, rIn);
        i == 0 ? p.moveTo(g.dx, g.dy) : p.lineTo(g.dx, g.dy);
        final back = at(0.45, rIn + 1.2), tip = at(0.92, rOut), face = at(0.78, rIn + 0.4);
        p.quadraticBezierTo(back.dx, back.dy, tip.dx, tip.dy);
        p.lineTo(face.dx, face.dy);
      }
      p.close();
      c.drawPath(p, fill);
      c.drawCircle(o, 11.2, cut);
      c.drawCircle(o, 3.2, Paint()..color = paper);
      // repère : on voit la lame tourner
      for (final a in [turn, turn + math.pi]) {
        c.drawCircle(o + Offset(math.cos(a), math.sin(a)) * 7.2, 1.1, Paint()..color = paper);
      }
    case CadTool.drill:
      // perceuse : la mèche à gauche, la pointe en (1, 13)
      final bit = Path()..moveTo(1, 13);
      for (var i = 0; i < 5; i++) {
        bit.lineTo(2.2 + i * 1.8, i.isEven ? 11.6 : 14.4);
      }
      bit.lineTo(11, 13);
      c.drawPath(bit, line..strokeWidth = 2);
      line.strokeWidth = 2.4;
      c.drawRRect(RRect.fromLTRBR(10.5, 9.8, 16.5, 16.2, const Radius.circular(1.6)), line);
      c.drawRRect(RRect.fromLTRBAndCorners(16.5, 6.5, 38, 18.5, topRight: const Radius.circular(5), bottomRight: const Radius.circular(3), topLeft: const Radius.circular(2), bottomLeft: const Radius.circular(2)), line);
      for (final y in const [10.0, 12.5, 15.0]) {
        c.drawLine(Offset(20, y), Offset(23, y), line..strokeWidth = 1.6);
      }
      c.drawLine(const Offset(27, 11), const Offset(34, 11), line..strokeWidth = 2);
      line.strokeWidth = 2.4;
      c.drawPath(
          Path()
            ..moveTo(26, 18.5)
            ..quadraticBezierTo(29, 24, 29, 30)
            ..moveTo(35.5, 18.5)
            ..quadraticBezierTo(36, 24, 37, 30),
          line);
      c.drawPath(
          Path()
            ..moveTo(26.6, 20)
            ..lineTo(24.5, 24)
            ..lineTo(28.4, 25),
          line..strokeWidth = 2);
      c.drawRRect(RRect.fromLTRBR(22, 30, 39, 37, const Radius.circular(2)), fill);
      c.drawLine(const Offset(24, 33.5), const Offset(37, 33.5), cut);
    case CadTool.edgeBand:
      // rouleau de chant : la bande se déroule vers le bas à gauche, son bout en (2, 36)
      c.save();
      c.translate(25, 15);
      c.rotate(-0.35);
      c.drawPath(
          Path()
            ..fillType = PathFillType.evenOdd
            ..addOval(Rect.fromCenter(center: const Offset(-2.6, 0), width: 21, height: 27))
            ..addOval(Rect.fromCenter(center: const Offset(-1.4, 0), width: 9, height: 13)),
          fill);
      c.drawPath(
          Path()
            ..fillType = PathFillType.evenOdd
            ..addOval(Rect.fromCenter(center: const Offset(2.4, 0), width: 20, height: 26))
            ..addOval(Rect.fromCenter(center: const Offset(2.4, 0), width: 9, height: 13)),
          fill);
      c.drawOval(Rect.fromCenter(center: const Offset(2.4, 0), width: 20, height: 26), cut);
      c.drawOval(Rect.fromCenter(center: const Offset(2.4, 0), width: 9, height: 13), cut);
      c.restore();
      c.drawPath(
          Path()
            ..moveTo(2, 36)
            ..lineTo(19.5, 26.2)
            ..lineTo(29, 27.6)
            ..lineTo(10, 38.4)
            ..close(),
          fill);
    case CadTool.groove:
      // panneau rainuré (en coupe) et languette qui s'y présente ; le fond de la rainure en (17, 27)
      c.drawPath(
          Path()
            ..moveTo(2, 22)
            ..lineTo(13, 22)
            ..lineTo(13, 29)
            ..lineTo(21, 29)
            ..lineTo(21, 22)
            ..lineTo(38, 22)
            ..lineTo(38, 36)
            ..lineTo(2, 36)
            ..close(),
          fill);
      c.drawPath(
          Path()
            ..moveTo(14.4, 3)
            ..lineTo(19.6, 3)
            ..lineTo(19.6, 16)
            ..lineTo(17, 19.4)
            ..lineTo(14.4, 16)
            ..close(),
          line..strokeWidth = 2);
      c.drawLine(const Offset(17, 6), const Offset(17, 12), line..strokeWidth = 1.6);
    default:
  }
}

/// Point du dessin qui suit le doigt ou la souris (dans le carré de 40).
Offset toolHotspot(CadTool t) => switch (t) {
      CadTool.cut => const Offset(20, 20),
      CadTool.drill => const Offset(1, 13),
      CadTool.edgeBand => const Offset(4, 37),
      CadTool.groove => const Offset(17, 29),
      _ => Offset.zero,
    };

/// Icône d'un outil (palette, menus).
class ToolGlyph extends StatelessWidget {
  final CadTool tool;
  final double size;
  final Color color, paper;
  const ToolGlyph(this.tool, {super.key, this.size = 22, required this.color, required this.paper});

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _GlyphPainter(tool, color, paper));
}

class _GlyphPainter extends CustomPainter {
  final CadTool tool;
  final Color color, paper;
  _GlyphPainter(this.tool, this.color, this.paper);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 40);
    paintToolGlyph(canvas, tool, color, paper);
  }

  @override
  bool shouldRepaint(_GlyphPainter o) => o.tool != tool || o.color != color || o.paper != paper;
}

/// Curseur de l'outil au point [at] : à la souris, la pointe de l'outil est exactement sous le pointeur ;
/// au doigt, le dessin est au-dessus du doigt, relié par un trait au point touché.
class ToolCursorPainter extends CustomPainter {
  final CadTool tool;
  final Offset at;
  final bool touch, isDark;
  ToolCursorPainter(this.tool, this.at, {this.touch = false, this.isDark = false});

  @override
  void paint(Canvas canvas, Size size) {
    const k = 1.05; // 42 pixels
    final ink = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF111827), paper = isDark ? const Color(0xFF111827) : Colors.white;
    final lift = touch ? const Offset(0, -64) : Offset.zero;
    if (touch) {
      canvas.drawLine(at, at + lift + const Offset(0, 12), Paint()
        ..color = const Color(0xFFF26522)
        ..strokeWidth = 1.4);
      canvas.drawCircle(at, 4, Paint()..color = const Color(0xFFF26522));
    }
    canvas.save();
    final hot = toolHotspot(tool) * k;
    canvas.translate(at.dx + lift.dx - hot.dx, at.dy + lift.dy - hot.dy);
    canvas.scale(k);
    final turn = at.dx / 22 + at.dy / 22; // la lame tourne quand on avance
    // liseré clair : le curseur reste visible sur toutes les matières
    canvas.saveLayer(const Rect.fromLTWH(-6, -6, 52, 52), Paint()..imageFilter = null);
    for (final d in const [Offset(1.3, 0), Offset(-1.3, 0), Offset(0, 1.3), Offset(0, -1.3)]) {
      canvas.save();
      canvas.translate(d.dx, d.dy);
      paintToolGlyph(canvas, tool, paper, paper, turn: turn);
      canvas.restore();
    }
    canvas.restore();
    paintToolGlyph(canvas, tool, ink, paper, turn: turn);
    canvas.restore();
    if (tool == CadTool.cut && !touch) {
      // centre de coupe : croix fine, la lame reste lisible autour
      final p = Paint()
        ..color = const Color(0xFFF26522)
        ..strokeWidth = 1.2;
      canvas.drawLine(at - const Offset(5, 0), at + const Offset(5, 0), p);
      canvas.drawLine(at - const Offset(0, 5), at + const Offset(0, 5), p);
    }
  }

  @override
  bool shouldRepaint(ToolCursorPainter o) => o.at != at || o.tool != tool || o.touch != touch || o.isDark != isDark;
}
