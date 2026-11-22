// Débit manuel, à la manière de SketchCut : feuille, méthode (par longueur, par largeur, optimale),
// liste des pièces saisies à la main (rotation, chants), aperçu des feuilles, PDF et fichier .sct.
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/engine.dart';
import 'app_state.dart';
import 'session.dart';
import 'busy.dart';
import 'cut_pdf.dart';
import 'tech_drawings.dart';
import 'theme.dart';
import 'web_io.dart';
import 'i18n.dart';

/// Choix de la méthode de débit, en trois vignettes.
class CutModePicker extends StatelessWidget {
  final int method;
  final ValueChanged<int> onChanged;
  const CutModePicker({super.key, required this.method, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(children: [
      for (final (m, label) in const [(1, 'Par longueur'), (2, 'Par largeur'), (3, 'Optimal')])
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: InkWell(
              onTap: () => onChanged(m),
              borderRadius: BorderRadius.circular(Tokens.radius),
              child: Container(
                padding: const EdgeInsets.all(Tokens.s2),
                decoration: BoxDecoration(
                  color: method == m ? scheme.primary.withValues(alpha: 0.08) : null,
                  borderRadius: BorderRadius.circular(Tokens.radius),
                  border: Border.all(color: method == m ? scheme.primary : scheme.outlineVariant, width: method == m ? 2 : 1),
                ),
                child: Column(children: [
                  SizedBox(height: 46, width: 84, child: CustomPaint(painter: _ModeIcon(m, scheme.onSurfaceVariant))),
                  const SizedBox(height: 4),
                  Text(label, style: Theme.of(context).textTheme.labelMedium),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }
}

class _ModeIcon extends CustomPainter {
  final int mode;
  final Color color;
  _ModeIcon(this.mode, this.color);

  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = color;
    final fill = Paint()..color = color.withValues(alpha: 0.12);
    void box(double x, double y, double w, double h) {
      final r = Rect.fromLTWH(x * s.width, y * s.height, w * s.width, h * s.height).deflate(1);
      c.drawRect(r, fill);
      c.drawRect(r, p);
    }

    switch (mode) {
      case 1: // bandes horizontales, tronçonnées
        for (final (y, cuts) in const [(0.0, [0.0, 0.42, 0.78]), (0.34, [0.0, 0.28, 0.7]), (0.67, [0.0, 0.5])]) {
          for (var i = 0; i < cuts.length; i++) {
            final x0 = cuts[i], x1 = i + 1 < cuts.length ? cuts[i + 1] : 1.0;
            box(x0, y, x1 - x0, 0.33);
          }
        }
      case 2: // bandes verticales
        for (final (x, cuts) in const [(0.0, [0.0, 0.55]), (0.4, [0.0, 0.3, 0.7]), (0.72, [0.0, 0.45, 0.8])]) {
          final w = x == 0.72 ? 0.28 : (x == 0.0 ? 0.4 : 0.32);
          for (var i = 0; i < cuts.length; i++) {
            final y0 = cuts[i], y1 = i + 1 < cuts.length ? cuts[i + 1] : 1.0;
            box(x, y0, w, y1 - y0);
          }
        }
      default: // libre : blocs dans les deux sens
        box(0, 0, 0.42, 0.3);
        box(0, 0.3, 0.42, 0.35);
        box(0, 0.65, 0.42, 0.35);
        box(0.45, 0, 0.55, 0.24);
        box(0.45, 0.26, 0.55, 0.16);
        box(0.45, 0.46, 0.3, 0.54);
        box(0.77, 0.46, 0.23, 0.26);
        box(0.77, 0.74, 0.23, 0.26);
    }
  }

  @override
  bool shouldRepaint(_ModeIcon o) => o.mode != mode || o.color != color;
}

/// Ouvre l'écran de débit manuel.
/// [offerOpen] : au démarrage, propose d'ouvrir un fichier SketchCut ou kitchinox déjà enregistré.
Future<void> openManualCut(BuildContext context, AppState state, {bool offerOpen = false}) {
  Session.route = 'debit';
  return Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => LeaveGuard(
      id: 'debit',
      current: () => jsonEncode(state.project.manual.toJson()),
      revert: (saved) => state.project.manual = saved == null || saved.isEmpty ? ManualCut() : ManualCut.fromJson(jsonDecode(saved) as Map<String, dynamic>),
      child: ManualCutPage(state: state, offerOpen: offerOpen),
    ),
  ));
}

/// Lit un fichier de débit : projet Kitchinox (.kin / .json) ou SketchCut (.sct).
/// Importe l'ensemble des panneaux du projet dans l'optimiseur de débit. Null si non reconnu.
(ManualCut, String)? manualCutFromFile(String name, List<int> bytes, AppState state) {
  String text;
  try {
    text = KinFormat.decode(Uint8List.fromList(bytes));
  } catch (_) {
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      text = latin1.decode(bytes); // SketchCut écrit en Windows-1252
    }
  }
  final lower = name.toLowerCase();
  if (lower.endsWith('.sct') || text.startsWith('<V')) {
    final job = ManualCut.fromSct(text);
    return (job, '${job.parts.length} référence(s) lues dans $name');
  }
  try {
    final p = Project.fromJson((jsonDecode(text) as Map).cast<String, dynamic>());
    if (p.manual.parts.isNotEmpty) return (p.manual, 'Débit manuel du projet « ${p.name} »');
    final e = LayoutEngine(state.catalog, p);
    final parts = cutList(e, p.cut, repereNumbers(e));
    if (parts.isEmpty) return null;
    final byMat = <String, int>{};
    for (final x in parts) {
      byMat[x.material] = (byMat[x.material] ?? 0) + x.area * x.qty;
    }
    final mat = (byMat.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
    final job = ManualCut(order: p.name, material: mat, sheetLength: p.cut.sheetLength, sheetWidth: p.cut.sheetWidth, kerf: p.cut.kerf, trim: p.cut.trim, method: p.cut.method);
    for (final x in parts) {
      job.parts.add(ManualPart(
        length: x.length,
        width: x.width,
        qty: x.qty,
        rotate: x.canRotate,
        edgeLong: x.edgeLong,
        edgeShort: x.edgeShort,
        desc: '${x.name} · ${x.cabinet} (${x.material})',
      ));
    }
    return (job, 'Projet « ${p.name} » : ${parts.length} panneau(x) importé(s) pour le débit');
  } catch (_) {
    return null;
  }
}

class ManualCutPage extends StatefulWidget {
  final AppState state;
  final bool offerOpen;
  const ManualCutPage({super.key, required this.state, this.offerOpen = false});
  @override
  State<ManualCutPage> createState() => _ManualCutPageState();
}

class _ManualCutPageState extends State<ManualCutPage> {
  ManualCut get job => widget.state.project.manual;
  CutPlan? _plan;
  bool _busy = false;

  int _gen = 0; // change quand un fichier remplace la liste : les champs repartent des nouvelles valeurs

  @override
  void initState() {
    super.initState();
    if (job.parts.isEmpty) job.parts.add(ManualPart());
    if (widget.offerOpen) WidgetsBinding.instance.addPostFrameCallback((_) => _offer());
  }

  Future<void> _offer() async {
    final open = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Débitage')),
        content: Text(tr('Saisir les pièces à la main, ou importer un fichier projet Kitchinox (.kin) ou SketchCut (.sct) ?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Saisie manuelle'))),
          FilledButton.icon(onPressed: () => Navigator.pop(ctx, true), icon: const Icon(Icons.file_open_outlined), label: Text(tr('Ouvrir un fichier (.kin / .sct)'))),
        ],
      ),
    );
    if (open == true) await _open();
  }

