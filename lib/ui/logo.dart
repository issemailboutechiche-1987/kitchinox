// Logo kitchinox (assets/logo.svg) dessiné par Flutter : lecture des tracés SVG (commandes
// M L H V C S Q T Z, absolues et relatives), animation « pochoir » : le contour se trace,
// puis la forme se remplit.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const logoOrange = Color(0xFFF26522);

/// Tracés du logo et taille de son viewBox.
class LogoShape {
  final List<Path> paths;
  final Size viewBox;
  const LogoShape(this.paths, this.viewBox);

  static LogoShape? _cache;
  static String? _svg;

  /// Texte SVG du logo (pour les PDF) ; null s'il n'est pas disponible.
  static Future<String?> svgText() async {
    try {
      return _svg ??= await rootBundle.loadString('assets/logo.svg');
    } catch (_) {
      return null;
    }
  }

  static Future<LogoShape> load() async => _cache ??= parse(await rootBundle.loadString('assets/logo.svg'));

  static LogoShape parse(String svg) {
    final vb = RegExp(r'viewBox="([^"]+)"').firstMatch(svg)?.group(1)?.split(RegExp(r'[\s,]+')).map(double.parse).toList();
    final paths = [for (final m in RegExp(r'\sd="([^"]+)"').allMatches(svg)) parsePath(m.group(1)!)];
    return LogoShape(paths, vb == null ? const Size(100, 100) : Size(vb[2], vb[3]));
  }
}

/// Lecture d'un attribut « d » SVG.
Path parsePath(String d) {
  final path = Path();
  final tokens = RegExp(r'[MmLlHhVvCcSsQqTtZz]|-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?').allMatches(d).map((m) => m.group(0)!).toList();
  var i = 0;
  var cx = 0.0, cy = 0.0, sx = 0.0, sy = 0.0; // point courant, début du sous-tracé
  double? lcx, lcy; // dernier point de contrôle (pour S / T)
  String cmd = 'M';
  bool isCmd(String t) => RegExp(r'^[A-Za-z]$').hasMatch(t);
  double n() => double.parse(tokens[i++]);
  while (i < tokens.length) {
    if (isCmd(tokens[i])) cmd = tokens[i++];
    final rel = cmd == cmd.toLowerCase();
    final ox = rel ? cx : 0.0, oy = rel ? cy : 0.0;
    switch (cmd.toUpperCase()) {
      case 'M':
        cx = ox + n();
        cy = oy + n();
        path.moveTo(cx, cy);
        sx = cx;
        sy = cy;
        cmd = rel ? 'l' : 'L'; // coordonnées suivantes : lignes
        lcx = null;
      case 'L':
        cx = ox + n();
        cy = oy + n();
        path.lineTo(cx, cy);
        lcx = null;
      case 'H':
        cx = (rel ? cx : 0) + n();
        path.lineTo(cx, cy);
        lcx = null;
      case 'V':
        cy = (rel ? cy : 0) + n();
        path.lineTo(cx, cy);
        lcx = null;
      case 'C':
        final x1 = ox + n(), y1 = oy + n(), x2 = ox + n(), y2 = oy + n(), x = ox + n(), y = oy + n();
        path.cubicTo(x1, y1, x2, y2, x, y);
        lcx = x2;
        lcy = y2;
        cx = x;
        cy = y;
      case 'S':
        final x1 = lcx == null ? cx : 2 * cx - lcx, y1 = lcy == null || lcx == null ? cy : 2 * cy - lcy;
        final x2 = ox + n(), y2 = oy + n(), x = ox + n(), y = oy + n();
        path.cubicTo(x1, y1, x2, y2, x, y);
        lcx = x2;
        lcy = y2;
        cx = x;
        cy = y;
      case 'Q':
        final x1 = ox + n(), y1 = oy + n(), x = ox + n(), y = oy + n();
        path.quadraticBezierTo(x1, y1, x, y);
        lcx = x1;
        lcy = y1;
        cx = x;
        cy = y;
      case 'T':
        final x1 = lcx == null ? cx : 2 * cx - lcx, y1 = lcy == null || lcx == null ? cy : 2 * cy - lcy;
        final x = ox + n(), y = oy + n();
        path.quadraticBezierTo(x1, y1, x, y);
        lcx = x1;
        lcy = y1;
        cx = x;
        cy = y;
      case 'Z':
        path.close();
        cx = sx;
        cy = sy;
        lcx = null;
      default:
        i++; // commande inconnue : on avance
    }
  }
  return path;
}

/// Logo animé : [draw] 0..1 trace le contour (pochoir), [fill] 0..1 remplit la forme.
class LogoPainter extends CustomPainter {
  final LogoShape shape;
  final double draw, fill;
  final Color color;
  LogoPainter(this.shape, {this.draw = 1, this.fill = 1, this.color = logoOrange});

  @override
  void paint(Canvas canvas, Size size) {
    final k = math.min(size.width / shape.viewBox.width, size.height / shape.viewBox.height);
    canvas.save();
    canvas.translate((size.width - shape.viewBox.width * k) / 2, (size.height - shape.viewBox.height * k) / 2);
    canvas.scale(k);
    if (fill > 0) {
      final p = Paint()..color = color.withValues(alpha: fill.clamp(0, 1));
      for (final path in shape.paths) {
        canvas.drawPath(path, p);
      }
    }
    if (draw > 0 && fill < 1) {
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1 / k * 2
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 1 - fill * 0.8);
      for (final path in shape.paths) {
        for (final m in path.computeMetrics()) {
          canvas.drawPath(m.extractPath(0, m.length * draw.clamp(0, 1)), stroke);
        }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(LogoPainter o) => o.draw != draw || o.fill != fill || o.color != color;
}

/// Logo plein (chargé une fois), à la taille de son parent.
class LogoMark extends StatelessWidget {
  const LogoMark({super.key});

  @override
  Widget build(BuildContext context) => FutureBuilder<LogoShape>(
        future: LogoShape.load(),
        builder: (context, snap) => snap.hasData
            ? CustomPaint(painter: LogoPainter(snap.data!, color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFFF8A4C) : logoOrange))
            : const SizedBox(),
      );
}
