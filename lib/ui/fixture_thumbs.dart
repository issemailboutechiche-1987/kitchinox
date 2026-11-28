// Vignettes dessinées des équipements du plan de travail : évier (vu de dessus), mitigeur (de profil),
// plaque de cuisson (vue de dessus), four (de face). Couleurs de la finition choisie.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/engine.dart';

const _bg = Color(0xFFF1EFEC);

Color sinkColor(String finish) => switch (finish) { 'noir_quartz' => const Color(0xFF2A2B2E), 'blanc_ceramique' => const Color(0xFFF7F7F5), _ => const Color(0xFFB9BEC4) };
Color tapColor(String finish) =>
    switch (finish) { 'noir_mat' => const Color(0xFF26272A), 'or_brosse' => const Color(0xFFC9A247), 'inox_brosse' => const Color(0xFFA9AEB3), _ => const Color(0xFFD9DDE1) };

class SinkThumb extends StatelessWidget {
  final SinkModel sink;
  final String finish;
  const SinkThumb(this.sink, this.finish, {super.key});
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _SinkPainter(sink, finish));
}

class _SinkPainter extends CustomPainter {
  final SinkModel s;
  final String finish;
  _SinkPainter(this.s, this.finish);
  @override
  void paint(Canvas c, Size z) {
    c.drawRect(Offset.zero & z, Paint()..color = _bg);
    // plan de travail, puis l'évier à l'échelle (1000 mm = largeur utile)
    final k = math.min(z.width * 0.9 / 1000, z.height * 0.8 / 520);
    final w = s.length * k, h = s.depth * k;
    final r = Rect.fromCenter(center: z.center(Offset.zero), width: w, height: h);
    final body = sinkColor(finish);
    final dark = HSLColor.fromColor(body).withLightness((HSLColor.fromColor(body).lightness * 0.72).clamp(0, 1)).toColor();
    c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(4 * k + 2)), Paint()..color = body);
    c.drawRRect(
        RRect.fromRectAndRadius(r, Radius.circular(4 * k + 2)),
        Paint()
          ..color = Colors.black26
          ..style = PaintingStyle.stroke);
    void bowl(Rect b) {
      c.drawRRect(RRect.fromRectAndRadius(b, Radius.circular(30 * k)), Paint()..color = dark);
      c.drawCircle(b.center, math.max(2, 22 * k), Paint()..color = Colors.black45);
    }

    final m = 40 * k;
    switch (s.layout) {
      case '2_drainer':
        bowl(Rect.fromLTRB(r.left + m, r.top + m, r.left + w * 0.36, r.bottom - m));
        bowl(Rect.fromLTRB(r.left + w * 0.39, r.top + m * 2.5, r.left + w * 0.58, r.bottom - m));
        _drainer(c, Rect.fromLTRB(r.left + w * 0.62, r.top + m, r.right - m, r.bottom - m), dark);
      case 'drainer':
        bowl(Rect.fromLTRB(r.left + m, r.top + m, r.left + w * 0.5, r.bottom - m));
        _drainer(c, Rect.fromLTRB(r.left + w * 0.55, r.top + m, r.right - m, r.bottom - m), dark);
      case '2':
        bowl(Rect.fromLTRB(r.left + m, r.top + m, r.center.dx - m / 2, r.bottom - m));
        bowl(Rect.fromLTRB(r.center.dx + m / 2, r.top + m, r.right - m, r.bottom - m));
      default:
        bowl(r.deflate(m));
    }
  }

  void _drainer(Canvas c, Rect d, Color col) {
    final p = Paint()
      ..color = col
      ..strokeWidth = 1.2;
    for (var i = 1; i < 7; i++) {
      final x = d.left + d.width * i / 7;
      c.drawLine(Offset(x, d.top + 3), Offset(x, d.bottom - 3), p);
    }
  }

  @override
  bool shouldRepaint(covariant _SinkPainter o) => o.s.id != s.id || o.finish != finish;
}

class FaucetThumb extends StatelessWidget {
  final FaucetModel tap;
  final String finish;
  const FaucetThumb(this.tap, this.finish, {super.key});
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _FaucetPainter(tap, finish));
}

class _FaucetPainter extends CustomPainter {
  final FaucetModel f;
  final String finish;
  _FaucetPainter(this.f, this.finish);
  @override
  void paint(Canvas c, Size z) {
    c.drawRect(Offset.zero & z, Paint()..color = _bg);
    final base = z.height * 0.86;
    c.drawRect(Rect.fromLTRB(0, base, z.width, z.height), Paint()..color = const Color(0xFFDCD8D2));
    final col = tapColor(finish);
    final pen = Paint()
      ..color = col
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(3, z.width * 0.055);
    final edge = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = pen.strokeWidth + 1.6;
    final x = z.width * 0.36;
    final top = base - z.height * 0.72 * (f.height / 540).clamp(0.55, 1.0);
    final path = Path()..moveTo(x, base);
    if (f.square) {
      path
        ..lineTo(x, top)
        ..lineTo(x + z.width * 0.34, top)
        ..lineTo(x + z.width * 0.34, top + z.height * 0.12);
    } else if (f.swan || f.spring) {
      path
        ..lineTo(x, top + z.height * 0.12)
        ..quadraticBezierTo(x, top - z.height * 0.02, x + z.width * 0.17, top)
        ..quadraticBezierTo(x + z.width * 0.34, top + z.height * 0.02, x + z.width * 0.34, top + z.height * 0.2);
    } else {
      path
        ..lineTo(x, top)
        ..lineTo(x + z.width * 0.3, top)
        ..lineTo(x + z.width * 0.3, top + z.height * 0.1);
    }
    c.drawPath(path, edge);
    c.drawPath(path, pen);
    if (f.spring) {
      // ressort autour du col
      final p = Paint()
        ..color = col
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      for (var i = 0; i < 7; i++) {
        final y = base - (base - top) * (0.25 + i * 0.08);
        c.drawOval(Rect.fromCenter(center: Offset(x, y), width: pen.strokeWidth * 2.4, height: 4), p);
      }
    }
    if (f.pullout) c.drawCircle(Offset(x + z.width * 0.3, top + z.height * 0.12), pen.strokeWidth * 0.7, Paint()..color = Colors.black38);
    // manette
    c.drawLine(Offset(x + pen.strokeWidth, base - (base - top) * 0.3), Offset(x - z.width * 0.16, base - (base - top) * 0.46), pen..strokeWidth = pen.strokeWidth * 0.6);
  }

