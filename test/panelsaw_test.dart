// Débit pour scie à panneaux : bandes sur toute la longueur, tronçons, recoupes.
// Référence : le placard de l'atelier optimisé par SketchCut (22 pièces → 4 feuilles 2800 x 2100).
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

void main() {
  final cs = CutSettings(); // 2800 x 2100, trait 4, recoupe 4, méthode 1 (par longueur)
  // chants du placard d'après le PDF SketchCut (soulignements : 1 ou 2 côtés)
  CutPart p(String name, int l, int w, int q, [int el = 0, int es = 0]) =>
      CutPart('MDF', name, 'placard', l, w, q, canRotate: false, edgeLong: el, edgeShort: es);
  final placard = [
    p('COTES', 2400, 600, 2, 1, 2),
    p('BAS HAUT', 1344, 600, 2),
    p('CENTRAL', 2400, 520, 1, 1),
    p('ETAGERE', 662, 520, 6, 1),
    p('TIROIRES', 518, 325, 3, 2, 2),
    p('PORTES', 2360, 705, 2),
    p('BAS', 1360, 98, 1),
    p('BAS LATERAL', 560, 98, 2),
    p('CACHE RAIL', 1344, 700, 1),
    p('PORTES 2', 2175, 667, 2),
  ];

  /// Vérifie qu'une feuille se coupe à la scie : bandes disjointes sur toute la longueur,
  /// pièces dans la feuille utile, sans chevauchement et séparées d'au moins un trait de scie.
  void checkPanelSaw(CutPlan plan) {
    for (final s in plan.sheets) {
      final ps = s.placements;
      for (final a in ps) {
        expect(a.x >= cs.trim - 0.01 && a.y >= cs.trim - 0.01, isTrue);
        expect(a.x + a.dx <= s.length - cs.trim + 0.01 && a.y + a.dy <= s.width - cs.trim + 0.01, isTrue, reason: 'hors feuille');
        for (final b in ps) {
          if (identical(a, b)) continue;
          final sepX = a.x + a.dx + cs.kerf <= b.x + 0.01 || b.x + b.dx + cs.kerf <= a.x + 0.01;
          final sepY = a.y + a.dy + cs.kerf <= b.y + 0.01 || b.y + b.dy + cs.kerf <= a.y + 0.01;
          expect(sepX || sepY, isTrue, reason: 'pièces trop proches');
        }
      }
      // bandes : intervalles en Y fusionnés ; aucune pièce ne chevauche deux bandes
      final ys = [for (final a in ps) (a.y, a.y + a.dy)]..sort((x, y) => x.$1.compareTo(y.$1));
      final bands = <(double, double)>[];
      for (final (y0, y1) in ys) {
        if (bands.isNotEmpty && y0 < bands.last.$2 - 0.01) {
          bands[bands.length - 1] = (bands.last.$1, y1 > bands.last.$2 ? y1 : bands.last.$2);
        } else {
          bands.add((y0, y1));
        }
      }
      expect(s.strips, greaterThan(0));
      expect(bands.length, lessThanOrEqualTo(s.strips));
    }
  }

  test('placard de l\'atelier : 4 feuilles comme SketchCut, sans rotation, coupes de scie', () {
    final plan = nest(placard, cs);
    expect(plan.notPlaced, isEmpty);
    expect(plan.sheets.length, lessThanOrEqualTo(4));
    expect(plan.sheets.expand((s) => s.placements).length, 22);
    expect(plan.sheets.expand((s) => s.placements).every((x) => !x.rotated), isTrue);
    checkPanelSaw(plan);
    // les portes de 705 partagent une bande de 705
    final doors = plan.sheets.expand((s) => s.placements).where((x) => x.part.name == 'PORTES').toList();
    expect(doors.every((d) => d.dx == 2360 && d.dy == 705), isTrue);
    expect(plan.cutLength, greaterThan(30));
    // ignore: avoid_print
    print('placard : ${plan.sheets.length} feuilles, coupes ${plan.cutLength.toStringAsFixed(2)} m, '
        'chutes ${plan.sheets.expand((s) => s.remnants).length}');
  });

  test('cuisine générée : débit scie valide ; la CNC reste disponible', () {
    final parts = [
      CutPart('MDF', 'Côté', 'bas', 750, 582, 14),
      CutPart('MDF', 'Dessus / dessous', 'bas', 564, 582, 14),
      CutPart('MDF', 'Porte', 'bas', 746, 596, 7),
      CutPart('MDF', 'Façade tiroir', 'bas', 596, 146, 6),
      CutPart('MDF', 'Côté', 'colonne', 2200, 582, 2),
      CutPart('MDF', 'Fileur', 'fileur', 750, 50, 3),
    ];
    final saw = nest(parts, cs);
    expect(saw.notPlaced, isEmpty);
    checkPanelSaw(saw);
    final cnc = nest(parts, CutSettings(machine: 'cnc'));
    expect(cnc.sheets.length, lessThanOrEqualTo(saw.sheets.length));
  });

  testWidgets('PDF du placard au format SketchCut', (t) async {
    await _loadFonts();
    final plan = nest(placard, cs);
    final e = LayoutEngine(Catalog('', 'mm', const []), Project(name: 'Placard'));
    await t.runAsync(() async {
      File('test/out/placard_decoupe.pdf').writeAsBytesSync(await buildCutPdf(e, plan, now: DateTime(2026, 11, 5), pixelRatio: 1.6));
    });
  });
}
