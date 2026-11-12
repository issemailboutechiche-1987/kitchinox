// Éditeur de la forme de la pièce : la pièce est rectangulaire par défaut, on peut la redessiner librement
// avec des traits et des arcs (tracé point par point, points déplaçables, longueurs et flèches saisies au clavier).
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/engine.dart';
import 'app_state.dart';
import 'theme.dart';
import 'i18n.dart';
import 'app_settings.dart';

const _orange = Color(0xFFF26A1B);

Future<void> showRoomShapeEditor(BuildContext context, AppState state, void Function(String) onMessage) => Navigator.of(context).push(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => RoomShapeEditor(state: state, onMessage: onMessage)),
    );

/// Formes de départ (mm).
List<RoomVertex> _preset(String id, double w, double d) => switch (id) {
      'L' => [RoomVertex(0, 0), RoomVertex(w, 0), RoomVertex(w, d * 0.55), RoomVertex(w * 0.55, d * 0.55), RoomVertex(w * 0.55, d), RoomVertex(0, d)],
      'pan' => [RoomVertex(0, 0), RoomVertex(w * 0.7, 0), RoomVertex(w, d * 0.3), RoomVertex(w, d), RoomVertex(0, d)],
      'arc' => [RoomVertex(0, 0), RoomVertex(w, 0), RoomVertex(w, d, w * 0.18), RoomVertex(0, d)],
      'T' => [
          RoomVertex(0, 0), RoomVertex(w, 0), RoomVertex(w, d * 0.45), RoomVertex(w * 0.7, d * 0.45), RoomVertex(w * 0.7, d), RoomVertex(w * 0.3, d),
          RoomVertex(w * 0.3, d * 0.45), RoomVertex(0, d * 0.45),
        ],
      _ => [RoomVertex(0, 0), RoomVertex(w, 0), RoomVertex(w, d), RoomVertex(0, d)],
    };

class RoomShapeEditor extends StatefulWidget {
  final AppState state;
  final void Function(String) onMessage;
  const RoomShapeEditor({super.key, required this.state, required this.onMessage});
  @override
  State<RoomShapeEditor> createState() => _RoomShapeEditorState();
}

class _RoomShapeEditorState extends State<RoomShapeEditor> {
  late List<RoomVertex> pts;
  bool drawing = false; // tracé point par point
  bool closed = true;
  String tool = 'line'; // segment suivant : 'line' | 'arc'
  int? selVertex, selEdge;
  int? _dragging;
  // repère écran
  double _k = 0.1, _ox = 0, _oy = 0;

  @override
  void initState() {
    super.initState();
    final r = widget.state.project.room;
    pts = r.outline == null ? _preset('rect', r.width, r.depth) : [for (final p in r.outline!) p.copy()];
  }

  // ---------------------------------------------------------------- géométrie
  double get _orient {
    var a = 0.0;
    for (var i = 0; i < pts.length; i++) {
      final p = pts[i], q = pts[(i + 1) % pts.length];
      a += p.x * q.y - q.x * p.y;
    }
    return a >= 0 ? 1 : -1;
  }

  /// Points d'un segment (arc découpé), en mm.
  List<Offset> _seg(int i, [int n = 20]) {
    final a = pts[i], b = pts[(i + 1) % pts.length];
    if (a.bulge.abs() < 0.5) return [Offset(a.x, a.y), Offset(b.x, b.y)];
    final len = math.sqrt(math.pow(b.x - a.x, 2) + math.pow(b.y - a.y, 2));
    if (len == 0) return [Offset(a.x, a.y)];
    final dx = (b.x - a.x) / len, dy = (b.y - a.y) / len;
    final o = _orient;
    final arc = Wall('x', a.x, a.y, dx, dy, -dy * o, dx * o, len, bulge: a.bulge);
    return [for (final (x, y) in arc.points(n)) Offset(x, y)];
  }

  double _len(int i) {
    final a = pts[i], b = pts[(i + 1) % pts.length];
    return math.sqrt(math.pow(b.x - a.x, 2) + math.pow(b.y - a.y, 2));
  }

  Offset _scr(double x, double y) => Offset(_ox + x * _k, _oy + y * _k);
  Offset _mm(Offset p) => Offset((p.dx - _ox) / _k, (p.dy - _oy) / _k);

