// Stock de l'atelier : chutes et feuilles entières, réservations, étiquettes QR, découpes validées.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/engine.dart';
import 'app_state.dart';
import 'i18n.dart';
import 'kx_top_bar.dart';
import 'stock_labels_pdf.dart';
import 'stock_store.dart';
import 'kx_choices.dart';
import 'theme.dart';
import 'web_io.dart';

Future<void> openStock(BuildContext context, AppState state) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => StockPage(state: state)));

class StockPage extends StatefulWidget {
  final AppState state;
  const StockPage({super.key, required this.state});
  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> {
  final store = StockStore.instance;
  final _search = TextEditingController();
  int _tab = 0; // 0 chutes, 1 feuilles, 2 découpes validées
  String _material = '';
  final Set<String> _picked = {};

  Stock get stock => store.stock;
  String get project => StockStore.labelOf(widget.state.project);

  void _msg(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  @override
  void initState() {
    super.initState();
    if (store.unreadable) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _msg(tr('Le stock enregistré était illisible : une copie a été gardée, importez votre dernière sauvegarde.'));
      });
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _update(void Function(Stock s) f) {
    if (!store.update(f)) _msg(tr('Stock non enregistré : le stockage de l’appareil est plein.'));
  }

  Future<void> _add(bool offcut, [StockPiece? edit]) async {
    final r = await showDialog<StockPiece>(context: context, builder: (_) => _PieceDialog(offcut: offcut, edit: edit, cs: widget.state.project.cut));
    if (r == null) return;
    _update((s) {
      if (edit == null) {
        s.add(
            material: r.material, thickness: r.thickness, length: r.length, width: r.width, qty: r.qty, offcut: offcut, place: r.place, date: stockToday());
      } else {
        edit
          ..material = r.material
          ..thickness = r.thickness
          ..length = r.length
          ..width = r.width
          ..qty = r.qty
          ..place = r.place;
      }
    });
  }

  Future<void> _delete(List<StockPiece> list) async {
    if (list.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Retirer du stock ?')),
        content: Text(trp('{0} élément(s) : {1}', [list.length, list.take(8).map((p) => p.id).join(', ')])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Annuler'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Retirer'))),
        ],
      ),
    );
    if (ok != true) return;
    _update((s) => list.forEach(s.pieces.remove));
    _picked.clear();
  }

  Future<void> _labels(List<StockPiece> list) async {
    if (list.isEmpty) {
      _msg(tr('Aucune chute à étiqueter'));
      return;
    }
    downloadBytes('etiquettes_stock.pdf', await buildStockLabelsPdf(list), mime: 'application/pdf');
  }

  void _export() => downloadBytes('kitchinox_stock_${stockToday()}.xlsx', store.exportXlsx(), mime: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');

  Future<void> _import() async {
    final f = await pickFile(accept: '.xlsx');
    if (f == null || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Remplacer le stock ?')),
        content: Text(trp('Le stock de cet appareil ({0} élément(s)) sera remplacé par celui du fichier.', [stock.pieces.length])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Annuler'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Remplacer'))),
        ],
      ),
    );
    if (ok != true) return;
    _msg(store.importXlsx(f.bytes) ? tr('Stock importé') : tr('Ce fichier n’est pas un stock kitchinox.'));
  }

  Future<void> _settings() async {
    final cs = widget.state.project.cut;
    var mode = cs.stockMode;
    final pct = TextEditingController(text: '${cs.offcutPct}');
    final l = TextEditingController(text: '${stock.minLength}'), w = TextEditingController(text: '${stock.minWidth}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(tr('Réglages du stock')),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(tr('Dans ce projet, utiliser les chutes'), style: Theme.of(ctx).textTheme.titleSmall),
                RadioGroup<String>(
                  groupValue: mode,
                  onChanged: (v) => setD(() => mode = v!),
                  child: Column(children: [
                    for (final (k, label) in [
                      ('always', tr('Dès qu’elles servent (au moins 40 % remplies)')),
                      ('save', tr('Seulement si elles évitent une feuille neuve')),
                      ('off', tr('Jamais')),
                    ])
                      RadioListTile<String>(value: k, title: Text(label), contentPadding: EdgeInsets.zero),
                  ]),
                ),
                const SizedBox(height: Tokens.s2),
                _field(pct, tr('Prix d’une chute au devis (% du prix de la feuille neuve)'), const ValueKey('stock_pct')),
                const SizedBox(height: Tokens.s4),
                Text(tr('Taille minimum d’une chute à garder (mm)'), style: Theme.of(ctx).textTheme.titleSmall),
                const SizedBox(height: Tokens.s2),
                Row(children: [
                  Expanded(child: _field(l, tr('Grand côté'), null)),
                  const SizedBox(width: Tokens.s3),
                  Expanded(child: _field(w, tr('Petit côté'), null)),
                ]),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Annuler'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Enregistrer'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    widget.state.edit(() => cs
      ..stockMode = mode
      ..offcutPct = (int.tryParse(pct.text) ?? cs.offcutPct).clamp(0, 100));
    _update((s) {
      final a = int.tryParse(l.text) ?? s.minLength, b = int.tryParse(w.text) ?? s.minWidth;
      s
        ..minLength = math.max(100, math.max(a, b))
        ..minWidth = math.max(100, math.min(a, b));
    });
  }

  bool _shown(StockPiece p) {
    if (p.offcut != (_tab == 0)) return false;
    if (_material.isNotEmpty && '${stockMaterial(p.material)} ${p.thickness}' != _material) return false;
    final q = StockPiece.idFromScan(_search.text).toLowerCase();
    return q.isEmpty || '${p.id} ${p.material} ${p.length}x${p.width} ${p.place} ${p.origin} ${p.reserved}'.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        _picked.removeWhere((id) => stock.byId(id) == null);
        final list = stock.pieces.where(_shown).toList()
          ..sort((a, b) {
            final c = stockMaterial(a.material).compareTo(stockMaterial(b.material));
            if (c != 0) return c;
            final d = a.thickness.compareTo(b.thickness);
            return d != 0 ? d : (b.length * b.width).compareTo(a.length * a.width);
          });
        final mats = {for (final p in stock.pieces) if (p.offcut == (_tab == 0)) '${stockMaterial(p.material)} ${p.thickness}': '${p.material} · ${p.thickness} mm'};
        final picked = [for (final p in list) if (_picked.contains(p.id)) p];
        return Scaffold(
          resizeToAvoidBottomInset: false,
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(KxTopBar.height + 1),
            child: SafeArea(
              bottom: false,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                KxTopBar(
                  history: false,
                  onHome: () => Navigator.of(context).maybePop(),
                  menus: [
                    KxMenu('Fichier', 'menu_file', [
                      kxItem('Importer un stock…', _import, icon: Icons.file_open_outlined, key: 'menu_stock_import'),
                      kxItem('Exporter le stock', _export, icon: Icons.download_outlined, key: 'menu_stock_export'),
                      const Divider(height: 1),
                      kxItem('Étiquettes des chutes (PDF)', () => _labels(picked.isEmpty ? list : picked), icon: Icons.qr_code_2, key: 'menu_stock_labels'),
                    ]),
                    KxMenu('Insertion', 'menu_insert', [
                      kxItem('Ajouter une chute', () => _add(true), icon: Icons.crop_landscape_outlined),
                      kxItem('Ajouter des feuilles', () => _add(false), icon: Icons.layers_outlined),
                    ]),
                    KxMenu('Outils', 'menu_tools', [kxItem('Réglages du stock', _settings, icon: Icons.tune, key: 'menu_stock_settings')]),
                  ],
                  trailing: [
                    OutlinedButton.icon(
                        key: const ValueKey('stock_add_offcut'), onPressed: () => _add(true), icon: const Icon(Icons.add), label: Text(tr('Chute'))),
                    const SizedBox(width: Tokens.s2),
                    OutlinedButton.icon(
                        key: const ValueKey('stock_add_sheet'), onPressed: () => _add(false), icon: const Icon(Icons.add), label: Text(tr('Feuilles'))),
                    const SizedBox(width: Tokens.s2),
                  ],
                ),
                const Divider(height: 1),
              ]),
            ),
          ),
          body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.all(Tokens.s4),
              child: Wrap(spacing: Tokens.s4, runSpacing: Tokens.s3, crossAxisAlignment: WrapCrossAlignment.center, children: [
                KxChoices<int>(
                  segments: [
                    ButtonSegment(value: 0, icon: const Icon(Icons.crop_landscape_outlined), label: Text(trp('Chutes ({0})', [stock.offcuts.length]))),
                    ButtonSegment(value: 1, icon: const Icon(Icons.layers_outlined), label: Text(trp('Feuilles ({0})', [stock.sheets.fold<int>(0, (a, p) => a + p.qty)]))),
                    ButtonSegment(value: 2, icon: const Icon(Icons.history), label: Text(tr('Découpes validées'))),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (v) => setState(() {
                    _tab = v.first;
                    _material = '';
                    _picked.clear();
                  }),
                ),
                if (_tab < 2)
                  SizedBox(
                    width: 300,
                    child: TextField(
                      key: const ValueKey('stock_search'),
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.qr_code_scanner),
                        hintText: tr('Chercher ou scanner une étiquette'),
                        isDense: true,
                        border: const OutlineInputBorder(),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(tooltip: tr('Effacer'), icon: const Icon(Icons.clear, size: 18), onPressed: () => setState(_search.clear)),
                      ),
                    ),
                  ),
                if (_tab < 2 && mats.length > 1)
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    ChoiceChip(label: Text(tr('Tout')), selected: _material.isEmpty, onSelected: (_) => setState(() => _material = '')),
                    for (final e in mats.entries)
                      ChoiceChip(label: Text(tr(e.value)), selected: _material == e.key, onSelected: (_) => setState(() => _material = e.key)),
                  ]),
                if (_tab == 0 && list.isNotEmpty)
                  Text(trp('{0} chute(s) · {1} m²', [list.length, list.fold<double>(0, (a, p) => a + p.area).toStringAsFixed(2)]), style: t.bodyMedium),
              ]),
            ),
            if (picked.isNotEmpty)
              Container(
                color: scheme.primaryContainer,
                padding: const EdgeInsets.symmetric(horizontal: Tokens.s4, vertical: Tokens.s1),
                child: Row(children: [
                  Expanded(child: Text(trp('{0} choisie(s)', [picked.length]), style: t.titleSmall?.copyWith(color: scheme.onPrimaryContainer))),
                  TextButton.icon(onPressed: () => _labels(picked), icon: const Icon(Icons.qr_code_2), label: Text(tr('Étiquettes'))),
                  TextButton.icon(
                      onPressed: () => _update((s) {
                            for (final p in picked) {
                              p.reserved = p.reserved == project ? '' : project;
                            }
                          }),
                      icon: const Icon(Icons.bookmark_outline),
                      label: Text(tr('Garder pour ce projet'))),
                  TextButton.icon(onPressed: () => _delete(picked), icon: const Icon(Icons.delete_outline), label: Text(tr('Retirer'))),
                ]),
              ),
            Divider(height: 1, color: scheme.outlineVariant),
            Expanded(child: _tab == 2 ? _moves(t, scheme) : _pieces(list, t, scheme)),
          ]),
        );
      },
    );
  }

  Widget _pieces(List<StockPiece> list, TextTheme t, ColorScheme scheme) {
    if (list.isEmpty) {
      final empty = _search.text.isEmpty && _material.isEmpty;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Tokens.s5),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(_tab == 0 ? Icons.crop_landscape_outlined : Icons.layers_outlined, size: 48, color: scheme.outline),
              const SizedBox(height: Tokens.s3),
              Text(
                !empty
                    ? tr('Rien ne correspond à la recherche.')
                    : _tab == 0
                        ? tr('Aucune chute. Ajoutez celles de l’atelier, ou validez une découpe : ses chutes se rangent ici et servent aux prochains projets.')
                        : tr('Aucune feuille. Ajoutez vos feuilles entières pour savoir combien il en reste à acheter.'),
                textAlign: TextAlign.center,
                style: t.bodyMedium,
              ),
            ]),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: Tokens.s5),
      itemCount: list.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: scheme.outlineVariant),
      itemBuilder: (context, i) {
        final p = list[i];
        return ListTile(
          key: ValueKey('stock_${p.id}'),
          onTap: () => _add(p.offcut, p),
          leading: Row(mainAxisSize: MainAxisSize.min, children: [
            Checkbox(
                value: _picked.contains(p.id), onChanged: (v) => setState(() => v == true ? _picked.add(p.id) : _picked.remove(p.id))),
            SizedBox(width: 64, height: 46, child: CustomPaint(painter: _ShapePainter(p.length, p.width, scheme))),
          ]),
          title: Text('${p.length} × ${p.width} mm · ${tr(p.material)} ${p.thickness}', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          subtitle: Text([
            p.id,
            if (p.offcut) '${p.area.toStringAsFixed(2)} m²',
            if (p.place.isNotEmpty) p.place,
            if (p.origin.isNotEmpty) trp('vient de {0}', [p.origin]),
            if (p.date.isNotEmpty) p.date,
          ].join(' · ')),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (p.reserved.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Chip(
                  avatar: const Icon(Icons.bookmark, size: 16),
                  label: Text(p.reserved, overflow: TextOverflow.ellipsis),
                  onDeleted: () => _update((s) => p.reserved = ''),
                  deleteButtonTooltipMessage: tr('Libérer'),
                ),
              ),
            if (!p.offcut) ...[
              IconButton(
                  tooltip: tr('Une de moins'),
                  onPressed: p.qty <= 1 ? null : () => _update((s) => p.qty--),
                  icon: const Icon(Icons.remove_circle_outline)),
              Text('${p.qty}', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              IconButton(tooltip: tr('Une de plus'), onPressed: () => _update((s) => p.qty++), icon: const Icon(Icons.add_circle_outline)),
            ],
            IconButton(tooltip: tr('Retirer'), onPressed: () => _delete([p]), icon: const Icon(Icons.delete_outline)),
          ]),
        );
      },
    );
  }

  Widget _moves(TextTheme t, ColorScheme scheme) {
    final list = stock.moves.reversed.toList();
    if (list.isEmpty) return Center(child: Text(tr('Aucune découpe validée pour l’instant.'), style: t.bodyMedium));
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: scheme.outlineVariant),
      itemBuilder: (context, i) {
        final m = list[i];
        final offcuts = m.taken.where((p) => p.offcut).toList();
        final sheets = m.taken.where((p) => !p.offcut).fold<int>(0, (a, p) => a + p.qty);
        return ListTile(
          leading: Icon(m.undone ? Icons.undo : Icons.content_cut, color: m.undone ? scheme.outline : scheme.primary),
          title: Text(m.project, style: t.titleSmall?.copyWith(decoration: m.undone ? TextDecoration.lineThrough : null)),
          subtitle: Text([
            m.date,
            trp('{0} feuille(s) du stock', [sheets]),
            trp('{0} achetée(s)', [m.bought]),
            trp('{0} chute(s) utilisée(s)', [offcuts.length]),
            trp('{0} chute(s) rangée(s)', [m.added.length]),
          ].join(' · ')),
          trailing: m.undone ? Text(tr('Annulée')) : TextButton(onPressed: () => _undo(m), child: Text(tr('Annuler la validation'))),
        );
      },
    );
  }

  Future<void> _undo(StockMove m) async {
    final gone = undoCut(widget.state, m);
    _msg(gone.isEmpty ? tr('Validation annulée : le stock est remis comme avant.') : trp('Validation annulée. Chutes déjà utilisées ailleurs : {0}', [gone.join(', ')]));
  }
}

