// Banc de mesure : chaque calcul de l'application chronométré sur une grande cuisine (stress test).
// Résultats dans test/out/perf_bench.json.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/cut_pdf.dart';
import 'package:kitchen_planner/ui/pdf_export.dart';
import 'package:kitchen_planner/ui/scene_export.dart';
import 'package:kitchen_planner/ui/tech_drawings.dart';

MaterialsDb db() {
  String f(String n) => File('assets/data/$n.json').readAsStringSync();
  return MaterialsDb.parse(appliances: f('appliances'), worktops: f('worktops'), panels: f('panels'), hardware: f('hardware'), handles: f('handles'));
}

/// Grande cuisine en U avec îlot, hauts et colonnes partout où c'est possible.
AppState stress() {
  final st = AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()), db: db());
  st.updateRoom(width: 6000, depth: 5000);
  st.engine.applyShape(RoomShape.uShape);
  for (final w in ['A', 'B', 'C']) {
    st.engine.autoFillWall(w, Band.low);
  }
  for (final w in ['A', 'B', 'C']) {
    st.engine.autoFillWall(w, Band.high);
  }
  final isl = st.engine.bestIslandSpot();
  if (isl != null) {
    st.project.room.island = isl;
    st.engine.autoFillWall('I', Band.low);
  }
  st.project.networks = true;
  applyNetworks(st.engine);
  st.refresh();
  return st;
}

double ms(Stopwatch s) => s.elapsedMicroseconds / 1000;

/// Durée moyenne (ms) de [f] sur [n] répétitions, après un échauffement.
double time(void Function() f, {int n = 5}) {
  f();
  final s = Stopwatch()..start();
  for (var i = 0; i < n; i++) {
    f();
  }
  return ms(s) / n;
}

void main() {
  testWidgets('banc de mesure', (t) async {
    final st = stress();
    final e = st.engine;
    final parts = cutList(e, st.project.cut, repereNumbers(e));
    final out = <String, Object>{
      'caissons': st.project.items.length,
      'pieces_debit': parts.fold<int>(0, (a, p) => a + p.qty),
      'pieces_distinctes': parts.length,
    };
    final catJson = File('assets/catalog.json').readAsStringSync();
    out['catalogue_json_kb'] = catJson.length ~/ 1024;
    out['catalogue_parse_ms'] = time(() => Catalog.parse(catJson), n: 3);
    out['materiaux_parse_ms'] = time(db, n: 3);
    out['fingerprint_ms'] = time(() => st.fingerprint);
    out['snapshot_json_ms'] = time(() => jsonEncode(st.project.toJson()));
    out['validate_ms'] = time(() => e.validate());
    out['issues_total_ms'] = time(() => [
          ...e.validate(),
          ...applianceChecks(e, st.db!),
          ...networkChecks(e),
          ...openingChecks(e),
          ...accessChecks(e),
          ...objectChecks(e),
          ...sizeChecks(e),
          ...designChecks(e),
          ...waterChecks(e),
        ]);
    out['access_ms'] = time(() => accessChecks(e));
    out['appliance_ms'] = time(() => applianceChecks(e, st.db!));
    out['network_checks_ms'] = time(() => networkChecks(e));
    out['opening_ms'] = time(() => openingChecks(e));
    out['object_ms'] = time(() => objectChecks(e));
    out['size_ms'] = time(() => sizeChecks(e));
    out['water_ms'] = time(() => waterChecks(e));
    out['design_ms'] = time(() => designChecks(e));
    out['networks_ms'] = time(() => generateNetworks(e));
    out['cutlist_ms'] = time(() => cutList(e, st.project.cut, repereNumbers(e)));
    out['nest_strips_ms'] = time(() => nest(parts, st.project.cut), n: 3);
    final cnc = CutSettings.fromJson(st.project.cut.toJson())..machine = 'cnc';
    out['nest_cnc_ms'] = time(() => nest(parts, cnc), n: 3);
    out['feuilles'] = nest(parts, st.project.cut).sheets.length;
    out['bom_ms'] = time(() => buildBom(e));
    out['estimate_ms'] = time(() => estimate(e, st.db!, st.project.specs, st.cutPlan, st.bom));
    // un « cadre » de l'interface : ce que lit l'écran à chaque reconstruction (issues, débit, devis)
    out['frame_reads_cached_ms'] = time(() {
      st.issues;
      st.cutPlan;
      st.bom;
      st.estimateLines;
    }, n: 20);
    // glisser un caisson : un pas de déplacement + relecture
    final c = st.project.items.firstWhere((c) => c.wallId == 'A' && e.modelOf(c).kind.isLow);
    st.beginDrag();
    var k = 0;
    out['drag_step_ms'] = time(() {
      st.dragTo(c.uid, s: c.s + ((k++).isEven ? 1 : -1));
      st.issues;
      st.cutPlan;
      st.estimateLines;
    }, n: 10);
    st.endDrag();
    // fichiers
    final sw = Stopwatch()..start();
    final scene = await t.runAsync(() => SceneExporter().build(st));
    out['scene3d_ms'] = ms(sw);
    out['scene3d_kb'] = jsonEncode(scene).length ~/ 1024;
    sw
      ..reset()
      ..start();
    final pdf = await t.runAsync(() => buildExecutionPdf(e, now: DateTime(2026, 11, 9), pixelRatio: 1.6, db: st.db));
    out['pdf_execution_ms'] = ms(sw);
    out['pdf_execution_kb'] = pdf!.length ~/ 1024;
    sw
      ..reset()
      ..start();
    final cut = await t.runAsync(() => buildCutPdf(e, st.cutPlan, now: DateTime(2026, 11, 9), pixelRatio: 1.6, db: st.db));
    out['pdf_debit_ms'] = ms(sw);
    out['pdf_debit_kb'] = cut!.length ~/ 1024;
    File('test/out/stress_debit.pdf').writeAsBytesSync(cut);
    out['profiler'] = PerformanceProfiler.instance.toJson()['stats']!;
    out['rss_mb'] = ProcessInfo.currentRss ~/ (1024 * 1024);
    out['rss_max_mb'] = ProcessInfo.maxRss ~/ (1024 * 1024);
    final js = const JsonEncoder.withIndent('  ').convert(out);
    // ignore: avoid_print
    print(js);
    Directory('test/out').createSync(recursive: true);
    File('test/out/perf_bench.json').writeAsStringSync(js);
  });
}
