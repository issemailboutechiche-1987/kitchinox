/// Pièce, murs et caissons posés.
///
/// Repère de la vue de dessus (mm) : X vers la droite, Y vers le bas (vers l'avant de la pièce),
/// Z vers le haut depuis le sol. Le mur du fond A est en haut (y = 0).
///
/// Les murs sont parcourus dans le sens horaire vu de dessus : A (fond) → B (droite) → D (avant)
/// → C (gauche) → A. Sur chaque mur, la position `s` part de l'extrémité GAUCHE quand on regarde
/// le mur depuis l'intérieur de la pièce, et `t` mesure la distance au mur (vers l'intérieur).
/// Ainsi l'extrémité droite d'un mur rejoint le début (s = 0) du mur suivant : c'est là que se
/// posent les angles.
library;

import 'dart:math' as math;

import 'cutting.dart';
import 'front_layout.dart';
import 'art.dart';
import 'furniture.dart';
import 'openings_catalog.dart';
import 'room_objects.dart';
import 'handles.dart';
import 'manual_cut.dart';
import 'materials.dart';
import 'networks.dart';
import 'quote.dart';
import 'standards.dart';

const _eps = 0.5;

class Box3 {
  final double x0, y0, z0, x1, y1, z1;
  const Box3(this.x0, this.y0, this.z0, this.x1, this.y1, this.z1);

  bool intersects(Box3 o) =>
      x0 < o.x1 - _eps &&
      o.x0 < x1 - _eps &&
      y0 < o.y1 - _eps &&
      o.y0 < y1 - _eps &&
      z0 < o.z1 - _eps &&
      o.z0 < z1 - _eps;

  @override
  String toString() => '[$x0..$x1 × $y0..$y1 × $z0..$z1]';
}

class Wall {
  final String id;
  final double x0, y0; // point de départ (s = 0)
  final double dx, dy; // direction le long du mur
  final double nx, ny; // normale vers l'intérieur
  final double length;
  bool enabled;
  /// Arc : flèche (mm) au milieu du segment, vers l'extérieur de la pièce (0 : mur droit).
  final double bulge;
  Wall(this.id, this.x0, this.y0, this.dx, this.dy, this.nx, this.ny, this.length, {this.enabled = true, this.bulge = 0});

  bool get straight => bulge.abs() < 0.5;

  /// Mur droit parallèle aux axes : le seul qui reçoit des caissons, des ouvertures et des objets adossés.
  bool get orthogonal => straight && (dx.abs() < 1e-6 || dy.abs() < 1e-6);

  /// Rotation (degrés) d'un objet posé dos à ce mur, face vers la pièce.
  int get rot => ((math.atan2(-nx, ny) * 180 / math.pi).round() % 360 + 360) % 360;

  (double, double) get end => (x0 + dx * length, y0 + dy * length);

  /// Points le long du mur (l'arc découpé en [n] morceaux), du départ à l'arrivée.
  List<(double, double)> points([int n = 24]) {
    final (ex, ey) = end;
    if (straight) return [(x0, y0), (ex, ey)];
    // arc par trois points : départ, sommet (flèche vers l'extérieur), arrivée
    final mx = (x0 + ex) / 2 - nx * bulge, my = (y0 + ey) / 2 - ny * bulge;
    final c = length / 2;
    final rad = (c * c + bulge * bulge) / (2 * bulge.abs());
    final sgn = bulge > 0 ? 1.0 : -1.0;
    // centre : sur la normale, côté opposé au sommet
    final cx = mx + nx * sgn * rad, cy = my + ny * sgn * rad;
    final a0 = math.atan2(y0 - cy, x0 - cx), a1 = math.atan2(ey - cy, ex - cx), am = math.atan2(my - cy, mx - cx);
    // sens de parcours passant par le sommet
    var sweep = a1 - a0;
    double norm(double a) => (a % (2 * math.pi) + 2 * math.pi) % (2 * math.pi);
    final toMid = norm(am - a0), toEnd = norm(sweep);
    sweep = toMid <= toEnd ? toEnd : toEnd - 2 * math.pi;
    return [for (var i = 0; i <= n; i++) (cx + rad * math.cos(a0 + sweep * i / n), cy + rad * math.sin(a0 + sweep * i / n))];
  }

  /// Milieu du mur (sommet de l'arc pour un mur courbe).
  (double, double) get middle {
    if (straight) return toPlan(length / 2, 0);
    final pts = points(24);
    return pts[12];
  }

  /// Longueur développée (arc) ou longueur du mur droit.
  double get developed {
    if (straight) return length;
    final pts = points(48);
    var l = 0.0;
    for (var i = 1; i < pts.length; i++) {
      l += math.sqrt(math.pow(pts[i].$1 - pts[i - 1].$1, 2) + math.pow(pts[i].$2 - pts[i - 1].$2, 2));
    }
    return l;
  }

  /// Coordonnées murales (s, t) → plan (x, y).
  (double, double) toPlan(double s, double t) => (x0 + dx * s + nx * t, y0 + dy * s + ny * t);

  /// Plan (x, y) → coordonnées murales (s, t).
  (double, double) toWall(double x, double y) {
    final px = x - x0, py = y - y0;
    return (px * dx + py * dy, px * nx + py * ny);
  }

