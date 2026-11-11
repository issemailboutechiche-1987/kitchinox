// Textures des finitions : bois, marbre, granit, béton, quartz, terrazzo, inox.
// Générées une fois au démarrage (motifs raccordables, 512 px), plus les photos importées
// par l'utilisateur (échantillon de façade ou de plan de travail).

import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../engine/engine.dart';

class TextureBank extends ChangeNotifier {
  TextureBank._();
  static final instance = TextureBank._();

  static const size = 512;
  final Map<String, ui.Image> _img = {};
  final Set<String> _pending = {};
  bool _started = false;

  /// Texture prête, sinon null : elle est alors générée en arrière-plan, seulement à la première demande
  /// (rien n'est calculé au démarrage) ; les vues se redessinent quand elle est prête.
  ui.Image? operator [](String key) {
    final img = _img[key];
    if (img == null) _ensure(key);
    return img;
  }

  bool get ready => _img.isNotEmpty;

  final Set<String> _making = {};
  Timer? _notify;

  static const _derived = {'parquet_light': 'wood_light', 'parquet_oak': 'wood_oak', 'parquet_walnut': 'wood_walnut'};

  bool _known(String key) => _generators.containsKey(key) || _derived.containsKey(key) || key == 'concrete_smooth' || key == 'concrete_dark';

  void _ensure(String key) {
    if (_making.contains(key) || !_known(key)) return;
    _making.add(key);
    Future<void>(() async {
      try {
        _img[key] = await _make(key);
        // plusieurs textures prêtes en même temps : un seul rafraîchissement
        _notify?.cancel();
        _notify = Timer(const Duration(milliseconds: 40), notifyListeners);
      } catch (_) {
        // pas de rendu d'image disponible (tests) : couleurs unies
      }
    });
  }

  Future<ui.Image> _make(String key) async {
    final gen = _generators[key];
    if (gen != null) return _img[key] ?? await _render(gen, key.hashCode);
    final wood = _derived[key];
    if (wood != null) {
      final w = _img[wood] ??= await _make(wood);
      final seed = {'parquet_light': 11, 'parquet_oak': 12, 'parquet_walnut': 13}[key]!;
      return _renderSized(2048, (c, r) => _parquet(c, r, w), seed);
    }
    if (key == 'concrete_dark') {
      return _renderSized(1024, (c, r) {
        _concreteSmooth(c, r);
        c.drawRect(const Rect.fromLTWH(0, 0, 1024, 1024), Paint()..color = const Color(0xFF2C2D30).withValues(alpha: 0.82));
      }, 22);
    }
    return _renderSized(1024, _concreteSmooth, 21);
  }

  /// Génère les textures intégrées (asynchrone, la vue se redessine à la fin).
  Future<void> init() async {
    if (_started) return;
    _started = true;
    for (final e in _generators.entries) {
      try {
        _img[e.key] = await _render(e.value, e.key.hashCode);
      } catch (_) {
        // pas de rendu d'image disponible (tests) : les vues gardent les couleurs unies
      }
    }
    // sols haute définition : parquets en lames (à partir des bois) et béton ciré lisse
    try {
      for (final (key, wood, seed) in const [
        ('parquet_light', 'wood_light', 11),
        ('parquet_oak', 'wood_oak', 12),
        ('parquet_walnut', 'wood_walnut', 13),
      ]) {
        final w = _img[wood];
        if (w != null) _img[key] = await _renderSized(2048, (c, r) => _parquet(c, r, w), seed);
      }
      _img['concrete_smooth'] = await _renderSized(1024, _concreteSmooth, 21);
      _img['concrete_dark'] = await _renderSized(1024, (c, r) {
        _concreteSmooth(c, r);
        c.drawRect(const Rect.fromLTWH(0, 0, 1024, 1024), Paint()..color = const Color(0xFF2C2D30).withValues(alpha: 0.82));
      }, 22);
    } catch (_) {}
    notifyListeners();
  }