  void _fit(Size size) {
    if (pts.isEmpty) {
      _k = math.min(size.width, size.height) / 8000;
      _ox = 60;
      _oy = 60;
      return;
    }
    final all = [for (var i = 0; i < pts.length; i++) ..._seg(i)];
    var x0 = all.map((p) => p.dx).reduce(math.min), x1 = all.map((p) => p.dx).reduce(math.max);
    var y0 = all.map((p) => p.dy).reduce(math.min), y1 = all.map((p) => p.dy).reduce(math.max);
    if (drawing) {
      // en tracé : on garde de la place autour pour continuer
      x0 -= 1500;
      y0 -= 1500;
      x1 += 1500;
      y1 += 1500;
    }
    final w = math.max(1000.0, x1 - x0), h = math.max(1000.0, y1 - y0);
    _k = math.min((size.width - 160) / w, (size.height - 140) / h);
    _ox = (size.width - w * _k) / 2 - x0 * _k;
    _oy = (size.height - h * _k) / 2 - y0 * _k;
  }

  /// Aimantation : 10 mm, et alignement horizontal / vertical (ou 45°) avec le point voisin.
  Offset _snap(Offset mm, int? neighbour) {
    var p = Offset((mm.dx / 10).round() * 10, (mm.dy / 10).round() * 10);
    if (neighbour != null && neighbour >= 0 && neighbour < pts.length) {
      final q = Offset(pts[neighbour].x, pts[neighbour].y);
      final d = p - q;
      final ang = math.atan2(d.dy, d.dx);
      for (final a in [0.0, math.pi / 4, math.pi / 2, 3 * math.pi / 4, math.pi, -math.pi / 4, -math.pi / 2, -3 * math.pi / 4]) {
        if ((ang - a).abs() < 6 * math.pi / 180) {
          final l = d.distance;
          final snapped = q + Offset(math.cos(a), math.sin(a)) * l;
          p = Offset((snapped.dx).roundToDouble(), (snapped.dy).roundToDouble());
          break;
        }
      }
    }
    return p;
  }

  int? _hitVertex(Offset s) {
    for (var i = 0; i < pts.length; i++) {
      if ((_scr(pts[i].x, pts[i].y) - s).distance < 22) return i;
    }
    return null;
  }

  int? _hitEdge(Offset s) {
    final n = closed ? pts.length : pts.length - 1;
    for (var i = 0; i < n; i++) {
      final seg = _seg(i);
      for (var j = 0; j + 1 < seg.length; j++) {
        final a = _scr(seg[j].dx, seg[j].dy), b = _scr(seg[j + 1].dx, seg[j + 1].dy);
        final ab = b - a;
        final t = ab.distanceSquared == 0 ? 0.0 : (((s - a).dx * ab.dx + (s - a).dy * ab.dy) / ab.distanceSquared).clamp(0.0, 1.0);
        if ((a + ab * t - s).distance < 16) return i;
      }
    }
    return null;
  }

  // ---------------------------------------------------------------- gestes
  void _tap(Offset s) {
    if (drawing) {
      final hit = _hitVertex(s);
      if (hit == 0 && pts.length >= 3) {
        setState(() {
          pts.last.bulge = tool == 'arc' ? _len(pts.length - 1) / 4 : 0;
          drawing = false;
          closed = true;
          selEdge = null;
        });
        return;
      }
      final p = _snap(_mm(s), pts.isEmpty ? null : pts.length - 1);
      setState(() {
        if (pts.isNotEmpty && tool == 'arc') {
          final last = pts.last;
          final l = (p - Offset(last.x, last.y)).distance;
          last.bulge = l / 4;
        }
        pts.add(RoomVertex(p.dx, p.dy));
      });
      return;
    }
    final v = _hitVertex(s);
    final e = v == null ? _hitEdge(s) : null;
    setState(() {
      selVertex = v;
      selEdge = e;
    });
  }

  void _panStart(Offset s) {
    if (drawing) return;
    _dragging = _hitVertex(s);
    if (_dragging != null) setState(() => selVertex = _dragging);
  }

  void _panUpdate(Offset s) {
    final i = _dragging;
    if (i == null) return;
    // aligné sur le point précédent ou le suivant
    final prev = (i - 1 + pts.length) % pts.length, next = (i + 1) % pts.length;
    var p = _snap(_mm(s), prev);
    final pn = _snap(_mm(s), next);
    if ((pn - _mm(s)).distance < (p - _mm(s)).distance) p = pn;
    setState(() {
      pts[i].x = p.dx;
      pts[i].y = p.dy;
    });
  }

