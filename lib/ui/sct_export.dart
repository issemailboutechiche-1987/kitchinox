// Export SketchCut PRO (.sct) : un fichier par type de panneau (caissons, façades, fonds, tiroirs), avec son
// format de feuille et son épaisseur. On choisit lesquels exporter. Commun à tous les modes.
import 'dart:convert';

import 'package:flutter/material.dart';

import '../engine/engine.dart';
import 'excel_export.dart';
import 'i18n.dart';
import 'theme.dart';
import 'web_io.dart';

/// Un fichier .sct : une matière débitée.
class SctFile {
  final String material;
  final PanelKind kind;
  final String title; // type de panneau affiché
  final String fileName;
  final List<int> bytes;
  String get content => utf8.decode(bytes, allowMalformed: true);
  final (int, int) sheet;
  final int thickness, parts, sheets;
  const SctFile(this.material, this.kind, this.title, this.fileName, this.bytes, this.sheet, this.thickness, this.parts, this.sheets);
}

String _safe(String s) {
  const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿ', to = 'aaaaaaceeeeiiiinooooouuuuyy';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = from.indexOf(ch.toLowerCase());
    b.write(i < 0 ? ch : to[i]);
  }
  return b.toString().replaceAll(RegExp(r'[^A-Za-z0-9؀-ۿ]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
}

/// Nom affiché d'un type de panneau.
String panelTitle(PanelKind kind) => switch (kind) {
      PanelKind.carcass => tr('Caissons (corps de meuble)'),
      PanelKind.front => tr('Façades (portes et tiroirs)'),
      PanelKind.back => tr('Fonds (dos)'),
      PanelKind.drawer => tr('Tiroirs (fond et dos)'),
    };

String _panelKey(PanelKind kind) => switch (kind) {
      PanelKind.carcass => 'Caissons',
      PanelKind.front => 'Facades',
      PanelKind.back => 'Fonds',
      PanelKind.drawer => 'Tiroirs',
    };

/// Classeurs Excel : un par panneau, dans le même ordre que les .sct.
List<SctFile> excelFiles(CutPlan plan, {required String name, required Project project}) {
  final cs = plan.settings;
  final out = <SctFile>[];
  for (final mat in plan.materials) {
    final kind = cs.panelKind(mat), t = cs.thicknessFor(mat), sheet = cs.sheetDimensionsFor(mat), key = _panelKey(kind);
    out.add(SctFile(
      mat,
      kind,
      panelTitle(kind),
      '${_safe(name)}_${key}_${_safe(mat)}_${sheet.$1}x${sheet.$2}_${t}mm.xlsx',
      buildExcelExport(plan, project: project, order: '${name}_$key', material: mat),
      sheet,
      t,
      plan.parts.where((p) => p.material == mat).fold<int>(0, (a, p) => a + p.qty),
      plan.newSheets(mat).length,
    ));
  }
  return out..stableSort((a, b) => a.kind.index.compareTo(b.kind.index));
}

/// Fichiers à exporter pour [plan], dans l'ordre caissons, façades, fonds, tiroirs.
List<SctFile> sctFiles(CutPlan plan, {required String name}) {
  final cs = plan.settings;
  final out = <SctFile>[];
  for (final mat in plan.materials) {
    final kind = cs.panelKind(mat);
    final title = panelTitle(kind);
    final key = _panelKey(kind);
    final sheet = cs.sheetDimensionsFor(mat);
    final t = cs.thicknessFor(mat);
    int count(List<CutPart> l) => l.fold<int>(0, (a, p) => a + p.qty);
    for (final s in plan.stockSheets(mat)) {
      out.add(SctFile(
        mat,
        kind,
        trp('Chute {0}', [s.stockId]),
        '${_safe(name)}_Chute_${_safe(s.stockId!)}_${s.length}x${s.width}_${t}mm.sct',
        utf8.encode(toSct(plan, mat, order: '${name}_${s.stockId}', thickness: '$t', offcut: s)),
        (s.length, s.width),
        t,
        count(sctParts(plan, mat, offcut: s)),
        1,
      ));
    }
    if (sctParts(plan, mat).isEmpty) continue; // tout tient dans les chutes
    out.add(SctFile(
      mat,
      kind,
      title,
      '${_safe(name)}_${key}_${_safe(mat)}_${sheet.$1}x${sheet.$2}_${t}mm.sct',
      utf8.encode(toSct(plan, mat, order: '${name}_$key', thickness: '$t')),
      sheet,
      t,
      count(sctParts(plan, mat)),
      plan.newSheets(mat).length,
    ));
  }
  return out..sort((a, b) => a.kind.index.compareTo(b.kind.index));
}

/// Choix des panneaux puis écriture des fichiers (dossier Kitchinox/export sur iPad, téléchargements sur le web).
/// Renvoie le message à afficher, ou null si l'utilisateur annule.
Future<String?> exportSctFiles(BuildContext context, CutPlan plan, {required String name}) =>
    exportPanelFiles(context, sctFiles(plan, name: name), title: 'Export SketchCut PRO (.sct)');

/// Le choix des panneaux, commun aux fichiers .sct et Excel.
Future<String?> exportPanelFiles(BuildContext context, List<SctFile> files, {required String title}) async {
  if (files.isEmpty) return tr('Aucune pièce à débiter');
  final chosen = {...files};
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) {
        final t = Theme.of(ctx).textTheme;
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: Row(children: [
            Icon(Icons.content_cut, color: scheme.primary),
            const SizedBox(width: Tokens.s2),
            Expanded(child: Text(tr(title))),
          ]),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(tr('Un fichier par type de panneau. Choisissez ceux à exporter :'), style: t.bodyMedium),
                Wrap(alignment: WrapAlignment.end, children: [
                  TextButton(onPressed: () => setD(() => chosen.addAll(files)), child: Text(tr('Tout cocher'))),
                  TextButton(onPressed: () => setD(chosen.clear), child: Text(tr('Tout décocher'))),
                ]),
                for (final f in files)
                  CheckboxListTile(
                    key: ValueKey(f.title.startsWith(tr('Chute')) ? 'sct_${f.fileName}' : 'sct_${f.material}'),
                    value: chosen.contains(f),
                    onChanged: (v) => setD(() => v == true ? chosen.add(f) : chosen.remove(f)),
                    secondary: Icon(
                        switch (f.kind) {
                          PanelKind.carcass => Icons.kitchen_outlined,
                          PanelKind.front => Icons.door_front_door_outlined,
                          PanelKind.back => Icons.flip_to_back,
                          PanelKind.drawer => Icons.inbox_outlined,
                        },
                        color: scheme.primary),
                    title: Text(f.title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    subtitle: Text('${tr(f.material)} · ${f.sheet.$1} × ${f.sheet.$2} × ${f.thickness} mm\n${trp('{0} pièce(s) · {1} feuille(s)', [f.parts, f.sheets])}'),
                    isThreeLine: true,
                  ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Annuler'))),
            FilledButton.icon(
              key: const ValueKey('sct_export'),
              icon: const Icon(Icons.download, size: 18),
              onPressed: chosen.isEmpty ? null : () => Navigator.pop(ctx, true),
              label: Text(trp('Exporter {0} fichier(s)', [chosen.length])),
            ),
          ],
        );
      },
    ),
  );
  if (ok != true) return null;
  String? path;
  for (final f in files.where(chosen.contains)) {
    path = await saveToKitchinox(f.fileName, f.bytes);
  }
  return path == null ? trp('{0} fichier(s) exporté(s)', [chosen.length]) : trp('{0} fichier(s) enregistré(s) dans Kitchinox/export', [chosen.length]);
}
