// Légèreté : la caméra 3D qui tourne ne relance pas toute l'application, les largeurs d'accessoires sont calculées une fois.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';

void main() {
  test('cadre de la sélection 3D : seuls ses auditeurs sont prévenus, pas l’application', () {
    final st = AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()));
    var app = 0, buttons = 0;
    st.addListener(() => app++);
    st.selRect3dNotifier.addListener(() => buttons++);
    for (var i = 0; i < 60; i++) {
      st.selRect3dNotifier.value = Rect.fromLTWH(100.0 + i, 80, 120, 90); // une seconde de caméra à 60 images/s
    }
    st.selRect3dNotifier.value = Rect.fromLTWH(159, 80, 120, 90); // même cadre : rien
    expect(buttons, 60);
    expect(app, 0, reason: 'aucun refresh() global pendant que la caméra bouge');
    expect(st.selRect3d, const Rect.fromLTWH(159, 80, 120, 90));
  });

  test('largeurs compatibles des accessoires : calculées au chargement, puis la même liste', () {
    KitchenAccessoriesCatalog.parse(File('assets/data/kitchen_accessories_catalog.json').readAsStringSync());
    final a = KitchenAccessoriesCatalog.all.firstWhere((x) => x.supportedWidths.isNotEmpty);
    expect(identical(a.supportedWidths, a.supportedWidths), isTrue);
    expect(a.supportedWidths, orderedEquals([...a.supportedWidths]..sort()));
    expect(() => a.supportedWidths.add(1), throwsUnsupportedError, reason: 'liste partagée : non modifiable');
  });
}
