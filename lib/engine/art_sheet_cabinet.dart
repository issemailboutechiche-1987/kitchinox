// Caisson simple à une porte, fabriqué depuis une feuille posée à plat :
// coupes à la guillotine (bandes en Y, puis pièces en X), puis liaisons des chants notées, prêtes à usiner.
//
//   construction : dessous pleine largeur, côtés posés dessus, dessus entre les côtés,
//   fond entre les côtés posé sur le dessous, porte en applique devant (jeu de 3 mm).
import 'art.dart';

class SheetCabinet {
  final ArtPanel bottom, left, right, top, back, door;
  final List<EdgeLink> links;
  final List<ArtPanel> offcuts; // chutes restantes de la feuille
  const SheetCabinet(this.bottom, this.left, this.right, this.top, this.back, this.door, this.links, this.offcuts);
  List<ArtPanel> get parts => [bottom, left, right, top, back, door];
}

/// Pièces à découper pour un caisson [w] × [h] × [d] en épaisseur [t] : (nom, longueur en X, largeur en Z).
List<(String, double, double)> sheetCabinetParts(double w, double h, double d, double t, {double doorGap = 3}) => [
      ('Côté gauche', h - t, d),
      ('Côté droit', h - t, d),
      ('Dessous', w, d),
      ('Dessus', w - 2 * t, d),
      ('Fond', w - 2 * t, h - 2 * t),
      ('Porte', w - doorGap, h - doorGap),
    ];

/// Coupe [sheet] (pièce libre à plat de [art]) et note les liaisons du caisson. Null si la feuille est trop petite
/// (rien n'est coupé dans ce cas).
SheetCabinet? cutSheetCabinet(ArtProject art, ArtPanel sheet, {double w = 600, double h = 720, double d = 560, double kerf = 4, double doorGap = 3}) {
  final t = sheet.h;
  final parts = sheetCabinetParts(w, h, d, t, doorGap: doorGap);
  // bande 1 (profondeur d) : côtés, dessous, dessus ; bande 2 : porte puis fond
  final row1 = parts.sublist(0, 4);
  final row2 = [parts[5], parts[4]];
  final row2Depth = row2.map((p) => p.$3).reduce((a, b) => a > b ? a : b);
  double rowLen(List<(String, double, double)> r) => r.fold<double>(0, (a, p) => a + p.$2 + kerf);
  if (rowLen(row1) > sheet.w + kerf || rowLen(row2) > sheet.w + kerf || d + kerf + row2Depth > sheet.d + 0.5) return null;

  final pieces = <String, ArtPanel>{};
  final offcuts = <ArtPanel>[];
  /// Coupe la bande [strip] en pièces le long de X, puis chaque pièce à sa largeur en Z.
  void cutRow(ArtPanel strip, List<(String, double, double)> row) {
    var rest = strip;
    for (final (name, len, depth) in row) {
      ArtPanel piece;
      if (rest.w - len > kerf + 1) {
        final (a, b) = art.splitPanel(rest, 0, rest.x + len + kerf / 2, kerf);
        piece = a;
        rest = b;
      } else {
        piece = rest;
      }
      if (piece.d - depth > kerf + 1) {
        final (a, b) = art.splitPanel(piece, 2, piece.z + depth + kerf / 2, kerf);
        piece = a;
        offcuts.add(b..note = 'Chute');
      }
      piece
        ..note = name
        ..role = ArtRole.decor;
      pieces[name] = piece;
    }
    if (!pieces.values.contains(rest)) offcuts.add(rest..note = 'Chute');
  }

  final (strip1, rest1) = art.splitPanel(sheet, 2, sheet.z + d + kerf / 2, kerf);
  ArtPanel strip2 = rest1;
  if (rest1.d - row2Depth > kerf + 1) {
    final (a, b) = art.splitPanel(rest1, 2, rest1.z + row2Depth + kerf / 2, kerf);
    strip2 = a;
    offcuts.add(b..note = 'Chute');
  }
  cutRow(strip1, row1);
  cutRow(strip2, row2);

  final bottom = pieces['Dessous']!, left = pieces['Côté gauche']!, right = pieces['Côté droit']!;
  final top = pieces['Dessus']!, back = pieces['Fond']!, door = pieces['Porte']!;
  bottom.role = ArtRole.tablette;
  door.hinge = 'left';
  // le chant du côté gauche qui recevra le dessus n'existe qu'une fois le côté debout : on simule l'assemblage
  final links = <EdgeLink>[
    EdgeLink(left.id, ArtProject.edgeWithNormal(left, 0, -1), bottom.id, ArtProject.edgeWithNormal(bottom, 0, -1), over: true),
    EdgeLink(right.id, ArtProject.edgeWithNormal(right, 0, -1), bottom.id, ArtProject.edgeWithNormal(bottom, 0, 1), over: true),
  ];
  final standing = ArtProject.assembleLinks(art.free, links);
  final leftUp = standing.firstWhere((p) => p.id == left.id);
  links.addAll([
    EdgeLink(top.id, ArtProject.edgeWithNormal(top, 0, -1), left.id, ArtProject.edgeWithNormal(leftUp, 1, 1), over: true),
    EdgeLink(back.id, ArtProject.edgeWithNormal(back, 2, -1), bottom.id, ArtProject.edgeWithNormal(bottom, 2, 1), over: true, align: 'center'),
    EdgeLink(door.id, ArtProject.edgeWithNormal(door, 2, -1), bottom.id, ArtProject.edgeWithNormal(bottom, 2, -1), over: true, outside: true, align: 'center'),
  ]);
  return SheetCabinet(bottom, left, right, top, back, door, links, offcuts);
}
