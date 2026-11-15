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
  int snapStep = 50; // mm : 10, 50, 100, 0 (libre)
  bool orthoSnap = true; // aimantation orthogonale 90° et 45°
  Offset? activeGuidelineX; // guide d'alignement vertical
  Offset? activeGuidelineY; // guide d'alignement horizontal
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

  /// Aimantation : grille choisie, alignement magnétique sur les autres points et orthogonal (90° / 45°).
  Offset _snap(Offset mm, int? neighbour, [int? ignoreIndex]) {
    activeGuidelineX = null;
    activeGuidelineY = null;
    final step = snapStep <= 0 ? 1 : snapStep;
    var p = Offset((mm.dx / step).round() * step.toDouble(), (mm.dy / step).round() * step.toDouble());

    // Alignement magnétique automatique avec les autres coins de la pièce
    for (var i = 0; i < pts.length; i++) {
      if (i == ignoreIndex) continue;
      final other = pts[i];
      if ((p.dx - other.x).abs() < math.max(35.0, step * 0.9)) {
        p = Offset(other.x, p.dy);
        activeGuidelineX = Offset(other.x, other.y);
      }
      if ((p.dy - other.y).abs() < math.max(35.0, step * 0.9)) {
        p = Offset(p.dx, other.y);
        activeGuidelineY = Offset(other.x, other.y);
      }
    }

    if (orthoSnap && neighbour != null && neighbour >= 0 && neighbour < pts.length) {
      final q = Offset(pts[neighbour].x, pts[neighbour].y);
      final d = p - q;
      final ang = math.atan2(d.dy, d.dx);
      for (final a in [0.0, math.pi / 4, math.pi / 2, 3 * math.pi / 4, math.pi, -math.pi / 4, -math.pi / 2, -3 * math.pi / 4]) {
        if ((ang - a).abs() < 14 * math.pi / 180) {
          final l = d.distance;
          final snapped = q + Offset(math.cos(a), math.sin(a)) * l;
          p = Offset((snapped.dx / step).round() * step.toDouble(), (snapped.dy / step).round() * step.toDouble());
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
    var p = _snap(_mm(s), prev, i);
    final pn = _snap(_mm(s), next, i);
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
            const SizedBox(height: Tokens.s4),
            Text(tr('Précision & Aimantation (Snap)'), style: t.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final (step, label) in const [(50, 'Grille 50 mm'), (100, 'Grille 100 mm'), (10, 'Grille 10 mm'), (0, 'Libre')])
                ChoiceChip(
                  label: Text(tr(label)),
                  selected: snapStep == step,
                  onSelected: (_) => setState(() => snapStep = step),
                ),
            ]),
            const SizedBox(height: 8),
            FilterChip(
              avatar: Icon(orthoSnap ? Icons.lock_outline : Icons.lock_open_outlined, size: 16),
              label: Text(tr('Verrouillage orthogonal (90° & 45°)')),
              selected: orthoSnap,
              onSelected: (v) => setState(() => orthoSnap = v),
            ),
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
    // Grille bien visible : grille fine (10 cm) et grille principale (50 cm ou 100 cm)
    final gFine = Paint()..color = const Color(0x18000000)..strokeWidth = 0.9;
    final gMain = Paint()..color = const Color(0x38000000)..strokeWidth = 1.4;
    final stepFine = 100 * s._k;
    final stepMain = 500 * s._k;
    if (stepFine > 6) {
      final x0 = s._ox % stepFine, y0 = s._oy % stepFine;
      for (var x = x0; x < size.width; x += stepFine) {
        c.drawLine(Offset(x, 0), Offset(x, size.height), gFine);
      }
      for (var y = y0; y < size.height; y += stepFine) {
        c.drawLine(Offset(0, y), Offset(size.width, y), gFine);
      }
    }
    if (stepMain > 10) {
      final x0 = s._ox % stepMain, y0 = s._oy % stepMain;
      for (var x = x0; x < size.width; x += stepMain) {
        c.drawLine(Offset(x, 0), Offset(x, size.height), gMain);
      }
      for (var y = y0; y < size.height; y += stepMain) {
        c.drawLine(Offset(0, y), Offset(size.width, y), gMain);
      }
    }
    // Indicateur HUD grille / aimantation active en bas à droite
    final snapLabel = s.snapStep > 0 ? 'Snap: ${s.snapStep} mm ${s.orthoSnap ? '(Ortho 90°/45°)' : ''}' : 'Snap: Libre';
    final snapTp = TextPainter(
      text: TextSpan(text: snapLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF55595F))),
      textDirection: TextDirection.ltr,
    )..layout();
    final snapBadge = Rect.fromLTWH(size.width - snapTp.width - 24, size.height - 32, snapTp.width + 16, 24);
    c.drawRRect(RRect.fromRectAndRadius(snapBadge, const Radius.circular(4)), Paint()..color = Colors.white.withValues(alpha: 0.85));
    c.drawRRect(RRect.fromRectAndRadius(snapBadge, const Radius.circular(4)), Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = const Color(0xFFD0D5DD));
    snapTp.paint(c, snapBadge.topLeft + const Offset(8, 5));
    // Lignes de guidage magnétique actives
    if (s.activeGuidelineX != null) {
      final scrX = s._scr(s.activeGuidelineX!.dx, 0).dx;
      c.drawLine(Offset(scrX, 0), Offset(scrX, size.height), Paint()..color = const Color(0xFF00ACC1)..strokeWidth = 1.5);
    }
    if (s.activeGuidelineY != null) {
      final scrY = s._scr(0, s.activeGuidelineY!.dy).dy;
      c.drawLine(Offset(0, scrY), Offset(size.width, scrY), Paint()..color = const Color(0xFF00ACC1)..strokeWidth = 1.5);
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
    // cotes et lignes de rappel architecturales sur chaque mur
    final dimPaint = Paint()..color = const Color(0xFF5A626A)..strokeWidth = 1.0;
    final selDimPaint = Paint()..color = _orange..strokeWidth = 1.8;
    final placedBadgeCenters = <Offset>[];
    for (var i = 0; i < n; i++) {
      final aMm = pts[i], bMm = pts[(i + 1) % pts.length];
      final l = s._len(i);
      if (l < 1) continue;
      final aScr = s._scr(aMm.x, aMm.y), bScr = s._scr(bMm.x, bMm.y);
      final dir = bScr - aScr;
      final dist = dir.distance;
      if (dist < 2) continue;
      final u = dir / dist;
      // Normale vers l'extérieur du polygone
      final norm = Offset(-u.dy, u.dx) * (s._orient > 0 ? -1 : 1);
      var offDist = math.max(24.0, 150 * s._k);
      // Anti-collision entre étiquettes de cotes sur murs voisins
      for (var tries = 0; tries < 4; tries++) {
        final candMid = (aScr + bScr) / 2 + norm * offDist;
        if (placedBadgeCenters.any((bc) => (bc - candMid).distance < 44)) {
          offDist += 24.0;
        } else {
          break;
        }
      }
      final p0 = aScr + norm * offDist;
      final p1 = bScr + norm * offDist;
      final isSel = se == i;
      final pLine = isSel ? selDimPaint : dimPaint;

      // Lignes de rappel
      c.drawLine(aScr + norm * 4, p0 + norm * 5, Paint()..color = const Color(0x665A626A)..strokeWidth = 0.8);
      c.drawLine(bScr + norm * 4, p1 + norm * 5, Paint()..color = const Color(0x665A626A)..strokeWidth = 0.8);

      // Ligne de cote
      c.drawLine(p0, p1, pLine);

      // Ticks à 45°
      final tick = (u + norm) * 4.5;
      c.drawLine(p0 - tick, p0 + tick, pLine);
      c.drawLine(p1 - tick, p1 + tick, pLine);

      // Badge de la cote
      final mid = (p0 + p1) / 2;
      placedBadgeCenters.add(mid);
      final txt = '${s.closed ? '${Room.outlineId(i)} : ' : ''}${l.round()} mm${aMm.bulge.abs() >= 0.5 ? ' (arc)' : ''}';
      final tp = TextPainter(
          text: TextSpan(text: txt, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: isSel ? _orange : const Color(0xFF2C3238))),
          textDirection: TextDirection.ltr)
        ..layout();
      final r = Rect.fromCenter(center: mid, width: tp.width + 12, height: tp.height + 6);
      c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(5)), Paint()..color = Colors.white);
      c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(5)), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSel ? 1.5 : 1.0
        ..color = isSel ? _orange : const Color(0xFFCBD2D9));
      tp.paint(c, r.topLeft + const Offset(6, 3));
    }

    // Équerres et angles aux coins (quand la pièce est fermée)
    if (s.closed && pts.length >= 3) {
      for (var i = 0; i < pts.length; i++) {
        final prev = pts[(i - 1 + pts.length) % pts.length];
        final curr = pts[i];
        final next = pts[(i + 1) % pts.length];
        final pScr = s._scr(curr.x, curr.y);
        final v1 = Offset(prev.x - curr.x, prev.y - curr.y);
        final v2 = Offset(next.x - curr.x, next.y - curr.y);
        if (v1.distanceSquared == 0 || v2.distanceSquared == 0) continue;
        final u1 = v1 / v1.distance;
        final u2 = v2 / v2.distance;
        final dot = (u1.dx * u2.dx + u1.dy * u2.dy).clamp(-1.0, 1.0);
        final angRad = math.acos(dot);
        final angDeg = (angRad * 180 / math.pi).round();

        // Équerre 90° parfaite (à ±1.5°)
        if ((angDeg - 90).abs() <= 1) {
          final s1 = u1 * 14.0;
          final s2 = u2 * 14.0;
          final cornerPath = Path()
            ..moveTo(pScr.dx + s1.dx, pScr.dy + s1.dy)
            ..lineTo(pScr.dx + s1.dx + s2.dx, pScr.dy + s1.dy + s2.dy)
            ..lineTo(pScr.dx + s2.dx, pScr.dy + s2.dy);
          c.drawPath(cornerPath, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = const Color(0xFF00897B));
        }
      }
    }

    // Coins (sommets)
    for (var i = 0; i < pts.length; i++) {
      final q = s._scr(pts[i].x, pts[i].y);
      final sel = s.selVertex == i;
      c.drawCircle(q, sel ? 9 : 7, Paint()..color = sel || (s.drawing && i == 0) ? _orange : Colors.white);
      c.drawCircle(q, sel ? 9 : 7, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF3D4650));
    }

    // HUD en temps réel lors du déplacement d'un point
    if (s._dragging != null && s._dragging! < pts.length) {
      final i = s._dragging!;
      final prev = (i - 1 + pts.length) % pts.length;
      final q = s._scr(pts[i].x, pts[i].y);
      final lPrev = s._len(prev).round();
      final lCurr = s._len(i).round();
      final pPrev = pts[prev], pCurr = pts[i], pNext = pts[(i + 1) % pts.length];
      final v1 = Offset(pPrev.x - pCurr.x, pPrev.y - pCurr.y);
      final v2 = Offset(pNext.x - pCurr.x, pNext.y - pCurr.y);
      var angleStr = '';
      if (v1.distanceSquared > 0 && v2.distanceSquared > 0) {
        final dot = (v1.dx * v2.dx + v1.dy * v2.dy) / (v1.distance * v2.distance);
        final deg = (math.acos(dot.clamp(-1.0, 1.0)) * 180 / math.pi).round();
        angleStr = ' · $deg°';
      }
      final hudText = 'Mur ${Room.outlineId(prev)}: $lPrev mm · Mur ${Room.outlineId(i)}: $lCurr mm$angleStr';
      final tp = TextPainter(
        text: TextSpan(
          text: hudText,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final hudCenter = q + const Offset(0, -32);
      final hudRect = Rect.fromCenter(center: hudCenter, width: tp.width + 16, height: tp.height + 8);
      c.drawRRect(RRect.fromRectAndRadius(hudRect, const Radius.circular(6)), Paint()..color = const Color(0xEE1E2328));
      tp.paint(c, hudRect.topLeft + const Offset(8, 4));
    }
  }

  @override
  bool shouldRepaint(_ShapePainter o) => true;
}
