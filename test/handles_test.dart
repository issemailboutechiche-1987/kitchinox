// Poignées : par endroit, sens, place, devis, vraies poignées en 3D, menu ; curseurs des outils de l'atelier.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/engine/art_cad.dart';
import 'package:kitchen_planner/ui/art_cursors.dart';
import 'package:kitchen_planner/ui/finishes.dart';
import 'package:kitchen_planner/ui/panels.dart';
import 'package:kitchen_planner/ui/scene_export.dart';
import 'package:kitchen_planner/ui/theme.dart';
import 'package:kitchen_planner/ui/toolbar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  String f(String n) => File('assets/data/$n.json').readAsStringSync();
  AppState kitchen() {
    final db = MaterialsDb.parse(appliances: f('appliances'), worktops: f('worktops'), panels: f('panels'), hardware: f('hardware'), handles: f('handles'));
    final st = AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()), db: db);
    st.engine.applyShape(RoomShape.linear);
    st.engine.add('base_standard_2doors', 'A', s: 0, width: 800);
    st.engine.add('base_drawers_multi', 'A', s: 800, width: 900);
    st.engine.add('wall_standard_2doors', 'A', s: 0, width: 800);
    return st;
  }

  HandleModel model(AppState st, String id) => st.db!.handles.byId(id)!;
  List<SupplyLine> lines(AppState st) => handleLines(st.engine, st.db!, cutList(st.engine, st.project.cut, repereOf(st)));

  test('par endroit : hauts sans poignée, tiroirs différents, devis par modèle', () {
    final st = kitchen();
    st.setHandle(model(st, 'handle_tubular_t_bar'), size: 160);
    final all = lines(st).fold<double>(0, (a, l) => a + l.qty);
    expect(lines(st), hasLength(1));
    st.setHandle(HandleCatalog.push, zone: 'haut');
    st.setHandle(model(st, 'knob_round_mushroom'), zone: 'tiroir');
    final l = lines(st);
    expect(l.map((x) => x.name), containsAll([model(st, 'handle_tubular_t_bar').name, model(st, 'knob_round_mushroom').name]));
    expect(l.fold<double>(0, (a, x) => a + x.qty), all, reason: 'une poignée ou un loqueteau par façade');
    final look = handleSetOf(st.project.style, st.db!.handles, st.catalog['wall_standard_2doors']);
    expect((look.door.kind, look.drawer.kind), ('push', 'knob'));
    // relu, puis remis comme partout
    final back = KitchenStyle.fromJson(st.project.style.toJson());
    expect(back.handleAt('haut').kind, 'push');
    st.clearHandleZone('haut');
    expect(st.project.style.handleAt('haut').id, 'handle_tubular_t_bar');
    // profil Gola : il vaut pour les bas et les tiroirs
    st.setHandle(HandleCatalog.gola);
    expect(st.project.style.handleAt('tiroir').kind, 'gola');
    st.setHandle(HandleCatalog.push, zone: 'haut');
    expect(st.engine.golaOn(st.catalog['wall_standard_2doors']), isFalse);
    expect(st.engine.golaOn(st.catalog['base_standard_2doors']), isTrue);
  });

  test('deux poignées sur les tiroirs larges : comptées au devis', () {
    final st = kitchen();
    st.setHandle(model(st, 'handle_tubular_t_bar'));
    final one = lines(st).single.qty;
    st.editHandle((c) => c.pair = true);
    expect(lines(st).fold<double>(0, (a, l) => a + l.qty), one + 2, reason: 'deux tiroirs de 900');
  });

  testWidgets('3D : vraies poignées, au bon endroit', (t) async {
    await t.runAsync(() async {
      final st = kitchen();
      st.setHandle(model(st, 'handle_tubular_t_bar'), size: 160);
      List<Map> grips(Map sc, String uid) => [
            for (final fr in sc['fronts'] as List)
              if (fr['uid'] == uid)
                for (final p in fr['parts'] as List)
                  for (final g in (p['grips'] as List? ?? const [])) g as Map
          ];
      final base = st.project.items[0], drawers = st.project.items[1];
      var sc = await SceneExporter().build(st);
      expect(grips(sc, base.uid), hasLength(2));
      expect(grips(sc, base.uid).every((g) => g['k'] == 'bar' && g['v'] == true && (g['y'] as double) < 300), isTrue, reason: 'bas : en haut de la porte');
      expect(grips(sc, drawers.uid), hasLength(2));
      st.editHandle((c) => c
        ..orient = 'h'
        ..pair = true);
      sc = await SceneExporter().build(st);
      expect(grips(sc, base.uid).every((g) => g['v'] == false), isTrue);
      expect(grips(sc, drawers.uid), hasLength(4));
      st.setHandle(HandleCatalog.push);
      sc = await SceneExporter().build(st);
      expect(grips(sc, base.uid), isEmpty);
    });
  });

  testWidgets('menu : endroit, famille, carte dessinée, finition, sens', (t) async {
    t.view.physicalSize = const Size(700, 2200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final st = kitchen();
    await t.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light, googleFonts: false),
        home: Scaffold(body: SizedBox(width: 420, child: ListenableBuilder(listenable: st, builder: (_, _) => StylePanel(state: st, section: StyleSection.handles))))));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('handle_preview')), findsOneWidget);
    await t.tap(find.text('Boutons'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('handle_knob_round_mushroom')));
    await t.pumpAndSettle();
    expect(st.project.style.handle, 'knob');
    await t.tap(find.byKey(const ValueKey('handle_finish_Laiton brossé')));
    await t.pumpAndSettle();
    expect(st.project.style.handleFinish, 'Laiton brossé');
    await t.tap(find.text('Meubles hauts'));
    await t.pumpAndSettle();
    await t.tap(find.text('Sans poignée'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('handle_push')));
    await t.pumpAndSettle();
    expect(st.project.style.handleAt('haut').kind, 'push');
    expect(st.project.style.handle, 'knob');
    await t.tap(find.byKey(const ValueKey('handle_like_all')));
    await t.pumpAndSettle();
    expect(st.project.style.handleByZone, isEmpty);
    await t.tap(find.text('Partout'));
    await t.pumpAndSettle();
    await t.tap(find.text('Barres'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('handle_handle_tubular_t_bar')));
    await t.pumpAndSettle();
    await t.tap(find.text('Horizontale'));
    await t.pumpAndSettle();
    expect(st.project.style.handleOrient, 'h');
    expect(t.takeException(), isNull);
    await expectLater(find.byType(StylePanel), matchesGoldenFile('goldens/poignees_menu.png'));
  });

  testWidgets('curseurs des outils : lame, perceuse, rouleau de chant, rainure', (t) async {
    t.view.physicalSize = const Size(560, 260);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    const tools = [CadTool.cut, CadTool.drill, CadTool.edgeBand, CadTool.groove];
    expect(tools.every(hasToolGlyph), isTrue);
    expect(hasToolGlyph(CadTool.select), isFalse);
    await t.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
            body: Column(children: [
          Row(children: [for (final x in tools) Padding(padding: const EdgeInsets.all(10), child: ToolGlyph(x, size: 110, color: Colors.black, paper: Colors.white))]),
          Expanded(
              child: Container(
                  color: const Color(0xFFDCC7A3),
                  child: CustomPaint(
                      size: Size.infinite,
                      painter: _Cursors(tools)))),
        ]))));
    expect(t.takeException(), isNull);
    await expectLater(find.byType(Scaffold), matchesGoldenFile('goldens/art_curseurs.png'));
  });
}

Map<String, int> repereOf(AppState st) => {for (var i = 0; i < st.project.items.length; i++) st.project.items[i].uid: i + 1};

class _Cursors extends CustomPainter {
  final List<CadTool> tools;
  _Cursors(this.tools);
  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < tools.length; i++) {
      ToolCursorPainter(tools[i], Offset(50.0 + i * 65, 90)).paint(canvas, size);
      ToolCursorPainter(tools[i], Offset(320.0 + i * 60, 110), touch: true).paint(canvas, size);
    }
  }

  @override
  bool shouldRepaint(_Cursors o) => false;
}
