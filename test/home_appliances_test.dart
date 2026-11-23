// Buanderie : chauffe-eau, lave-linge et sèche-linge par forme et capacité.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/objects_panel.dart';
import 'package:kitchen_planner/ui/panels.dart';
import 'package:kitchen_planner/ui/scene_export.dart';
import 'package:kitchen_planner/ui/textures.dart';
import 'package:kitchen_planner/ui/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  String f(String n) => File('assets/data/$n.json').readAsStringSync();
  AppState laundry() {
    final u = FurnitureUniverse.parse('buanderie', f('furniture/buanderie'));
    return AppState(universeCatalog(u), project: Project(universe: 'buanderie', room: Room(width: 3800, depth: 3200, height: 2600)))..objectCatalog = CatalogObject.parse(f('objects'));
  }

  test('catalogue : formes et capacités, cotes et prix cohérents', () {
    expect(homeAppliances.where(isHeater).length, greaterThanOrEqualTo(9));
    expect(homeAppliances.where(isWashAppliance).length, greaterThanOrEqualTo(12));
    for (final a in homeAppliances) {
      expect(a.variants, isNotEmpty, reason: a.id);
      expect(a.def, lessThan(a.variants.length), reason: a.id);
      expect({for (final v in a.variants) v.label}, hasLength(a.variants.length), reason: a.id);
      for (final v in a.variants) {
        expect(v.min, lessThan(v.max), reason: '${a.id} ${v.label}');
        expect((v.z ?? a.z) + v.h, lessThanOrEqualTo(2500), reason: '${a.id} ${v.label} : sous un plafond de 2,60 m');
      }
    }
  });

  testWidgets('poser, changer de capacité et de type ; réseaux, devis, sauvegarde', (t) async {
    final st = laundry();
    st.addObject('fixture:chauffe_eau');
    var o = st.project.objects.single;
    expect((o.capacity!.label, objectName(o)), ('100 L', 'Chauffe-eau vertical 100 L'));
    st.editObject(o.uid, (x) => x.setCapacity(x.fixture!.variants.last, st.project.room.height));
    o = st.project.objects.single;
    expect((o.variant, o.h, o.z + o.h <= 2600), ('200 L', 1570, true));
    st.replaceFixture(o.uid, 'chauffe_eau_gaz');
    o = st.project.objects.single;
    expect(o.ref, 'fixture:chauffe_eau_gaz');
    st.setNetworks(true);
    final gas = st.project.points.where((x) => x.forUid == o.uid).map((x) => x.kind).toSet();
    expect(gas, containsAll({NetKind.gas, NetKind.duct, NetKind.waterCold, NetKind.waterHot}));
    expect(gas.contains(NetKind.cable), isFalse);
    expect(networkChecks(st.engine).where((i) => i.code == 'net_fixture'), isEmpty);
    st.addObject('fixture:ll_hublot');
    st.setNetworks(true);
    final ll = st.project.objects.last;
    st.regenerateNetworks(all: true);
    expect(st.project.points.where((x) => x.forUid == ll.uid).map((x) => x.kind), containsAll([NetKind.socket20, NetKind.valveMachine, NetKind.drain]));
    final lines = fixtureSupplyLines(st.engine);
    expect(lines.map((l) => l.section).toSet(), {heaterCategory, washCategory});
    expect(lines.every((l) => l.total.min > 0), isTrue);
    final back = Project.fromJson(st.project.toJson());
    expect(back.objects.map((x) => x.variant), st.project.objects.map((x) => x.variant));
    // ancien projet : chauffe-eau sans capacité, cotes gardées
    final old = RoomObject.fromJson({'uid': 'x', 'ref': 'fixture:chauffe_eau', 'x': 300, 'y': 225, 'z': 1100, 'w': 450, 'h': 1000, 'd': 450});
    expect(old.capacity!.label, '100 L');
  });

  testWidgets('machines d’un meuble : elles se choisissent et tiennent dans leur place', (t) async {
    await t.runAsync(() async {
      await TextureBank.instance.init();
      for (final id in ['laundry_washer_dryer_side_by_side', 'laundry_washer_dryer_column']) {
        final st = laundry();
        final c = st.engine.add(id, 'A', s: 200);
        final slots = machineSlots(c);
        expect(slots, hasLength(2));
        for (final sl in slots) {
          final list = machinesFor(sl);
          expect(list.length, greaterThan(3), reason: id);
          for (final (fx, vs) in list) {
            for (final v in vs) {
              st.edit(() => st.project.byUid(c.uid)!.machines = ['${fx.id}|${v.label}', '${fx.id}|${v.label}']);
              final item = st.project.byUid(c.uid)!;
              for (final m in st.engine.machinesIn(item)) {
                expect(m.s - m.w / 2, greaterThanOrEqualTo(item.s + 17), reason: '$id ${fx.id} ${v.label}');
                expect(m.s + m.w / 2, lessThanOrEqualTo(item.right - 17), reason: '$id ${fx.id} ${v.label}');
                expect(m.z + m.h, lessThanOrEqualTo(item.top), reason: '$id ${fx.id} ${v.label}');
              }
            }
          }
        }
        st.edit(() => st.project.byUid(c.uid)!.machines = ['ll_sechant|9/6 kg', 'sl_evac|7 kg']);
        final sc = await SceneExporter().build(st);
        expect([for (final o in sc['objects'] as List) if ('${o['uid']}'.startsWith('machine-')) o['type']], ['ll_sechant', 'sl_evac']);
        expect(PlacedCabinet.fromJson(st.project.byUid(c.uid)!.toJson()).machines, ['ll_sechant|9/6 kg', 'sl_evac|7 kg']);
        expect(fixtureSupplyLines(st.engine).map((l) => l.name), contains('Lave-linge séchant 9/6 kg'));
      }
    });
  });

  testWidgets('panneau Objets et fiches', (t) async {
    final st = laundry();
    Widget app(Widget w) => MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: SizedBox(width: 780, height: 590, child: w)));
    await t.pumpWidget(app(ObjectsPanel(state: st, onMessage: (_) {})));
    expect(find.text('Lave-linge hublot'), findsOneWidget);
    await t.tap(find.widgetWithText(ChoiceChip, heaterCategory));
    await t.pump();
    expect(find.text('Chauffe-eau extra-plat'), findsOneWidget);
    expect(find.text('40 L – 100 L'), findsOneWidget);
    st.addObject('fixture:chauffe_eau_plat');
    await t.pumpWidget(app(ObjectCard(state: st, onMessage: (_) {})));
    await t.tap(find.byKey(const ValueKey('cap_65 L')));
    expect(st.project.objects.single.h, 1090);
    expect(t.takeException(), isNull);
    final c = st.engine.add('laundry_washer_dryer_column', 'A', s: 200);
    st.goTo(PlanStep.layout);
    st.select(c.uid);
    await t.pumpWidget(app(InspectorCard(state: st, onMessage: (_) {})));
    await t.pump();
    expect(find.byKey(ValueKey('${c.uid}-machine0-ll_hublot'), skipOffstage: false), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
