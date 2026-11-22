// Non-régression du débit : l'optimisation de la vitesse ne doit pas changer le calepinage.
// La référence (test/data/nest_reference.txt) : algorithme d'origine, tris rendus stables (comme le navigateur).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/tech_drawings.dart';

import 'perf_bench_test.dart' show stress;

String signature(CutPlan plan) {
  final b = StringBuffer('feuilles ${plan.sheets.length} refusées ${plan.notPlaced.length}\n');
  for (final s in plan.sheets) {
    b.writeln('#${s.number} ${s.material} ${s.strips} ${s.cutLen.round()}');
    for (final p in s.placements) {
      b.writeln('  ${p.part.key} ${p.index} ${p.x.round()} ${p.y.round()} ${p.dx}x${p.dy} ${p.rotated}');
    }
  }
  return b.toString();
}

void main() {
  test('débit identique à la référence (scie à panneaux, 3 méthodes, CNC)', () {
    final st = stress();
    final e = st.engine;
    // la référence débite caissons et façades dans la même feuille : on garde son jeu de pièces pour juger l'algorithme
    final parts = [
      for (final p in cutList(e, st.project.cut, repereNumbers(e)))
        CutPart(p.material.replaceAll(' (façades)', ''), p.name, p.cabinet, p.length, p.width, p.qty,
            canRotate: p.canRotate, edgeLong: p.edgeLong, edgeShort: p.edgeShort, grooveLong: p.grooveLong, grooveShort: p.grooveShort)
    ];
    final out = StringBuffer();
    final counts = <int, int>{};
    for (final m in [1, 2, 3]) {
      final cs = CutSettings.fromJson(st.project.cut.toJson())..method = m;
      final sw = Stopwatch()..start();
      final plan = nest(parts, cs);
      // ignore: avoid_print
      print('méthode $m : ${sw.elapsedMilliseconds} ms, ${plan.sheets.length} feuilles');
      counts[m] = plan.sheets.length;
      out.writeln('== méthode $m');
      out.write(signature(plan));
    }
    // « optimale » ne fait jamais moins bien que « par longueur » ou « par largeur »
    expect(counts[3]!, lessThanOrEqualTo(counts[1]!));
    expect(counts[3]!, lessThanOrEqualTo(counts[2]!));
    final cnc = CutSettings.fromJson(st.project.cut.toJson())..machine = 'cnc';
    out.writeln('== cnc');
    out.write(signature(nest(parts, cnc)));
    final ref = File('test/data/nest_reference.txt');
    if (!ref.existsSync()) {
      ref.writeAsStringSync(out.toString());
      return;
    }
    expect(out.toString(), ref.readAsStringSync());
  });

  test("tri stable : à égalité, l'ordre d'arrivée est gardé (même résultat qu'un navigateur)", () {
    for (final n in [0, 1, 2, 15, 16, 17, 33, 100, 1000]) {
      final items = [for (var i = 0; i < n; i++) ((i * 7919) % 13, i)];
      final mine = [...items]..stableSort((a, b) => a.$1.compareTo(b.$1));
      // référence : tri par (clé, rang d'arrivée), sans égalité possible
      final ref = [...items]..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
      expect(mine, ref, reason: 'n = $n');
    }
  });

  test('calcul hors du fil de l\'interface : même plan après l\'aller-retour JSON (Worker / Isolate)', () {
    final st = stress();
    final parts = cutList(st.engine, st.project.cut, repereNumbers(st.engine));
    final direct = nest(parts, st.project.cut);
    final res = jsonDecode(nestJob(nestRequest(7, parts, st.project.cut))) as Map<String, dynamic>;
    expect(res['id'], 7);
    final back = nestFromResponse(res, parts, st.project.cut);
    expect(signature(back), signature(direct));
    expect(back.sheets.first.remnants, direct.sheets.first.remnants);
    expect(back.cutLength, direct.cutLength);
  });

  test('état de l\'app : débit en arrière-plan, ancien plan affiché, puis mise à jour ; rien pendant un glisser', () async {
    AppState.backgroundNest = true;
    addTearDown(() => AppState.backgroundNest = false);
    final st = stress();
    var notified = 0;
    st.addListener(() => notified++);
    final sw = Stopwatch()..start();
    final first = st.cutPlan; // pas encore calculé : plan vide, immédiatement
    expect(sw.elapsedMilliseconds, lessThan(200));
    expect(st.cutPending, isTrue);
    expect(first.sheets, isEmpty);
    final ready = await st.cutPlanReady();
    expect(st.cutPending, isFalse);
    expect(ready.sheets, isNotEmpty);
    expect(identical(st.cutPlan, ready), isTrue);
    expect(notified, greaterThan(0));
    // glisser : le débit attend la fin du geste
    final c = st.project.items.firstWhere((c) => c.wallId == 'A');
    st.beginDrag();
    c.height -= 20;
    st.refresh();
    expect(identical(st.cutPlan, ready), isTrue, reason: 'pendant le geste, le plan affiché ne change pas');
    st.endDrag();
    final after = await st.cutPlanReady();
    expect(after.sheets, isNotEmpty);
    expect(PerformanceProfiler.instance.stats['nesting']!.count, greaterThan(0));
    final diag = jsonDecode(PerformanceProfiler.instance.exportJson()) as Map<String, dynamic>;
    expect((diag['stats'] as Map).containsKey('nesting'), isTrue);
  });
}
