// Concepteur des autres univers (dressing, salle de bain / WC, meuble TV, intérieur) : catalogue de
// modules à gauche, mur en vue de face au centre, fiche du module à droite ; débit, quincaillerie et
// estimation en bas ; plan de coupe PDF, fichier .sct ou envoi vers le débit manuel.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/engine.dart';
import 'app_state.dart';
import 'sct_export.dart';
import 'busy.dart';
import 'cut_pdf.dart';
import 'logo.dart';
import 'manual_cut_page.dart';
import 'kx_choices.dart';
import 'theme.dart';
import 'web_io.dart';
import 'i18n.dart';

final _catalogs = <String, FurnitureUniverse>{};

Future<FurnitureUniverse> loadUniverse(String id) async =>
    _catalogs[id] ??= FurnitureUniverse.parse(id, await rootBundle.loadString('assets/data/furniture/$id.json'));

Future<void> openFurniture(BuildContext context, AppState state, String universe) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => FurniturePage(state: state, universe: universe)));

class FurniturePage extends StatefulWidget {
  final AppState state;
  final String universe;
  const FurniturePage({super.key, required this.state, required this.universe});
  @override
  State<FurniturePage> createState() => _FurniturePageState();
}

class _FurniturePageState extends State<FurniturePage> {
  FurnitureUniverse? cat;
  String? selected;
  int _uid = 0;
  String _category = '';

  FurnitureProject get proj => widget.state.project.furniture.putIfAbsent(widget.universe, () => FurnitureProject(universe: widget.universe));

  @override
  void initState() {
    super.initState();
    loadUniverse(widget.universe).then((c) {
      if (mounted) setState(() => cat = c);
    });
  }

  void _changed() {
    setState(() {});
    widget.state.refresh();
  }

  FurnitureItem? get sel => proj.items.where((i) => i.uid == selected).firstOrNull;

  void _add(FurnitureModel m) {
    final it = FurnitureItem(
      uid: 'f${DateTime.now().microsecondsSinceEpoch}${_uid++}',
      modelId: m.id,
      width: m.widths.first,
      height: m.heights.contains(2400) ? 2400 : m.heights.first,
      depth: m.depths.first,
      setup: m.setup.copy(),
    );
    if (m.setup.shape == 'L' || m.setup.shape == 'diagonal') it.setup.returnWidth = it.width;
    proj.items.add(it);
    selected = it.uid;
    _changed();
  }

  // ------------------------------------------------------------------ export
  CutSettings get _cs => widget.state.project.cut;

  Future<void> _pdf() async {
    final plan = furniturePlan(proj, _cs);
    if (plan.parts.isEmpty) return;
    final e = LayoutEngine(widget.state.catalog, Project(name: proj.name));
    final bytes = await runBusy(context, tr('Plan de coupe…'), () => buildCutPdf(e, plan));
    downloadBytes('${proj.name}_plan_de_decoupe.pdf', bytes, mime: 'application/pdf');
  }