  Future<void> _open() async {
    final f = await pickFile(accept: '.kin,.sct');
    if (f == null || !mounted) return;
    final r = manualCutFromFile(f.name, f.bytes, widget.state);
    if (r == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(trp('Fichier non reconnu : {0}', [tr(f.name)]))));
      return;
    }
    final (job, msg) = r;
    if (job.parts.isEmpty) job.parts.add(ManualPart());
    setState(() {
      widget.state.project.manual = job;
      _gen++;
      _plan = job.parts.any((p) => p.length > 0 && p.width > 0) ? job.plan() : null;
    });
    widget.state.refresh();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _changed({bool recalc = true}) {
    Session.autosave('debit', () => jsonEncode(job.toJson()));
    if (recalc && job.parts.any((p) => p.length > 0 && p.width > 0 && p.qty > 0)) {
      try {
        _plan = job.plan();
      } catch (_) {}
    }
    setState(() {});
    widget.state.refresh();
  }

  void _validateRow(int i) {
    final p = job.parts[i];
    if (p.length > 0 && p.width > 0) {
      if (p.qty <= 0) p.qty = 1;
      if (i == job.parts.length - 1) {
        job.parts.add(ManualPart());
      }
      _changed(recalc: true);
    }
  }

  Future<void> _calc() async {
    final plan = await runBusy(context, tr('Optimisation du débit…'), () => job.plan());
    if (mounted) setState(() => _plan = plan);
  }

  Future<void> _pdf() async {
    final plan = _plan ?? job.plan();
    if (plan.parts.isEmpty) return;
    setState(() => _busy = true);
    try {
      final e = LayoutEngine(Catalog('', 'mm', const []), Project(name: job.order));
      final bytes = await runBusy(context, tr('Plan de coupe…'), () => buildCutPdf(e, plan));
      downloadBytes('${job.order}_plan_de_decoupe.pdf', bytes, mime: 'application/pdf');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _sct() {
    final plan = _plan ?? job.plan();
    if (plan.parts.isEmpty) return;
    downloadBytes('${job.order}.sct', toSct(plan, job.material, order: job.order, thickness: '${job.thickness}').codeUnits);
  }

  Widget _num(String label, int value, ValueChanged<int> on, {double width = 110}) => SizedBox(
        width: width,
        child: TextFormField(
          initialValue: '$value',
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
          onChanged: (v) {
            on(int.tryParse(v) ?? 0);
            _changed(recalc: true);
          },
        ),
      );

  Widget _cell(ManualPart p, String field, int value, ValueChanged<int> on, {double width = 84, VoidCallback? onSubmitted}) => SizedBox(
        width: width,
        child: TextFormField(
          key: ValueKey('${identityHashCode(p)}-$field'),
          initialValue: value == 0 ? '' : '$value',
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 10)),
          onChanged: (v) {
            on(int.tryParse(v) ?? 0);
            _changed(recalc: p.length > 0 && p.width > 0 && p.qty > 0);
          },
          onFieldSubmitted: (_) => onSubmitted?.call(),
        ),
      );

  Widget _edges(ManualPart p, bool long) {
    final v = long ? p.edgeLong : p.edgeShort;
    return Tooltip(
      message: trp('Chants sur {0} : {1} (cliquer pour changer)', [long ? 'la longueur' : 'la largeur', v]),
      child: InkWell(
        onTap: () {
          final n = (v + 1) % 3;
          if (long) {
            p.edgeLong = n;
          } else {
            p.edgeShort = n;
          }
          _changed();
        },
        child: SizedBox(
          width: 34,
          height: 34,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < 2; i++)
              Container(height: 2.5, width: 22, margin: const EdgeInsets.symmetric(vertical: 1.5), color: i < v ? Colors.black87 : Colors.black12),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final plan = _plan;
    final head = t.labelMedium?.copyWith(fontWeight: FontWeight.w800);
    final totalParts = job.parts.fold<int>(0, (s, p) => s + (p.length > 0 && p.width > 0 ? p.qty : 0));

    final settings = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('Feuille'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: Tokens.s2),
      Wrap(spacing: Tokens.s2, runSpacing: Tokens.s3, children: [
        SizedBox(
          width: 230,
          child: TextFormField(
            initialValue: job.order,
            decoration: InputDecoration(labelText: tr('Commande'), isDense: true, border: OutlineInputBorder()),
            onChanged: (v) {
              job.order = v;
              _changed();
            },
          ),
        ),
        SizedBox(
          width: 230,
          child: TextFormField(
            initialValue: job.material,
            decoration: InputDecoration(labelText: tr('Matériau'), isDense: true, border: OutlineInputBorder()),
            onChanged: (v) {
              job.material = v;
              _changed();
            },
          ),
        ),
        _num('Épaisseur', job.thickness, (v) => job.thickness = v),
        _num('Longueur (mm)', job.sheetLength, (v) => job.sheetLength = v),
        _num('Largeur (mm)', job.sheetWidth, (v) => job.sheetWidth = v),
        _num('Trait de scie', job.kerf, (v) => job.kerf = v),
        _num('Recoupe', job.trim, (v) => job.trim = v),
      ]),
      const SizedBox(height: Tokens.s4),
      Text(tr('Méthode'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: Tokens.s2),
      SizedBox(
        width: 380,
        child: CutModePicker(
          method: job.method,
          onChanged: (m) {
            job.method = m;
            _changed();
          },
        ),
      ),
      const SizedBox(height: Tokens.s2),
      SizedBox(
        width: 420,
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('Matière à fil ou veinée (bois, marbre, décor)')),
          subtitle: Text(job.grain
              ? tr('Aucune pièce ne pivote : la longueur suit la longueur de la feuille.')
              : tr('Couleur unie : chaque pièce peut pivoter si sa case est cochée.')),
          value: job.grain,
          onChanged: (v) {
            job.grain = v;
            _changed();
          },
        ),
      ),
    ]);

    final table = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(tr('Pièces'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(width: Tokens.s2),
        Text(trp('{0} pièce(s)', [totalParts]), style: t.bodySmall),
      ]),
      const SizedBox(height: Tokens.s2),
      Row(children: [
        SizedBox(width: 28, child: Text('#', style: head)),
        SizedBox(width: 84, child: Text(tr('Longueur'), style: head, textAlign: TextAlign.center)),
        const SizedBox(width: 34),
        SizedBox(width: 84, child: Text(tr('Largeur'), style: head, textAlign: TextAlign.center)),
        const SizedBox(width: 34),
        SizedBox(width: 64, child: Text(tr('Qté'), style: head, textAlign: TextAlign.center)),
        SizedBox(width: 48, child: Text(tr('Rot.'), style: head, textAlign: TextAlign.center)),
        Expanded(child: Text(tr('Description'), style: head)),
        SizedBox(width: 52, child: Text('OK', style: head, textAlign: TextAlign.center)),
        const SizedBox(width: 40),
      ]),
      const SizedBox(height: Tokens.s1),
      for (var i = 0; i < job.parts.length; i++)
        Padding(
          key: ObjectKey(job.parts[i]),
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(children: [
            SizedBox(width: 28, child: Text('${i + 1}', style: t.bodySmall)),
            _cell(job.parts[i], 'l', job.parts[i].length, (v) => job.parts[i].length = v, onSubmitted: () => _validateRow(i)),
            _edges(job.parts[i], true),
            _cell(job.parts[i], 'w', job.parts[i].width, (v) => job.parts[i].width = v, onSubmitted: () => _validateRow(i)),
            _edges(job.parts[i], false),
            _cell(job.parts[i], 'q', job.parts[i].qty, (v) => job.parts[i].qty = v, width: 64, onSubmitted: () => _validateRow(i)),
            SizedBox(
              width: 48,
              child: Tooltip(
                message: job.grain ? tr('Matière à fil : rotation interdite') : tr('La pièce peut pivoter sur la feuille'),
                child: IconButton(
                  icon: Icon(Icons.sync, color: job.parts[i].rotate && !job.grain ? scheme.primary : scheme.outlineVariant),
                  onPressed: job.grain
                      ? null
                      : () {
                          job.parts[i].rotate = !job.parts[i].rotate;
                          _changed(recalc: true);
                        },
                ),
              ),
            ),
            Expanded(
              child: TextFormField(
                key: ValueKey('${identityHashCode(job.parts[i])}-d'),
                initialValue: job.parts[i].desc,
                decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                onChanged: (v) {
                  job.parts[i].desc = v;
                  _changed(recalc: false);
                },
                onFieldSubmitted: (_) => _validateRow(i),
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 48,
              height: 38,
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.zero,
                  backgroundColor: (job.parts[i].length > 0 && job.parts[i].width > 0) ? scheme.primaryContainer : scheme.surfaceContainerHighest,
                ),
                onPressed: () => _validateRow(i),
                child: Text(tr('OK'), style: TextStyle(fontWeight: FontWeight.w800, color: (job.parts[i].length > 0 && job.parts[i].width > 0) ? scheme.onPrimaryContainer : scheme.onSurfaceVariant)),
              ),
            ),
            IconButton(
              tooltip: tr('Supprimer'),
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () {
                job.parts.removeAt(i);
                if (job.parts.isEmpty) job.parts.add(ManualPart());
                _changed(recalc: true);
              },
            ),
          ]),
        ),
      const SizedBox(height: Tokens.s2),
      Wrap(spacing: Tokens.s2, children: [
        OutlinedButton.icon(
          onPressed: () {
            job.parts.add(ManualPart());
            _changed(recalc: false);
          },
          icon: const Icon(Icons.add),
          label: Text(tr('Ajouter une pièce')),
        ),
        TextButton.icon(
          onPressed: () {
            job.parts
              ..clear()
              ..add(ManualPart());
            _changed(recalc: true);
          },
          icon: const Icon(Icons.clear_all),
          label: Text(tr('Tout effacer')),
        ),
      ]),
      const SizedBox(height: Tokens.s1),
      Text(tr('Chants : cliquez les traits à côté d’une cote (0, 1 ou 2 chants sur ce côté). Appuyez sur Entrée ou OK pour découper en temps réel.'), style: t.bodySmall),
    ]);

    Widget buildResults([bool compact = false]) {
      if (plan == null || plan.sheets.isEmpty) {
        return Container(
          padding: const EdgeInsets.all(Tokens.s5),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(Tokens.radius),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.content_cut, size: 48, color: scheme.primary.withValues(alpha: 0.5)),
                const SizedBox(height: Tokens.s2),
                Text(tr('Découpe en temps réel'), style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(tr('Saisissez les dimensions et cliquez sur OK ou Entrée : la feuille se découpe instantanément sous vos yeux.'), textAlign: TextAlign.center, style: t.bodySmall),
              ],
            ),
          ),
        );
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          children: [
            Expanded(child: Text(tr('Découpe en temps réel'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
              child: Text(
                trp('{0} % utilisé', [((plan.sheets.isEmpty ? 0.0 : plan.sheets.fold<double>(0.0, (a, s) => a + s.usage) / plan.sheets.length) * 100).toStringAsFixed(1)]),
                style: t.labelSmall?.copyWith(color: scheme.onPrimaryContainer, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: Tokens.s2),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            Text(trp('{0} feuille(s)', [plan.sheets.length]), style: t.labelMedium),
            Text('•', style: t.labelMedium),
            Text(trp('{0} pièces', [plan.partCount]), style: t.labelMedium),
            Text('•', style: t.labelMedium),
            Text(trp('Coupes : {0} m', [plan.cutLength.toStringAsFixed(2)]), style: t.labelMedium),
            Text('•', style: t.labelMedium),
            Text(trp('Chant : {0} m', [plan.edgeLength(job.material).toStringAsFixed(2)]), style: t.labelMedium),
          ],
        ),
        if (plan.notPlaced.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFFFFEBE6), borderRadius: BorderRadius.circular(6)),
            child: Text(trp('Attention : {0} pièce(s) trop grande(s) pour la feuille !', [plan.notPlaced.length]),
                style: const TextStyle(color: Color(0xFFD32F2F), fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
        const SizedBox(height: Tokens.s3),
        Wrap(
          spacing: Tokens.s4,
          runSpacing: Tokens.s4,
          children: [
            for (final s in plan.sheets)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: compact ? 340 : 420,
                    height: (compact ? 340 : 420) * (s.length / s.width).clamp(0.4, 2.5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: scheme.outlineVariant, width: 1.5),
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: CustomPaint(painter: _SheetPainter(s)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    trp('Feuille {0} ({1} × {2} mm) · {3} % utilisé · {4} pièces',
                        [s.number, s.width, s.length, (s.usage * 100).toStringAsFixed(1), s.placements.length]),
                    style: t.labelMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
          ],
        ),
      ]);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Débitage en temps réel')),
        actions: [
          TextButton.icon(onPressed: _open, icon: const Icon(Icons.file_open_outlined), label: Text(tr('Ouvrir .sct / kitchinox'))),
          const SizedBox(width: Tokens.s2),
          FilledButton.icon(onPressed: _calc, icon: const Icon(Icons.calculate_outlined), label: Text(tr('Recalculer'))),
          const SizedBox(width: Tokens.s2),
          OutlinedButton.icon(
              onPressed: _busy ? null : _pdf, icon: const Icon(Icons.picture_as_pdf_outlined), label: Text(tr('Plan de coupe (PDF)'))),
          const SizedBox(width: Tokens.s2),
          OutlinedButton.icon(onPressed: _sct, icon: const Icon(Icons.content_cut), label: Text(tr('Fichier .sct'))),
          const SizedBox(width: Tokens.s4),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 960;
          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: math.min(620, constraints.maxWidth * 0.52),
                  child: ListView(
                    key: ValueKey(_gen),
                    padding: const EdgeInsets.all(Tokens.s5),
                    children: [
                      settings,
                      const Divider(height: Tokens.s6),
                      table,
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(Tokens.s5),
                    children: [
                      buildResults(false),
                    ],
                  ),
                ),
              ],
            );
          }
          return ListView(
            key: ValueKey(_gen),
            padding: const EdgeInsets.all(Tokens.s5),
            children: [
              settings,
              const Divider(height: Tokens.s6),
              table,
              const Divider(height: Tokens.s6),
              buildResults(true),
            ],
          );
        },
      ),
    );
  }
}

class _SheetPainter extends CustomPainter {
  final CutSheet sheet;
  _SheetPainter(this.sheet);
  @override
  void paint(Canvas c, Size size) => paintSawSheet(c, size, sheet);
  @override
  bool shouldRepaint(_SheetPainter o) => !identical(o.sheet, sheet);
}