  static Future<ui.Image> _renderSized(int px, void Function(Canvas, math.Random) draw, int seed) async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec, Rect.fromLTWH(0, 0, px.toDouble(), px.toDouble()));
    draw(c, math.Random(seed));
    return rec.endRecording().toImage(px, px);
  }

  /// Parquet : motif de 2160 mm (12 rangées de lames de 180 mm), lames de 1200 à 2000 mm
  /// à joints décalés, chacune avec son morceau de bois et sa nuance, joints fins et chanfrein.
  static void _parquet(Canvas c, math.Random r, ui.Image wood) {
    const px = 2048.0, mm = 2160.0, k = px / mm;
    const rowH = 180 * k;
    final seam = Paint()
      ..color = const Color(0xFF3B2A1C).withValues(alpha: 0.55)
      ..strokeWidth = 1.6;
    final bevel = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..strokeWidth = 1.2;
    for (var row = 0; row < 12; row++) {
      final y = row * rowH;
      var x = -r.nextDouble() * 1600 * k;
      while (x < px) {
        final len = (1200 + r.nextDouble() * 800) * k;
        for (final shift in [0.0, px]) {
          final rect = Rect.fromLTWH(x - shift, y, len, rowH);
          if (rect.right <= 0 || rect.left >= px) continue;
          // bois : un tirage du motif par lame (fil le long de la lame)
          final m = Matrix4.identity()
            ..translateByDouble(rect.left - r.nextDouble() * 400, y - r.nextDouble() * 400, 0, 1)
            ..scaleByDouble(1400 * k / wood.width, 1400 * k / wood.width, 1, 1);
          c.save();
          c.clipRect(rect);
          c.drawRect(rect, Paint()..shader = ImageShader(wood, TileMode.repeated, TileMode.repeated, m.storage, filterQuality: FilterQuality.high));
          c.drawRect(rect, Paint()..color = (r.nextBool() ? Colors.black : Colors.white).withValues(alpha: r.nextDouble() * 0.09));
          c.restore();
          c.drawLine(rect.topLeft, rect.topRight, bevel);
          c.drawLine(rect.bottomLeft, rect.bottomRight, seam);
          c.drawLine(rect.topRight, rect.bottomRight, seam);
        }
        x += len;
      }
    }
  }

  /// Béton ciré : fond lisse, nuances nuageuses très douces, traces de lissage, grain fin.
  static void _concreteSmooth(Canvas c, math.Random r) {
    const s = 1024.0;
    c.drawRect(const Rect.fromLTWH(0, 0, s, s), Paint()..color = const Color(0xFFA3A39E));
    void wrap(void Function() f) {
      for (final dx in [-s, 0.0, s]) {
        for (final dy in [-s, 0.0, s]) {
          c.save();
          c.translate(dx, dy);
          f();
          c.restore();
        }
      }
    }

    final cloud = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 80);
    for (var i = 0; i < 26; i++) {
      final o = Offset(r.nextDouble() * s, r.nextDouble() * s);
      final rad = 120 + r.nextDouble() * 260;
      cloud.color = (r.nextBool() ? Colors.white : Colors.black).withValues(alpha: 0.05 + r.nextDouble() * 0.05);
      wrap(() => c.drawCircle(o, rad, cloud));
    }
    // traces de taloche : arcs larges et très légers
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    for (var i = 0; i < 40; i++) {
      final o = Offset(r.nextDouble() * s, r.nextDouble() * s);
      final rad = 140 + r.nextDouble() * 220;
      stroke
        ..strokeWidth = 18 + r.nextDouble() * 30
        ..color = (r.nextBool() ? Colors.white : Colors.black).withValues(alpha: 0.025 + r.nextDouble() * 0.03);
      final a0 = r.nextDouble() * math.pi * 2;
      wrap(() => c.drawArc(Rect.fromCircle(center: o, radius: rad), a0, 0.8 + r.nextDouble() * 1.2, false, stroke));
    }
    // grain très fin
    final p = Paint();
    for (var i = 0; i < 9000; i++) {
      p.color = (r.nextBool() ? Colors.white : Colors.black).withValues(alpha: 0.035);
      c.drawCircle(Offset(r.nextDouble() * s, r.nextDouble() * s), 0.6 + r.nextDouble() * 0.8, p);
    }
  }

  /// Décode les textures importées qui ne le sont pas encore.
  Future<void> syncCustom(List<CustomTexture> list) async {
    var changed = false;
    for (final t in list) {
      final key = 'custom:${t.id}';
      if (_img.containsKey(key) || _pending.contains(key) || t.data.isEmpty) continue;
      _pending.add(key);
      try {
        _img[key] = await decode(base64Decode(t.data));
        changed = true;
      } catch (_) {
        // image illisible : on garde la teinte moyenne
      } finally {
        _pending.remove(key);
      }
    }
    if (changed) notifyListeners();
  }

  static Future<ui.Image> decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 1024);
    return (await codec.getNextFrame()).image;
  }

  /// Teinte moyenne d'une image (pour les vues sans texture et la vignette).
  static Future<int> averageColor(ui.Image img) async {
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return 0xFFBBBBBB;
    var r = 0, g = 0, b = 0, n = 0;
    final step = math.max(4, (data.lengthInBytes ~/ 4 ~/ 4000)) * 4;
    for (var i = 0; i + 3 < data.lengthInBytes; i += step) {
      r += data.getUint8(i);
      g += data.getUint8(i + 1);
      b += data.getUint8(i + 2);
      n++;
    }
    if (n == 0) return 0xFFBBBBBB;
    return 0xFF000000 | ((r ~/ n) << 16) | ((g ~/ n) << 8) | (b ~/ n);
  }

  static Future<ui.Image> _render(void Function(Canvas, math.Random) draw, int seed) async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec, const Rect.fromLTWH(0, 0, 512, 512));
    draw(c, math.Random(seed));
    final pic = rec.endRecording();
    return pic.toImage(size, size);
  }

  // ---------------------------------------------------------------------------
  // Motifs
  // ---------------------------------------------------------------------------

  static const double _s = 512;

  /// Dessine [f] neuf fois (décalé d'une tuile) pour que le motif se raccorde.
  static void _wrap(Canvas c, void Function() f) {
    for (final dx in [-_s, 0.0, _s]) {
      for (final dy in [-_s, 0.0, _s]) {
        c.save();
        c.translate(dx, dy);
        f();
        c.restore();
      }
    }
  }

  static Color _jit(Color base, math.Random r, double amount) {
    final h = HSLColor.fromColor(base);
    return h.withLightness((h.lightness + (r.nextDouble() - 0.5) * amount).clamp(0.0, 1.0)).toColor();
  }

  static void Function(Canvas, math.Random) _wood(Color base, Color dark, {double density = 1}) => (c, r) {
        c.drawRect(const Rect.fromLTWH(0, 0, _s, _s), Paint()..color = base);
        // bandes larges et douces (variation de teinte du placage)
        for (var i = 0; i < 14; i++) {
          final y0 = r.nextDouble() * _s, h = 12 + r.nextDouble() * 46;
          final p = Paint()
            ..color = (r.nextBool() ? dark : Colors.white).withValues(alpha: 0.04 + r.nextDouble() * 0.06)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
          _wrap(c, () => c.drawRect(Rect.fromLTWH(-20, y0, _s + 40, h), p));
        }
        // fil : lignes presque droites, légèrement ondulées (périodiques en x)
        final n = (160 * density).round();
        for (var i = 0; i < n; i++) {
          final y0 = r.nextDouble() * _s;
          final k = 1 + r.nextInt(2);
          final a = 0.4 + r.nextDouble() * (r.nextDouble() < 0.2 ? 5 : 1.8);
          final ph = r.nextDouble() * math.pi * 2;
          final w = 0.4 + r.nextDouble() * (r.nextDouble() < 0.1 ? 2.2 : 0.9);
          final col = Color.lerp(base, dark, 0.35 + r.nextDouble() * 0.6)!.withValues(alpha: 0.10 + r.nextDouble() * 0.28);
          final path = Path();
          for (var x = 0.0; x <= _s; x += 8) {
            final y = y0 + a * math.sin(2 * math.pi * k * x / _s + ph);
            x == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
          }
          final p = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = w
            ..color = col;
          _wrap(c, () => c.drawPath(path, p));
        }
        // pores : petits traits dans le sens du fil
        final pore = Paint()..strokeWidth = 0.7;
        for (var i = 0; i < 1800; i++) {
          final x = r.nextDouble() * _s, y = r.nextDouble() * _s;
          pore.color = dark.withValues(alpha: 0.08 + r.nextDouble() * 0.14);
          c.drawLine(Offset(x, y), Offset(math.min(_s, x + 3 + r.nextDouble() * 9), y), pore);
        }
      };

  static void Function(Canvas, math.Random) _marble(Color base, Color vein, {Color? cloud}) => (c, r) {
        c.drawRect(const Rect.fromLTWH(0, 0, _s, _s), Paint()..color = base);
        final soft = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30);
        for (var i = 0; i < 18; i++) {
          final o = Offset(r.nextDouble() * _s, r.nextDouble() * _s);
          soft.color = (cloud ?? vein).withValues(alpha: 0.05 + r.nextDouble() * 0.06);
          final rad = 40 + r.nextDouble() * 90;
          _wrap(c, () => c.drawCircle(o, rad, soft));
        }
        for (var i = 0; i < 6; i++) {
          final path = Path();
          var x = r.nextDouble() * _s, y = r.nextDouble() * _s;
          var ang = r.nextDouble() * math.pi * 2;
          path.moveTo(x, y);
          final len = 30 + r.nextInt(45);
          for (var k = 0; k < len; k++) {
            ang += (r.nextDouble() - 0.5) * 0.45;
            x += math.cos(ang) * 9;
            y += math.sin(ang) * 9;
            path.lineTo(x, y);
          }
          final main = i < 3;
          final halo = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = main ? 6 : 3
            ..color = vein.withValues(alpha: main ? 0.18 : 0.10)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
          final line = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = main ? 1.6 : 0.8
            ..color = vein.withValues(alpha: main ? 0.65 : 0.4);
          _wrap(c, () {
            c.drawPath(path, halo);
            c.drawPath(path, line);
          });
        }
      };

  static void Function(Canvas, math.Random) _speckle(Color base, List<Color> grains, {int count = 9000, double maxR = 2.2}) => (c, r) {
        c.drawRect(const Rect.fromLTWH(0, 0, _s, _s), Paint()..color = base);
        final p = Paint();
        for (var i = 0; i < count; i++) {
          p.color = grains[r.nextInt(grains.length)].withValues(alpha: 0.5 + r.nextDouble() * 0.5);
          c.drawCircle(Offset(r.nextDouble() * _s, r.nextDouble() * _s), 0.4 + r.nextDouble() * maxR, p);
        }
      };

  static void _concrete(Canvas c, math.Random r) {
    const base = Color(0xFF9C9D99);
    c.drawRect(const Rect.fromLTWH(0, 0, _s, _s), Paint()..color = base);
    final soft = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26);
    for (var i = 0; i < 40; i++) {
      final o = Offset(r.nextDouble() * _s, r.nextDouble() * _s);
      soft.color = (r.nextBool() ? Colors.white : Colors.black).withValues(alpha: 0.05 + r.nextDouble() * 0.06);
      final rad = 25 + r.nextDouble() * 70;
      _wrap(c, () => c.drawCircle(o, rad, soft));
    }
    final p = Paint();
    for (var i = 0; i < 6000; i++) {
      p.color = _jit(base, r, 0.35).withValues(alpha: 0.35);
      c.drawCircle(Offset(r.nextDouble() * _s, r.nextDouble() * _s), 0.5 + r.nextDouble() * 1.2, p);
    }
    for (var i = 0; i < 60; i++) {
      p.color = const Color(0xFF5E5F5C).withValues(alpha: 0.5);
      c.drawCircle(Offset(r.nextDouble() * _s, r.nextDouble() * _s), 0.8 + r.nextDouble() * 1.8, p);
    }
  }

  static void _terrazzo(Canvas c, math.Random r) {
    c.drawRect(const Rect.fromLTWH(0, 0, _s, _s), Paint()..color = const Color(0xFFEDE8E0));
    const chips = [Color(0xFFC9A28A), Color(0xFF8E8C88), Color(0xFF3F4A44), Color(0xFFD8C6A8), Color(0xFFB5543F), Color(0xFF6E7F8A)];
    final p = Paint();
    for (var i = 0; i < 420; i++) {
      final o = Offset(r.nextDouble() * _s, r.nextDouble() * _s);
      final rad = 2 + r.nextDouble() * (r.nextDouble() < 0.1 ? 14 : 6);
      final n = 5 + r.nextInt(3);
      final path = Path();
      for (var k = 0; k < n; k++) {
        final a = k / n * math.pi * 2 + r.nextDouble() * 0.5;
        final rr = rad * (0.6 + r.nextDouble() * 0.5);
        final q = o + Offset(math.cos(a) * rr, math.sin(a) * rr);
        k == 0 ? path.moveTo(q.dx, q.dy) : path.lineTo(q.dx, q.dy);
      }
      path.close();
      p.color = chips[r.nextInt(chips.length)];
      _wrap(c, () => c.drawPath(path, p));
    }
  }

  static void _steel(Canvas c, math.Random r) {
    c.drawRect(const Rect.fromLTWH(0, 0, _s, _s), Paint()..color = const Color(0xFFC6CACE));
    final p = Paint()..strokeWidth = 1;
    for (var y = 0.0; y < _s; y += 1) {
      p.color = (r.nextBool() ? Colors.white : Colors.black).withValues(alpha: r.nextDouble() * 0.08);
      c.drawLine(Offset(0, y), Offset(_s, y), p);
    }
  }

  /// Carrelage : [n] x [n] carreaux par motif, joints de [grout] px, légère variation de teinte.
  static void Function(Canvas, math.Random) _tiles(Color base, Color grout, int n, {double groutW = 4, double vary = 0.04, bool speckle = false}) =>
      (c, r) {
        c.drawRect(const Rect.fromLTWH(0, 0, _s, _s), Paint()..color = grout);
        final step = _s / n;
        for (var i = 0; i < n; i++) {
          for (var j = 0; j < n; j++) {
            final rect = Rect.fromLTWH(i * step + groutW / 2, j * step + groutW / 2, step - groutW, step - groutW);
            c.drawRect(rect, Paint()..color = _jit(base, r, vary));
            if (speckle) {
              final p = Paint();
              for (var k = 0; k < 160; k++) {
                p.color = _jit(base, r, 0.25).withValues(alpha: 0.35);
                c.drawCircle(Offset(rect.left + r.nextDouble() * rect.width, rect.top + r.nextDouble() * rect.height), 0.5 + r.nextDouble(), p);
              }
            }
            // reflet doux
            c.drawRect(
                rect,
                Paint()
                  ..shader = LinearGradient(colors: [Colors.white.withValues(alpha: 0.10), Colors.transparent], begin: Alignment.topLeft, end: Alignment.center)
                      .createShader(rect));
          }
        }
      };

  /// Briques / carreaux métro : rangées décalées d'une demi-brique.
  static void Function(Canvas, math.Random) _bricks(Color base, Color mortar, int cols, int rows, {double vary = 0.06, double joint = 4}) => (c, r) {
        c.drawRect(const Rect.fromLTWH(0, 0, _s, _s), Paint()..color = mortar);
        final bw = _s / cols, bh = _s / rows;
        for (var j = 0; j < rows; j++) {
          final off = j.isOdd ? bw / 2 : 0.0;
          for (var i = -1; i < cols; i++) {
            final rect = Rect.fromLTWH(i * bw + off + joint / 2, j * bh + joint / 2, bw - joint, bh - joint);
            final col = _jit(base, r, vary);
            c.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), Paint()..color = col);
            c.drawRect(Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height * 0.25),
                Paint()..color = Colors.white.withValues(alpha: 0.12));
          }
        }
      };

  /// Zellige : petits carreaux émaillés, couleur irrégulière et reflets.
  static void Function(Canvas, math.Random) _zellige(Color base) => (c, r) {
        c.drawRect(const Rect.fromLTWH(0, 0, _s, _s), Paint()..color = const Color(0xFFE9E4DA));
        const n = 5;
        const step = _s / n;
        for (var i = 0; i < n; i++) {
          for (var j = 0; j < n; j++) {
            final rect = Rect.fromLTWH(i * step + 2, j * step + 2, step - 4, step - 4);
            final col = _jit(base, r, 0.16);
            c.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), Paint()..color = col);
            final hl = Rect.fromCenter(center: rect.center + Offset((r.nextDouble() - 0.5) * 40, (r.nextDouble() - 0.5) * 40), width: 40, height: 30);
            c.drawOval(hl, Paint()
              ..color = Colors.white.withValues(alpha: 0.18)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
          }
        }
      };

  /// Carreaux de ciment : motif géométrique (rosace) sur fond clair.
  static void Function(Canvas, math.Random) _cement(Color bg, Color ink, Color accent) => (c, r) {
        c.drawRect(const Rect.fromLTWH(0, 0, _s, _s), Paint()..color = bg);
        const n = 4;
        const step = _s / n;
        final inkP = Paint()..color = ink;
        final acc = Paint()..color = accent;
        for (var i = 0; i < n; i++) {
          for (var j = 0; j < n; j++) {
            final o = Offset(i * step, j * step);
            final cx = o + const Offset(step / 2, step / 2);
            // quart de cercle dans chaque coin → rosace aux jonctions
            for (final (dx, dy) in [(0.0, 0.0), (step, 0.0), (0.0, step), (step, step)]) {
              c.drawCircle(o + Offset(dx, dy), step * 0.32, inkP);
            }
            final star = Path();
            for (var k = 0; k < 8; k++) {
              final a = k * math.pi / 4;
              final rr = k.isEven ? step * 0.30 : step * 0.13;
              final q = cx + Offset(math.cos(a) * rr, math.sin(a) * rr);
              k == 0 ? star.moveTo(q.dx, q.dy) : star.lineTo(q.dx, q.dy);
            }
            star.close();
            c.drawPath(star, acc);
            c.drawCircle(cx, step * 0.06, Paint()..color = bg);
            c.drawRect(Rect.fromLTWH(o.dx, o.dy, step, step), Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = Colors.black.withValues(alpha: 0.12));
          }
        }
      };

  static void _paint(Canvas c, math.Random r) {
    // peinture : grain très léger (gris neutre, teinté par la couleur de la finition)
    c.drawRect(const Rect.fromLTWH(0, 0, _s, _s), Paint()..color = const Color(0xFFF2F2F2));
    final p = Paint();
    for (var i = 0; i < 4000; i++) {
      p.color = (r.nextBool() ? Colors.white : Colors.black).withValues(alpha: 0.03);
      c.drawCircle(Offset(r.nextDouble() * _s, r.nextDouble() * _s), 0.8 + r.nextDouble() * 1.5, p);
    }
  }

  static final Map<String, void Function(Canvas, math.Random)> _generators = {
    'tile_white': _tiles(const Color(0xFFF1F0EC), const Color(0xFFCFCBC3), 2),
    'tile_grey': _tiles(const Color(0xFF9C9D99), const Color(0xFF7D7E7A), 2, speckle: true),
    'tile_terracotta': _tiles(const Color(0xFFB8653F), const Color(0xFFD9C7B0), 4, vary: 0.10, groutW: 5),
    'tile_marble': _tiles(const Color(0xFFEDEAE4), const Color(0xFFD6D2CA), 2, groutW: 2),
    'cement': _cement(const Color(0xFFEDE7DA), const Color(0xFF2F4B5C), const Color(0xFFB9853C)),
    'subway': _bricks(const Color(0xFFF7F7F4), const Color(0xFFD5D3CD), 4, 8, vary: 0.03),
    'subway_green': _bricks(const Color(0xFF5E8A74), const Color(0xFFDAD8D0), 4, 8, vary: 0.08),
    'brick': _bricks(const Color(0xFFA5533A), const Color(0xFFCFC2B0), 2, 7, vary: 0.12, joint: 6),
    'zellige_green': _zellige(const Color(0xFF2E6B57)),
    'zellige_white': _zellige(const Color(0xFFF2EFE6)),
    'zellige_blue': _zellige(const Color(0xFF2E5E86)),
    'paint': _paint,

    'wood_oak': _wood(const Color(0xFFC9A273), const Color(0xFF8A6239)),
    'wood_light': _wood(const Color(0xFFE2C9A4), const Color(0xFFB08C62), density: 0.8),
    'wood_walnut': _wood(const Color(0xFF6E4A31), const Color(0xFF3B2516), density: 1.1),
    'wood_smoked': _wood(const Color(0xFF8B7663), const Color(0xFF4E4034)),
    'marble_white': _marble(const Color(0xFFF1EEEA), const Color(0xFF8C8C8F), cloud: const Color(0xFFB9B4AC)),
    'marble_black': _marble(const Color(0xFF242426), const Color(0xFFE8E6E1), cloud: const Color(0xFF55555A)),
    'marble_green': _marble(const Color(0xFF2F4A3F), const Color(0xFFD9E3DA), cloud: const Color(0xFF14261E)),
    'granite_black': _speckle(const Color(0xFF232427), const [Color(0xFF0E0E10), Color(0xFF4A4B50), Color(0xFF7D7E83), Color(0xFFB5B6B8)]),
    'granite_grey': _speckle(const Color(0xFF9A9894), const [Color(0xFF2D2C2B), Color(0xFF5E5C59), Color(0xFFD9D6D0), Color(0xFF8A7765)]),
    'quartz_white': _speckle(const Color(0xFFEFEDE8), const [Color(0xFFD5D2CB), Color(0xFFBDB9B1), Color(0xFFFFFFFF), Color(0xFF9F9A92)], count: 5000, maxR: 1.3),
    'concrete': _concrete,
    'quartz_grey': _speckle(const Color(0xFFC6C5C0), const [Color(0xFFA9A7A1), Color(0xFF8E8C87), Color(0xFFE9E8E4), Color(0xFF77746F)], count: 5000, maxR: 1.3),
    'terrazzo': _terrazzo,
    'steel': _steel,
  };
}

/// Peinture d'une finition pour une surface dont les coordonnées locales sont en mm.
/// [vertical] : fil du bois vertical (portes). Sans texture chargée : couleur unie.
Paint texturePaint(String? tex, Color color, double tileMm, {bool vertical = false, Offset origin = Offset.zero}) {
  final img = tex == null ? null : TextureBank.instance[tex];
  if (img == null) return Paint()..color = color;
  final k = tileMm / img.width;
  final m = Matrix4.identity()..translateByDouble(origin.dx, origin.dy, 0, 1);
  if (vertical) m.rotateZ(math.pi / 2);
  m.scaleByDouble(k, k, 1, 1);
  return Paint()
    ..color = color
    ..shader = ImageShader(img, TileMode.repeated, TileMode.repeated, m.storage, filterQuality: FilterQuality.medium);
}