  Future<void> _sct() async {
    final msg = await exportSctFiles(context, furniturePlan(proj, _cs), name: proj.name);
    if (msg != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _toManual() {
    final plan = furniturePlan(proj, _cs);
    if (plan.parts.isEmpty) return;
    openManualCut(context, widget.state, project: () => plan, name: proj.name);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final c = cat;
    return Scaffold(
      resizeToAvoidBottomInset: false, // le clavier passe par-dessus la scène
      appBar: AppBar(
        leading: IconButton(tooltip: tr('Accueil'), icon: const Icon(Icons.home_outlined), onPressed: () => Navigator.of(context).maybePop()),
        titleSpacing: 0,
        title: Text(tr(FurnitureUniverse.names[widget.universe] ?? widget.universe), style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        flexibleSpace: const SafeArea(child: Center(child: SizedBox(width: 64, height: 46, child: LogoMark()))),
        actions: [
          OutlinedButton.icon(onPressed: proj.items.isEmpty ? null : _toManual, icon: const Icon(Icons.edit_note), label: Text(tr('Débit manuel'))),
          const SizedBox(width: Tokens.s2),
          OutlinedButton.icon(onPressed: proj.items.isEmpty ? null : _sct, icon: const Icon(Icons.content_cut), label: Text(tr('.sct'))),
          const SizedBox(width: Tokens.s2),
          FilledButton.icon(onPressed: proj.items.isEmpty ? null : _pdf, icon: const Icon(Icons.picture_as_pdf_outlined), label: Text(tr('Plan de coupe'))),
          const SizedBox(width: Tokens.s4),
        ],
      ),
      body: c == null
          ? const Center(child: CircularProgressIndicator())
          : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(width: 300, child: _catalogPanel(c, t, scheme)),
              VerticalDivider(width: 1, color: scheme.outlineVariant),
              Expanded(
                child: Column(children: [
                  _wallBar(t),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(Tokens.s4),
                      child: LayoutBuilder(
                        builder: (context, box) => GestureDetector(
                          onTapUp: (d) {
                            final hit = _FrontPainter.hit(proj, box.biggest, d.localPosition);
                            setState(() => selected = hit?.uid);
                          },
                          child: CustomPaint(size: box.biggest, painter: _FrontPainter(proj, c, selected, scheme, context.pc)),
                        ),
                      ),
                    ),
                  ),
                  _summary(t, scheme),
                ]),
              ),
              if (sel != null) ...[
                VerticalDivider(width: 1, color: scheme.outlineVariant),
                SizedBox(width: 340, child: _inspector(c, sel!, t, scheme)),
              ],
            ]),
    );
  }

  // ------------------------------------------------------------------ catalogue
  Widget _catalogPanel(FurnitureUniverse c, TextTheme t, ColorScheme scheme) {
    final cats = ['', ...{for (final m in c.models) m.category}.where((x) => x.isNotEmpty)];
    final shown = c.models.where((m) => _category.isEmpty || m.category == _category).toList();
    return ListView(padding: const EdgeInsets.all(Tokens.s3), children: [
      Text(tr('Modules'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: Tokens.s1),
      Text(tr('Touchez un module pour l’ajouter à droite des autres.'), style: t.bodySmall),
      if (cats.length > 2) ...[
        const SizedBox(height: Tokens.s2),
        Wrap(spacing: 4, runSpacing: 4, children: [
          for (final k in cats)
            ChoiceChip(
              label: Text(k.isEmpty ? tr('Tout') : k.split(RegExp(r'[,&(]')).first.trim(), overflow: TextOverflow.ellipsis),
              selected: _category == k,
              onSelected: (_) => setState(() => _category = k),
            ),
        ]),
      ],
      const SizedBox(height: Tokens.s2),
      for (final m in shown)
        Padding(
          padding: const EdgeInsets.only(bottom: Tokens.s2),
          child: Card(
            margin: EdgeInsets.zero,
            child: InkWell(
              onTap: () => _add(m),
              child: Padding(
                padding: const EdgeInsets.all(Tokens.s3),
                child: Row(children: [
                  SizedBox(width: 54, height: 64, child: CustomPaint(painter: _ThumbPainter(m, scheme))),
                  const SizedBox(width: Tokens.s3),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr(m.name), style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700), maxLines: 3, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(trp('L {0} · H {1} · P {2}', [_range(m.widths), _range(m.heights), _range(m.depths)]), style: t.labelSmall),
                    ]),
                  ),
                  Icon(Icons.add_circle_outline, color: scheme.primary),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }

  static String _range(List<int> v) => v.length == 1 ? '${v.first}' : '${v.reduce(math.min)}–${v.reduce(math.max)}';

  // ------------------------------------------------------------------ mur
  Widget _wallBar(TextTheme t) {
    Widget num(String label, int v, void Function(int) on) => SizedBox(
          width: 140,
          child: TextFormField(
            key: ValueKey('$label-${widget.universe}'),
            initialValue: '$v',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: label, suffixText: 'mm', isDense: true, border: const OutlineInputBorder()),
            onChanged: (s) {
              final n = int.tryParse(s);
              if (n != null && n >= 300) {
                on(n);
                _changed();
              }
            },
          ),
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(Tokens.s4, Tokens.s3, Tokens.s4, 0),
      child: Wrap(spacing: Tokens.s3, runSpacing: Tokens.s2, crossAxisAlignment: WrapCrossAlignment.center, children: [
        num('Largeur du mur', proj.wallWidth, (v) => proj.wallWidth = v),
        num('Hauteur sous plafond', proj.wallHeight, (v) => proj.wallHeight = v),
        if (widget.universe == 'dressing')
          KxChoices<String>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 'battantes', label: Text(tr('Portes battantes'))),
              ButtonSegment(value: 'coulissantes', label: Text(tr('Coulissantes'))),
            ],
            selected: {proj.doorSystem},
            onSelectionChanged: (v) {
              proj.doorSystem = v.first;
              if (v.first == 'coulissantes') {
                for (final i in proj.items) {
                  if (i.depth < 660) i.depth = 660;
                }
              }
              _changed();
            },
          ),
        Text(trp('{0} / {1} mm occupés', [proj.usedWidth, proj.wallWidth]), style: t.bodySmall),
      ]),
    );
  }

  // ------------------------------------------------------------------ fiche du module
  Widget _inspector(FurnitureUniverse c, FurnitureItem it, TextTheme t, ColorScheme scheme) {
    final m = c.model(it.modelId);
    final s = it.setup;
    final idx = proj.items.indexOf(it);
    Widget chips(String label, List<int> values, int current, void Function(int) on) => Padding(
          padding: const EdgeInsets.only(bottom: Tokens.s3),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: t.labelLarge),
            const SizedBox(height: 4),
            Wrap(spacing: 4, runSpacing: 4, children: [
              for (final v in {...values, current}.toList()..sort())
                ChoiceChip(
                  label: Text('$v'),
                  selected: v == current,
                  onSelected: (_) {
                    on(v);
                    _changed();
                  },
                ),
              ActionChip(
                avatar: const Icon(Icons.edit, size: 16),
                label: Text(tr('Autre')),
                onPressed: () async {
                  final ctrl = TextEditingController(text: '$current');
                  final v = await showDialog<int>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(label),
                      content: TextField(
                          controller: ctrl,
                          autofocus: true,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(suffixText: 'mm')),
                      actions: [FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text)), child: Text(tr('OK')))],
                    ),
                  );
                  if (v != null && v >= 36) {
                    on(v);
                    _changed();
                  }
                },
              ),
            ]),
          ]),
        );
    Widget counter(String label, int v, void Function(int) on, {int max = 12}) => Row(children: [
          Expanded(child: Text(label, style: t.bodyMedium)),
          IconButton(
              onPressed: v > 0
                  ? () {
                      on(v - 1);
                      _changed();
                    }
                  : null,
              icon: const Icon(Icons.remove_circle_outline)),
          SizedBox(width: 24, child: Text('$v', textAlign: TextAlign.center, style: t.titleSmall)),
          IconButton(
              onPressed: v < max
                  ? () {
                      on(v + 1);
                      _changed();
                    }
                  : null,
              icon: const Icon(Icons.add_circle_outline)),
        ]);
    return ListView(padding: const EdgeInsets.all(Tokens.s4), children: [
      Row(children: [
        Expanded(child: Text(trp('Module {0}', [idx + 1]), style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
        IconButton(tooltip: tr('Fermer'), onPressed: () => setState(() => selected = null), icon: const Icon(Icons.close)),
      ]),
      Text(tr(m?.name ?? it.modelId), style: t.bodySmall),
      const SizedBox(height: Tokens.s3),
      if (m != null && m.variants.isNotEmpty && m.variants.first.contains('/'))
        chips('Format d’angle (mur 1)', m.widths, it.width, (v) {
          it.width = v;
          it.setup.returnWidth = v;
        })
      else
        chips('Largeur (mm)', m?.widths ?? const [], it.width, (v) => it.width = v),
      chips('Hauteur (mm)', m?.heights ?? const [], it.height, (v) => it.height = v),
      chips('Profondeur (mm)', m?.depths ?? const [], it.depth, (v) => it.depth = v),
      if (!s.panel) ...[
        Text(tr('Composition'), style: t.labelLarge),
        if (s.shape == 'box' || s.shape == 'desk') ...[
          counter('Portes', s.doors, (v) => s.doors = v, max: 6),
          counter('Tiroirs', s.drawers, (v) => s.drawers = v, max: 8),
        ],
        if (s.shape == 'box') counter('Abattants', s.flaps, (v) => s.flaps = v, max: 6),
        counter('Étagères', s.shelves, (v) => s.shelves = v, max: 12),
        counter('Barres de penderie', s.rods, (v) => s.rods = v, max: 2),
        if (s.drawers > 0) chips('Hauteur d’une façade de tiroir', const [160, 200, 240, 300], s.drawerFront, (v) => s.drawerFront = v),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('Suspendu')),
          value: s.wallHung,
          onChanged: (v) {
            s.wallHung = v;
            if (v && s.z == 0) s.z = 300;
            _changed();
          },
        ),
        if (s.wallHung) chips('Hauteur du bas (mm)', const [200, 300, 450, 700, 1200, 1500], s.z, (v) => s.z = v),
        if (s.doors > 0)
          Wrap(spacing: 6, children: [
            FilterChip(label: Text(tr('Vitrées')), selected: s.glass, onSelected: (v) => setState(() => s.glass = v)),
            FilterChip(label: Text(tr('Miroir')), selected: s.mirror, onSelected: (v) => setState(() => s.mirror = v)),
          ]),
      ],
      const SizedBox(height: Tokens.s4),
      Wrap(spacing: Tokens.s2, runSpacing: Tokens.s2, children: [
        OutlinedButton.icon(
          onPressed: idx > 0
              ? () {
                  proj.items.removeAt(idx);
                  proj.items.insert(idx - 1, it);
                  _changed();
                }
              : null,
          icon: const Icon(Icons.arrow_back),
          label: Text(tr('Gauche')),
        ),
        OutlinedButton.icon(
          onPressed: idx < proj.items.length - 1
              ? () {
                  proj.items.removeAt(idx);
                  proj.items.insert(idx + 1, it);
                  _changed();
                }
              : null,
          icon: const Icon(Icons.arrow_forward),
          label: Text(tr('Droite')),
        ),
        OutlinedButton.icon(
          onPressed: () {
            final copy = FurnitureItem.fromJson(it.toJson()..['uid'] = 'f${DateTime.now().microsecondsSinceEpoch}${_uid++}');
            proj.items.insert(idx + 1, copy);
            selected = copy.uid;
            _changed();
          },
          icon: const Icon(Icons.copy),
          label: Text(tr('Dupliquer')),
        ),
        TextButton.icon(
          onPressed: () {
            proj.items.removeAt(idx);
            selected = null;
            _changed();
          },
          icon: const Icon(Icons.delete_outline),
          label: Text(tr('Supprimer')),
        ),
      ]),
    ]);
  }

  // ------------------------------------------------------------------ résumé
  Widget _summary(TextTheme t, ColorScheme scheme) {
    if (proj.items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(Tokens.s4),
        child: Text(tr('Ajoutez des modules depuis la liste de gauche.'), style: t.bodyMedium),
      );
    }
    final (parts, hw) = furnitureCutList(proj);
    final plan = nestCached(parts, _cs);
    final sp = widget.state.project.specs;
    final sheetsMdf = plan.sheets.where((s) => s.material != furnitureBack).length;
    final sheetsBack = plan.sheets.where((s) => s.material == furnitureBack).length;
    final edge = parts.fold<double>(0, (a, p) => a + p.edgeLength * p.qty) / 1000;
    final mdf = sheetsMdf * (sp.sheetPrice ?? 850);
    final cutting = plan.sheets.length * sp.cuttingPerSheet;
    final edgeMin = edge * (sp.edgePriceMin ?? 9), edgeMax = edge * (sp.edgePriceMax ?? 12);
    final checks = proj.checks();
    final acc = cat!.accessories;
    return Container(
      constraints: const BoxConstraints(maxHeight: 300),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: scheme.outlineVariant))),
      child: ListView(padding: const EdgeInsets.all(Tokens.s4), children: [
        for (final c in checks)
          Row(children: [
            Icon(Icons.warning_amber_rounded, size: 18, color: scheme.tertiary),
            const SizedBox(width: 6),
            Expanded(child: Text(c, style: t.bodySmall)),
          ]),
        if (checks.isNotEmpty) const SizedBox(height: Tokens.s2),
        Wrap(spacing: Tokens.s5, runSpacing: Tokens.s2, children: [
          _stat(t, 'Pièces', '${plan.partCount}'),
          _stat(t, 'Feuilles MDF 18', '$sheetsMdf'),
          _stat(t, 'Feuilles HDF 6', '$sheetsBack'),
          _stat(t, 'Chant', '${edge.toStringAsFixed(1)} m'),
          _stat(t, 'Panneaux + chant + découpe', '${(mdf + cutting + edgeMin).round()} – ${(mdf + cutting + edgeMax).round()} MAD'),
        ]),
        Text(tr('Fonds HDF 6 mm, quincaillerie et accessoires non chiffrés ici (prix à saisir).'), style: t.bodySmall),
        const SizedBox(height: Tokens.s3),
        Text(tr('Quincaillerie'), style: t.labelLarge),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final e in hw.entries) Chip(label: Text('${e.key} : ${e.value == e.value.roundToDouble() ? e.value.round() : e.value.toStringAsFixed(1)}')),
        ]),
        if (acc.isNotEmpty) ...[
          const SizedBox(height: Tokens.s3),
          Text(tr('Accessoires du catalogue'), style: t.labelLarge),
          for (final a in acc)
            Row(children: [
              Expanded(child: Text(tr(a.name), style: t.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis)),
              Text(a.min == null ? '' : trp('{0}{1} MAD / {2}', [a.min!.round(), a.max != a.min ? '–${a.max!.round()}' : '', a.unit]), style: t.labelSmall),
              IconButton(
                  onPressed: (proj.accessories[a.id] ?? 0) > 0
                      ? () {
                          proj.accessories[a.id] = proj.accessories[a.id]! - 1;
                          if (proj.accessories[a.id] == 0) proj.accessories.remove(a.id);
                          _changed();
                        }
                      : null,
                  icon: const Icon(Icons.remove, size: 18)),
              Text('${proj.accessories[a.id] ?? 0}'),
              IconButton(
                  onPressed: () {
                    proj.accessories[a.id] = (proj.accessories[a.id] ?? 0) + 1;
                    _changed();
                  },
                  icon: const Icon(Icons.add, size: 18)),
            ]),
          Builder(builder: (context) {
            var lo = 0.0, hi = 0.0;
            for (final e in proj.accessories.entries) {
              final a = acc.where((x) => x.id == e.key).firstOrNull;
              if (a?.min == null) continue;
              lo += a!.min! * e.value;
              hi += a.max! * e.value;
            }
            return hi == 0 ? const SizedBox() : Text(trp('Accessoires : {0} – {1} MAD', [lo.round(), hi.round()]), style: t.labelLarge);
          }),
        ],
      ]),
    );
  }

  Widget _stat(TextTheme t, String k, String v) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(k, style: t.labelSmall),
        Text(v, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
      ]);
}