  // ---------------------------------------------------------------- actions
  void _setLength(int i, double l) {
    final a = pts[i], b = pts[(i + 1) % pts.length];
    final cur = _len(i);
    if (cur == 0 || l <= 0) return;
    final dx = (b.x - a.x) / cur * (l - cur), dy = (b.y - a.y) / cur * (l - cur);
    // on allonge le mur : les points suivants se décalent (sauf le premier, pour garder la pièce fermée)
    setState(() {
      for (var k = i + 1; k < pts.length; k++) {
        pts[k].x += dx;
        pts[k].y += dy;
      }
    });
  }

  void _splitEdge(int i) {
    final a = pts[i], b = pts[(i + 1) % pts.length];
    setState(() {
      pts.insert(i + 1, RoomVertex(((a.x + b.x) / 2).roundToDouble(), ((a.y + b.y) / 2).roundToDouble()));
      a.bulge = 0;
      selEdge = null;
      selVertex = i + 1;
    });
  }

  String? _problem() {
    if (pts.length < 3) return 'Il faut au moins 3 murs';
    for (var i = 0; i < pts.length; i++) {
      if (_len(i) < 300) return 'Mur ${Room.outlineId(i)} trop court (moins de 30 cm)';
    }
    // segments qui se croisent (pièce impossible)
    bool cross(Offset a, Offset b, Offset c, Offset d) {
      double o(Offset p, Offset q, Offset r) => (q.dx - p.dx) * (r.dy - p.dy) - (q.dy - p.dy) * (r.dx - p.dx);
      return o(a, b, c) * o(a, b, d) < 0 && o(c, d, a) * o(c, d, b) < 0;
    }

    for (var i = 0; i < pts.length; i++) {
      for (var j = i + 2; j < pts.length; j++) {
        if (i == 0 && j == pts.length - 1) continue;
        final a = Offset(pts[i].x, pts[i].y), b = Offset(pts[(i + 1) % pts.length].x, pts[(i + 1) % pts.length].y);
        final c = Offset(pts[j].x, pts[j].y), d = Offset(pts[(j + 1) % pts.length].x, pts[(j + 1) % pts.length].y);
        if (cross(a, b, c, d)) return 'Les murs ${Room.outlineId(i)} et ${Room.outlineId(j)} se croisent';
      }
    }
    if (pts.length > 14) return 'Au plus 14 murs';
    return null;
  }

