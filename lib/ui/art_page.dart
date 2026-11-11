// Atelier Art : le meuble se construit sur la base universelle d'un caisson en panneaux de bois.
// À gauche, les réglages par étape (Caisson, Intérieur, Façades, Extérieur, Débit) ; au centre la 3D :
// un doigt tourne, deux doigts déplacent et zooment, toucher une zone la choisit pour régler sa façade.
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/engine.dart';
import 'app_state.dart';
import 'art_camera.dart';
import 'busy.dart';
import 'cut_pdf.dart';
import 'finishes.dart';
import 'logo.dart';
import 'manual_cut_page.dart';
import 'session.dart';
import 'theme.dart';
import 'web_io.dart';
import 'i18n.dart';

Future<void> openArt(BuildContext context, AppState state) {
  Session.route = 'art';
  return Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => LeaveGuard(
      id: 'art',
      current: () => jsonEncode(state.project.art.toJson()),
      revert: (saved) => state.project.art = saved == null || saved.isEmpty ? ArtProject() : ArtProject.fromJson(jsonDecode(saved) as Map<String, dynamic>),
      child: ArtPage(state: state),
    ),
  ));
}

/// Couleur d'une finition (façades ou caissons).
Color artColor(String id) =>
    (fronts.where((f) => f.id == id).firstOrNull ?? carcasses.where((f) => f.id == id).firstOrNull)?.color ?? const Color(0xFFE9E4DC);

const _orange = Color(0xFFF26A1B);

class ArtPage extends StatefulWidget {
  final AppState state;
  const ArtPage({super.key, required this.state});
  @override
  State<ArtPage> createState() => _ArtPageState();
}

class _ArtPageState extends State<ArtPage> {
  ArtProject get art => widget.state.project.art;
  final cam = ArtCamera();
  int boxIndex = 0;
  String? zoneId;
  int column = 0;
  String tab = 'caisson';
  bool showFronts = true;
  bool showDims = true;
  bool exploded = false; // vue éclatée : chaque composant écarté de sa place
  bool byComp = false; // couleurs par composant
  Comp? focus; // composant mis en avant (les autres en transparence)
  final _undo = <String>[], _redo = <String>[];
  Offset? _last;
  Offset? _downAt;
  bool _moved = false;

  ArtBox? get box => art.boxes.isEmpty ? null : art.boxes[boxIndex.clamp(0, art.boxes.length - 1)];

  @override
  void initState() {
    super.initState();
    cam.fit(art.panels);
    final b = box;
    if (b != null) zoneId = b.zones.first.id;
  }

  // ---------------------------------------------------------------- historique
  String _snap() => jsonEncode(art.toJson());

  void _restore(String s) {
    final a = ArtProject.fromJson(jsonDecode(s) as Map<String, dynamic>);
    art.boxes
      ..clear()
      ..addAll(a.boxes);
    art.free
      ..clear()
      ..addAll(a.free);
    boxIndex = boxIndex.clamp(0, math.max(0, art.boxes.length - 1));
  }

  /// Une modification : mémorisée pour Annuler, enregistrée, redessinée.
  void change(void Function() f) {
    _undo.add(_snap());
    if (_undo.length > 100) _undo.removeAt(0);
    _redo.clear();
    f();
    final b = box;
    if (b != null && !b.zones.any((z) => z.id == zoneId)) zoneId = b.zones.first.id;
    if (b != null) column = column.clamp(0, b.columns - 1);
    Session.autosave('art', () => jsonEncode(art.toJson()));
    widget.state.refresh();
    setState(() {});
  }

  void _undoOnce() {
    if (_undo.isEmpty) return;
    _redo.add(_snap());
    _restore(_undo.removeLast());
    setState(() {});
  }

  void _redoOnce() {
    if (_redo.isEmpty) return;
    _undo.add(_snap());
    _restore(_redo.removeLast());
    setState(() {});
  }

  void _fit() => setState(() => cam.fit(art.panels));

  // ---------------------------------------------------------------- caissons
  void _addBox(ArtBox b) {
    change(() {
      art.boxes.add(b);
      boxIndex = art.boxes.length - 1;
      zoneId = b.zones.first.id;
      column = 0;
    });
    _fit();
  }

  Future<void> _chooseBase() async {
    final b = await showDialog<ArtBox>(context: context, builder: (_) => const _PresetDialog());
    if (b != null) _addBox(b);
  }

  Future<void> _importJson() async {
    final f = await pickFile(accept: '.json');
    if (f == null) return;
    try {
      final j = jsonDecode(utf8.decode(f.bytes)) as Map<String, dynamic>;
      final b = j['model'] == 'universal_parametric_box' || j.containsKey('structure_envelope') ? ArtBox.fromUniversal(j) : ArtBox.fromJson(j);
      _addBox(b);
      _msg(trp('Caisson importé : {0} colonne(s), {1} zone(s)', [b.columns, b.zones.length]));
    } catch (_) {
      _msg(tr('Fichier JSON illisible'));
    }
  }