Widget _field(TextEditingController c, String label, Key? key) => TextField(
      key: key,
      controller: c,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
    );

/// Forme de la pièce à l'échelle (2800 mm en largeur), longueur à l'horizontale.
class _ShapePainter extends CustomPainter {
  final int l, w;
  final ColorScheme scheme;
  _ShapePainter(this.l, this.w, this.scheme);
  @override
  void paint(Canvas c, Size s) {
    final k = math.min(s.width / math.max(l, 1200), s.height / math.max(w, 800));
    final r = Rect.fromCenter(center: s.center(Offset.zero), width: math.max(4, l * k), height: math.max(4, w * k));
    c.drawRect(r, Paint()..color = scheme.primary.withValues(alpha: 0.14));
    c.drawRect(r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = scheme.primary);
  }

  @override
  bool shouldRepaint(_ShapePainter o) => o.l != l || o.w != w || o.scheme != scheme;
}

class _PieceDialog extends StatefulWidget {
  final bool offcut;
  final StockPiece? edit;
  final CutSettings cs;
  const _PieceDialog({required this.offcut, required this.edit, required this.cs});
  @override
  State<_PieceDialog> createState() => _PieceDialogState();
}

class _PieceDialogState extends State<_PieceDialog> {
  late final TextEditingController _l, _w, _t, _q, _place, _mat;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.edit, cs = widget.cs;
    final (sl, sw) = cs.sheetDimensionsFor(cs.carcassMaterial);
    _mat = TextEditingController(text: e?.material ?? cs.carcassMaterial);
    _t = TextEditingController(text: '${e?.thickness ?? cs.carcassThickness}');
    _l = TextEditingController(text: e == null ? (widget.offcut ? '' : '$sl') : '${e.length}');
    _w = TextEditingController(text: e == null ? (widget.offcut ? '' : '$sw') : '${e.width}');
    _q = TextEditingController(text: '${e?.qty ?? 1}');
    _place = TextEditingController(text: e?.place ?? '');
  }

  @override
  void dispose() {
    for (final c in [_l, _w, _t, _q, _place, _mat]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Panneaux du projet et déjà en stock : (matière, épaisseur, format).
  List<(String, int, (int, int))> get _choices {
    final cs = widget.cs;
    final out = <String, (String, int, (int, int))>{};
    void add(String m, int t, (int, int) f) => out.putIfAbsent('${stockMaterial(m)}|$t', () => (m, t, f));
    for (final m in [cs.carcassMaterial, cs.frontMaterial, cs.backMaterial]) {
      add(m, cs.thicknessFor(m), cs.sheetDimensionsFor(m));
    }
    for (final p in StockStore.instance.stock.pieces) {
      add(p.material, p.thickness, (p.length, p.width));
    }
    return out.values.toList();
  }

  void _ok() {
    final l = int.tryParse(_l.text) ?? 0, w = int.tryParse(_w.text) ?? 0, t = int.tryParse(_t.text) ?? 0, q = int.tryParse(_q.text) ?? 0;
    if (_mat.text.trim().isEmpty || l < 50 || w < 50 || l > 5000 || w > 5000 || t < 2 || t > 60 || q < 1) {
      setState(() => _error = tr('Vérifiez la matière, l’épaisseur (2 à 60 mm) et les cotes (50 à 5000 mm).'));
      return;
    }
    Navigator.pop(context,
        StockPiece(id: '', material: _mat.text.trim(), thickness: t, length: l, width: w, qty: q, offcut: widget.offcut, place: _place.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text(widget.edit != null ? widget.edit!.id : (widget.offcut ? tr('Ajouter une chute') : tr('Ajouter des feuilles'))),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (widget.edit == null) ...[
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final (m, th, f) in _choices)
                  ActionChip(
                    label: Text('${tr(m)} · $th mm'),
                    onPressed: () => setState(() {
                      _mat.text = m;
                      _t.text = '$th';
                      if (!widget.offcut) {
                        _l.text = '${f.$1}';
                        _w.text = '${f.$2}';
                      }
                    }),
                  ),
              ]),
              const SizedBox(height: Tokens.s3),
            ],
            Row(children: [
              Expanded(
                flex: 3,
                child: TextField(
                    key: const ValueKey('piece_material'),
                    controller: _mat,
                    decoration: InputDecoration(labelText: tr('Matière'), border: const OutlineInputBorder(), isDense: true)),
              ),
              const SizedBox(width: Tokens.s3),
              Expanded(child: _field(_t, tr('Épaisseur'), const ValueKey('piece_t'))),
            ]),
            const SizedBox(height: Tokens.s3),
            Row(children: [
              Expanded(child: _field(_l, tr('Longueur, sens du fil (mm)'), const ValueKey('piece_l'))),
              const SizedBox(width: Tokens.s3),
              Expanded(child: _field(_w, tr('Largeur (mm)'), const ValueKey('piece_w'))),
              if (!widget.offcut) ...[
                const SizedBox(width: Tokens.s3),
                SizedBox(width: 96, child: _field(_q, tr('Quantité'), const ValueKey('piece_q'))),
              ],
            ]),
            const SizedBox(height: Tokens.s3),
            TextField(
                controller: _place,
                decoration: InputDecoration(labelText: tr('Emplacement (rayon, mur…)'), border: const OutlineInputBorder(), isDense: true)),
            if (_error != null) ...[
              const SizedBox(height: Tokens.s2),
              Text(_error!, style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error)),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Annuler'))),
        FilledButton(key: const ValueKey('piece_ok'), onPressed: _ok, child: Text(tr('Enregistrer'))),
      ],
    );
  }
}