  /// Boîte occupée par une bande le long du mur.
  Box3 strip(double s, double width, double depth, double z, double height) {
    final (ax, ay) = toPlan(s, 0);
    final (bx, by) = toPlan(s + width, depth);
    return Box3(math.min(ax, bx), math.min(ay, by), z, math.max(ax, bx), math.max(ay, by), z + height);
  }

  /// Boîte occupée par un rectangle (s0..s0+width) et profondeur (t0..t1) le long du mur.
  Box3 stripRange(double s, double width, double t0, double t1, double z, double height) {
    final (ax, ay) = toPlan(s, t0);
    final (bx, by) = toPlan(s + width, t1);
    return Box3(math.min(ax, bx), math.min(ay, by), z, math.max(ax, bx), math.max(ay, by), z + height);
  }

  /// Boîte du plan exprimée en intervalles (s, t) de ce mur.
  (double, double, double, double) boxToWall(Box3 b) {
    final (s0, t0) = toWall(b.x0, b.y0);
    final (s1, t1) = toWall(b.x1, b.y1);
    return (math.min(s0, s1), math.max(s0, s1), math.min(t0, t1), math.max(t0, t1));
  }
}

/// Sommet du contour libre de la pièce ; [bulge] : flèche de l'arc du segment qui part de ce sommet (0 : trait).
class RoomVertex {
  double x, y, bulge;
  RoomVertex(this.x, this.y, [this.bulge = 0]);
  RoomVertex copy() => RoomVertex(x, y, bulge);
  List<double> toJson() => [x, y, if (bulge != 0) bulge];
  factory RoomVertex.fromJson(List j) => RoomVertex((j[0] as num).toDouble(), (j[1] as num).toDouble(), j.length > 2 ? (j[2] as num).toDouble() : 0);
}

/// Îlot central : un linéaire de caissons posé dans la pièce, façades tournées vers le mur du fond (A).
/// [x0], [y0] : coin du linéaire côté mur C et côté mur A (mm) ; [length] le long de X.
/// Le plan de travail déborde de [overhang] mm à l'arrière (coin repas).
class Island {
  double x0, y0, length;
  double overhang;
  bool flip; // façades vers la salle (le débord repas passe de l'autre côté)
  Island({required this.x0, required this.y0, required this.length, this.overhang = 300, this.flip = false});

  static const depth = 600.0;

  Map<String, dynamic> toJson() => {'x0': x0, 'y0': y0, 'length': length, 'overhang': overhang, if (flip) 'flip': true};
  factory Island.fromJson(Map<String, dynamic> j) => Island(
        x0: (j['x0'] as num).toDouble(),
        y0: (j['y0'] as num).toDouble(),
        length: (j['length'] as num).toDouble(),
        overhang: (j['overhang'] as num?)?.toDouble() ?? 300,
        flip: j['flip'] == true,
      );
}

class Room {
  double width; // X
  double depth; // Y
  double height; // sous plafond
  Island? island;
  final Map<String, bool> _enabled;

  /// Contour libre (traits et arcs) ; null : pièce rectangulaire [width] x [depth].
  List<RoomVertex>? outline;

  Room({this.width = 3600, this.depth = 3000, this.height = 2600, this.island, Map<String, bool>? enabledWalls, this.outline})
      : _enabled = {'A': true, 'B': true, 'D': true, 'C': true, ...?enabledWalls};

  /// Murs d'une pièce rectangulaire (ordre du tour de la pièce).
  static const wallOrder = ['A', 'B', 'D', 'C'];

  static const wallNames = {
    'A': 'Mur du fond', 'B': 'Mur droit', 'D': 'Mur avant', 'C': 'Mur gauche', 'I': 'Îlot',
    'E': 'Mur E', 'F': 'Mur F', 'G': 'Mur G', 'H': 'Mur H', 'J': 'Mur J', 'K': 'Mur K', 'L': 'Mur L', 'M': 'Mur M', 'N': 'Mur N', 'O': 'Mur O',
  };