  void _apply() {
    final pb = _problem();
    if (pb != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(pb), behavior: SnackBarBehavior.floating, width: 520));
      return;
    }
    final msg = widget.state.setRoomOutline(pts);
    Navigator.of(context).pop();
    widget.onMessage(msg);
  }

  // ---------------------------------------------------------------- écran
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final r = widget.state.project.room;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Forme de la pièce')),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('Annuler'))),
          const SizedBox(width: 8),
          FilledButton.icon(onPressed: drawing ? null : _apply, icon: const Icon(Icons.check), label: Text(tr('Valider'))),
          const SizedBox(width: 12),
        ],
      ),
      body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // ---- panneau
        SizedBox(
          width: 320,
          child: ListView(padding: const EdgeInsets.all(Tokens.s4), children: [
            Text(tr('Partir d’une forme'), style: t.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final (id, label) in const [('rect', 'Rectangle'), ('L', 'En L'), ('pan', 'Pan coupé'), ('arc', 'Mur arrondi'), ('T', 'En T')])
                ActionChip(
                  label: Text(label),
                  onPressed: () => setState(() {
                    pts = _preset(id, r.width, r.depth);
                    drawing = false;
                    closed = true;
                    selEdge = selVertex = null;
                  }),
                ),
            ]),
            const SizedBox(height: Tokens.s4),
            Text(tr('Dessiner librement'), style: t.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
                drawing
                    ? tr('Touchez pour poser chaque coin. Touchez le premier point pour fermer la pièce. Les traits s’aimantent à l’horizontale, à la verticale et à 45°.')
                    : tr('Effacez et tracez la pièce coin par coin, en traits droits ou en arcs.'),
                style: t.bodySmall),
            SizedBox(height: 8),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 'line', icon: Icon(Icons.horizontal_rule), label: Text(tr('Trait'))),
                ButtonSegment(value: 'arc', icon: Icon(Icons.architecture), label: Text(tr('Arc'))),
              ],
              selected: {tool},
              onSelectionChanged: (v) => setState(() => tool = v.first),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (!drawing)
                OutlinedButton.icon(
                  onPressed: () => setState(() {
                    pts = [];
                    drawing = true;
                    closed = false;
                    selEdge = selVertex = null;
                  }),
                  icon: const Icon(Icons.draw_outlined),
                  label: Text(tr('Nouveau tracé')),
                )
              else ...[
                OutlinedButton.icon(
                  onPressed: pts.isEmpty ? null : () => setState(() => pts.removeLast()),
                  icon: const Icon(Icons.undo),
                  label: Text(tr('Dernier point')),
                ),
                FilledButton.icon(
                  onPressed: pts.length < 3
                      ? null
                      : () => setState(() {
                            drawing = false;
                            closed = true;
                          }),
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(tr('Fermer la pièce')),
                ),
              ],
            ]),
            if (!drawing && selEdge != null && selEdge! < pts.length) ..._edgePanel(t, selEdge!),
            if (!drawing && selVertex != null && selVertex! < pts.length) ...[
              const SizedBox(height: Tokens.s4),
              Text(trp('Coin {0}', [selVertex! + 1]), style: t.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(tr('Glissez-le sur le plan, ou supprimez-le.'), style: t.bodySmall),
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: pts.length <= 3
                    ? null
                    : () => setState(() {
                          pts.removeAt(selVertex!);
                          selVertex = null;
                        }),
                icon: const Icon(Icons.delete_outline),
                label: Text(tr('Supprimer ce coin')),
              ),
            ],
            const SizedBox(height: Tokens.s4),
            if (!drawing) Text(_problem() ?? trp('Surface : {0} m² · {1} murs', [_area().toStringAsFixed(1).replaceAll('.', ','), pts.length]), style: t.bodySmall?.copyWith(color: _problem() == null ? null : scheme.error)),
            const SizedBox(height: Tokens.s3),
            Text(tr('Les caissons, portes et fenêtres se posent sur les murs droits horizontaux ou verticaux. Les arcs et les murs en biais sont dessinés '
                'en plan, en 3D et sur le plan d’exécution.'),
                style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
          ]),
        ),
        VerticalDivider(width: 1, color: scheme.outlineVariant),
        // ---- plan
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            if (_dragging == null) _fit(c.biggest);
            return GestureDetector(
              onTapUp: (d) => _tap(d.localPosition),
              onPanStart: (d) => _panStart(d.localPosition),
              onPanUpdate: (d) => _panUpdate(d.localPosition),
              onPanEnd: (_) => setState(() => _dragging = null),
              child: CustomPaint(
                key: const Key('room-shape-canvas'),
                size: c.biggest,
                painter: _ShapePainter(this),
              ),
            );
          }),
        ),
      ]),
    );
  }

  double _area() {
    final poly = [for (var i = 0; i < pts.length; i++) ..._seg(i).sublist(0, math.max(1, _seg(i).length - 1))];
    var a = 0.0;
    for (var i = 0; i < poly.length; i++) {
      final p = poly[i], q = poly[(i + 1) % poly.length];
      a += p.dx * q.dy - q.dx * p.dy;
    }
    return a.abs() / 2 / 1e6;
  }

  List<Widget> _edgePanel(TextTheme t, int i) {
    final a = pts[i];
    return [
      const SizedBox(height: Tokens.s4),
      Text(trp('Mur {0}', [Room.outlineId(i)]), style: t.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
      SizedBox(height: 8),
      SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: [ButtonSegment(value: false, label: Text(tr('Trait'))), ButtonSegment(value: true, label: Text(tr('Arc')))],
        selected: {a.bulge.abs() >= 0.5},
        onSelectionChanged: (v) => setState(() => a.bulge = v.first ? (_len(i) / 4).roundToDouble() : 0),
      ),
      const SizedBox(height: 10),
      _MmInput(
        key: ValueKey('len-$i-${_len(i).round()}'),
        label: a.bulge.abs() >= 0.5 ? tr('Corde (longueur droite)') : tr('Longueur'),
        value: _len(i),
        onSubmit: (v) => _setLength(i, v),
      ),
      if (a.bulge.abs() >= 0.5) ...[
        const SizedBox(height: 10),
        _MmInput(
          key: ValueKey('bulge-$i-${a.bulge.round()}'),
          label: tr('Flèche de l’arc (creux au milieu)'),
          value: a.bulge.abs(),
          onSubmit: (v) => setState(() => a.bulge = (a.bulge < 0 ? -v : v)),
        ),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: () => setState(() => a.bulge = -a.bulge),
          icon: const Icon(Icons.swap_vert),
          label: Text(a.bulge > 0 ? tr('Arc vers l’intérieur') : tr('Arc vers l’extérieur')),
        ),
      ],
      const SizedBox(height: 8),
      OutlinedButton.icon(onPressed: () => _splitEdge(i), icon: const Icon(Icons.add_circle_outline), label: Text(tr('Ajouter un coin au milieu'))),
    ];
  }
}

