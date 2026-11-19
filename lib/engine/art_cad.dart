// Modèles et géométrie CAO pour le Mode Art :
// Outils de dessin 2D (Ligne, Rectangle, Rectangle orienté, Cercle, Polygone, Arc, Main levée),
// Outils de transformation (Déplacer, Pivoter, Échelle, Symétrie),
// Outils de mesure (Mètre ruban, Cotation),
// Outil Pousser / Tirer (Extrusion SketchUp),
// Outils de menuiserie (Bande de chant, Rainure).

import 'dart:math' as math;

import 'art.dart';
import '../ui/art_camera.dart';

/// Outils CAO disponibles dans l'atelier Art.
enum CadTool {
  select('Sélection', 'Sélectionner et inspecter des panneaux ou esquisses'),
  line('Ligne', 'Tracer des segments précis'),
  freehand('Main levée', 'Tracé libre et courbes'),
  rectangle('Rectangle', 'Rectangle standard par deux points opposés'),
  rotatedRectangle('Rectangle orienté', 'Rectangle incliné par trois points (base + angle/hauteur)'),
  circle('Cercle', 'Cercle défini par son centre et son rayon'),
  polygon('Polygone', 'Polygone régulier (triangle, hexagone, octogone, etc.)'),
  arc('Arc', 'Arc de cercle défini par trois points'),
  move('Déplacer', 'Déplacer les éléments sélectionnés selon les axes X, Y, Z'),
  rotate('Pivoter', 'Faire pivoter les éléments selon un axe et un angle'),
  scale('Échelle', 'Mettre à l’échelle ou redimensionner'),
  symmetry('Symétrie', 'Créer un miroir selon un axe ou une face'),
  tape('Mètre ruban', 'Mesurer la distance exacte entre deux points'),
  dimension('Cotation', 'Ajouter une ligne de cote permanente avec valeur en mm'),
  pushPull('Pousser / Tirer', 'Extruder une esquisse 2D en panneau 3D ou épaissir/allonger une face'),
  edgeBand('Bande de chant', 'Appliquer ou modifier le chant (0.4, 1.0, 2.0 mm) sur les arêtes'),
  groove('Rainure', 'Créer ou configurer une rainure pour fond ou usinage');

  final String label;
  final String description;
  const CadTool(this.label, this.description);

  bool get isDrawing =>
      this == line ||
      this == freehand ||
      this == rectangle ||
      this == rotatedRectangle ||
      this == circle ||
      this == polygon ||
      this == arc;

  bool get isTransform =>
      this == move || this == rotate || this == scale || this == symmetry;

  bool get isMeasurement => this == tape || this == dimension;

  bool get isWoodwork => this == edgeBand || this == groove;
}

/// Forme 2D ou esquisse vectorielle dans l'espace 3D.
abstract class CadShape {
  final String id;
  bool selected;
  V3 normal;

  CadShape({required this.id, this.selected = false, this.normal = const V3(0, 0, -1)});

  List<V3> get vertices;
  bool get isClosed;

  Map<String, dynamic> toJson();

  static CadShape fromJson(Map<String, dynamic> j) {
    final type = j['type'] as String? ?? 'line';
    switch (type) {
      case 'rect':
        return CadRect.fromJson(j);
      case 'polyline':
        return CadPolyline.fromJson(j);
      case 'circle':
        return CadCircle.fromJson(j);
      case 'polygon':
        return CadPolygon.fromJson(j);
      case 'arc':
        return CadArc.fromJson(j);
      case 'freehand':
        return CadFreehand.fromJson(j);
      default:
        return CadLine.fromJson(j);
    }
  }

  /// Boîte englobante (min, max).
  (V3, V3) get bounds {
    final v = vertices;
    if (v.isEmpty) return (V3.zero, V3.zero);
    var minX = v.first.x, minY = v.first.y, minZ = v.first.z;
    var maxX = v.first.x, maxY = v.first.y, maxZ = v.first.z;
    for (final p in v) {
      minX = math.min(minX, p.x);
      minY = math.min(minY, p.y);
      minZ = math.min(minZ, p.z);
      maxX = math.max(maxX, p.x);
      maxY = math.max(maxY, p.y);
      maxZ = math.max(maxZ, p.z);
    }
    return (V3(minX, minY, minZ), V3(maxX, maxY, maxZ));
  }