  /// Identifiant du mur n° [i] d'un contour libre (A, B, C… sans I, réservé à l'îlot).
  static String outlineId(int i) => const ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'J', 'K', 'L', 'M', 'N', 'O'][i];

  /// Murs de cette pièce, dans l'ordre du tour.
  List<String> get order => outline == null ? wallOrder : [for (var i = 0; i < outline!.length; i++) outlineId(i)];

  /// Linéaires où l'on pose des caissons : les murs, plus l'îlot s'il existe.
  List<String> get runIds => [...order, if (island != null) 'I'];

  List<Wall> get walls => [for (final id in order) wall(id)];

  /// Mur suivant / précédent dans le tour de la pièce.
  String nextOf(String id) => id == 'I' ? '' : order[(order.indexOf(id) + 1) % order.length];
  String prevOf(String id) => id == 'I' ? '' : order[(order.indexOf(id) + order.length - 1) % order.length];

  Wall wall(String id) {
    final en = _enabled[id] ?? true;
    final ol = outline;
    if (ol != null && id != 'I') {
      final i = order.indexOf(id);
      if (i < 0) throw ArgumentError('mur inconnu : $id');
      final a = ol[i], b = ol[(i + 1) % ol.length];
      final len = math.sqrt(math.pow(b.x - a.x, 2) + math.pow(b.y - a.y, 2));
      final dx = len == 0 ? 1.0 : (b.x - a.x) / len, dy = len == 0 ? 0.0 : (b.y - a.y) / len;
      final w = Wall(id, a.x, a.y, dx, dy, -dy, dx, len, bulge: a.bulge);
      w.enabled = en && w.orthogonal;
      return w;
    }
    switch (id) {
      case 'A':
        return Wall('A', 0, 0, 1, 0, 0, 1, width, enabled: en);
      case 'B':
        return Wall('B', width, 0, 0, 1, -1, 0, depth, enabled: en);
      case 'D':
        return Wall('D', width, depth, -1, 0, 0, -1, width, enabled: en);
      case 'C':
        return Wall('C', 0, depth, 0, -1, 1, 0, depth, enabled: en);
      case 'I':
        final i = island;
        if (i == null) throw ArgumentError('pas d\'îlot');
        if (i.flip) return Wall('I', i.x0, i.y0 + i.overhang, 1, 0, 0, 1, i.length);
        // ligne arrière des caissons, façades vers le mur A (même sens de lecture que le mur D)
        return Wall('I', i.x0 + i.length, i.y0 + Island.depth, -1, 0, 0, -1, i.length);
    }
    throw ArgumentError('mur inconnu : $id');
  }

  void setWallEnabled(String id, bool v) => _enabled[id] = v;
  bool isWallEnabled(String id) {
    if (id == 'I') return island != null;
    if (!order.contains(id)) return false;
    return (_enabled[id] ?? true) && (outline == null || wall(id).orthogonal);
  }

  /// Mur suivant d'une pièce rectangulaire (sens horaire). Pour une pièce quelconque : [nextOf].
  static String nextWall(String id) => id == 'I' ? '' : wallOrder[(wallOrder.indexOf(id) + 1) % 4];

  /// Mur précédent d'une pièce rectangulaire. Pour une pièce quelconque : [prevOf].
  static String previousWall(String id) => id == 'I' ? '' : wallOrder[(wallOrder.indexOf(id) + 3) % 4];

  // ---------------------------------------------------------------- contour libre
  /// Pose un contour libre : sens horaire à l'écran, coin haut-gauche à l'origine, premier mur en haut.
  (double, double) setOutline(List<RoomVertex> pts) {
    if (pts.length < 3) {
      outline = null;
      return (0, 0);
    }
    var v = [for (final p in pts) p.copy()];
    double area() {
      var a = 0.0;
      for (var i = 0; i < v.length; i++) {
        final p = v[i], q = v[(i + 1) % v.length];
        a += p.x * q.y - q.x * p.y;
      }
      return a;
    }

    if (area() < 0) {
      // sens inverse : on retourne la liste, chaque flèche suit son segment
      final n = v.length;
      final rev = <RoomVertex>[];
      for (var i = 0; i < n; i++) {
        final p = v[(n - i) % n];
        final seg = v[(2 * n - i - 1) % n]; // segment qui arrivait sur p
        rev.add(RoomVertex(p.x, p.y, seg.bulge));
      }
      v = rev;
    }
    // départ : le sommet le plus haut (puis le plus à gauche) → le premier mur est le mur du haut
    var k = 0;
    for (var i = 1; i < v.length; i++) {
      if (v[i].y < v[k].y - 0.5 || ((v[i].y - v[k].y).abs() <= 0.5 && v[i].x < v[k].x)) k = i;
    }
    v = [...v.sublist(k), ...v.sublist(0, k)];
    outline = v;
    // origine au coin haut-gauche de l'encombrement (arcs compris)
    final pts2 = [for (final w in walls) ...w.points(16)];
    final minX = pts2.map((p) => p.$1).reduce(math.min), minY = pts2.map((p) => p.$2).reduce(math.min);
    for (final p in v) {
      p.x -= minX;
      p.y -= minY;
    }
    final pts3 = [for (final w in walls) ...w.points(16)];
    width = pts3.map((p) => p.$1).reduce(math.max);
    depth = pts3.map((p) => p.$2).reduce(math.max);
    return (minX, minY);
  }

  /// Revient à la pièce rectangulaire de l'encombrement actuel.
  void clearOutline() => outline = null;

  /// Contour du sol (arcs découpés), dans le sens du tour.
  List<(double, double)> get floorPolygon {
    if (outline == null) return [(0, 0), (width, 0), (width, depth), (0, depth)];
    return [
      for (final w in walls) ...w.points(24).sublist(0, w.straight ? 1 : 24),
    ];
  }

  /// Le point est-il dans la pièce ?
  bool contains(double x, double y) {
    if (outline == null) return x >= 0 && y >= 0 && x <= width && y <= depth;
    final poly = floorPolygon;
    var inside = false;
    for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final (xi, yi) = poly[i];
      final (xj, yj) = poly[j];
      if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) inside = !inside;
    }
    return inside;
  }

  /// Surface au sol (m²).
  double get area {
    final poly = floorPolygon;
    var a = 0.0;
    for (var i = 0; i < poly.length; i++) {
      final p = poly[i], q = poly[(i + 1) % poly.length];
      a += p.$1 * q.$2 - q.$1 * p.$2;
    }
    return a.abs() / 2 / 1e6;
  }

  /// Change l'encombrement : le contour libre est mis à l'échelle.
  void resize({double? width, double? depth}) {
    final ol = outline;
    if (ol != null) {
      final kx = width == null || this.width == 0 ? 1.0 : width / this.width, ky = depth == null || this.depth == 0 ? 1.0 : depth / this.depth;
      for (final p in ol) {
        p.x *= kx;
        p.y *= ky;
        p.bulge *= (kx + ky) / 2;
      }
    }
    if (width != null) this.width = width;
    if (depth != null) this.depth = depth;
  }

  Map<String, dynamic> toJson() => {
        'width': width,
        'depth': depth,
        'height': height,
        'walls': Map<String, bool>.from(_enabled),
        if (island != null) 'island': island!.toJson(),
        if (outline != null) 'outline': [for (final p in outline!) p.toJson()],
      };

  factory Room.fromJson(Map<String, dynamic> j) => Room(
        width: (j['width'] as num).toDouble(),
        depth: (j['depth'] as num).toDouble(),
        height: (j['height'] as num).toDouble(),
        enabledWalls: (j['walls'] as Map?)?.cast<String, bool>(),
        island: j['island'] == null ? null : Island.fromJson((j['island'] as Map).cast<String, dynamic>()),
        outline: j['outline'] == null ? null : [for (final p in j['outline'] as List) RoomVertex.fromJson(p as List)],
      );
}

