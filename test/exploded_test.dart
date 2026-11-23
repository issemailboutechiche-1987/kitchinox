// Vue éclatée de l'atelier dessin : les pièces s'écartent dans le plan de la vue, aucune ne cache une autre.
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/art.dart';
import 'package:kitchen_planner/ui/art_camera.dart';
import 'package:kitchen_planner/ui/art_page.dart';

void main() {
  test('vue éclatée de face : plus aucun chevauchement, l’ordre gauche / droite gardé', () {
    // une boîte dessinée à la main : côtés, dessus, dessous, fond, étagère et porte qui se recouvrent de face
    ArtPanel pn(String id, double x, double y, double z, double w, double h, double d) => ArtPanel(id: id, role: ArtRole.montant, x: x, y: y, z: z, w: w, h: h, d: d);
    final ps = [
      pn('P1', 0, 0, 0, 18, 720, 560),
      pn('P2', 582, 0, 0, 18, 720, 560),
      pn('P3', 18, 702, 0, 564, 18, 560),
      pn('P4', 18, 0, 0, 564, 18, 560),
      pn('P5', 18, 18, 550, 564, 684, 8),
      pn('P6', 18, 350, 0, 564, 18, 540),
      pn('P7', 0, 0, -20, 600, 720, 18),
    ];
    final front = ArtCamera(yaw: 0, pitch: 0).forward; // vue de face : on regarde le long de z
    final out = separatePanels(ps, front);
    for (var i = 0; i < out.length; i++) {
      for (var j = i + 1; j < out.length; j++) {
        final a = out[i], b = out[j];
        final apart = a.x + a.w <= b.x || b.x + b.w <= a.x || a.y + a.h <= b.y || b.y + b.h <= a.y;
        expect(apart, isTrue, reason: '${a.id} et ${b.id} se recouvrent encore de face');
      }
    }
    expect(out[0].x, lessThan(out[1].x), reason: 'le côté gauche reste à gauche');
    expect(ps.first.x, 0, reason: 'les pièces du projet ne bougent pas');
  });
}