// ------------------------------------------------------------------ dessin de face

class _FrontPainter extends CustomPainter {
  final FurnitureProject p;
  final FurnitureUniverse cat;
  final String? selected;
  final ColorScheme scheme;
  final PlannerColors pc;
  _FrontPainter(this.p, this.cat, this.selected, this.scheme, this.pc);

  static (double, Offset) _frame(FurnitureProject p, Size size) {
    final w = math.max(p.wallWidth, p.usedWidth).toDouble();
    final k = math.min((size.width - 80) / w, (size.height - 60) / p.wallHeight);
    final ox = (size.width - w * k) / 2;
    final oy = (size.height + p.wallHeight * k) / 2 - 10; // sol
    return (k, Offset(ox, oy));
  }

  static FurnitureItem? hit(FurnitureProject p, Size size, Offset at) {
    final (k, o) = _frame(p, size);
    for (final it in p.items) {
      final x = o.dx + p.xOf(it) * k, y = o.dy - (FurnitureProject.zOf(it) + it.height) * k;
      if (Rect.fromLTWH(x, y, it.width * k, it.height * k).contains(at)) return it;
    }
    return null;
  }

  @override
  void paint(Canvas c, Size size) {
    final (k, o) = _frame(p, size);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = pc.cabinetStroke;
    // mur et sol
    final wall = Rect.fromLTWH(o.dx, o.dy - p.wallHeight * k, p.wallWidth * k, p.wallHeight * k);
    c.drawRect(wall, Paint()..color = pc.room);
    c.drawRect(wall, Paint()
      ..style = PaintingStyle.stroke
      ..color = pc.wallBand
      ..strokeWidth = 2);
    c.drawLine(Offset(o.dx - 20, o.dy), Offset(o.dx + math.max(p.wallWidth, p.usedWidth) * k + 20, o.dy), line..strokeWidth = 2);
    line.strokeWidth = 1.2;
    void text(String s, Offset at, {double size = 11, Color? color}) {
      final tp = TextPainter(text: TextSpan(text: s, style: TextStyle(fontSize: size, color: color ?? pc.dimension)), textDirection: TextDirection.ltr)..layout();
      tp.paint(c, at - Offset(tp.width / 2, tp.height / 2));
    }

    text('${p.wallWidth} mm', Offset(o.dx + p.wallWidth * k / 2, o.dy + 22));
    for (var n = 0; n < p.items.length; n++) {
      final it = p.items[n];
      final s = it.setup;
      final r = Rect.fromLTWH(o.dx + p.xOf(it) * k, o.dy - (FurnitureProject.zOf(it) + it.height) * k, it.width * k, it.height * k);
      c.drawRect(r, Paint()..color = s.panel ? pc.finish : pc.base);
      final inner = r.deflate(18 * k);
      if (s.panel) {
        if (s.shape == 'slats') {
          for (var x = r.left; x < r.right; x += 86 * k) {
            c.drawRect(Rect.fromLTWH(x, r.top, 36 * k, r.height), Paint()..color = pc.frontLine.withValues(alpha: 0.5));
          }
        }
      } else {
        // tiroirs en bas, puis portes / abattants / niches au-dessus
        var bottom = r.bottom;
        for (var d = 0; d < s.drawers; d++) {
          final h = s.drawerFront * k;
          final dr = Rect.fromLTRB(r.left + 2, bottom - h + 2, r.right - 2, bottom - 2);
          c.drawRect(dr, line);
          c.drawLine(Offset(dr.center.dx - 18, dr.top + 10), Offset(dr.center.dx + 18, dr.top + 10), line..strokeWidth = 2.5);
          line.strokeWidth = 1.2;
          bottom -= h;
        }
        final rest = Rect.fromLTRB(r.left, r.top, r.right, bottom);
        if (s.flaps > 0) {
          final fh = rest.height / s.flaps;
          for (var f = 0; f < s.flaps; f++) {
            final fr = Rect.fromLTWH(rest.left + 2, rest.top + f * fh + 2, rest.width - 4, fh - 4);
            c.drawRect(fr, line);
            c.drawLine(Offset(fr.center.dx - 18, s.liftUp ? fr.bottom - 8 : fr.top + 8), Offset(fr.center.dx + 18, s.liftUp ? fr.bottom - 8 : fr.top + 8),
                line..strokeWidth = 2.5);
            line.strokeWidth = 1.2;
          }
        } else if (s.doors > 0 && p.doorSystem != 'coulissantes') {
          final dw = rest.width / s.doors;
          for (var d = 0; d < s.doors; d++) {
            final dr = Rect.fromLTWH(rest.left + d * dw + 2, rest.top + 2, dw - 4, rest.height - 4);
            if (s.glass || s.mirror) {
              c.drawRect(dr.deflate(8), Paint()..color = (s.mirror ? const Color(0xFFCFE3EE) : const Color(0x55A8C8D8)));
            }
            c.drawRect(dr, line);
            final hx = d.isEven ? dr.right - 8 : dr.left + 8;
            c.drawLine(Offset(hx, dr.center.dy - 20), Offset(hx, dr.center.dy + 20), line..strokeWidth = 2.5);
            line.strokeWidth = 1.2;
          }
        } else {
          // ouvert : étagères et penderies visibles
          final dash = Paint()
            ..color = pc.frontLine
            ..strokeWidth = 1;
          final inRest = Rect.fromLTRB(inner.left, inner.top, inner.right, math.min(inner.bottom, bottom));
          final n2 = s.shelves + (s.rods >= 2 ? 1 : 0);
          for (var i = 1; i <= n2; i++) {
            final y = inRest.top + inRest.height * i / (n2 + 1);
            c.drawLine(Offset(inRest.left, y), Offset(inRest.right, y), dash);
          }
          for (var i = 0; i < s.rods; i++) {
            final y = inRest.top + 60 * k + i * inRest.height / 2;
            c.drawLine(Offset(inRest.left + 4, y), Offset(inRest.right - 4, y), Paint()
              ..color = const Color(0xFF8A8F95)
              ..strokeWidth = 3);
          }
        }
      }
      c.drawRect(r, line);
      if (it.uid == selected) {
        c.drawRect(r.inflate(2), Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = pc.selected);
      }
      text('${n + 1}', Offset(r.left + 12, r.top + 12), size: 11, color: scheme.onSurfaceVariant);
      text('${it.width}', Offset(r.center.dx, o.dy + 8), size: 10);
    }
    // portes coulissantes : vantaux devant tous les modules
    if (p.doorSystem == 'coulissantes' && p.items.isNotEmpty) {
      final total = p.usedWidth * k;
      final h = p.items.map((i) => i.height).reduce(math.max) * k;
      final n = math.max(2, (p.usedWidth / 1000).ceil());
      final w = total / n;
      for (var i = 0; i < n; i++) {
        final r = Rect.fromLTWH(o.dx + i * w, o.dy - h, w, h);
        c.drawRect(r, Paint()..color = (i.isEven ? pc.frontLine : pc.cabinetStroke).withValues(alpha: 0.10));
        c.drawRect(r.deflate(1), line);
      }
    }
  }