/// Un caisson posé dans la pièce.
class PlacedCabinet {
  final String uid;
  String modelId;
  String wallId;
  double s; // position du bord gauche le long du mur
  double z; // hauteur du bas du caisson depuis le sol
  int width;
  int height;
  int depth;
  int? widthRight; // angles : bras sur le mur suivant
  String? opening;
  String? variant;
  String? internal;
  List<String>? appliances; // électroménager choisi (null = celui prévu par défaut)
  String? front; // finition propre à ce caisson (null = style de la cuisine)
  List<FrontRow>? layout; // composition de façade personnalisée (null = celle du modèle)
  List<String>? machines; // machines logées dans un meuble de buanderie : « type|capacité » (null = celles par défaut)
  bool noBack; // caisson personnalisé : sans fond arrière
  // joues (costados) de ce caisson : null automatique, 'oui' ajoutée, 'pris' ajoutée sur la largeur du caisson, 'non' sans
  String? cheekL, cheekR;
  String? accessory; // équipement intérieur (ex: INOXA 8104Y, Blum Space Tower...)

  PlacedCabinet({
    required this.uid,
    required this.modelId,
    required this.wallId,
    required this.s,
    required this.z,
    required this.width,
    required this.height,
    required this.depth,
    this.widthRight,
    this.opening,
    this.variant,
    this.internal,
    this.appliances,
    this.front,
    this.layout,
    this.machines,
    this.noBack = false,
    this.cheekL,
    this.cheekR,
    this.accessory,
  });

  String? cheek(bool left) => left ? cheekL : cheekR;
  bool hasCheek(bool left) => cheek(left) == 'oui' || cheek(left) == 'pris';

  /// Largeur prise sur le caisson par ses joues (mm).
  int get cheekTaken => (cheekL == 'pris' ? 18 : 0) + (cheekR == 'pris' ? 18 : 0);


  double get right => s + width;
  double get top => z + height;

  PlacedCabinet copy() => PlacedCabinet.fromJson(toJson());

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'model': modelId,
        'wall': wallId,
        's': s,
        'z': z,
        'width': width,
        'height': height,
        'depth': depth,
        if (widthRight != null) 'width_right': widthRight,
        if (opening != null) 'opening': opening,
        if (variant != null) 'variant': variant,
        if (internal != null) 'internal': internal,
        if (appliances != null) 'appliances': appliances,
        if (front != null) 'front': front,
        if (layout != null) 'layout': [for (final r in layout!) r.toJson()],
        if (machines != null) 'machines': machines,
        if (noBack) 'no_back': true,
        if (cheekL != null) 'cheek_l': cheekL,
        if (cheekR != null) 'cheek_r': cheekR,
        if (accessory != null) 'accessory': accessory,
      };

  factory PlacedCabinet.fromJson(Map<String, dynamic> j) => PlacedCabinet(
        uid: j['uid'] as String,
        modelId: j['model'] as String,
        wallId: j['wall'] as String,
        s: (j['s'] as num).toDouble(),
        z: (j['z'] as num).toDouble(),
        width: (j['width'] as num).toInt(),
        height: (j['height'] as num).toInt(),
        depth: (j['depth'] as num).toInt(),
        widthRight: (j['width_right'] as num?)?.toInt(),
        opening: j['opening'] as String?,
        variant: j['variant'] as String?,
        internal: j['internal'] as String?,
        cheekL: j['cheek_l'] as String?,
        cheekR: j['cheek_r'] as String?,
        appliances: (j['appliances'] as List?)?.cast<String>(),
        front: j['front'] as String?,
        layout: j['layout'] == null ? null : parseRows(j['layout']),
        machines: (j['machines'] as List?)?.cast<String>(),
        noBack: j['no_back'] == true,
        accessory: j['accessory'] as String?,
      );
}

/// Porte ou fenêtre sur un mur. Les caissons ne peuvent pas l'occuper.
class Opening {
  final String uid;
  String type; // 'door' | 'window'
  String wallId;
  double s; // bord gauche le long du mur
  double width;
  double z; // allège (0 pour une porte)
  double height;
  String? model; // modèle du catalogue des menuiseries (null : modèle par défaut du type)
  String hinge; // charnières (ou côté de coulissement) : 'left' | 'right'