  void _msg(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating, width: 420));

  /// Répartit [n] colonnes de même largeur.
  void _equalColumns(ArtBox b, int n) {
    final t = b.t;
    final cw = (b.w - 2 * t - (n - 1) * t) / n;
    b.seps
      ..clear()
      ..addAll([for (var k = 1; k < n; k++) (t + k * cw + (k - 1) * t).roundToDouble()]);
    b.shelves.removeWhere((c, _) => c >= n);
    b.covers.removeWhere((id, _) => (int.tryParse(id.substring(1, id.indexOf('z'))) ?? 0) >= n);
  }

  // ---------------------------------------------------------------- sélection dans la 3D
  void _tap(Offset px) {
    final xs = art.boxOrigins;
    for (var i = 0; i < art.boxes.length; i++) {
      final b = art.boxes[i];
      for (final z in b.zones) {
        final zf = -b.tFront;
        final pts = [
          V3(xs[i] + z.fx0, z.fy0, zf),
          V3(xs[i] + z.fx1, z.fy0, zf),
          V3(xs[i] + z.fx1, z.fy1, zf),
          V3(xs[i] + z.fx0, z.fy1, zf),
        ].map((v) => cam.project(v).$1).toList();
        if ((Path()..addPolygon(pts, true)).contains(px)) {
          setState(() {
            boxIndex = i;
            zoneId = z.id;
            column = z.col;
            if (tab == 'caisson' || tab == 'debit' || tab == 'exterieur') tab = 'facades';
          });
          return;
        }
      }
    }
  }

  // ---------------------------------------------------------------- débit
  Future<void> _pdf() async {
    final plan = art.plan(widget.state.project.cut);
    if (plan.parts.isEmpty) return;
    final e = LayoutEngine(widget.state.catalog, Project(name: art.name));
    downloadBytes('${art.name}_plan_de_decoupe.pdf', await runBusy(context, tr('Plan de coupe…'), () => buildCutPdf(e, plan)), mime: 'application/pdf');
  }

  void _sct() {
    final plan = art.plan(widget.state.project.cut);
    for (final m in plan.materials) {
      downloadBytes('${art.name}_${m.split(' ').take(2).join('_')}.sct', toSct(plan, m, order: art.name, thickness: m.replaceAll(RegExp(r'\D'), '')).codeUnits);
    }
  }

  void _toManual() {
    final cs = widget.state.project.cut;
    final parts = art.cutParts();
    if (parts.isEmpty) return;
    final mats = {for (final p in parts) p.material}.toList();
    final mat = mats.firstWhere((m) => m.contains('caisson'), orElse: () => mats.first);
    final job = ManualCut(order: art.name, material: mat, sheetLength: cs.sheetLength, sheetWidth: cs.sheetWidth, kerf: cs.kerf, trim: cs.trim, method: cs.method);
    for (final x in parts.where((x) => x.material == mat)) {
      job.parts.add(ManualPart(length: x.length, width: x.width, qty: x.qty, rotate: x.canRotate, edgeLong: x.edgeLong, edgeShort: x.edgeShort, desc: '${x.name} · ${x.cabinet}'));
    }
    widget.state.project.manual = job;
    openManualCut(context, widget.state);
  }

  // ---------------------------------------------------------------- écran
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final side = MediaQuery.sizeOf(context).width < 1200 ? 340.0 : 380.0;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undoOnce,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): _redoOnce,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: SafeArea(
            child: Column(children: [
              _topBar(t, scheme),
              Divider(height: 1, color: scheme.outlineVariant),
              Expanded(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SizedBox(width: side, child: _side(t, scheme)),
                  VerticalDivider(width: 1, color: scheme.outlineVariant),
                  Expanded(child: ClipRect(child: _viewport())),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _topBar(TextTheme t, ColorScheme scheme) {
    Widget view(String id, String label) => TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(44, 40), padding: const EdgeInsets.symmetric(horizontal: 10)),
          onPressed: () => setState(() {
            cam.view(id);
            cam.fit(art.panels);
          }),
          child: Text(label),
        );
    return Container(
      color: scheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: Tokens.s2, vertical: 4),
      child: Row(children: [
        IconButton(tooltip: tr('Accueil'), icon: const Icon(Icons.home_outlined), onPressed: () => Navigator.of(context).maybePop()),
        const SizedBox(width: 48, height: 40, child: LogoMark()),
        const SizedBox(width: 8),
        Text(tr('Atelier'), style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const Spacer(),
        Flexible(
          flex: 6,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: Row(children: [
              view('iso', '3D'),
              view('face', 'Face'),
              view('dessus', 'Dessus'),
              view('droite', 'Côté'),
              const SizedBox(width: 6),
              FilterChip(label: Text(tr('Façades')), selected: showFronts, onSelected: (v) => setState(() => showFronts = v)),
              const SizedBox(width: 6),
              FilterChip(label: Text(tr('Cotes')), selected: showDims, onSelected: (v) => setState(() => showDims = v)),
              const SizedBox(width: 6),
              FilterChip(label: Text(tr('Éclaté')), selected: exploded, onSelected: (v) => setState(() => exploded = v)),
              const SizedBox(width: 6),
              FilterChip(label: Text(tr('Composants')), selected: byComp, onSelected: (v) => setState(() => byComp = v)),
              IconButton(tooltip: tr('Tout voir'), onPressed: _fit, icon: const Icon(Icons.fit_screen_outlined)),
              IconButton(tooltip: tr('Annuler'), onPressed: _undo.isEmpty ? null : _undoOnce, icon: const Icon(Icons.undo)),
              IconButton(tooltip: tr('Rétablir'), onPressed: _redo.isEmpty ? null : _redoOnce, icon: const Icon(Icons.redo)),
            ]),
          ),
        ),
      ]),
    );
  }

  // ---------------------------------------------------------------- 3D
  Widget _viewport() => LayoutBuilder(builder: (context, c) {
        cam.size = c.biggest;
        return Listener(
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) setState(() => cam.zoomAt(e.scrollDelta.dy > 0 ? 1.12 : 0.89));
          },
          child: GestureDetector(
            onScaleStart: (d) {
              _last = d.localFocalPoint;
              _downAt = d.localFocalPoint;
              _moved = false;
            },
            onScaleUpdate: (d) {
              final delta = d.localFocalPoint - (_last ?? d.localFocalPoint);
              _last = d.localFocalPoint;
              if ((d.localFocalPoint - (_downAt ?? d.localFocalPoint)).distance > 6) _moved = true;
              setState(() {
                if (d.pointerCount >= 2) {
                  cam.pan(delta);
                  if (d.scale != 1) cam.zoomAt(1 / math.pow(d.scale, 0.05));
                } else {
                  cam.orbit(delta);
                }
              });
            },
            onScaleEnd: (_) {
              if (!_moved && _downAt != null) _tap(_downAt!);
            },
            child: Stack(children: [
              CustomPaint(
                key: const Key('art-viewport'),
                size: c.biggest,
                painter: _ScenePainter(
                    cam: cam,
                    art: art,
                    boxIndex: boxIndex,
                    zoneId: zoneId,
                    showFronts: showFronts,
                    showDims: showDims && !exploded,
                    exploded: exploded,
                    byComp: byComp || focus != null,
                    focus: focus),
              ),
              if (!art.isEmpty) Positioned(left: 12, top: 12, child: _legend()),
            ]),
          ),
        );
      });

  /// Les composants communs à tout meuble, avec leur nombre dans ce projet : toucher pour les mettre en avant.
  Widget _legend() {
    final t = Theme.of(context).textTheme;
    final counts = <Comp, int>{};
    for (final p in art.panels) {
      final c = p.comp;
      if (c == null) continue;
      // un tiroir = une façade (son caisson est compté avec)
      if (c == Comp.tiroir && p.role != ArtRole.tiroir) continue;
      counts[c] = (counts[c] ?? 0) + 1;
    }
    return Material(
      color: Colors.white.withValues(alpha: 0.94),
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 230),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(tr('Structure du meuble'), style: t.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            for (final c in Comp.values)
              if (counts[c] != null)
                InkWell(
                  onTap: () => setState(() => focus = focus == c ? null : c),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                    decoration: BoxDecoration(color: focus == c ? Color(c.color).withValues(alpha: 0.16) : null, borderRadius: BorderRadius.circular(6)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 12, height: 12, decoration: BoxDecoration(color: Color(c.color), borderRadius: BorderRadius.circular(3))),
                      const SizedBox(width: 8),
                      Flexible(child: Text(tr(c.label), style: t.bodySmall?.copyWith(fontWeight: focus == c ? FontWeight.w800 : FontWeight.w500))),
                      const SizedBox(width: 8),
                      Text('${counts[c]}', style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
            if (focus != null) ...[
              const SizedBox(height: 4),
              Text(focus!.hint, style: t.labelSmall),
            ],
          ]),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- panneau de réglages
  Widget _side(TextTheme t, ColorScheme scheme) {
    final b = box;
    if (b == null) return _start(t, scheme);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // caissons du meuble
      SizedBox(
        height: 52,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(Tokens.s3, 8, Tokens.s3, 4), children: [
          for (var i = 0; i < art.boxes.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text('${i + 1} · ${art.boxes[i].name}'),
                selected: i == boxIndex,
                onSelected: (_) => setState(() {
                  boxIndex = i;
                  zoneId = art.boxes[i].zones.first.id;
                  column = 0;
                }),
              ),
            ),
          ActionChip(avatar: const Icon(Icons.add, size: 18), label: Text(tr('Caisson')), onPressed: _chooseBase),
        ]),
      ),
      // étapes : 1 caisson, 2 intérieur, 3 façades, 4 extérieur, 5 débit
      Row(children: [
        for (final (id, n, label) in const [('caisson', 1, 'Caisson'), ('interieur', 2, 'Intérieur'), ('facades', 3, 'Façades'), ('exterieur', 4, 'Extérieur'), ('debit', 5, 'Débit')])
          Expanded(
            child: InkWell(
              onTap: () => setState(() => tab = id),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: tab == id ? _orange : scheme.outlineVariant, width: tab == id ? 3 : 1))),
                child: Column(children: [
                  CircleAvatar(
                    radius: 11,
                    backgroundColor: tab == id ? _orange : scheme.surfaceContainerHighest,
                    child: Text('$n', style: t.labelSmall?.copyWith(color: tab == id ? Colors.white : scheme.onSurface, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(height: 3),
                  FittedBox(child: Text(label, style: t.labelMedium?.copyWith(fontWeight: tab == id ? FontWeight.w800 : FontWeight.w500))),
                ]),
              ),
            ),
          ),
      ]),
      Expanded(
        child: switch (tab) {
          'interieur' => _interior(b, t, scheme),
          'facades' => _fronts(b, t, scheme),
          'exterieur' => _exterior(b, t, scheme),
          'debit' => _cut(t, scheme),
          _ => _carcass(b, t, scheme),
        },
      ),
    ]);
  }

  Widget _start(TextTheme t, ColorScheme scheme) => ListView(padding: const EdgeInsets.all(Tokens.s4), children: [
        Text(tr('Choisissez une base'), style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(tr('Tout meuble en bois a la même structure : côtés, bas, haut, derrière, séparations, étagères, puis portes, tiroirs, pieds et joues. '
            'On choisit une base, on la divise en colonnes et en étagères, puis on habille chaque zone.'),
            style: t.bodySmall),
        const SizedBox(height: Tokens.s3),
        for (final p in artPresets) _presetTile(p, t, () => _addBox(p.build())),
        const SizedBox(height: Tokens.s2),
        OutlinedButton.icon(onPressed: () => _addBox(ArtBox(name: 'Caisson vide', covers: {})), icon: const Icon(Icons.crop_square), label: Text(tr('Caisson vide 800 x 720'))),
        const SizedBox(height: 6),
        OutlinedButton.icon(onPressed: _importJson, icon: const Icon(Icons.file_open_outlined), label: Text(tr('Importer un caisson (JSON)'))),
        if (art.free.isNotEmpty) ...[
          const SizedBox(height: Tokens.s3),
          Text(trp('{0} panneau(x) libre(s) d’un ancien dessin.', [art.free.length]), style: t.bodySmall),
          TextButton(onPressed: () => change(art.free.clear), child: Text(tr('Les effacer'))),
        ],
      ]);

  Widget _section(TextTheme t, String title, [String? hint]) => Padding(
        padding: const EdgeInsets.only(top: Tokens.s4, bottom: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: t.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
          if (hint != null) Text(hint, style: t.bodySmall),
        ]),
      );

  Widget _num(String label, double v, void Function(double) on, {double min = 0, double max = 4000, double width = 104, String suffix = 'mm'}) => SizedBox(
        width: width,
        child: TextFormField(
          key: ValueKey('$boxIndex-$label-${v.round()}'),
          initialValue: '${v.round()}',
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: label, suffixText: suffix, isDense: true, border: const OutlineInputBorder()),
          onFieldSubmitted: (s) {
            final n = double.tryParse(s);
            if (n == null) return;
            change(() => on(n.clamp(min, max).toDouble()));
          },
        ),
      );

  Widget _finishRow(TextTheme t, String label, String value, List<Finish> list, void Function(String) on) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: t.labelMedium),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final f in list)
            Tooltip(
              message: f.name,
              child: InkWell(
                onTap: () => change(() => on(f.id)),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: f.color,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: value == f.id ? _orange : const Color(0x33000000), width: value == f.id ? 3 : 1),
                  ),
                ),
              ),
            ),
        ]),
      ]);

  // ---- 1. caisson : dimensions, épaisseurs, dessus, fond, finitions
  Widget _carcass(ArtBox b, TextTheme t, ColorScheme scheme) {
    void resizeW(double nw) {
      final k = (nw - 2 * b.t) / (b.w - 2 * b.t);
      for (var i = 0; i < b.seps.length; i++) {
        b.seps[i] = (b.t + (b.seps[i] - b.t) * k).roundToDouble();
      }
      b.w = nw;
    }

    return ListView(padding: const EdgeInsets.fromLTRB(Tokens.s3, 0, Tokens.s3, Tokens.s4), children: [
      _section(t, 'Nom'),
      TextFormField(
        key: ValueKey('name-$boxIndex'),
        initialValue: b.name,
        decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
        onFieldSubmitted: (s) => change(() => b.name = s.trim().isEmpty ? b.name : s.trim()),
      ),
      _section(t, 'Dimensions hors-tout', 'Sans pieds ni façade.'),
      Wrap(spacing: 8, runSpacing: 10, children: [
        _num('Largeur', b.w, resizeW, min: 150, max: 3000),
        _num('Hauteur', b.h, (v) {
          b.h = v;
          final n = b.pruneShelves();
          if (n > 0) WidgetsBinding.instance.addPostFrameCallback((_) => _msg(trp('{0} étagère(s) au-dessus de la nouvelle hauteur retirée(s)', [n])));
        }, min: 150, max: 2800),
        _num('Profondeur', b.d, (v) => b.d = v, min: 150, max: 900),
      ]),
      _section(t, 'Épaisseurs'),
      Wrap(spacing: 8, runSpacing: 10, children: [
        _num('Structure', b.t, (v) => b.t = v, min: 10, max: 40),
        _num('Fond', b.tBack, (v) => b.tBack = v, min: 3, max: 22),
        _num('Façade', b.tFront, (v) => b.tFront = v, min: 10, max: 40),
      ]),
      _section(t, 'Dessus', 'Traverses pour un bas de cuisine (sous plan de travail), panneau plein pour un haut ou un dressing.'),
      SegmentedButton<TopType>(
        showSelectedIcon: false,
        segments: [for (final x in TopType.values) ButtonSegment(value: x, label: Text(tr(x.label)))],
        selected: {b.top},
        onSelectionChanged: (v) => change(() => b.top = v.first),
      ),
      if (b.top == TopType.stretchers) ...[
        const SizedBox(height: 8),
        _num('Traverses', b.stretcher, (v) => b.stretcher = v, min: 50, max: 200),
      ],
      _section(t, 'Fond'),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final x in BackType.values) ChoiceChip(label: Text(tr(x.label)), selected: b.back == x, onSelected: (_) => change(() {
              b.back = x;
              if (x == BackType.screwed) b.tBack = 18;
              if (x != BackType.screwed && b.tBack == 18) b.tBack = 6;
            })),
      ]),
      if (b.back == BackType.groove) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 10, children: [
          _num('Retrait', b.backRecess, (v) => b.backRecess = v, max: 60),
          _num('Rainure', b.groove, (v) => b.groove = v, max: 15),
        ]),
      ],
      _section(t, 'Finitions'),
      _finishRow(t, 'Caisson', b.carcass, carcasses, (id) => b.carcass = id),
      const SizedBox(height: Tokens.s3),
      _finishRow(t, 'Façades', b.front, fronts.where((f) => !f.id.startsWith('tex:')).toList(), (id) => b.front = id),
      const SizedBox(height: Tokens.s4),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
            onPressed: () => change(() {
                  art.boxes.insert(boxIndex + 1, b.copy()..name = '${b.name} (copie)');
                  boxIndex++;
                }),
            icon: const Icon(Icons.copy, size: 18),
            label: Text(tr('Dupliquer'))),
        TextButton.icon(
            onPressed: () => change(() {
                  art.boxes.removeAt(boxIndex);
                  boxIndex = math.max(0, boxIndex - 1);
                  zoneId = box?.zones.first.id;
                }),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text(tr('Supprimer'))),
      ]),
    ]);
  }

  // ---- 2. intérieur : colonnes et tablettes
  Widget _interior(ArtBox b, TextTheme t, ColorScheme scheme) {
    final spans = b.columnSpans;
    final col = column.clamp(0, b.columns - 1);
    final (x0, x1) = spans[col];
    final shelves = b.shelvesOf(col);
    final innerH = b.innerTop - b.innerBottom;
    return ListView(padding: const EdgeInsets.fromLTRB(Tokens.s3, 0, Tokens.s3, Tokens.s4), children: [
      _section(t, 'Colonnes', 'Séparations verticales, du dessous au dessus.'),
      Row(children: [
        IconButton.outlined(onPressed: b.columns <= 1 ? null : () => change(() => _equalColumns(b, b.columns - 1)), icon: const Icon(Icons.remove)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('${b.columns}', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
        IconButton.outlined(onPressed: b.columns >= 8 ? null : () => change(() => _equalColumns(b, b.columns + 1)), icon: const Icon(Icons.add)),
        const SizedBox(width: 10),
        Expanded(child: Text(tr('largeurs égales'), style: t.bodySmall)),
      ]),
      if (b.seps.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 10, children: [
          for (var i = 0; i < b.seps.length; i++)
            _num('Séparation ${i + 1}', b.seps[i], (v) => b.seps[i] = v, min: b.t + 50, max: b.w - b.t - 50, width: 130),
        ]),
        Text(tr('Position de la face gauche, depuis le bord gauche du caisson.'), style: t.bodySmall),
      ],
      _section(t, 'Étagères de la colonne'),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (var c = 0; c < b.columns; c++)
          ChoiceChip(label: Text(trp('Col. {0} · {1}', [c + 1, (spans[c].$2 - spans[c].$1).round()])), selected: col == c, onSelected: (_) => setState(() => column = c)),
      ]),
      const SizedBox(height: 8),
      Text(trp('Hauteur intérieure {0} mm · largeur {1} mm. Une étagère fixe sépare deux zones de façade ; une mobile reste dans la zone (taquets).', [innerH.round(), (x1 - x0).round()]),
          style: t.bodySmall),
      const SizedBox(height: 8),
      for (final s in shelves)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            _num('Hauteur', s.y, (v) => s.y = v, min: 40, max: innerH - b.t - 40, width: 110),
            const SizedBox(width: 8),
            Expanded(
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                style: ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [ButtonSegment(value: true, label: Text(tr('Fixe'))), ButtonSegment(value: false, label: Text(tr('Mobile')))],
                selected: {s.fixed},
                onSelectionChanged: (v) => change(() => s.fixed = v.first),
              ),
            ),
            IconButton(tooltip: tr('Retirer'), onPressed: () => change(() => b.shelves[col]?.remove(s)), icon: const Icon(Icons.close)),
          ]),
        ),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
          onPressed: () => change(() {
            // au milieu du plus grand vide
            final ys = [0.0, for (final s in shelves) ...[s.y, s.y + b.t], innerH];
            var best = 0.0, at = innerH / 2;
            for (var i = 0; i + 1 < ys.length; i += 2) {
              if (ys[i + 1] - ys[i] > best) {
                best = ys[i + 1] - ys[i];
                at = (ys[i] + ys[i + 1] - b.t) / 2;
              }
            }
            (b.shelves[col] ??= []).add(ArtShelf(at.roundToDouble()));
          }),
          icon: const Icon(Icons.add),
          label: Text(tr('Étagère')),
        ),
        for (final n in const [2, 3, 4])
          TextButton(
            onPressed: () => change(() {
              final fixed = shelves.where((s) => s.fixed).toList();
              final step = (innerH - n * b.t) / (n + 1);
              b.shelves[col] = [...fixed, for (var k = 1; k <= n; k++) ArtShelf((k * step + (k - 1) * b.t).roundToDouble())];
            }),
            child: Text(trp('{0} mobiles réparties', [n])),
          ),
        TextButton(onPressed: () => change(() => b.shelves[col] = []), child: Text(tr('Vider'))),
        if (b.columns > 1)
          TextButton(
            onPressed: () => change(() {
              for (var c = 0; c < b.columns; c++) {
                b.shelves[c] = [for (final s in shelves) ArtShelf(s.y, fixed: s.fixed)];
              }
            }),
            child: Text(tr('Copier sur toutes les colonnes')),
          ),
      ]),
    ]);
  }

  // ---- 3. façades par zone
  Widget _fronts(ArtBox b, TextTheme t, ColorScheme scheme) {
    final zones = b.zones;
    final z = zones.where((x) => x.id == zoneId).firstOrNull ?? zones.first;
    final cv = b.covers[z.id];
    final type = cv?.type ?? CoverType.open;
    final fw = z.fx1 - z.fx0, fh = z.fy1 - z.fy0;
    ArtCover cover() => b.covers.putIfAbsent(z.id, () => ArtCover(type: CoverType.open));
    String zoneName(ArtZone x) {
      final rows = zones.where((y) => y.col == x.col).length;
      final pos = rows == 1 ? '' : (x.row == 0 ? ' · bas' : (x.row == rows - 1 ? ' · haut' : ' · milieu ${x.row}'));
      return b.columns == 1 ? 'Zone ${x.row + 1}$pos' : 'Col. ${x.col + 1}$pos';
    }

    return ListView(padding: EdgeInsets.fromLTRB(Tokens.s3, 0, Tokens.s3, Tokens.s4), children: [
      _section(t, 'Zone', 'Touchez une zone dans la 3D, ou choisissez-la ici.'),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final x in zones) ChoiceChip(label: Text(zoneName(x)), selected: x.id == z.id, onSelected: (_) => setState(() => zoneId = x.id)),
      ]),
      SizedBox(height: 6),
      Text(trp('Façade {0} x {1} mm · intérieur {2} x {3} mm', [fw.round(), fh.round(), z.width.round(), z.height.round()]), style: t.bodySmall),
      _section(t, 'Habillage'),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final x in CoverType.values)
          ChoiceChip(
            label: Text(tr(x.label)),
            selected: type == x,
            onSelected: (_) => change(() {
              cover().type = x;
              if (x == CoverType.door && fw > 600) cover().hinge = 'double';
            }),
          ),
      ]),
      if (type == CoverType.door) ...[
        _section(t, 'Ouverture'),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: 'left', label: Text(tr('Gauche'))),
            ButtonSegment(value: 'right', label: Text(tr('Droite'))),
            ButtonSegment(value: 'double', label: Text(tr('Deux portes'))),
          ],
          selected: {cv!.hinge},
          onSelectionChanged: (v) => change(() => cv.hinge = v.first),
        ),
        const SizedBox(height: 6),
        Text(trp('{0} charnière(s) par porte pour {1} mm de haut.', [ArtBox.hingesFor(fh), fh.round()]), style: t.bodySmall),
      ],
      if (type == CoverType.drawers) ...[
        _section(t, 'Nombre de tiroirs'),
        Row(children: [
          IconButton.outlined(onPressed: cv!.count <= 1 ? null : () => change(() => cv.count--), icon: const Icon(Icons.remove)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('${cv.count}', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
          IconButton.outlined(onPressed: cv.count >= 8 ? null : () => change(() => cv.count++), icon: const Icon(Icons.add)),
          SizedBox(width: 10),
          Expanded(child: Text(trp('façades de {0} mm', [((fh - b.gap * (cv.count - 1)) / cv.count).round()]), style: t.bodySmall)),
        ]),
        _section(t, 'Caisson de tiroir'),
        SegmentedButton<DrawerBox>(
          showSelectedIcon: false,
          segments: [ButtonSegment(value: DrawerBox.metal, label: Text(tr('Double paroi métal'))), ButtonSegment(value: DrawerBox.wood, label: Text(tr('Bois')))],
          selected: {b.drawerBox},
          onSelectionChanged: (v) => change(() => b.drawerBox = v.first),
        ),
        const SizedBox(height: 6),
        Text(trp('Coulisses {0} mm (profondeur utile {1} mm).', [b.slideLength, b.innerDepth.round()]), style: t.bodySmall),
      ],
      _section(t, 'Accessoires de la zone'),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final e in accessoryNames.entries)
          FilterChip(
            label: Text(e.value),
            selected: cv?.accessories.contains(e.key) ?? false,
            onSelected: (on) => change(() => on ? cover().accessories.add(e.key) : cover().accessories.remove(e.key)),
          ),
      ]),
      _section(t, 'Pour toutes les façades'),
      Text(tr('Ouverture'), style: t.labelMedium),
      const SizedBox(height: 4),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final (id, label) in const [('bar', 'Poignée barre'), ('knob', 'Bouton'), ('gola', 'Profil Gola'), ('push', 'Pousser-lâcher')])
          ChoiceChip(label: Text(label), selected: b.handle == id, onSelected: (_) => change(() => b.handle = id)),
      ]),
      const SizedBox(height: 10),
      _num('Jeu autour', b.gap, (v) => b.gap = v, min: 1, max: 6),
    ]);
  }

  // ---- 4. extérieur : base, joues, fileurs, corniche
  Widget _exterior(ArtBox b, TextTheme t, ColorScheme scheme) => ListView(padding: const EdgeInsets.fromLTRB(Tokens.s3, 0, Tokens.s3, Tokens.s4), children: [
        _section(t, 'Base'),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final x in BaseType.values)
            ChoiceChip(
              label: Text(tr(x.label)),
              selected: b.base == x,
              onSelected: (_) => change(() {
                b.base = x;
                if (x == BaseType.wall && b.baseH < 300) b.baseH = 1450;
                if (x != BaseType.wall && b.baseH > 300) b.baseH = 100;
              }),
            ),
        ]),
        if (b.base != BaseType.none) ...[
          const SizedBox(height: 10),
          _num(b.base == BaseType.wall ? 'Bas du meuble depuis le sol' : 'Hauteur', b.baseH, (v) => b.baseH = v, max: 2400, width: 220),
        ],
        _section(t, 'Joues de finition', 'Panneau de façade qui cache le côté du caisson et affleure la porte.'),
        Wrap(spacing: 6, children: [
          FilterChip(label: Text(tr('Gauche')), selected: b.cheekLeft, onSelected: (v) => change(() => b.cheekLeft = v)),
          FilterChip(label: Text(tr('Droite')), selected: b.cheekRight, onSelected: (v) => change(() => b.cheekRight = v)),
        ]),
        _section(t, 'Fileurs', 'Bandes d’ajustement contre un mur.'),
        Wrap(spacing: 8, runSpacing: 10, children: [
          _num('Gauche', b.fillerLeft, (v) => b.fillerLeft = v, max: 200),
          _num('Droite', b.fillerRight, (v) => b.fillerRight = v, max: 200),
        ]),
        _section(t, 'Corniche et cache-lumière'),
        Wrap(spacing: 6, children: [
          FilterChip(label: Text(tr('Corniche en haut')), selected: b.cornice, onSelected: (v) => change(() => b.cornice = v)),
          FilterChip(label: Text(tr('Cache-lumière en bas')), selected: b.valance, onSelected: (v) => change(() => b.valance = v)),
        ]),
      ]);

  // ---- 5. débit et quincaillerie (tout le meuble)
  Widget _cut(TextTheme t, ColorScheme scheme) {
    final parts = art.cutParts();
    final plan = nestCached(parts, widget.state.project.cut);
    final sp = widget.state.project.specs;
    final edge = parts.fold<double>(0, (a, p) => a + p.edgeLength * p.qty) / 1000;
    final mdf = plan.sheets.where((s) => !s.material.startsWith('HDF')).length;
    final cost = mdf * (sp.sheetPrice ?? 850) + plan.sheets.length * sp.cuttingPerSheet + edge * (sp.edgePriceMin ?? 9);
    final warn = [for (final b in art.boxes) ...b.warnings()];
    final byMat = <String, List<CutPart>>{};
    for (final p in parts) {
      (byMat[p.material] ??= []).add(p);
    }
    return ListView(padding: const EdgeInsets.fromLTRB(Tokens.s3, Tokens.s3, Tokens.s3, Tokens.s4), children: [
      Text(trp('{0} caisson(s) · {1} pièces · {2} feuille(s)', [art.boxes.length, parts.fold<int>(0, (a, p) => a + p.qty), plan.sheets.length]), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
      Text(trp('Chant {0} m · panneaux + chant + découpe ≈ {1} MAD', [edge.toStringAsFixed(1), cost.round()]), style: t.bodySmall),
      for (final w in warn)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.warning_amber_rounded, size: 18, color: scheme.error),
            const SizedBox(width: 6),
            Expanded(child: Text(w, style: t.bodySmall)),
          ]),
        ),
      const SizedBox(height: Tokens.s3),
      FilledButton.icon(onPressed: parts.isEmpty ? null : _pdf, icon: const Icon(Icons.picture_as_pdf_outlined), label: Text(tr('Plan de coupe (PDF)'))),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(child: OutlinedButton.icon(onPressed: parts.isEmpty ? null : _sct, icon: const Icon(Icons.content_cut), label: Text(tr('.sct')))),
        const SizedBox(width: 6),
        Expanded(child: OutlinedButton.icon(onPressed: parts.isEmpty ? null : _toManual, icon: const Icon(Icons.edit_note), label: Text(tr('Débit manuel')))),
      ]),
      for (final e in byMat.entries) ...[
        _section(t, e.key),
        for (final p in e.value)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(children: [
              SizedBox(width: 34, child: Text(trp('{0} ×', [p.qty]), style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700))),
              Expanded(child: Text(tr(p.name), style: t.bodySmall)),
              Text(trp('{0} x {1}', [p.length, p.width]), style: t.bodySmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ),
      ],
      _section(t, 'Quincaillerie et visserie'),
      for (final (name, usage, q) in art.hardware())
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 40, child: Text(trp('{0} ×', [q]), style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700))),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: t.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                Text(usage, style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
              ]),
            ),
          ]),
        ),
    ]);
  }

  Widget _presetTile(ArtPreset p, TextTheme t, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: Tokens.s2),
        child: Card(
          margin: EdgeInsets.zero,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(Tokens.s2),
              child: Row(children: [
                SizedBox(width: 76, height: 64, child: CustomPaint(painter: _PresetPainter(p))),
                const SizedBox(width: Tokens.s2),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr(p.name), style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Text(tr(p.description), style: t.labelSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      );
}

/// Choix de la base d'un nouveau caisson.
class _PresetDialog extends StatelessWidget {
  const _PresetDialog();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text(tr('Nouveau caisson')),
      content: SizedBox(
        width: 520,
        height: 460,
        child: GridView.extent(
          maxCrossAxisExtent: 250,
          childAspectRatio: 1.25,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            for (final p in artPresets)
              Card(
                margin: EdgeInsets.zero,
                child: InkWell(
                  onTap: () => Navigator.of(context).pop(p.build()),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(children: [
                      Expanded(child: CustomPaint(painter: _PresetPainter(p), size: Size.infinite)),
                      Text(tr(p.name), style: t.labelLarge?.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('Annuler')))],
    );
  }
}

// ------------------------------------------------------------------ rendu 3D

void _paintPanels(Canvas c, ArtCamera cam, List<ArtPanel> panels, {double edge = 1, bool byComp = false, Comp? focus}) {
  final faces = <(double, Face)>[];
  for (final panel in panels) {
    for (final f in facesOf(panel)) {
      final toCam = cam.ortho ? cam.forward * -1 : (cam.eye - f.center);
      if (f.normal.dot(toCam) <= 0) continue;
      faces.add((cam.project(f.center).$2, f));
    }
  }
  faces.sort((a, b) => b.$1.compareTo(a.$1));
  final light = const V3(-0.35, 0.85, -0.4).unit;
  for (final (_, f) in faces) {
    final cs = f.corners.map((v) => cam.project(v).$1).toList();
    final path = Path()..addPolygon(cs, true);
    final comp = f.panel.comp;
    final base = byComp && comp != null ? Color(comp.color) : artColor(f.panel.finish);
    final hsl = HSLColor.fromColor(base);
    final lum = 0.62 + 0.38 * math.max(0.0, f.normal.dot(light));
    final ghost = focus != null && comp != focus;
    final fill = hsl.withLightness((hsl.lightness * lum + 0.04).clamp(0.0, 1.0)).toColor();
    c.drawPath(path, Paint()..color = ghost ? fill.withValues(alpha: 0.12) : fill);
    c.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = edge
      ..color = ghost ? const Color(0x221F1A17) : const Color(0xCC1F1A17));
  }
}

class _ScenePainter extends CustomPainter {
  final ArtCamera cam;
  final ArtProject art;
  final int boxIndex;
  final String? zoneId;
  final bool showFronts, showDims, exploded, byComp;
  final Comp? focus;
  _ScenePainter({
    required this.cam,
    required this.art,
    required this.boxIndex,
    required this.zoneId,
    required this.showFronts,
    required this.showDims,
    this.exploded = false,
    this.byComp = false,
    this.focus,
  });

  /// Vue éclatée : chaque composant s'écarte du centre de son caisson dans sa direction naturelle.
  List<ArtPanel> _explode(List<ArtPanel> ps) {
    final xs = art.boxOrigins;
    final out = <ArtPanel>[];
    for (final p in ps) {
      final c = p.comp;
      final i = p.id.startsWith('b') ? int.tryParse(p.id.substring(1, p.id.indexOf('_'))) : null;
      if (c == null || i == null || i >= art.boxes.length) {
        out.add(p);
        continue;
      }
      final cx = xs[i] + art.boxes[i].w / 2;
      final side = (p.x + p.w / 2) < cx ? -1.0 : 1.0;
      final q = p.copy();
      switch (c) {
        case Comp.cote:
          q.x += side * 260;
        case Comp.joue:
          q.x += side * 480;
        case Comp.fileur:
          q.x += side * 620;
        case Comp.dessus || Comp.traverse:
          q.y += 260;
        case Comp.corniche:
          q.y += 420;
        case Comp.dessous:
          q.y -= 120;
        case Comp.pied:
          q.y -= 300;
        case Comp.fond:
          q.z += 420;
        case Comp.etagere:
          q.z -= 160;
        case Comp.porte || Comp.abattant || Comp.tiroir:
          q.z -= 520;
        case Comp.separation:
          break;
      }
      out.add(q);
    }
    return out;
  }

  Offset p(V3 v) => cam.project(v).$1;

  @override
  void paint(Canvas c, Size size) {
    c.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFEDEFF1), Color(0xFFF8F5F1)])
              .createShader(Offset.zero & size));
    // sol : grille de 50 cm
    final g = Paint()
      ..color = const Color(0x18000000)
      ..strokeWidth = 1;
    const ext = 4000.0;
    for (var v = -ext; v <= ext; v += 500) {
      c.drawLine(p(V3(v, 0, -ext)), p(V3(v, 0, ext)), g);
      c.drawLine(p(V3(-ext, 0, v)), p(V3(ext, 0, v)), g);
    }
    if (art.isEmpty) {
      final tp = TextPainter(
          text: const TextSpan(text: 'Choisissez une base à gauche', style: TextStyle(fontSize: 16, color: Color(0xFF6B7178), fontWeight: FontWeight.w600)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(c, size.center(Offset(-tp.width / 2, -tp.height / 2)));
      return;
    }
    var panels = art.panels.where((x) => showFronts || exploded || !(x.comp?.isFront ?? x.role.isFront)).toList();
    if (exploded) panels = _explode(panels);
    _paintPanels(c, cam, panels, byComp: byComp, focus: focus);
    // poignées
    if (showFronts && !exploded && focus == null) {
      for (var i = 0; i < art.boxes.length; i++) {
        final b = art.boxes[i];
        if (b.handle == 'push') continue;
        for (final pn in panels.where((x) => x.id.startsWith('b${i}_') && x.role.isFront)) {
          final z = pn.z - 1;
          if (b.handle == 'gola') {
            c.drawLine(p(V3(pn.x, pn.top - 4, z)), p(V3(pn.right, pn.top - 4, z)), Paint()
              ..color = const Color(0xFF3C4148)
              ..strokeWidth = 2.5);
            continue;
          }
          final door = pn.role == ArtRole.porte;
          final hx = door ? (pn.hinge == 'left' ? pn.right - 40 : pn.x + 40) : pn.x + pn.w / 2;
          final cy = door ? pn.y + pn.h / 2 : pn.top - math.min(60, pn.h / 2);
          if (b.handle == 'knob') {
            c.drawCircle(p(V3(hx, cy, z)), 3.5, Paint()..color = const Color(0xFF6B7178));
          } else {
            final a = door ? V3(hx, cy - 80, z) : V3(hx - 80, cy, z);
            final e = door ? V3(hx, cy + 80, z) : V3(hx + 80, cy, z);
            c.drawLine(p(a), p(e), Paint()
              ..color = const Color(0xFF6B7178)
              ..strokeWidth = 3
              ..strokeCap = StrokeCap.round);
          }
        }
      }
    }
    // tringles
    final xs = art.boxOrigins;
    for (var i = 0; i < art.boxes.length; i++) {
      final b = art.boxes[i];
      for (final z in b.zones) {
        final cv = b.coverOf(z);
        if (!cv.accessories.contains('rod') || (showFronts && cv.type != CoverType.open)) continue;
        final y = z.y1 - 60, dz = b.innerDepth / 2;
        c.drawLine(p(V3(xs[i] + z.x0, y, dz)), p(V3(xs[i] + z.x1, y, dz)), Paint()
          ..color = const Color(0xFF8A9096)
          ..strokeWidth = 3);
      }
    }
    // zone choisie
    if (!exploded && focus == null && boxIndex < art.boxes.length && zoneId != null) {
      final b = art.boxes[boxIndex];
      final z = b.zones.where((x) => x.id == zoneId).firstOrNull;
      if (z != null) {
        final ox = xs[boxIndex], zf = -b.tFront - 2;
        final pts = [V3(ox + z.fx0, z.fy0, zf), V3(ox + z.fx1, z.fy0, zf), V3(ox + z.fx1, z.fy1, zf), V3(ox + z.fx0, z.fy1, zf)].map(p).toList();
        final path = Path()..addPolygon(pts, true);
        c.drawPath(path, Paint()..color = _orange.withValues(alpha: 0.14));
        c.drawPath(path, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = _orange);
      }
    }
    // cotes du caisson choisi
    if (showDims && boxIndex < art.boxes.length) {
      final b = art.boxes[boxIndex];
      final ox = xs[boxIndex];
      const col = Color(0xFF1D4ED8);
      _dim(c, V3(ox, b.y0, -b.tFront - 60), V3(ox + b.w, b.y0, -b.tFront - 60), '${b.w.round()}', col);
      _dim(c, V3(ox - 60, b.y0, -b.tFront), V3(ox - 60, b.y0 + b.h, -b.tFront), '${b.h.round()}', col);
      _dim(c, V3(ox + b.w + 60, b.y0, 0), V3(ox + b.w + 60, b.y0, b.d), '${b.d.round()}', col);
      if (b.y0 > 0) _dim(c, V3(ox + b.w + 60, 0, -b.tFront), V3(ox + b.w + 60, b.y0, -b.tFront), '${b.y0.round()}', const Color(0xFF6B7178));
    }
  }

  void _dim(Canvas c, V3 a, V3 b, String text, Color col) {
    final pa = p(a), pb = p(b);
    final paint = Paint()
      ..color = col
      ..strokeWidth = 1.4;
    c.drawLine(pa, pb, paint);
    final dir = pb - pa;
    final n = dir.distance == 0 ? Offset.zero : Offset(-dir.dy, dir.dx) / dir.distance * 5;
    c.drawLine(pa - n, pa + n, paint);
    c.drawLine(pb - n, pb + n, paint);
    final tp = TextPainter(text: TextSpan(text: text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: col)), textDirection: TextDirection.ltr)
      ..layout();
    final at = Offset.lerp(pa, pb, 0.5)! - Offset(tp.width / 2, tp.height / 2);
    c.drawRRect(RRect.fromRectAndRadius((at & tp.size).inflate(3), const Radius.circular(4)), Paint()..color = Colors.white.withValues(alpha: 0.92));
    tp.paint(c, at);
  }

  @override
  bool shouldRepaint(_ScenePainter o) => true;
}

class _PresetPainter extends CustomPainter {
  final ArtPreset preset;
  _PresetPainter(this.preset);
  @override
  void paint(Canvas c, Size size) {
    final b = preset.build();
    var k = 0;
    final panels = b.panels(() => 'p${k++}');
    final cam = ArtCamera()..size = size;
    cam.fit(panels);
    _paintPanels(c, cam, panels, edge: 0.5);
  }

  @override
  bool shouldRepaint(_PresetPainter o) => o.preset != preset;
}
