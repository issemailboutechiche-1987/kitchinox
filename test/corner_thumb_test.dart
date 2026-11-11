// Vignettes des meubles d'angle (vue de dessus) : capture de contrôle.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/fronts.dart';

void main() {
  final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());
  testWidgets('vignettes d\'angle', (t) async {
    final models = cat.models.where((m) => m.kind.isCorner).toList();
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Wrap(children: [
          for (final m in models)
            Container(
              width: 140,
              height: 140,
              margin: const EdgeInsets.all(8),
              color: const Color(0xFFEFF1F0),
              child: FrontThumb(model: m, fill: const Color(0xFFF4F3EF), stroke: const Color(0xFFB9B5A8), line: const Color(0xFF8E8A7F)),
            ),
        ]),
      ),
    ));
    await expectLater(find.byType(Wrap), matchesGoldenFile('goldens/12_angles.png'));
  });
}