  Opening({
    required this.uid,
    required this.type,
    required this.wallId,
    required this.s,
    required this.width,
    required this.z,
    required this.height,
    this.model,
    this.hinge = 'left',
  });

  bool get isDoor => type == 'door';
  double get right => s + width;

  /// Volume interdit aux caissons : une porte bloque le passage devant elle (900 mm),
  /// une fenêtre bloque les caissons hauts et les colonnes à sa hauteur.
  /// Porte battante : au moins son débattement ; coulissante, pliante : le passage (900 mm).
  Box3 box(Room room) =>
      room.wall(wallId).strip(s, width, isDoor ? math.max(900.0, openingModelOf(this)?.swing(width) ?? width) : 300, z, height);

  Map<String, dynamic> toJson() =>
      {'uid': uid, 'type': type, 'wall': wallId, 's': s, 'width': width, 'z': z, 'height': height, if (model != null) 'model': model, if (hinge != 'left') 'hinge': hinge};

  factory Opening.fromJson(Map<String, dynamic> j) => Opening(
        uid: j['uid'] as String,
        type: j['type'] as String,
        wallId: j['wall'] as String,
        s: (j['s'] as num).toDouble(),
        width: (j['width'] as num).toDouble(),
        z: (j['z'] as num).toDouble(),
        height: (j['height'] as num).toDouble(),
        model: j['model'] as String?,
        hinge: j['hinge'] as String? ?? 'left',
      );
}

/// Finitions choisies (identifiants ; les couleurs sont dans l'interface).
class KitchenStyle {
  String front;
  String? frontUpper; // façades des éléments hauts (null = [front])
  String? frontLower; // façades des bas et colonnes (null = [front])
  String worktop;
  String handle; // rendu : 'bar' | 'knob' | 'gola' | 'edge' | 'groove' | ... (voir HandleRender)
  String? handleId; // modèle du catalogue des poignées
  int? handleSize; // entraxe / longueur / diamètre choisi (mm)
  String? handleFinish;
  bool tallXxl; // barres XXL verticales sur les colonnes
  String handleOrient; // 'auto' | 'v' | 'h'
  String handlePos; // 'auto' | 'centre'
  bool handlePair; // deux poignées sur les tiroirs larges
  final Map<String, HandleChoice> handleByZone; // poignée propre à un endroit (voir handleZones)
  String carcass;
  String floor; // sol
  String wall; // murs
  String? splash; // crédence entre le plan de travail et les hauts (null = comme les murs)
  bool endPanels; // joues de finition posées automatiquement aux extrémités visibles
  String? endPanelFinish; // finition personnalisée des joues / côtés visibles (si null : suit les façades)
  String frontProfile; // modèle de façade : 'lisse' | 'shaker' | 'shaker_fin' | 'mouluree' | 'cannelee'
  String? islandFront; // façades de l'îlot (null : comme les bas)
  String? islandTop; // plan de l'îlot (null : comme les autres)
  /// Plinthe : null comme les façades (un ton plus foncé), 'plan' comme le plan de travail,
  /// 'alu', 'inox', 'noir', 'blanc', ou « f:finition » un décor de façade.
  String? plinth;
  bool islandWaterfall; // plan en cascade : jambages jusqu'au sol
  String islandBack; // dos de l'îlot : 'lisse' | 'cadre' | 'cannele'
  final Set<String> decor; // décor du rendu (voir decorItems)
  bool showDecor; // décor montré en 3D
  String lighting; // 'aucun' | 'led_hauts' | 'led_hauts_plinthes'
  String? sink; // modèle d'évier (null : évier 1 bac avec égouttoir)
  String? faucet; // modèle de mitigeur (null : mitigeur standard)
  String faucetFinish; // 'chrome' | 'noir_mat' | 'or_brosse' | 'inox_brosse'
  String faucetLever; // 'side_pin' | 'side_flat' | 'top_lever' | 'retro_cross'
  String sinkMount; // 'inset' (à poser) | 'undermount' (sous plan)
  String sinkFinish; // 'inox' | 'noir_quartz' | 'blanc_ceramique'
  String hobType; // 'induction' | 'gaz' | 'vitro'
  int hobWidth; // 0 (auto), 60, 80, 90
  String ovenFinish; // 'black_inox' | 'full_black' | 'blanc' | 'inox_brosse' | 'black_gold'
  String ovenHandle; // 'bar' | 'square' | 'retro' | 'integrated'
  String socketFinish; // 'blanc' | 'noir_mat' | 'anthracite' | 'alu_brosse' | 'or_brosse'
  final List<CustomTexture> textures; // textures ajoutées par l'utilisateur

