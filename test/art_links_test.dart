import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/art.dart';
import 'package:kitchen_planner/engine/art_cut_import.dart';
import 'package:kitchen_planner/engine/art_fittings.dart';
import 'package:kitchen_planner/engine/art_machining.dart';

void main() {
  test('fichier de débit : CSV avec en-tête, séparateurs variés, quantités ; JSON', () {
    final csv = parseCutFile('nom;longueur;largeur;qte;ep\nCôté;720;560;2;18\nDessus, 800, 560, 1\n# commentaire\n600\t300');
    expect(csv.map((p) => (p.name, p.length, p.width, p.qty)).toList(), [('Côté', 720.0, 560.0, 2), ('Dessus', 800.0, 560.0, 1), ('Pièce 3', 600.0, 300.0, 1)]);
    final js = parseCutFile('{"parts":[{"l":700,"w":400,"q":3,"d":"Étagère"}]}');
    expect((js.single.name, js.single.qty), ('Étagère', 3));
    expect(parseCutFile('rien à lire'), isEmpty);
    var n = 0;
    final placed = layoutCutParts(csv, newId: () => 'p${n++}');
    expect(placed, hasLength(4));
    expect(placed.every((p) => p.h == 18), isTrue, reason: 'à plat');
    // pas de chevauchement entre pièces posées
    for (var i = 0; i < placed.length; i++) {
      for (var j = i + 1; j < placed.length; j++) {
        final a = placed[i], b = placed[j];
        expect(a.right <= b.x || b.right <= a.x || a.back <= b.z || b.back <= a.z, isTrue);
      }
    }
  });

  test('liaisons notées : aperçu assemblé sans bouger les pièces, Usiner applique, assemblage choisi par jonction', () {
    final art = ArtProject();
    final b = ArtPanel(id: 'b', role: ArtRole.decor, x: 0, y: 0, z: 0, w: 600, h: 18, d: 400);
    final a = ArtPanel(id: 'a', role: ArtRole.decor, x: 900, y: 0, z: 0, w: 400, h: 18, d: 300);
    art.free.addAll([b, a]);
    art.edgeLinks.add(EdgeLink('a', 1, 'b', 2, joint: JointType.tourillons.name));
    final round = ArtProject.fromJson(art.toJson());
    expect(round.edgeLinks.single.joint, 'tourillons');
    final preview = ArtProject.assembleLinks(art.free, art.edgeLinks);
    expect((a.w, a.h, a.d), (400, 18, 300), reason: 'les pièces à plat ne bougent pas');
    final pa = preview.firstWhere((p) => p.id == 'a');
    expect((pa.w, pa.h, pa.d), (18, 300, 400));
    expect(art.applyEdgeLinks(), 1);
    expect(art.edgeLinks, isEmpty);
    expect((a.w, a.h, a.d), (18, 300, 400));
    expect(art.jointFits[ArtProject.jointKey('a', 'b')], 'tourillons');
    final glued = computeMachiningElements(art.panels, fittings: art.fittings, jointCuts: art.jointCuts, jointFits: art.jointFits);
    final auto = computeMachiningElements(art.panels, fittings: art.fittings, jointCuts: art.jointCuts);
    expect(glued.screwsCount, 0, reason: 'tourillons collés seuls : pas de vis');
    expect(auto.screwsCount, greaterThan(0), reason: 'réglage général : vis + tourillons');
  });
}
