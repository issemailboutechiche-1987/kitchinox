// Plinthe : comme les façades, comme le plan de travail, ou une autre matière ; gardée dans le projet.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/finishes.dart';
import 'package:kitchen_planner/ui/scene_export.dart';
import 'package:kitchen_planner/ui/textures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());

  testWidgets('plinthe : matière au choix, en 3D, au récapitulatif et dans le fichier', (t) async {
    final st = AppState(cat, project: Project(room: Room(width: 3600, depth: 3000, height: 2600)));
    st.engine.add('base_standard_single_door', 'A', s: 0, width: 600);
    st.project.style.front = 'vert_foret';
    await t.runAsync(() async {
      await TextureBank.instance.init();
      Future<Map> plinthMat() async {
        final sc = await SceneExporter().build(st);
        // la plinthe : volume sans meuble, posé au sol, sous les caissons
        return ((sc['solids'] as List).firstWhere((s) => s['uid'] == null && s['top'] != true && (s['z0'] as num) == 0 && (s['z1'] as num) < 200) as Map)['mat'] as Map;
      }

      final def = await plinthMat();
      st.edit(() => st.project.style.plinth = 'plan');
      final plan = await plinthMat();
      expect(plan, isNot(def), reason: 'la plinthe prend la matière du plan de travail');
      expect(plinthFinish(st.project.style)!.id, st.project.style.worktop);
      st.edit(() => st.project.style.plinth = 'alu');
      expect(((await plinthMat())['metal'] as num?) ?? 0, greaterThan(0.5));
      st.edit(() => st.project.style.plinth = 'f:chene');
      expect(plinthFinish(st.project.style)!.id, 'chene');
    });
    expect(st.bom.lines.firstWhere((l) => l.ref == 'plinth').details, contains('chene'));
    expect(KitchenStyle.fromJson(st.project.style.toJson()).plinth, 'f:chene');
  });
}