  KitchenStyle({
    this.front = 'blanc_mat',
    this.frontUpper,
    this.frontLower,
    this.worktop = 'quartz_blanc',
    this.handle = 'bar',
    this.handleId,
    this.handleSize,
    this.handleFinish,
    this.tallXxl = false,
    this.handleOrient = 'auto',
    this.handlePos = 'auto',
    this.handlePair = false,
    Map<String, HandleChoice>? handleByZone,
    this.carcass = 'blanc',
    this.floor = 'parquet_clair',
    this.wall = 'blanc_casse',
    this.splash,
    this.endPanels = true,
    this.endPanelFinish,
    this.frontProfile = 'lisse',
    this.islandFront,
    this.islandTop,
    this.plinth,
    this.islandWaterfall = false,
    this.islandBack = 'lisse',
    Set<String>? decor,
    this.showDecor = true,
    this.lighting = 'aucun',
    this.sink,
    this.faucet,
    this.faucetFinish = 'chrome',
    this.faucetLever = 'side_pin',
    this.sinkMount = 'inset',
    this.sinkFinish = 'inox',
    this.hobType = 'induction',
    this.hobWidth = 0,
    this.ovenFinish = 'black_inox',
    this.ovenHandle = 'bar',
    this.socketFinish = 'blanc',
    List<CustomTexture>? textures,
  })  : decor = decor ?? {},
        handleByZone = handleByZone ?? {},
        textures = textures ?? [];

  /// Poignée générale.
  HandleChoice get handleChoice => HandleChoice(kind: handle, id: handleId, size: handleSize, finish: handleFinish, orient: handleOrient, pos: handlePos, pair: handlePair);

  /// Poignée d'un endroit. Avec le profil Gola, seuls les meubles hauts peuvent être différents (le profil est dans les caissons bas).
  HandleChoice handleAt(String zone) => (handle == 'gola' && zone != 'haut') ? handleChoice : (handleByZone[zone] ?? handleChoice);

  /// Finition des façades d'un caisson : la sienne, sinon celle des hauts / des bas, sinon la générale.
  String frontOf(PlacedCabinet c, {required bool high}) => c.front ?? (c.wallId == 'I' ? islandFront : null) ?? (high ? frontUpper : frontLower) ?? front;

  Map<String, dynamic> toJson() => {
        'front': front,
        if (frontUpper != null) 'front_upper': frontUpper,
        if (frontLower != null) 'front_lower': frontLower,
        'worktop': worktop,
        'handle': handle,
        if (handleId != null) 'handle_id': handleId,
        if (handleSize != null) 'handle_size': handleSize,
        if (handleFinish != null) 'handle_finish': handleFinish,
        if (tallXxl) 'tall_xxl': true,
        if (handleOrient != 'auto') 'handle_orient': handleOrient,
        if (handlePos != 'auto') 'handle_pos': handlePos,
        if (handlePair) 'handle_pair': true,
        if (handleByZone.isNotEmpty) 'handle_zones': {for (final e in handleByZone.entries) e.key: e.value.toJson()},
        'carcass': carcass,
        'floor': floor,
        'wall': wall,
        if (splash != null) 'splash': splash,
        if (!endPanels) 'end_panels': false,
        if (endPanelFinish != null) 'end_panel_finish': endPanelFinish,
        if (frontProfile != 'lisse') 'front_profile': frontProfile,
        if (islandFront != null) 'island_front': islandFront,
        if (islandTop != null) 'island_top': islandTop,
        if (plinth != null) 'plinth': plinth,
        if (islandWaterfall) 'island_waterfall': true,
        if (islandBack != 'lisse') 'island_back': islandBack,
        if (decor.isNotEmpty) 'decor': [...decor],
        if (!showDecor) 'show_decor': false,
        if (lighting != 'aucun') 'lighting': lighting,
        if (sink != null) 'sink': sink,
        if (faucet != null) 'faucet': faucet,
        if (faucetFinish != 'chrome') 'faucet_finish': faucetFinish,
        if (faucetLever != 'side_pin') 'faucet_lever': faucetLever,
        if (sinkMount != 'inset') 'sink_mount': sinkMount,
        if (sinkFinish != 'inox') 'sink_finish': sinkFinish,
        if (hobType != 'induction') 'hob_type': hobType,
        if (hobWidth != 0) 'hob_width': hobWidth,
        if (ovenFinish != 'black_inox') 'oven_finish': ovenFinish,
        if (ovenHandle != 'bar') 'oven_handle': ovenHandle,
        if (socketFinish != 'blanc') 'socket_finish': socketFinish,
        if (textures.isNotEmpty) 'textures': [for (final t in textures) t.toJson()],
      };