  /// Centre géométrique de la forme.
  V3 get center {
    final v = vertices;
    if (v.isEmpty) return V3.zero;
    var sx = 0.0, sy = 0.0, sz = 0.0;
    for (final p in v) {
      sx += p.x;
      sy += p.y;
      sz += p.z;
    }
    final n = v.length.toDouble();
    return V3(sx / n, sy / n, sz / n);
  }

  /// Applique un déplacement relatif.
  void translate(V3 delta);

  /// Extrude la forme en un panneau ArtPanel 3D avec l'épaisseur [thickness].
  ArtPanel? extrude(String newId, double thickness, {String finish = 'blanc_mat', ArtRole role = ArtRole.decor}) {
    final (bMin, bMax) = bounds;
    final w = math.max(1.0, (bMax.x - bMin.x).abs());
    final h = math.max(1.0, (bMax.y - bMin.y).abs());
    final d = math.max(thickness, 1.0);
    return ArtPanel(
      id: newId,
      role: role,
      x: bMin.x,
      y: bMin.y,
      z: bMin.z,
      w: w,
      h: h,
      d: d,
      finish: finish,
    );
  }
}

/// Segment droit / Ligne.
class CadLine extends CadShape {
  V3 p1, p2;

  CadLine({required super.id, required this.p1, required this.p2, super.selected, super.normal});

  @override
  List<V3> get vertices => [p1, p2];

  @override
  bool get isClosed => false;

  double get length => (p2 - p1).length;

  @override
  void translate(V3 delta) {
    p1 = p1 + delta;
    p2 = p2 + delta;
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'line',
        'id': id,
        'p1': {'x': p1.x, 'y': p1.y, 'z': p1.z},
        'p2': {'x': p2.x, 'y': p2.y, 'z': p2.z},
      };

  factory CadLine.fromJson(Map<String, dynamic> j) {
    final p1 = j['p1'] as Map<String, dynamic>;
    final p2 = j['p2'] as Map<String, dynamic>;
    return CadLine(
      id: j['id'] as String,
      p1: V3((p1['x'] as num).toDouble(), (p1['y'] as num).toDouble(), (p1['z'] as num).toDouble()),
      p2: V3((p2['x'] as num).toDouble(), (p2['y'] as num).toDouble(), (p2['z'] as num).toDouble()),
    );
  }
}

/// Tracé libre à main levée.
class CadFreehand extends CadShape {
  final List<V3> points;

  CadFreehand({required super.id, required this.points, super.selected, super.normal});

  @override
  List<V3> get vertices => points;

  @override
  bool get isClosed => points.length > 2 && (points.first - points.last).length < 20;

  @override
  void translate(V3 delta) {
    for (var i = 0; i < points.length; i++) {
      points[i] = points[i] + delta;
    }
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'freehand',
        'id': id,
        'points': [for (final p in points) {'x': p.x, 'y': p.y, 'z': p.z}],
      };

  factory CadFreehand.fromJson(Map<String, dynamic> j) => CadFreehand(
        id: j['id'] as String,
        points: [
          for (final p in (j['points'] as List))
            V3(((p as Map)['x'] as num).toDouble(), (p['y'] as num).toDouble(), (p['z'] as num).toDouble())
        ],
      );
}

/// Rectangle 2D dans un plan 3D (standard ou orienté avec angle).
class CadRect extends CadShape {
  V3 p1, p2, p3, p4;
  double angle; // en radians

  CadRect({
    required super.id,
    required this.p1,
    required this.p2,
    required this.p3,
    required this.p4,
    this.angle = 0,
    super.selected,
    super.normal,
  });

  /// Construit un rectangle 2D dans le plan XY de face à partir de 2 coins opposés.
  factory CadRect.fromDiagonal(String id, V3 a, V3 b, {double z = 0, V3 normal = const V3(0, 0, -1)}) {
    final x0 = math.min(a.x, b.x), x1 = math.max(a.x, b.x);
    final y0 = math.min(a.y, b.y), y1 = math.max(a.y, b.y);
    return CadRect(
      id: id,
      p1: V3(x0, y0, z),
      p2: V3(x1, y0, z),
      p3: V3(x1, y1, z),
      p4: V3(x0, y1, z),
      angle: 0,
      normal: normal,
    );
  }

