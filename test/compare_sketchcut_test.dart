// Jeu d'essai « 2 feuilles MDF » pour comparer kitchinox et SketchCut :
// écrit le fichier SketchCut (.sct) des pièces et le plan de coupe kitchinox (PDF + résumé).
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/cut_pdf.dart';

Future<void> _loadFonts() async {
  final flutterRoot = File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.parent.path;
  final dir = '$flutterRoot/bin/cache/artifacts/material_fonts';
  final l = FontLoader('Roboto');
  for (final f in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']) {
    l.addFont(Future.value(ByteData.sublistView(File('$dir/$f').readAsBytesSync())));
  }
  await l.load();
}

/// Une petite cuisine mélangée : bas, hauts, colonne, tiroirs, façades, fileurs (MDF 18).
final essai = [
  CutPart('MDF 18', 'Côté colonne', 'colonne', 2000, 582, 2, edgeLong: 1),
  CutPart('MDF 18', 'Côté bas', 'bas', 720, 562, 6, edgeLong: 1),
  CutPart('MDF 18', 'Dessus / dessous bas', 'bas', 564, 562, 6, edgeLong: 1),
  CutPart('MDF 18', 'Côté haut', 'haut', 700, 320, 4, edgeLong: 1),
  CutPart('MDF 18', 'Dessus / dessous haut', 'haut', 564, 320, 4, edgeLong: 1),
  CutPart('MDF 18', 'Porte', 'bas', 716, 596, 3, edgeLong: 2, edgeShort: 2),
  CutPart('MDF 18', 'Porte', 'haut', 696, 396, 2, edgeLong: 2, edgeShort: 2),
  CutPart('MDF 18', 'Façade tiroir', 'bas', 596, 236, 3, edgeLong: 2, edgeShort: 2),
  CutPart('MDF 18', 'Avant / arrière tiroir', 'bas', 524, 150, 4, edgeLong: 1),
  CutPart('MDF 18', 'Fileur', 'fileur', 720, 60, 2, edgeLong: 1),
];

void main() {
  testWidgets('essai 2 feuilles : fichier SketchCut + plan kitchinox', (t) async {
    await _loadFonts();
    final cs = CutSettings(); // 2800 x 2100, trait 4, recoupe 4, par longueur, scie à panneaux
    final plan = nest(essai, cs);
    final out = Directory('D:/kitchinox/comparaison')..createSync(recursive: true);
    File('${out.path}/essai_2_feuilles.sct').writeAsStringSync(toSct(plan, 'MDF 18', order: 'essai 2 feuilles', date: DateTime(2026, 11, 6)));
    final b = StringBuffer('Essai 2 feuilles MDF 2800 x 2100, trait 4, recoupe 4, méthode par longueur\r\n\r\nPièces :\r\n');
    for (final p in essai) {
      b.write('  ${p.qty} x ${p.length} x ${p.width}  ${p.name} (${p.cabinet})\r\n');
    }
    b.write('\r\nRésultat kitchinox : ${plan.sheets.length} feuille(s), pièces non placées : ${plan.notPlaced.length}\r\n');
    for (final s in plan.sheets) {
      b.write('  feuille ${s.number} : ${(s.usage * 100).toStringAsFixed(1)} %, ${s.strips} bandes, coupe ${(s.cutLen / 1000).toStringAsFixed(2)} m\r\n');
    }
    File('${out.path}/essai_2_feuilles_resume.txt').writeAsStringSync('﻿${b.toString()}');
    final e = LayoutEngine(Catalog('', 'mm', const []), Project(name: 'Essai 2 feuilles'));
    await t.runAsync(() async {
      File('${out.path}/essai_2_feuilles_kitchinox.pdf').writeAsBytesSync(await buildCutPdf(e, plan, now: DateTime(2026, 11, 6), pixelRatio: 1.6));
    });
    expect(plan.notPlaced, isEmpty);
  });
}