  factory KitchenStyle.fromJson(Map<String, dynamic> j) => KitchenStyle(
        front: j['front'] as String? ?? 'blanc_mat',
        frontUpper: j['front_upper'] as String?,
        frontLower: j['front_lower'] as String?,
        worktop: j['worktop'] as String? ?? 'quartz_blanc',
        handle: j['handle'] as String? ?? 'bar',
        handleId: j['handle_id'] as String?,
        handleSize: (j['handle_size'] as num?)?.toInt(),
        handleFinish: j['handle_finish'] as String?,
        tallXxl: j['tall_xxl'] as bool? ?? false,
        handleOrient: j['handle_orient'] as String? ?? 'auto',
        handlePos: j['handle_pos'] as String? ?? 'auto',
        handlePair: j['handle_pair'] == true,
        handleByZone: {for (final e in ((j['handle_zones'] as Map?) ?? const {}).entries) '${e.key}': HandleChoice.fromJson((e.value as Map).cast<String, dynamic>())},
        carcass: j['carcass'] as String? ?? 'blanc',
        floor: j['floor'] as String? ?? 'parquet_clair',
        wall: j['wall'] as String? ?? 'blanc_casse',
        splash: j['splash'] as String?,
        endPanels: j['end_panels'] as bool? ?? true,
        endPanelFinish: j['end_panel_finish'] as String?,
        frontProfile: j['front_profile'] as String? ?? 'lisse',
        islandFront: j['island_front'] as String?,
        islandTop: j['island_top'] as String?,
        plinth: j['plinth'] as String?,
        islandWaterfall: j['island_waterfall'] == true,
        islandBack: j['island_back'] as String? ?? 'lisse',
        decor: {for (final x in (j['decor'] as List? ?? const [])) '$x'},
        showDecor: j['show_decor'] as bool? ?? true,
        lighting: j['lighting'] as String? ?? 'aucun',
        sink: j['sink'] as String?,
        faucet: j['faucet'] as String?,
        faucetFinish: j['faucet_finish'] as String? ?? 'chrome',
        faucetLever: j['faucet_lever'] as String? ?? 'side_pin',
        sinkMount: j['sink_mount'] as String? ?? 'inset',
        sinkFinish: j['sink_finish'] as String? ?? 'inox',
        hobType: j['hob_type'] as String? ?? 'induction',
        hobWidth: (j['hob_width'] as num?)?.toInt() ?? 0,
        ovenFinish: j['oven_finish'] as String? ?? 'black_inox',
        ovenHandle: j['oven_handle'] as String? ?? 'bar',
        socketFinish: j['socket_finish'] as String? ?? 'blanc',
        textures: [for (final t in (j['textures'] as List? ?? const [])) CustomTexture.fromJson((t as Map).cast<String, dynamic>())],
      );
}

/// Texture importée (photo d'un échantillon) : image encodée en base64, taille réelle d'un motif.
class CustomTexture {
  final String id;
  String name;
  String target; // 'front' | 'worktop' | 'both' | 'floor' | 'wall'
  final String data; // image (PNG / JPEG) en base64
  int tile; // largeur réelle couverte par l'image (mm)
  int color; // teinte moyenne (ARGB) pour les vues sans texture
  CustomTexture({required this.id, required this.name, required this.target, required this.data, this.tile = 600, this.color = 0xFFBBBBBB});

  bool get forFront => target == 'front' || target == 'both';
  bool get forWorktop => target == 'worktop' || target == 'both';
  bool get forFloor => target == 'floor';
  bool get forWall => target == 'wall';

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'target': target, 'data': data, 'tile': tile, 'color': color};
  factory CustomTexture.fromJson(Map<String, dynamic> j) => CustomTexture(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Texture',
        target: j['target'] as String? ?? 'both',
        data: j['data'] as String? ?? '',
        tile: (j['tile'] as num?)?.toInt() ?? 600,
        color: (j['color'] as num?)?.toInt() ?? 0xFFBBBBBB,
      );
}

/// Formes de cuisine : quels murs sont utilisés.
enum RoomShape {
  linear('Linéaire', {'A'}),
  lShape('En L', {'A', 'B'}),
  uShape('En U', {'C', 'A', 'B'}),
  parallel('Parallèle', {'A', 'D'}),
  open('Pièce entière', {'A', 'B', 'C', 'D'});

  final String label;
  final Set<String> walls;
  const RoomShape(this.label, this.walls);
}

/// Fiche client du projet : particulier ou société (ICE : identifiant commun de l'entreprise, Maroc, 15 chiffres)
/// et numéros déjà attribués aux plans de ce projet (une réédition garde son numéro).
class ClientInfo {
  String name;
  String company;
  String ice;
  final Map<String, String> numbers;
  ClientInfo({this.name = '', this.company = '', this.ice = '', Map<String, String>? numbers}) : numbers = numbers ?? {};

  bool get isEmpty => name.trim().isEmpty && company.trim().isEmpty && ice.trim().isEmpty;

  /// Désignation du client : la société, sinon le nom (les deux si renseignés).
  String get label {
    final n = name.trim(), c = company.trim();
    if (c.isEmpty) return n;
    if (n.isEmpty) return c;
    return '$c ($n)';
  }

  /// ICE valide : 15 chiffres.
  static bool validIce(String s) => RegExp(r'^\d{15}$').hasMatch(s.replaceAll(' ', ''));

  Map<String, dynamic> toJson() => {
        if (name.isNotEmpty) 'name': name,
        if (company.isNotEmpty) 'company': company,
        if (ice.isNotEmpty) 'ice': ice,
        if (numbers.isNotEmpty) 'numbers': numbers,
      };