  /// Construit un rectangle orienté par 3 points : pA -> pB (axe de base) et pC pour la largeur/hauteur.
  factory CadRect.from3Points(String id, V3 pA, V3 pB, V3 pC) {
    final base = pB - pA;
    final baseLen = base.length;
    if (baseLen < 1e-4) {
      return CadRect.fromDiagonal(id, pA, pC);
    }
    final uBase = base * (1 / baseLen);
    // Vecteur perpendiculaire dans le même plan
    final vAC = pC - pA;
    final proj = uBase * vAC.dot(uBase);
    final perp = vAC - proj;
    final p3 = pB + perp;
    final p4 = pA + perp;
    final angle = math.atan2(base.y, base.x);
    return CadRect(
      id: id,
      p1: pA,
      p2: pB,
      p3: p3,
      p4: p4,
      angle: angle,
    );
  }

  @override
  List<V3> get vertices => [p1, p2, p3, p4];

  @override
  bool get isClosed => true;

  double get width => (p2 - p1).length;
  double get height => (p4 - p1).length;

  @override
  void translate(V3 delta) {
    p1 = p1 + delta;
    p2 = p2 + delta;
    p3 = p3 + delta;
    p4 = p4 + delta;
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'rect',
        'id': id,
        'p1': {'x': p1.x, 'y': p1.y, 'z': p1.z},
        'p2': {'x': p2.x, 'y': p2.y, 'z': p2.z},
        'p3': {'x': p3.x, 'y': p3.y, 'z': p3.z},
        'p4': {'x': p4.x, 'y': p4.y, 'z': p4.z},
        'angle': angle,
      };