  @override
  bool shouldRepaint(covariant _FaucetPainter o) => o.f.id != f.id || o.finish != finish;
}

class HobThumb extends StatelessWidget {
  final String type; // induction, gaz, vitro
  const HobThumb(this.type, {super.key});
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _HobPainter(type));
}

class _HobPainter extends CustomPainter {
  final String type;
  _HobPainter(this.type);
  @override
  void paint(Canvas c, Size z) {
    c.drawRect(Offset.zero & z, Paint()..color = _bg);
    final r = Rect.fromCenter(center: z.center(Offset.zero), width: z.width * 0.82, height: z.height * 0.78);
    c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(5)), Paint()..color = type == 'gaz' ? const Color(0xFF8E9399) : const Color(0xFF1B1C1F));
    final spots = [Offset(r.left + r.width * 0.28, r.top + r.height * 0.3), Offset(r.left + r.width * 0.72, r.top + r.height * 0.3), Offset(r.left + r.width * 0.28, r.top + r.height * 0.72), Offset(r.left + r.width * 0.72, r.top + r.height * 0.72)];
    for (final (i, o) in spots.indexed) {
      final rad = r.height * (i.isEven ? 0.2 : 0.15);
      if (type == 'gaz') {
        c.drawCircle(o, rad, Paint()..color = const Color(0xFF2A2B2E));
        final grid = Paint()
          ..color = const Color(0xFF2A2B2E)
          ..strokeWidth = 2;
        c.drawLine(o - Offset(rad * 1.4, 0), o + Offset(rad * 1.4, 0), grid);
        c.drawLine(o - Offset(0, rad * 1.4), o + Offset(0, rad * 1.4), grid);
      } else {
        c.drawCircle(
            o,
            rad,
            Paint()
              ..color = type == 'vitro' ? const Color(0xFFB3412E) : const Color(0xFF9AA0A6)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HobPainter o) => o.type != type;
}

class OvenThumb extends StatelessWidget {
  final String finish, handle;
  const OvenThumb(this.finish, this.handle, {super.key});
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _OvenPainter(finish, handle));
}

class _OvenPainter extends CustomPainter {
  final String finish, handle;
  _OvenPainter(this.finish, this.handle);
  @override
  void paint(Canvas c, Size z) {
    c.drawRect(Offset.zero & z, Paint()..color = _bg);
    final frame = switch (finish) {
      'inox_brosse' => const Color(0xFFB9BEC4),
      'blanc' => const Color(0xFFF7F7F5),
      'full_black' || 'black_gold' => const Color(0xFF1B1C1F),
      _ => const Color(0xFFB9BEC4),
    };
    final glass = finish == 'blanc' ? const Color(0xFF3A3D42) : const Color(0xFF111214);
    final accent = finish == 'black_gold' ? const Color(0xFFC9A247) : const Color(0xFFD9DDE1);
    final r = Rect.fromCenter(center: z.center(Offset.zero), width: z.height * 0.95, height: z.height * 0.88);
    c.drawRect(r, Paint()..color = frame);
    c.drawRect(Rect.fromLTRB(r.left, r.top, r.right, r.top + r.height * 0.16), Paint()..color = finish == 'blanc' ? const Color(0xFFE8E8E6) : glass);
    final door = Rect.fromLTRB(r.left + 3, r.top + r.height * 0.24, r.right - 3, r.bottom - 3);
    c.drawRect(door, Paint()..color = glass);
    final hy = r.top + r.height * 0.31;
    final pen = Paint()
      ..color = accent
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    switch (handle) {
      case 'square':
        c.drawRect(Rect.fromLTRB(door.left + 6, hy - 2, door.right - 6, hy + 2), Paint()..color = accent);
      case 'retro':
        c.drawArc(Rect.fromLTRB(door.left + 6, hy - 4, door.right - 6, hy + 8), math.pi, math.pi, false, pen..style = PaintingStyle.stroke);
      case 'integrated':
        c.drawLine(Offset(door.left + 4, door.top + 1), Offset(door.right - 4, door.top + 1), pen..strokeWidth = 2);
      default:
        c.drawLine(Offset(door.left + 6, hy), Offset(door.right - 6, hy), pen);
    }
  }

  @override
  bool shouldRepaint(covariant _OvenPainter o) => o.finish != finish || o.handle != handle;
}