  @override
  bool shouldRepaint(_FrontPainter o) => true;
}

class _ThumbPainter extends CustomPainter {
  final FurnitureModel m;
  final ColorScheme scheme;
  _ThumbPainter(this.m, this.scheme);
  @override
  void paint(Canvas c, Size s) {
    final w = m.widths.first.toDouble(), h = m.heights.reduce(math.max).toDouble();
    final k = math.min(s.width / w, s.height / h) * 0.9;
    final r = Rect.fromCenter(center: s.center(Offset.zero), width: w * k, height: h * k);
    c.drawRect(r, Paint()..color = scheme.primaryContainer);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..color = scheme.onPrimaryContainer;
    c.drawRect(r, line);
    final st = m.setup;
    final parts = st.drawers + st.flaps + (st.doors > 0 ? 1 : 0);
    if (parts > 1) {
      for (var i = 1; i < parts; i++) {
        final y = r.top + r.height * i / parts;
        c.drawLine(Offset(r.left, y), Offset(r.right, y), line);
      }
    }
    if (st.doors > 1) c.drawLine(Offset(r.center.dx, r.top), Offset(r.center.dx, r.bottom), line);
    if (st.rods > 0) c.drawLine(Offset(r.left + 3, r.top + r.height * 0.2), Offset(r.right - 3, r.top + r.height * 0.2), line..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_ThumbPainter o) => o.m != m;
}