  factory CadRect.fromJson(Map<String, dynamic> j) {
    V3 parseV3(Map m) => V3((m['x'] as num).toDouble(), (m['y'] as num).toDouble(), (m['z'] as num).toDouble());
    return CadRect(
      id: j['id'] as String,
      p1: parseV3(j['p1'] as Map),
      p2: parseV3(j['p2'] as Map),
      p3: parseV3(j['p3'] as Map),
      p4: parseV3(j['p4'] as Map),
      angle: (j['angle'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Cercle 2D dans l'espace 3D.
class CadCircle extends CadShape {
  V3 centerPt;
  double radius;

  CadCircle({
    required super.id,
    required this.centerPt,
    required this.radius,
    super.selected,
    super.normal,
  });

  @override
  List<V3> get vertices {
    const segments = 32;
    final pts = <V3>[];
    // Plan XY ou plan adapté selon la normale
    final isZ = normal.z.abs() > 0.8;
    for (var i = 0; i < segments; i++) {
      final theta = 2 * math.pi * i / segments;
      final dx = radius * math.cos(theta);
      final dy = radius * math.sin(theta);
      if (isZ) {
        pts.add(V3(centerPt.x + dx, centerPt.y + dy, centerPt.z));
      } else {
        pts.add(V3(centerPt.x + dx, centerPt.y, centerPt.z + dy));
      }
    }
    return pts;
  }

  @override
  bool get isClosed => true;

  @override
  void translate(V3 delta) {
    centerPt = centerPt + delta;
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'circle',
        'id': id,
        'center': {'x': centerPt.x, 'y': centerPt.y, 'z': centerPt.z},
        'radius': radius,
      };

  factory CadCircle.fromJson(Map<String, dynamic> j) {
    final c = j['center'] as Map;
    return CadCircle(
      id: j['id'] as String,
      centerPt: V3((c['x'] as num).toDouble(), (c['y'] as num).toDouble(), (c['z'] as num).toDouble()),
      radius: (j['radius'] as num).toDouble(),
    );
  }
}

/// Polygone régulier (3 pour triangle, 5 pentagone, 6 hexagone, 8 octogone, etc.).
class CadPolygon extends CadShape {
  V3 centerPt;
  double radius;
  int sides;
  double angle;

  CadPolygon({
    required super.id,
    required this.centerPt,
    required this.radius,
    this.sides = 6,
    this.angle = 0,
    super.selected,
    super.normal,
  });

  @override
  List<V3> get vertices {
    final n = math.max(3, sides);
    final pts = <V3>[];
    final isZ = normal.z.abs() > 0.8;
    for (var i = 0; i < n; i++) {
      final theta = angle + 2 * math.pi * i / n;
      final dx = radius * math.cos(theta);
      final dy = radius * math.sin(theta);
      if (isZ) {
        pts.add(V3(centerPt.x + dx, centerPt.y + dy, centerPt.z));
      } else {
        pts.add(V3(centerPt.x + dx, centerPt.y, centerPt.z + dy));
      }
    }
    return pts;
  }

  @override
  bool get isClosed => true;

  @override
  void translate(V3 delta) {
    centerPt = centerPt + delta;
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'polygon',
        'id': id,
        'center': {'x': centerPt.x, 'y': centerPt.y, 'z': centerPt.z},
        'radius': radius,
        'sides': sides,
        'angle': angle,
      };

  factory CadPolygon.fromJson(Map<String, dynamic> j) {
    final c = j['center'] as Map;
    return CadPolygon(
      id: j['id'] as String,
      centerPt: V3((c['x'] as num).toDouble(), (c['y'] as num).toDouble(), (c['z'] as num).toDouble()),
      radius: (j['radius'] as num).toDouble(),
      sides: (j['sides'] as num?)?.toInt() ?? 6,
      angle: (j['angle'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Arc de cercle défini par trois points (départ, fin, point intermédiaire / flèche).
class CadArc extends CadShape {
  V3 startPt, endPt, controlPt;

  CadArc({
    required super.id,
    required this.startPt,
    required this.endPt,
    required this.controlPt,
    super.selected,
    super.normal,
  });

  @override
  List<V3> get vertices {
    const segments = 24;
    final pts = <V3>[];
    // Approximation quadratique par courbe de Bézier pour un affichage net
    for (var i = 0; i <= segments; i++) {
      final t = i / segments.toDouble();
      final u = 1 - t;
      // B(t) = u^2 * P0 + 2*u*t * P1 + t^2 * P2
      final x = u * u * startPt.x + 2 * u * t * controlPt.x + t * t * endPt.x;
      final y = u * u * startPt.y + 2 * u * t * controlPt.y + t * t * endPt.y;
      final z = u * u * startPt.z + 2 * u * t * controlPt.z + t * t * endPt.z;
      pts.add(V3(x, y, z));
    }
    return pts;
  }

  @override
  bool get isClosed => false;

  @override
  void translate(V3 delta) {
    startPt = startPt + delta;
    endPt = endPt + delta;
    controlPt = controlPt + delta;
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'arc',
        'id': id,
        'start': {'x': startPt.x, 'y': startPt.y, 'z': startPt.z},
        'end': {'x': endPt.x, 'y': endPt.y, 'z': endPt.z},
        'control': {'x': controlPt.x, 'y': controlPt.y, 'z': controlPt.z},
      };

  factory CadArc.fromJson(Map<String, dynamic> j) {
    V3 parseV3(Map m) => V3((m['x'] as num).toDouble(), (m['y'] as num).toDouble(), (m['z'] as num).toDouble());
    return CadArc(
      id: j['id'] as String,
      startPt: parseV3(j['start'] as Map),
      endPt: parseV3(j['end'] as Map),
      controlPt: parseV3(j['control'] as Map),
    );
  }
}

/// Ligne de cote permanente dessinée dans l'espace avec texte de mesure (ex: « 800 mm »).
class CadDimension {
  final String id;
  V3 p1, p2;
  double offset; // décalage de la ligne de cote perpendiculaire
  String text;

  CadDimension({
    required this.id,
    required this.p1,
    required this.p2,
    this.offset = 40,
    String? text,
  }) : text = text ?? '${(p2 - p1).length.round()} mm';

  double get distance => (p2 - p1).length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'p1': {'x': p1.x, 'y': p1.y, 'z': p1.z},
        'p2': {'x': p2.x, 'y': p2.y, 'z': p2.z},
        'offset': offset,
        'text': text,
      };

  factory CadDimension.fromJson(Map<String, dynamic> j) {
    V3 parseV3(Map m) => V3((m['x'] as num).toDouble(), (m['y'] as num).toDouble(), (m['z'] as num).toDouble());
    return CadDimension(
      id: j['id'] as String,
      p1: parseV3(j['p1'] as Map),
      p2: parseV3(j['p2'] as Map),
      offset: (j['offset'] as num?)?.toDouble() ?? 40,
      text: j['text'] as String?,
    );
  }
}

/// Mesure temporaire de ruban à mesurer.
class CadTapeMeasure {
  V3 p1, p2;
  CadTapeMeasure(this.p1, this.p2);

  double get distance => (p2 - p1).length;
  double get dx => (p2.x - p1.x).abs();
  double get dy => (p2.y - p1.y).abs();
  double get dz => (p2.z - p1.z).abs();
}

/// Tracé polygonal multi-segments (ouvert ou fermé).
class CadPolyline extends CadShape {
  final List<V3> points;
  bool closed;

  CadPolyline({
    required super.id,
    required this.points,
    this.closed = false,
    super.selected,
    super.normal,
  });

  @override
  List<V3> get vertices => points;

  @override
  bool get isClosed => closed;

  @override
  void translate(V3 delta) {
    for (var i = 0; i < points.length; i++) {
      points[i] = points[i] + delta;
    }
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'polyline',
        'id': id,
        'closed': closed,
        'points': [for (final p in points) {'x': p.x, 'y': p.y, 'z': p.z}],
      };

  factory CadPolyline.fromJson(Map<String, dynamic> j) => CadPolyline(
        id: j['id'] as String,
        closed: (j['closed'] as bool?) ?? false,
        points: [
          for (final p in (j['points'] as List))
            V3(((p as Map)['x'] as num).toDouble(), (p['y'] as num).toDouble(), (p['z'] as num).toDouble())
        ],
      );
}

/// Plan de travail 2D pour contraindre les créations et esquisses dans l'espace 3D.
enum CadWorkPlane {
  ground('Sol (XZ)', 'Plan horizontal au sol', 1, 0),
  front('Façade (XY)', 'Plan vertical de face', 2, 0),
  side('Côté (YZ)', 'Plan vertical de profil', 0, 0);

  final String label;
  final String description;
  final int axis; // 0: X, 1: Y, 2: Z
  final double plane;
  const CadWorkPlane(this.label, this.description, this.axis, this.plane);
}

/// Contrainte orthogonale stricte à 90° (mode Ortho CAD).
V3 snapOrtho(V3 from, V3 to, CadWorkPlane plane) {
  switch (plane) {
    case CadWorkPlane.ground:
      final dx = (to.x - from.x).abs();
      final dz = (to.z - from.z).abs();
      return dx >= dz
          ? V3(to.x, from.y, from.z)
          : V3(from.x, from.y, to.z);
    case CadWorkPlane.front:
      final dx = (to.x - from.x).abs();
      final dy = (to.y - from.y).abs();
      return dx >= dy
          ? V3(to.x, from.y, from.z)
          : V3(from.x, to.y, from.z);
    case CadWorkPlane.side:
      final dy = (to.y - from.y).abs();
      final dz = (to.z - from.z).abs();
      return dy >= dz
          ? V3(from.x, to.y, from.z)
          : V3(from.x, from.y, to.z);
  }
}

/// Cible d'accrochage magnétique (Snap)
class CadSnapTarget {
  final V3 position;
  final String label;
  final bool isOrigin;
  CadSnapTarget({required this.position, required this.label, this.isOrigin = false});
}

/// Types d'usinage et perçages en menuiserie professionnelle
enum MachiningKind {
  dowel('Tourillon bois Ø8x35 mm', 'Positionnement précis et rigidité mécanique', 8.0, 35.0),
  screw('Vis d’assemblage Confirmat Ø7x50 mm', 'Liaison démontable caisson', 7.0, 50.0),
  shelfHole('Perçage taquet système 32 (Ø5 mm)', 'Pas de 32 mm pour étagère mobile', 5.0, 12.0),
  hingeCup('Boîtier charnière Ø35 mm', 'Fraisage boîtier encastré', 35.0, 12.5),
  groove('Rainure pour fond (10x8 mm)', 'Usinage longitudinal pour panneau de fond', 6.0, 8.0);

  final String label;
  final String description;
  final double diameter;
  final double depth;
  const MachiningKind(this.label, this.description, this.diameter, this.depth);
}

/// Élément unitaire d'usinage positionné dans l'espace 3D
class MachiningElement {
  final MachiningKind kind;
  final V3 position;
  final V3 normal;
  final double length;
  final double diameter;
  final String? panelId;
  final String? partnerPanelId;

  MachiningElement({
    required this.kind,
    required this.position,
    this.normal = const V3(0, 1, 0),
    this.length = 0,
    this.diameter = 0,
    this.panelId,
    this.partnerPanelId,
  });
}

/// Résumé global des usinages pour le projet
class MachiningSummary {
  final List<MachiningElement> elements;
  final int dowelsCount;
  final int screwsCount;
  final int shelfHolesCount;
  final int hingeCupsCount;
  final int groovesCount;
  final double totalEdgeMeters;
  final double totalGrooveMeters;

  MachiningSummary({
    required this.elements,
    required this.dowelsCount,
    required this.screwsCount,
    required this.shelfHolesCount,
    required this.hingeCupsCount,
    required this.groovesCount,
    required this.totalEdgeMeters,
    required this.totalGrooveMeters,
  });
}

/// Analyse l'ensemble des panneaux du projet pour calculer automatiquement tous les usinages
MachiningSummary computeMachiningElements(List<ArtPanel> panels) {
  final elements = <MachiningElement>[];
  var dowels = 0;
  var screws = 0;
  var shelfHoles = 0;
  var hingeCups = 0;
  var grooves = 0;
  var totalEdgeMeters = 0.0;
  var totalGrooveMeters = 0.0;

  // 1. Chants & Rainures déclarés sur les panneaux
  for (final p in panels) {
    if (p.edgeLong > 0) totalEdgeMeters += (p.w * p.edgeLong) / 1000.0;
    if (p.edgeShort > 0) totalEdgeMeters += (p.h * p.edgeShort) / 1000.0;
    if (p.hasGroove) {
      grooves++;
      final glen = p.grooveLong > 0 ? p.w : (p.grooveShort > 0 ? p.h : p.w);
      totalGrooveMeters += glen / 1000.0;
      elements.add(MachiningElement(
        kind: MachiningKind.groove,
        position: V3(p.x + p.w / 2, p.y + p.h / 2, p.z + p.grooveOffset),
        normal: const V3(0, 0, 1),
        length: glen,
        diameter: p.grooveWidth,
        panelId: p.id,
      ));
    }

    // 2. Boîtiers de charnières sur portes et façades
    if (p.role == ArtRole.porte || p.role.isFront) {
      final hCount = p.h > 1200 ? 3 : 2;
      final hingeSideX = (p.hinge == 'right') ? p.right - 21.5 : p.x + 21.5;
      final yPositions = [
        p.y + 100,
        if (hCount == 3) p.y + p.h / 2,
        p.top - 100,
      ];
      for (final hy in yPositions) {
        hingeCups++;
        elements.add(MachiningElement(
          kind: MachiningKind.hingeCup,
          position: V3(hingeSideX, hy, p.z + p.d),
          normal: const V3(0, 0, -1),
          diameter: 35.0,
          panelId: p.id,
        ));
      }
    }

    // 3. Perçages système 32 mm pour taquets sur les montants verticaux
    if (p.role == ArtRole.montant && p.h > 350) {
      final zFront = p.z + 37;
      final zBack = p.back - 37;
      final yStart = p.y + 160;
      final yEnd = p.top - 160;
      for (var y = yStart; y <= yEnd; y += 32) {
        shelfHoles += 2;
        elements.add(MachiningElement(
          kind: MachiningKind.shelfHole,
          position: V3(p.x + p.w / 2, y, zFront),
          normal: const V3(1, 0, 0),
          diameter: 5.0,
          panelId: p.id,
        ));
        elements.add(MachiningElement(
          kind: MachiningKind.shelfHole,
          position: V3(p.x + p.w / 2, y, zBack),
          normal: const V3(1, 0, 0),
          diameter: 5.0,
          panelId: p.id,
        ));
      }
    }
  }

  // 4. Jonctions mécaniques entre panneaux adjacents à 90° (Tourillons et Vis Confirmat)
  for (var i = 0; i < panels.length; i++) {
    final a = panels[i];
    for (var j = i + 1; j < panels.length; j++) {
      final b = panels[j];

      // Vérifie si les 2 panneaux se touchent ou sont adjacents (gap <= 2 mm)
      final xOverlap = math.max(0.0, math.min(a.right, b.right) - math.max(a.x, b.x));
      final yOverlap = math.max(0.0, math.min(a.top, b.top) - math.max(a.y, b.y));
      final zOverlap = math.max(0.0, math.min(a.back, b.back) - math.max(a.z, b.z));

      // Jonction X : A et B se touchent en X, se superposent en Y et Z
      final touchX = (a.right - b.x).abs() <= 2.5 || (b.right - a.x).abs() <= 2.5;
      final touchY = (a.top - b.y).abs() <= 2.5 || (b.top - a.y).abs() <= 2.5;

      if (touchX && yOverlap >= 12 && zOverlap >= 80) {
        final jX = (a.right - b.x).abs() <= 2.5 ? (a.right + b.x) / 2 : (b.right + a.x) / 2;
        final jY = (math.max(a.y, b.y) + math.min(a.top, b.top)) / 2;
        final z0 = math.max(a.z, b.z) + 40;
        final z1 = math.min(a.back, b.back) - 40;

        // 2 ou 3 Tourillons Ø8x35 mm
        dowels += 2;
        elements.add(MachiningElement(
          kind: MachiningKind.dowel,
          position: V3(jX, jY, z0),
          normal: const V3(1, 0, 0),
          diameter: 8.0,
          length: 35.0,
          panelId: a.id,
          partnerPanelId: b.id,
        ));
        elements.add(MachiningElement(
          kind: MachiningKind.dowel,
          position: V3(jX, jY, z1),
          normal: const V3(1, 0, 0),
          diameter: 8.0,
          length: 35.0,
          panelId: a.id,
          partnerPanelId: b.id,
        ));

        // 2 Vis Confirmat Ø7x50 mm
        screws += 2;
        elements.add(MachiningElement(
          kind: MachiningKind.screw,
          position: V3(jX, jY, z0 + 32),
          normal: const V3(1, 0, 0),
          diameter: 7.0,
          length: 50.0,
          panelId: a.id,
          partnerPanelId: b.id,
        ));
        elements.add(MachiningElement(
          kind: MachiningKind.screw,
          position: V3(jX, jY, z1 - 32),
          normal: const V3(1, 0, 0),
          diameter: 7.0,
          length: 50.0,
          panelId: a.id,
          partnerPanelId: b.id,
        ));
      } else if (touchY && xOverlap >= 12 && zOverlap >= 80) {
        final jY = (a.top - b.y).abs() <= 2.5 ? (a.top + b.y) / 2 : (b.top + a.y) / 2;
        final jX = (math.max(a.x, b.x) + math.min(a.right, b.right)) / 2;
        final z0 = math.max(a.z, b.z) + 40;
        final z1 = math.min(a.back, b.back) - 40;

        dowels += 2;
        elements.add(MachiningElement(
          kind: MachiningKind.dowel,
          position: V3(jX, jY, z0),
          normal: const V3(0, 1, 0),
          diameter: 8.0,
          length: 35.0,
          panelId: a.id,
          partnerPanelId: b.id,
        ));
        elements.add(MachiningElement(
          kind: MachiningKind.dowel,
          position: V3(jX, jY, z1),
          normal: const V3(0, 1, 0),
          diameter: 8.0,
          length: 35.0,
          panelId: a.id,
          partnerPanelId: b.id,
        ));

        screws += 2;
        elements.add(MachiningElement(
          kind: MachiningKind.screw,
          position: V3(jX, jY, z0 + 32),
          normal: const V3(0, 1, 0),
          diameter: 7.0,
          length: 50.0,
          panelId: a.id,
          partnerPanelId: b.id,
        ));
        elements.add(MachiningElement(
          kind: MachiningKind.screw,
          position: V3(jX, jY, z1 - 32),
          normal: const V3(0, 1, 0),
          diameter: 7.0,
          length: 50.0,
          panelId: a.id,
          partnerPanelId: b.id,
        ));
      }
    }
  }

  return MachiningSummary(
    elements: elements,
    dowelsCount: dowels,
    screwsCount: screws,
    shelfHolesCount: shelfHoles,
    hingeCupsCount: hingeCups,
    groovesCount: grooves,
    totalEdgeMeters: totalEdgeMeters,
    totalGrooveMeters: totalGrooveMeters,
  );
}