class _MmInput extends StatelessWidget {
  final String label;
  final double value;
  final void Function(double) onSubmit;
  const _MmInput({super.key, required this.label, required this.value, required this.onSubmit});
  @override
  Widget build(BuildContext context) => TextFormField(
        initialValue: lenValue(value),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.allow(lenInputPattern)],
        decoration: InputDecoration(labelText: label, suffixText: lenSuffix, isDense: true, border: const OutlineInputBorder()),
        onFieldSubmitted: (s) {
          final v = editedLen(s, value);
          if (v != null && v > 0) onSubmit(v);
        },
      );
}

class _ShapePainter extends CustomPainter {
  final _RoomShapeEditorState s;
  _ShapePainter(this.s);

  @override
  void paint(Canvas c, Size size) {
    c.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFF7F4F0));
    // grille de 50 cm
    final g = Paint()
      ..color = const Color(0x16000000)
      ..strokeWidth = 1;
    final step = 500 * s._k;
    if (step > 6) {
      final x0 = s._ox % step, y0 = s._oy % step;
      for (var x = x0; x < size.width; x += step) {
        c.drawLine(Offset(x, 0), Offset(x, size.height), g);
      }
      for (var y = y0; y < size.height; y += step) {
        c.drawLine(Offset(0, y), Offset(size.width, y), g);
      }
    }
    final pts = s.pts;
    if (pts.isEmpty) return;
    final n = s.closed ? pts.length : pts.length - 1;
    final path = Path();
    var first = true;
    for (var i = 0; i < n; i++) {
      for (final p in s._seg(i)) {
        final q = s._scr(p.dx, p.dy);
        first ? path.moveTo(q.dx, q.dy) : path.lineTo(q.dx, q.dy);
        first = false;
      }
    }
    if (s.closed) {
      path.close();
      c.drawPath(path, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * 120 * s._k
        ..strokeJoin = StrokeJoin.miter
        ..color = const Color(0xFFD8D2CB));
      c.drawPath(path, Paint()..color = const Color(0xFFE6D3B3));
    }
    c.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF3D4650));
    // mur choisi
    final se = s.selEdge;
    if (se != null && se < n) {
      final seg = s._seg(se);
      final hp = Path();
      for (var j = 0; j < seg.length; j++) {
        final q = s._scr(seg[j].dx, seg[j].dy);
        j == 0 ? hp.moveTo(q.dx, q.dy) : hp.lineTo(q.dx, q.dy);
      }
      c.drawPath(hp, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = _orange);
    }
    // cotes et noms des murs
    for (var i = 0; i < n; i++) {
      final seg = s._seg(i);
      final mid = seg.length == 2 ? (seg[0] + seg[1]) / 2 : seg[seg.length ~/ 2];
      final a = pts[i], b = pts[(i + 1) % pts.length];
      final l = s._len(i);
      if (l < 1) continue;
      final nx = -(b.y - a.y) / l * s._orient, ny = (b.x - a.x) / l * s._orient; // vers l'intérieur
      final at = s._scr(mid.dx - nx * 260, mid.dy - ny * 260);
      final txt = '${s.closed ? '${Room.outlineId(i)} · ' : ''}${l.round()}${a.bulge.abs() >= 0.5 ? ' (arc)' : ''}';
      final tp = TextPainter(
          text: TextSpan(text: txt, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: se == i ? _orange : const Color(0xFF3D4650))),
          textDirection: TextDirection.ltr)
        ..layout();
      final r = Rect.fromCenter(center: at, width: tp.width + 10, height: tp.height + 4);
      c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)), Paint()..color = Colors.white);
      tp.paint(c, r.topLeft + const Offset(5, 2));
    }
    // coins
    for (var i = 0; i < pts.length; i++) {
      final q = s._scr(pts[i].x, pts[i].y);
      final sel = s.selVertex == i;
      c.drawCircle(q, sel ? 9 : 7, Paint()..color = sel || (s.drawing && i == 0) ? _orange : Colors.white);
      c.drawCircle(q, sel ? 9 : 7, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF3D4650));
    }
  }

  @override
  bool shouldRepaint(_ShapePainter o) => true;
}