// ------------------------------------------------------------------ valider une découpe

/// Projet dans le stock : la cuisine, ou une création de l'atelier, ou un débit manuel.
String stockLabelFor(AppState state, {String? art, String? manual}) =>
    [StockStore.labelOf(state.project), if (art != null) 'Art : $art', ?manual].join(' · ');

/// Annule une découpe validée et défige le plan du projet ouvert s'il est concerné.
List<String> undoCut(AppState state, StockMove m) {
  var gone = const <String>[];
  StockStore.instance.update((s) => gone = s.undo(m));
  final p = state.project;
  void release() {
    if (m.project == stockLabelFor(state)) p.cut.stockFrozen = null;
    if (m.project == stockLabelFor(state, art: p.art.name)) p.art.stockFrozen = null;
    if (m.project == stockLabelFor(state, manual: p.manual.order)) p.manual.stockFrozen = null;
  }

  state.edit(release);
  return gone;
}

/// Découpe faite à l'atelier : sort du stock ce qui a servi et y range les chutes cochées.
/// [freeze] : fige les chutes du plan de ce projet. Renvoie le message à afficher, ou null si rien n'est fait.
Future<String?> showCutDone(BuildContext context, AppState state, CutPlan plan,
    {required String project, required CutSettings settings, required void Function(List<StockPiece>? frozen) freeze}) async {
  if (plan.sheets.isEmpty) return tr('Aucune pièce à débiter');
  final store = StockStore.instance;
  final done = store.stock.lastCut(project);
  if (done != null) {
    final undo = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Découpe déjà validée')),
        content: Text(trp('Le {0}. Le plan est figé et ses chutes sont rangées. Annulez la validation pour le refaire.', [done.date])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Fermer'))),
          FilledButton(key: const ValueKey('cut_undo'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Annuler la validation'))),
        ],
      ),
    );
    if (undo != true) return null;
    final gone = undoCut(state, done);
    return gone.isEmpty ? tr('Validation annulée : le stock est remis comme avant.') : trp('Validation annulée. Chutes déjà utilisées ailleurs : {0}', [gone.join(', ')]);
  }
  // une chute du plan a pu être prise par un autre projet depuis le calcul
  final missing = [for (final s in plan.stockSheets()) if (store.stock.byId(s.stockId!) == null) s.stockId!];
  if (missing.isNotEmpty) return trp('Chutes plus disponibles : {0}. Rouvrez le plan pour le recalculer.', [missing.join(', ')]);
  final needs = store.stock.needs(plan, project: project);
  final left = store.stock.leftovers(plan, project: project, date: stockToday());
  final keep = {...left};
  final place = TextEditingController();
  var labels = left.isNotEmpty;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) {
        final t = Theme.of(ctx).textTheme;
        final scheme = Theme.of(ctx).colorScheme;
        Widget h(String s) => Padding(
            padding: const EdgeInsets.only(top: Tokens.s4, bottom: Tokens.s1), child: Text(s, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)));
        final used = plan.stockSheets().toList();
        return AlertDialog(
          title: Text(tr('Valider la découpe')),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(project, style: t.bodyMedium),
                if (used.isNotEmpty) ...[
                  h(trp('Chutes utilisées ({0})', [used.length])),
                  for (final s in used) Text('${s.stockId} · ${s.length} × ${s.width} · ${tr(s.material)} · ${(s.usage * 100).round()} %', style: t.bodySmall),
                ],
                h(tr('Feuilles neuves')),
                for (final n in needs)
                  Text(
                    '${tr(n.material)} ${n.thickness} · ${n.length} × ${n.width} : ${trp('{0} feuille(s), {1} en stock, {2} à acheter', [n.needed, n.inStock, n.toBuy])}',
                    style: t.bodySmall?.copyWith(fontWeight: n.toBuy > 0 ? FontWeight.w700 : null),
                  ),
                if (needs.isEmpty) Text(tr('Aucune : les chutes suffisent.'), style: t.bodySmall),
                h(trp('Chutes à ranger ({0})', [left.length])),
                if (left.isEmpty) Text(tr('Aucune assez grande pour être gardée.'), style: t.bodySmall),
                for (final p in left)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: keep.contains(p),
                    onChanged: (v) => setD(() => v == true ? keep.add(p) : keep.remove(p)),
                    title: Text('${p.length} × ${p.width} mm · ${tr(p.material)} ${p.thickness}'),
                  ),
                if (left.isNotEmpty) ...[
                  const SizedBox(height: Tokens.s2),
                  TextField(
                      controller: place,
                      decoration: InputDecoration(labelText: tr('Emplacement (rayon, mur…)'), border: const OutlineInputBorder(), isDense: true)),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: labels,
                    onChanged: (v) => setD(() => labels = v),
                    title: Text(tr('Imprimer les étiquettes des chutes')),
                  ),
                ],
                const SizedBox(height: Tokens.s2),
                Text(tr('Le plan de découpe de ce projet sera figé. Vous pourrez annuler la validation.'),
                    style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Annuler'))),
            FilledButton.icon(
                key: const ValueKey('cut_ok'), onPressed: () => Navigator.pop(ctx, true), icon: const Icon(Icons.check), label: Text(tr('Valider'))),
          ],
        );
      },
    ),
  );
  if (ok != true) return null;
  for (final p in keep) {
    p.place = place.text.trim();
  }
  // le plan se refait à l'identique avec les chutes d'aujourd'hui
  final snapshot = [for (final p in settings.stock) p.copy()];
  late StockMove move;
  state.edit(() => freeze(snapshot));
  final saved = store.update((s) => move = s.validate(plan, project: project, date: stockToday(), keep: [for (final p in left) if (keep.contains(p)) p]));
  if (labels && move.added.isNotEmpty) {
    downloadBytes('etiquettes_stock.pdf', await buildStockLabelsPdf(move.added), mime: 'application/pdf');
  }
  if (!saved) return tr('Stock non enregistré : le stockage de l’appareil est plein.');
  return trp('Découpe validée : {0} chute(s) utilisée(s), {1} rangée(s)', [move.taken.where((p) => p.offcut).length, move.added.length]);
}