  factory ClientInfo.fromJson(Map<String, dynamic> j) => ClientInfo(
        name: j['name'] as String? ?? '',
        company: j['company'] as String? ?? '',
        ice: j['ice'] as String? ?? '',
        numbers: {for (final e in ((j['numbers'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'},
      );
}

class Project {
  String name;
  ClientInfo client = ClientInfo();
  QuoteSettings quote = QuoteSettings(); // devis final : choix par poste, remise, TVA, validation
  String universe; // 'cuisine' | 'dressing' | 'bain' | 'tv' | 'interieur'
  Room room;
  KitchenStandards standards;
  KitchenStyle style;
  CutSettings cut;
  ManualCut manual = ManualCut(); // débit manuel (pièces saisies à la main)
  final Map<String, FurnitureProject> furniture = {}; // dressing, bain, tv, intérieur
  ArtProject art = ArtProject(); // mode Art : création libre
  ProjectSpecs specs;
  final List<PlacedCabinet> items;
  final Map<String, int> accessories = {}; // accessoires de meubles choisis (id → quantité)
  final List<Opening> openings;
  final List<RoomObject> objects = []; // sanitaires et objets de décoration posés librement
  final List<NetPoint> points; // réseaux : électricité, eau, évacuations, gaz, hotte
  bool networks; // réseaux affichés et tenus à jour automatiquement
  int _nextId;

  Project({
    this.name = 'Cuisine',
    this.universe = 'cuisine',
    Room? room,
    this.standards = const KitchenStandards(),
    KitchenStyle? style,
    CutSettings? cut,
    ProjectSpecs? specs,
    List<PlacedCabinet>? items,
    List<Opening>? openings,
    List<NetPoint>? points,
    this.networks = false,
  })  : room = room ?? Room(),
        style = style ?? KitchenStyle(),
        cut = cut ?? CutSettings(),
        specs = specs ?? ProjectSpecs(),
        items = items ?? [],
        openings = openings ?? [],
        points = points ?? [],
        _nextId = (items?.length ?? 0) + (openings?.length ?? 0) + (points?.length ?? 0) + 1;

  String newUid([String prefix = 'c']) {
    String uid;
    do {
      uid = '$prefix${_nextId++}';
    } while (items.any((i) => i.uid == uid) || openings.any((o) => o.uid == uid) || points.any((x) => x.uid == uid));
    return uid;
  }

  PlacedCabinet? byUid(String uid) {
    for (final i in items) {
      if (i.uid == uid) return i;
    }
    return null;
  }

  NetPoint? pointByUid(String uid) {
    for (final x in points) {
      if (x.uid == uid) return x;
    }
    return null;
  }

  Opening? openingByUid(String uid) {
    for (final o in openings) {
      if (o.uid == uid) return o;
    }
    return null;
  }

  RoomShape? get shape {
    for (final sh in RoomShape.values) {
      if (Room.wallOrder.every((w) => room.isWallEnabled(w) == sh.walls.contains(w))) return sh;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'format': 'kitchen_planner/2',
        'name': name,
        if (universe != 'cuisine') 'universe': universe,
        'room': room.toJson(),
        'standards': standards.toJson(),
        'style': style.toJson(),
        'cut': cut.toJson(),
        'specs': specs.toJson(),
        'items': items.map((i) => i.toJson()).toList(),
        'openings': openings.map((o) => o.toJson()).toList(),
        if (objects.isNotEmpty) 'objects': [for (final o in objects) o.toJson()],
        if (points.isNotEmpty) 'points': points.map((x) => x.toJson()).toList(),
        if (networks) 'networks': true,
        if (!client.isEmpty || client.numbers.isNotEmpty) 'client': client.toJson(),
        if (!quote.isDefault) 'quote': quote.toJson(),
        if (accessories.isNotEmpty) 'accessories': accessories,
        if (manual.parts.isNotEmpty) 'manual_cut': manual.toJson(),
        if (!art.isEmpty) 'art': art.toJson(),
        if (furniture.values.any((f) => f.items.isNotEmpty)) 'furniture': {for (final e in furniture.entries) e.key: e.value.toJson()},
      };

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        name: j['name'] as String? ?? 'Cuisine',
        universe: j['universe'] as String? ?? 'cuisine',
        room: Room.fromJson(j['room'] as Map<String, dynamic>),
        standards: KitchenStandards.fromJson((j['standards'] as Map?)?.cast<String, dynamic>() ?? const {}),
        style: KitchenStyle.fromJson((j['style'] as Map?)?.cast<String, dynamic>() ?? const {}),
        cut: CutSettings.fromJson((j['cut'] as Map?)?.cast<String, dynamic>() ?? const {}),
        specs: ProjectSpecs.fromJson((j['specs'] as Map?)?.cast<String, dynamic>() ?? const {}),
        items: [for (final i in (j['items'] as List)) PlacedCabinet.fromJson((i as Map).cast<String, dynamic>())],
        openings: [
          for (final o in (j['openings'] as List? ?? const [])) Opening.fromJson((o as Map).cast<String, dynamic>())
        ],
        points: [for (final x in (j['points'] as List? ?? const [])) NetPoint.fromJson((x as Map).cast<String, dynamic>())],
        networks: j['networks'] as bool? ?? false,
      )
        ..objects.addAll([for (final o in (j['objects'] as List? ?? const [])) RoomObject.fromJson((o as Map).cast<String, dynamic>())])
        ..client = ClientInfo.fromJson((j['client'] as Map?)?.cast<String, dynamic>() ?? const {})
        ..quote = QuoteSettings.fromJson((j['quote'] as Map?)?.cast<String, dynamic>() ?? const {})
        ..accessories.addAll({for (final e in ((j['accessories'] as Map?) ?? const {}).entries) '${e.key}': (e.value as num).toInt()})
        ..art = ArtProject.fromJson((j['art'] as Map?)?.cast<String, dynamic>() ?? const {})
        ..manual = ManualCut.fromJson((j['manual_cut'] as Map?)?.cast<String, dynamic>() ?? const {})
        ..furniture.addAll({
          for (final e in ((j['furniture'] as Map?) ?? const {}).entries)
            '${e.key}': FurnitureProject.fromJson((e.value as Map).cast<String, dynamic>()),
        });
}
