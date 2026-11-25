// Mode AR : options envoyées à la vue 3D (réseaux tracés compris) et lecture des statistiques du paquet.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/ar_mode.dart';

void main() {
  test('options : cuisine seule par défaut, réseaux tracés seulement s’il y a des points', () {
    final st = AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()));
    const o = ArOptions();
    expect(o.isEmpty, isFalse);
    expect(const ArOptions(kitchen: false).isEmpty, isTrue);
    var j = jsonDecode(o.copyWith(nets: true).toJson(st)) as Map;
    expect(j['kitchen'], isTrue);
    expect(j['marker'], isTrue);
    expect(j['nets'], isNull, reason: 'pas encore de points de réseau');

    final e = st.engine;
    e.applyShape(RoomShape.lShape);
    e.addOpening('door', 'D', s: 2000);
    e.autoFillWall('A', Band.low);
    applyNetworks(e);
    st.project.networks = true;
    j = jsonDecode(o.copyWith(nets: true, walls: true).toJson(st)) as Map;
    expect(j['walls'], isTrue);
    final nets = j['nets'] as Map;
    expect((nets['runs'] as List), isNotEmpty);
    expect(nets['board'], hasLength(7));
    expect((nets['colors'] as Map)['PE'], 0x4CAF50);
  });

  test('statistiques du paquet', () {
    final s = ArStats.fromJson({'meshes': 59, 'vertices': 508, 'materials': 8, 'textures': 2, 'dropped': 1, 'size': 3 * 1024 * 1024 + 200, 'quickLook': true});
    expect(s.meshes, 59);
    expect(s.dropped, 1);
    expect(s.quickLook, isTrue);
    expect(s.sizeText, '3.0 Mo');
    expect(const ArStats(size: 46140).sizeText, '46 Ko');
    expect(arQuickLookAvailable, isFalse, reason: 'hors navigateur');
    expect(openArPackage(), isFalse);
  });
}
