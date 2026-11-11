// Meubles d'angle : formats à 4 paramètres et formules de débit (L 90°, pan coupé 45°, borgne), Gola.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/ui/app_state.dart';

void main() {
  final cat = Catalog.parse(File('assets/catalog.json').readAsStringSync());
  List<CornerPart> parts(String id, {int? w, int? wr, bool gola = false}) {
    final m = cat[id];
    final c = PlacedCabinet(uid: 'x', modelId: id, wallId: 'A', s: 0, z: m.kind.isHigh ? 1500 : 100, width: w ?? m.defaultWidth,
        height: m.defaultHeight, depth: m.depth, widthRight: wr ?? m.widthRight);
    return cornerCutList(m, c, T: 18, td: 18, gap: 4, gola: gola);
  }

  CornerPart part(List<CornerPart> l, String name) => l.firstWhere((p) => p.$2.startsWith(name));

  test('angle bas en L 900/900 : portes 295 et 277 comme le tableau, dos et fond en L', () {
    final l = parts('corner_base_l_shaped', w: 900, wr: 900);
    expect(part(l, 'Porte maître').$4, 295);
    expect(part(l, 'Porte esclave').$4, 277);
    final h = cat['corner_base_l_shaped'].defaultHeight;
    expect(part(l, 'Porte maître').$3, h - 4);
    expect(part(l, 'Dos porteur mur 1').$4, 882);
    expect(part(l, 'Dos porteur mur 2').$4, 864);
    expect(part(l, 'Fond en L').$3, 864);
    expect(part(l, 'Traverse').$5, 2);
    // Gola : portes raccourcies de 35 mm
    expect(part(parts('corner_base_l_shaped', w: 900, wr: 900, gola: true), 'Porte maître').$3, h - 35);
  });

  test('pan coupé 900/900 : porte oblique de 418 ; borgne 1200 : porte d’accès et panneau fixe', () {
    expect(part(parts('corner_base_diagonal', w: 900, wr: 900), 'Porte oblique').$4, 418);
    final b = parts('corner_base_blind', w: 1200);
    expect(part(b, 'Panneau fixe').$4, 598);
    expect(part(b, 'Porte d’accès').$4, 598);
    expect(part(b, 'Fileur d’angle').$5, 2);
    expect(b.any((p) => p.$1 == 'fond'), isTrue);
  });

  test('débit de la cuisine : les pièces d’angle suivent les formules', () {
    final e = LayoutEngine(cat, Project(room: Room(width: 4000, depth: 3000, height: 2600)));
    e.applyShape(RoomShape.lShape);
    e.add('corner_base_l_shaped', 'A');
    final cl = cutList(e, e.project.cut, const {});
    expect(cl.any((p) => p.name.startsWith('Porte maître')), isTrue);
    expect(cl.any((p) => p.name.startsWith('Dos porteur')), isTrue);
  });

  test('format d’angle choisi dans la fiche : le bras reste dans l’angle', () {
    final st = AppState(cat, project: Project(room: Room(width: 4000, depth: 3000, height: 2600)));
    st.edit(() {
      st.engine.applyShape(RoomShape.lShape);
      st.engine.add('corner_base_l_shaped', 'A');
    });
    final c = st.project.items.single;
    expect(st.setCornerSize(c.uid, cornerSizes['corner_base_l_shaped']!.firstWhere((s) => s.w2 == 1050)), isNull);
    expect((c.width, c.widthRight), (900, 1050));
    expect(c.right, st.project.room.wall('A').length);
  });
}
