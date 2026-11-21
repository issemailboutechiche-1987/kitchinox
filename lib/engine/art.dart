/// Mode Art (création libre) : le meuble est un ensemble de panneaux, chacun un pavé dans l'espace
/// (x de gauche à droite, y depuis le sol, z depuis la face avant vers le mur). On dessine librement ;
/// le débit, les assemblages (vis) et la quincaillerie se déduisent des panneaux et de leurs contacts.
library;

import 'dart:math' as math;

import 'art_box.dart';
import 'art_cad.dart';
import 'art_machining.dart';
import 'art_fittings.dart';
import 'cutting.dart';
import 'public_prices.dart';

/// Rôle d'un panneau : détermine le dessin, la matière par défaut, les chants et la quincaillerie.
enum ArtRole {
  montant('Montant'),
  tablette('Tablette'),
  porte('Porte'),
  tiroir('Façade de tiroir'),
  abattant('Abattant'),
  fond('Fond'),
  plateau('Plateau'),
  decor('Panneau décor');

  final String label;
  const ArtRole(this.label);
  bool get isFront => this == porte || this == tiroir || this == abattant;
}

class ArtPanel {
  final String id;
  ArtRole role;
  double x, y, z; // coin avant bas gauche (mm)
  double w, h, d; // largeur, hauteur, profondeur (mm)
  String finish; // finition (id de la façade ou du caisson)
  String hinge; // porte : 'left' | 'right'
  Comp? comp; // composant universel (caissons paramétriques)
  /// Perçages posés à la main : position depuis le coin bas avant gauche de la pièce, face (axe, sens), Ø, profondeur.
  final List<ArtHole> holes = [];
  String? note; // usinage particulier noté au débit (disque CNC, découpe circulaire)
  String? hingeType; // porte : type de charnière (null : celui du meuble)
  String? material; // panneau du tarif (MDF, latté, stratifié, mince) : matière, épaisseur et format de feuille

  // Usinages & menuiserie : chants et rainures
  int edgeLong; // chants sur côtés longs (0, 1, 2)
  int edgeShort; // chants sur côtés courts (0, 1, 2)
  double edgeThickness; // épaisseur chant (0.4, 1.0, 2.0 mm)
  bool hasGroove; // rainure présente
  double grooveOffset; // décalage depuis l'arête (mm)
  double grooveDepth; // profondeur (mm)
  double grooveWidth; // largeur (mm)
  int grooveLong; // rainure sur longueur (0, 1, 2)
  int grooveShort; // rainure sur largeur (0, 1, 2)

  ArtPanel({
    required this.id,
    required this.role,
    required this.x,
    required this.y,
    this.z = 0,
    required this.w,
    required this.h,
    required this.d,
    this.finish = 'blanc_mat',
    this.hinge = 'left',
    this.comp,
    this.material,
    this.hingeType,
    this.note,
    this.edgeLong = 0,
    this.edgeShort = 0,
    this.edgeThickness = 1.0,
    this.hasGroove = false,
    this.grooveOffset = 10,
    this.grooveDepth = 8,
    this.grooveWidth = 6,
    this.grooveLong = 0,
    this.grooveShort = 0,
  });

  double get right => x + w;
  double get top => y + h;
  double get back => z + d;
  double get thickness => [w, h, d].reduce(math.min);

  ArtPanel copy({String? id}) => _copy(id)..holes.addAll(holes.map((h) => h.copy()));

  ArtPanel _copy(String? id) => ArtPanel(
        id: id ?? this.id,
        role: role,
        x: x,
        y: y,
        z: z,
        w: w,
        h: h,
        d: d,
        finish: finish,
        hinge: hinge,
        comp: comp,
        material: material,
        hingeType: hingeType,
        note: note,
        edgeLong: edgeLong,
        edgeShort: edgeShort,
        edgeThickness: edgeThickness,
        hasGroove: hasGroove,
        grooveOffset: grooveOffset,
        grooveDepth: grooveDepth,
        grooveWidth: grooveWidth,
        grooveLong: grooveLong,
        grooveShort: grooveShort,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'x': x,
        'y': y,
        'z': z,
        'w': w,
        'h': h,
        'd': d,
        'finish': finish,
        'hinge': hinge,
        if (material != null) 'mat': material,
        if (hingeType != null) 'hinge_type': hingeType,
        if (note != null) 'note': note,
        if (holes.isNotEmpty) 'holes': [for (final h in holes) h.toJson()],
        'edge_long': edgeLong,
        'edge_short': edgeShort,
        'edge_th': edgeThickness,
        'groove': hasGroove,
        'groove_off': grooveOffset,
        'groove_depth': grooveDepth,
        'groove_w': grooveWidth,
        'groove_l': grooveLong,
        'groove_s': grooveShort,
      };

  factory ArtPanel.fromJson(Map<String, dynamic> j) => _fromJson(j)
    ..holes.addAll([for (final h in (j['holes'] as List? ?? const [])) ArtHole.fromJson((h as Map).cast<String, dynamic>())]);

  static ArtPanel _fromJson(Map<String, dynamic> j) => ArtPanel(
        id: '${j['id']}',
        role: ArtRole.values.firstWhere((r) => r.name == j['role'], orElse: () => ArtRole.decor),
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        z: (j['z'] as num?)?.toDouble() ?? 0,
        w: (j['w'] as num).toDouble(),
        h: (j['h'] as num).toDouble(),
        d: (j['d'] as num).toDouble(),
        finish: j['finish'] as String? ?? 'blanc_mat',
        hinge: j['hinge'] as String? ?? 'left',
        material: j['mat'] as String?,
        hingeType: j['hinge_type'] as String?,
        note: j['note'] as String?,
        edgeLong: (j['edge_long'] as num?)?.toInt() ?? 0,
        edgeShort: (j['edge_short'] as num?)?.toInt() ?? 0,
        edgeThickness: (j['edge_th'] as num?)?.toDouble() ?? 1.0,
        hasGroove: j['groove'] == true,
        grooveOffset: (j['groove_off'] as num?)?.toDouble() ?? 10.0,
        grooveDepth: (j['groove_depth'] as num?)?.toDouble() ?? 8.0,
        grooveWidth: (j['groove_w'] as num?)?.toDouble() ?? 6.0,
        grooveLong: (j['groove_l'] as num?)?.toInt() ?? 0,
        grooveShort: (j['groove_s'] as num?)?.toInt() ?? 0,
      );
}

/// Perçage posé à la main sur une pièce.
class ArtHole {
  double dx, dy, dz; // position depuis le coin bas avant gauche de la pièce (mm)
  int axis, sign; // face percée : axe de sa normale et sens
  double dia, depth;
  ArtHole({required this.dx, required this.dy, required this.dz, required this.axis, required this.sign, this.dia = 8, this.depth = 12});
  ArtHole copy() => ArtHole(dx: dx, dy: dy, dz: dz, axis: axis, sign: sign, dia: dia, depth: depth);
  Map<String, dynamic> toJson() => {'dx': dx, 'dy': dy, 'dz': dz, 'axis': axis, 'sign': sign, 'dia': dia, 'depth': depth};
  factory ArtHole.fromJson(Map<String, dynamic> j) => ArtHole(
        dx: (j['dx'] as num).toDouble(),
        dy: (j['dy'] as num).toDouble(),
        dz: (j['dz'] as num).toDouble(),
        axis: (j['axis'] as num).toInt(),
        sign: (j['sign'] as num).toInt(),
        dia: (j['dia'] as num?)?.toDouble() ?? 8,
        depth: (j['depth'] as num?)?.toDouble() ?? 12,
      );
}

/// Liaison de deux chants notée en mode découpe (pièces encore à plat) : appliquée par « Usiner ».
/// La pièce [a] passe sous (ou sur) la pièce [b], son chant [ea] contre le chant [eb] de [b].
class EdgeLink {
  final String a, b;
  final int ea, eb;
  String align; // start | center | end | custom
  double offset;
  bool over, miter;
  String? joint; // assemblage choisi (nom de JointType) ; null : automatique (réglage général)
  EdgeLink(this.a, this.ea, this.b, this.eb, {this.align = 'start', this.offset = 0, this.over = false, this.miter = false, this.joint});

  Map<String, dynamic> toJson() => {
        'a': a, 'ea': ea, 'b': b, 'eb': eb,
        if (align != 'start') 'align': align,
        if (offset != 0) 'offset': offset,
        if (over) 'over': true,
        if (miter) 'miter': true,
        if (joint != null) 'joint': joint,
      };
  factory EdgeLink.fromJson(Map<String, dynamic> j) => EdgeLink(j['a'] as String, (j['ea'] as num).toInt(), j['b'] as String, (j['eb'] as num).toInt(),
      align: j['align'] as String? ?? 'start',
      offset: (j['offset'] as num?)?.toDouble() ?? 0,
      over: j['over'] as bool? ?? false,
      miter: j['miter'] as bool? ?? false,
      joint: j['joint'] as String?);
}

class ArtProject {
  String name;
  double wallWidth, wallHeight;
  /// Caissons paramétriques, posés côte à côte de gauche à droite.
  final List<ArtBox> boxes;
  /// Panneaux libres (anciens projets, planches ajoutées à la main).
  final List<ArtPanel> free;
  /// Esquisses 2D (lignes, rectangles, cercles, polygones, arcs, main levée).
  final List<CadShape> sketches;
  /// Lignes de cotes / mesures enregistrées.
  final List<CadDimension> dimensions;
  /// Accessoires choisis : charnières, assemblages, suspension, pieds, jonction entre caissons.
  ArtFittings fittings = ArtFittings();
  /// Coupes d'angle notées par assemblage (« id1|id2 », ids triés) : 'onglet' (45°) ou 'chanfrein'.
  final Map<String, String> jointCuts = {};
  /// Assemblage choisi par jonction (« id1|id2 » → nom de JointType) ; absent : le réglage général.
  final Map<String, String> jointFits = {};
  /// Liaisons de chants notées en mode découpe, pas encore usinées.
  final List<EdgeLink> edgeLinks = [];
  /// Calques masqués / verrouillés : « comp:nom » pour un composant des caissons, identifiant pour une pièce libre.
  final Set<String> hiddenLayers = {}, lockedLayers = {};

  static String layerOf(ArtPanel p) => p.comp != null ? 'comp:${p.comp!.name}' : p.id;
  bool isHidden(ArtPanel p) => hiddenLayers.contains(layerOf(p));
  bool isLocked(ArtPanel p) => lockedLayers.contains(layerOf(p));

  static String jointKey(String a, String b) => a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';
  String? jointCut(ArtPanel a, ArtPanel b) => jointCuts[jointKey(a.id, b.id)];
  int _next = 1;

  ArtProject({
    this.name = 'Création libre',
    this.wallWidth = 3000,
    this.wallHeight = 2600,
    List<ArtPanel>? panels,
    List<ArtBox>? boxes,
    List<CadShape>? sketches,
    List<CadDimension>? dimensions,
  })  : free = panels ?? [],
        boxes = boxes ?? [],
        sketches = sketches ?? [],
        dimensions = dimensions ?? [] {
    for (final p in free) {
      final n = int.tryParse(p.id.replaceAll(RegExp(r'\D'), '')) ?? 0;
      if (n >= _next) _next = n + 1;
    }
  }

  String newId() => 'p${_next++}';

  /// Position (gauche du caisson) de chaque caisson, côte à côte.
  List<double> get boxOrigins {
    final out = <double>[];
    var x = 0.0;
    for (final b in boxes) {
      out.add(x + b.leftExtra);
      x += b.overallWidth;
    }
    return out;
  }

  /// Tous les panneaux : ceux des caissons (identifiants `b<n>_<k>`), puis les panneaux libres.
  List<ArtPanel> get panels {
    final out = <ArtPanel>[];
    final xs = boxOrigins;
    for (var i = 0; i < boxes.length; i++) {
      var k = 0;
      out.addAll(boxes[i].panels(() => 'b${i}_${k++}', ox: xs[i]));
    }
    return [...out, ...free];
  }

  bool get isEmpty => boxes.isEmpty && free.isEmpty && sketches.isEmpty;

  Map<String, dynamic> toJson() => {
        'name': name,
        'wall_width': wallWidth,
        'wall_height': wallHeight,
        if (boxes.isNotEmpty) 'boxes': [for (final b in boxes) b.toJson()],
        'panels': [for (final p in free) p.toJson()],
        if (sketches.isNotEmpty) 'sketches': [for (final s in sketches) s.toJson()],
        if (dimensions.isNotEmpty) 'dimensions': [for (final d in dimensions) d.toJson()],
        if (!fittings.isDefault) 'fittings': fittings.toJson(),
        if (jointCuts.isNotEmpty) 'joint_cuts': jointCuts,
        if (jointFits.isNotEmpty) 'joint_fits': jointFits,
        if (edgeLinks.isNotEmpty) 'edge_links': [for (final l in edgeLinks) l.toJson()],
        if (hiddenLayers.isNotEmpty) 'hidden': hiddenLayers.toList(),
        if (lockedLayers.isNotEmpty) 'locked': lockedLayers.toList(),
      };

  factory ArtProject.fromJson(Map<String, dynamic> j) => ArtProject(
        name: j['name'] as String? ?? 'Création libre',
        wallWidth: (j['wall_width'] as num?)?.toDouble() ?? 3000,
        wallHeight: (j['wall_height'] as num?)?.toDouble() ?? 2600,
        panels: [for (final p in (j['panels'] as List? ?? const [])) ArtPanel.fromJson((p as Map).cast<String, dynamic>())],
        boxes: [for (final b in (j['boxes'] as List? ?? const [])) ArtBox.fromJson((b as Map).cast<String, dynamic>())],
        sketches: [for (final s in (j['sketches'] as List? ?? const [])) CadShape.fromJson((s as Map).cast<String, dynamic>())],
        dimensions: [for (final d in (j['dimensions'] as List? ?? const [])) CadDimension.fromJson((d as Map).cast<String, dynamic>())],
      )
        ..fittings = ArtFittings.fromJson((j['fittings'] as Map?)?.cast<String, dynamic>() ?? const {})
        ..jointCuts.addAll({for (final e in ((j['joint_cuts'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'})
        ..jointFits.addAll({for (final e in ((j['joint_fits'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'})
        ..edgeLinks.addAll([for (final l in (j['edge_links'] as List? ?? const [])) EdgeLink.fromJson((l as Map).cast<String, dynamic>())])
        ..hiddenLayers.addAll([for (final e in (j['hidden'] as List? ?? const [])) '$e'])
        ..lockedLayers.addAll([for (final e in (j['locked'] as List? ?? const [])) '$e']);

  /// Encombrement (x0, y0, x1, y1) en vue de face.
  (double, double, double, double)? get bounds {
    if (panels.isEmpty) return null;
    return (
      panels.map((p) => p.x).reduce(math.min),
      panels.map((p) => p.y).reduce(math.min),
      panels.map((p) => p.right).reduce(math.max),
      panels.map((p) => p.top).reduce(math.max),
    );
  }

  // ---------------------------------------------------------------- outils de dessin
  /// Planche dessinée en vue de face : montant si elle est étroite, tablette si elle est basse, sinon façade.
  ArtPanel addDrawn(double x, double y, double w, double h, {double depth = 400, double t = 18, String finish = 'blanc_mat', ArtRole? role}) {
    final r = role ?? (w <= 40 ? ArtRole.montant : h <= 40 ? ArtRole.tablette : ArtRole.porte);
    final p = switch (r) {
      ArtRole.montant => ArtPanel(id: newId(), role: r, x: x, y: y, w: t, h: h, d: depth, finish: finish),
      ArtRole.tablette || ArtRole.plateau => ArtPanel(id: newId(), role: r, x: x, y: y, w: w, h: t, d: depth, finish: finish),
      ArtRole.fond => ArtPanel(id: newId(), role: r, x: x, y: y, z: depth - 6, w: w, h: h, d: 6, finish: finish),
      _ => ArtPanel(id: newId(), role: r, x: x, y: y, z: -t, w: w, h: h, d: t, finish: finish),
    };
    free.add(p);
    return p;
  }

  /// Caisson complet dans le rectangle : 2 côtés, dessus, dessous, fond 6 mm, et une ou deux portes.
  List<ArtPanel> addBox(double x, double y, double w, double h, {double depth = 400, double t = 18, int doors = 1, String carcass = 'blanc', String front = 'blanc_mat'}) {
    final out = <ArtPanel>[
      ArtPanel(id: newId(), role: ArtRole.montant, x: x, y: y, w: t, h: h, d: depth, finish: carcass),
      ArtPanel(id: newId(), role: ArtRole.montant, x: x + w - t, y: y, w: t, h: h, d: depth, finish: carcass),
      ArtPanel(id: newId(), role: ArtRole.tablette, x: x + t, y: y, w: w - 2 * t, h: t, d: depth, finish: carcass),
      ArtPanel(id: newId(), role: ArtRole.tablette, x: x + t, y: y + h - t, w: w - 2 * t, h: t, d: depth, finish: carcass),
      // fond de 6 mm encastré de 8 mm dans des rainures, à 10 mm du dos
      ArtPanel(id: newId(), role: ArtRole.fond, x: x + t - 8, y: y + t - 8, z: depth - 16, w: w - 2 * t + 16, h: h - 2 * t + 16, d: 6, finish: carcass),
    ];
    if (doors > 0) {
      final dw = (w - 4 - 3 * (doors - 1)) / doors;
      for (var i = 0; i < doors; i++) {
        out.add(ArtPanel(id: newId(), role: ArtRole.porte, x: x + 2 + i * (dw + 3), y: y + 2, z: -t, w: dw, h: h - 4, d: t, finish: front, hinge: i.isEven ? 'left' : 'right'));
      }
    }
    free.addAll(out);
    return out;
  }

  /// Copie miroir (symétrie gauche-droite) des panneaux choisis, posée à droite de l'ensemble.
  List<ArtPanel> mirror(List<ArtPanel> sel) {
    if (sel.isEmpty) return const [];
    final x0 = sel.map((p) => p.x).reduce(math.min), x1 = sel.map((p) => p.right).reduce(math.max);
    // symétrie autour du bord droit : la copie occupe [x1, x1 + (x1 - x0)]
    assert(x0 <= x1);
    final out = [
      for (final p in sel)
        p.copy(id: newId())
          ..x = x1 + (x1 - p.right)
          ..hinge = p.hinge == 'left' ? 'right' : 'left',
    ];
    free.addAll(out);
    return out;
  }

  // ---------------------------------------------------------------- assemblage de deux pièces
  static double _lo(ArtPanel p, int a) => a == 0 ? p.x : a == 1 ? p.y : p.z;
  static double _hi(ArtPanel p, int a) => a == 0 ? p.right : a == 1 ? p.top : p.back;
  static double _th(ArtPanel p) => [p.w, p.h, p.d].reduce(math.min);
  static int _ta(ArtPanel p) => p.w <= p.h && p.w <= p.d ? 0 : (p.h <= p.d ? 1 : 2);
  static void _setLo(ArtPanel p, int a, double v) {
    final hi = _hi(p, a);
    if (a == 0) {
      p.x = v;
      p.w = hi - v;
    } else if (a == 1) {
      p.y = v;
      p.h = hi - v;
    } else {
      p.z = v;
      p.d = hi - v;
    }
  }

  static void _setHi(ArtPanel p, int a, double v) {
    if (a == 0) {
      p.w = v - p.x;
    } else if (a == 1) {
      p.h = v - p.y;
    } else {
      p.d = v - p.z;
    }
  }

  /// Angle formé par [a] et [b] : axe de contact, pièce qui présente sa face (hôte) et celle qui présente son chant.
  /// Null si elles ne se touchent pas en angle.
  static (int, ArtPanel, ArtPanel)? corner(ArtPanel a, ArtPanel b) {
    double ov(int k) => math.min(_hi(a, k), _hi(b, k)) - math.max(_lo(a, k), _lo(b, k));
    for (var ax = 0; ax < 3; ax++) {
      final touch = (_hi(a, ax) - _lo(b, ax)).abs() <= 0.6 || (_hi(b, ax) - _lo(a, ax)).abs() <= 0.6;
      if (!touch) continue;
      final others = [for (var k = 0; k < 3; k++) if (k != ax) k];
      if (ov(others[0]) < 5 || ov(others[1]) < 5) continue;
      final aFace = _ta(a) == ax, bFace = _ta(b) == ax;
      if (aFace == bFace) continue;
      return aFace ? (ax, a, b) : (ax, b, a);
    }
    return null;
  }

  /// Fait passer [top] par-dessus [under] dans leur angle : [top] couvre le chant de [under],
  /// qui se raccourcit d'autant (les cotes extérieures du meuble ne changent pas).
  bool putOver(ArtPanel top, ArtPanel under) {
    final c = corner(top, under);
    if (c == null) return false;
    final (ax, host, guest) = c;
    if (identical(host, top)) return true; // déjà dessus
    // aujourd'hui : [under] (hôte) présente sa face, [top] (invité) vient buter contre elle
    final gt = _ta(guest), ht = _th(host), gth = _th(guest);
    // l'hôte se raccourcit du côté où se trouve l'invité, de l'épaisseur de l'invité
    final guestAtHi = (_lo(guest, gt) + _hi(guest, gt)) / 2 > (_lo(host, gt) + _hi(host, gt)) / 2;
    if (guestAtHi) {
      _setHi(host, gt, _hi(host, gt) - gth);
    } else {
      _setLo(host, gt, _lo(host, gt) + gth);
    }
    // l'invité s'allonge vers l'hôte pour couvrir son chant
    final hostAtHi = (_lo(host, ax) + _hi(host, ax)) / 2 > (_lo(guest, ax) + _hi(guest, ax)) / 2;
    if (hostAtHi) {
      _setHi(guest, ax, _hi(guest, ax) + ht);
    } else {
      _setLo(guest, ax, _lo(guest, ax) - ht);
    }
    jointCuts.remove(jointKey(top.id, under.id));
    return true;
  }

  /// Coupe d'angle à 45° (onglet) entre [a] et [b] : les deux pièces vont jusqu'à l'angle extérieur ;
  /// [kind] 'onglet', 'chanfrein' (arête abattue, assemblage inchangé) ou null (bout à bout).
  bool setJointCut(ArtPanel a, ArtPanel b, String? kind) {
    final key = jointKey(a.id, b.id);
    if (kind == 'onglet' && jointCuts[key] != 'onglet') {
      final c = corner(a, b);
      if (c == null) return false;
      final (ax, host, guest) = c;
      // l'invité s'allonge jusqu'à la face extérieure de l'hôte : les deux bouts seront coupés à 45°
      final hostAtHi = (_lo(host, ax) + _hi(host, ax)) / 2 > (_lo(guest, ax) + _hi(guest, ax)) / 2;
      if (hostAtHi) {
        _setHi(guest, ax, _hi(guest, ax) + _th(host));
      } else {
        _setLo(guest, ax, _lo(guest, ax) - _th(host));
      }
    } else if (kind != 'onglet' && jointCuts[key] == 'onglet') {
      // retour au bout à bout : la pièce la plus longue sur l'axe commun reprend sa place d'invitée
      final aT = _ta(a), bT = _ta(b);
      // l'invité est celui qui déborde dans l'épaisseur de l'autre
      final aIntoB = math.min(_hi(a, bT), _hi(b, bT)) - math.max(_lo(a, bT), _lo(b, bT)) > 0.6;
      final guest = aIntoB ? a : b, host = aIntoB ? b : a;
      final ax = _ta(host);
      final hostAtHi = (_lo(host, ax) + _hi(host, ax)) / 2 > (_lo(guest, ax) + _hi(guest, ax)) / 2;
      if (hostAtHi) {
        _setHi(guest, ax, _lo(host, ax));
      } else {
        _setLo(guest, ax, _hi(host, ax));
      }
      assert(aT >= 0);
    }
    if (kind == null) {
      jointCuts.remove(key);
    } else {
      jointCuts[key] = kind;
    }
    return true;
  }

  /// Les 4 chants d'une pièce, numérotés 1 à 4 : (axe de la normale, sens).
  /// 1 : bas de la largeur, 2 : bout droit de la longueur, 3 : haut de la largeur, 4 : bout gauche.
  static List<(int, int)> edgesOf(ArtPanel p) {
    final t = _ta(p);
    final ins = [for (var k = 0; k < 3; k++) if (k != t) k];
    final u = (_hi(p, ins[0]) - _lo(p, ins[0])) >= (_hi(p, ins[1]) - _lo(p, ins[1])) ? ins[0] : ins[1];
    final v = ins.firstWhere((k) => k != u);
    return [(v, -1), (u, 1), (v, 1), (u, -1)];
  }

  /// Lie le chant [ea] (1 à 4) de [a] au chant [eb] de [b] : [a] se place sous [b], perpendiculaire,
  /// son chant contre la face de [b], à fleur du chant [eb] ; [b] passe dessus (il couvre le chant de [a]).
  /// [b] ne bouge pas. Faux si les numéros sont hors de 1 à 4.
  static bool linkEdges(ArtPanel a, int ea, ArtPanel b, int eb, {String align = 'start', double offset = 0, bool over = false}) {
    if (ea < 1 || ea > 4 || eb < 1 || eb > 4) return false;
    final (aAx, _) = edgesOf(a)[ea - 1];
    final (bAx, bSign) = edgesOf(b)[eb - 1];
    final tb = _ta(b);
    final lb = [0, 1, 2].firstWhere((k) => k != tb && k != bAx); // direction du chant de b
    // dimensions de a : épaisseur, longueur de son chant, hauteur (distance de ce chant au chant opposé)
    final ta = _ta(a);
    final aLen = [0, 1, 2].firstWhere((k) => k != ta && k != aAx); // le chant de a court le long de cet axe
    final t = _th(a), len = _hi(a, aLen) - _lo(a, aLen), h = _hi(a, aAx) - _lo(a, aAx);
    final lo = <int, double>{}, hi = <int, double>{};
    // le long du chant de b : aligné au début, au centre, à la fin, ou décalé de [offset] depuis le début
    lo[lb] = switch (align) {
      'end' => _hi(b, lb) - len,
      'center' => (_lo(b, lb) + _hi(b, lb) - len) / 2,
      'custom' => _lo(b, lb) + offset,
      _ => _lo(b, lb),
    };
    hi[lb] = lo[lb]! + len;
    // sous b (côté négatif de son épaisseur) ou dessus, collé à sa face
    if (over) {
      lo[tb] = _hi(b, tb);
      hi[tb] = lo[tb]! + h;
    } else {
      hi[tb] = _lo(b, tb);
      lo[tb] = hi[tb]! - h;
    }
    // à fleur du chant choisi de b, vers l'intérieur
    if (bSign > 0) {
      hi[bAx] = _hi(b, bAx);
      lo[bAx] = hi[bAx]! - t;
    } else {
      lo[bAx] = _lo(b, bAx);
      hi[bAx] = lo[bAx]! + t;
    }
    a
      ..x = lo[0]!
      ..y = lo[1]!
      ..z = lo[2]!
      ..w = hi[0]! - lo[0]!
      ..h = hi[1]! - lo[1]!
      ..d = hi[2]! - lo[2]!;
    if (a.role == ArtRole.decor || a.role == ArtRole.tablette) a.role = bAx == 0 ? ArtRole.montant : a.role;
    return true;
  }

  /// Pièces assemblées selon [links], dans l'ordre (copies : les pièces à plat ne bougent pas).
  /// Une liaison dont une pièce manque est ignorée.
  static List<ArtPanel> assembleLinks(List<ArtPanel> flat, List<EdgeLink> links) {
    final out = [for (final p in flat) p.copy(id: p.id)];
    final byId = {for (final p in out) p.id: p};
    for (final l in links) {
      final a = byId[l.a], b = byId[l.b];
      if (a == null || b == null || identical(a, b)) continue;
      linkEdges(a, l.ea, b, l.eb, align: l.align, offset: l.offset, over: l.over);
    }
    return out;
  }

  /// Usine les liaisons notées : les pièces prennent leur place assemblée, les onglets et les assemblages
  /// choisis sont enregistrés, puis la liste est vidée. Renvoie le nombre de liaisons appliquées.
  int applyEdgeLinks() {
    final done = edgeLinks.where((l) => free.any((p) => p.id == l.a) && free.any((p) => p.id == l.b) && l.a != l.b).toList();
    final placed = {for (final p in assembleLinks(free, done)) p.id: p};
    for (final p in free) {
      final q = placed[p.id]!;
      p
        ..x = q.x
        ..y = q.y
        ..z = q.z
        ..w = q.w
        ..h = q.h
        ..d = q.d
        ..role = q.role;
    }
    for (final l in done) {
      final key = jointKey(l.a, l.b);
      jointCuts.remove(key);
      final a = free.firstWhere((p) => p.id == l.a), b = free.firstWhere((p) => p.id == l.b);
      if (l.miter) setJointCut(a, b, 'onglet');
      if (l.joint == null) {
        jointFits.remove(key);
      } else {
        jointFits[key] = l.joint!;
      }
    }
    edgeLinks.clear();
    return done.length;
  }

  /// Oriente [p] : 'montant' (debout, épaisseur en largeur), 'tablette' (à plat), 'facade' (de face) ;
  /// sa plus grande dimension devient la hauteur (montant, façade) ou la largeur (tablette). Le coin bas avant gauche reste en place.
  static void orient(ArtPanel p, String how) {
    final d = [p.w, p.h, p.d]..sort();
    final (t, mid, big) = (d[0], d[1], d[2]);
    switch (how) {
      case 'montant':
        p.w = t;
        p.h = big;
        p.d = mid;
        if (p.role.isFront || p.role == ArtRole.tablette) p.role = ArtRole.montant;
      case 'tablette':
        p.w = big;
        p.h = t;
        p.d = mid;
        if (p.role.isFront || p.role == ArtRole.montant) p.role = ArtRole.tablette;
      default:
        p.w = mid;
        p.h = big;
        p.d = t;
    }
  }

  // ---------------------------------------------------------------- débit et assemblage
  /// Matière d'un panneau : façades et décors en MDF façade, fonds minces en HDF, le reste en caisson.
  /// Panneau du tarif choisi pour [p], s'il existe.
  static PublicPanel? panelOf(ArtPanel p) => p.material == null ? null : PublicPrices.byId(p.material!);

  /// Le panneau a un sens (veinage d'un décor, âme d'un latté) : pas de rotation au débit.
  static bool hasGrain(ArtPanel p) {
    final pp = panelOf(p);
    if (pp == null) return false;
    return pp.family == 'Latté' || !(pp.id.contains('blanc') || pp.id.contains('noir'));
  }

  static String materialOf(ArtPanel p) {
    final pp = panelOf(p);
    if (pp != null) return '${pp.name} ${pp.thickness} · ${pp.length}×${pp.width}';
    final t = p.thickness.round();
    if (p.role == ArtRole.fond || t <= 8) return 'HDF $t (fonds)';
    if (p.role.isFront || p.role == ArtRole.decor || p.role == ArtRole.plateau) return 'MDF $t (façades)';
    return 'MDF $t (caisson)';
  }

  List<CutPart> cutParts() {
    final parts = <String, CutPart>{};
    for (final b in boxes) {
      for (final c in b.cutParts()) {
        parts.containsKey(c.key) ? parts[c.key]!.qty += c.qty : parts[c.key] = c;
      }
    }
    // chants et rainures déduits de l'usinage (arêtes visibles, fonds encastrés), sauf réglage manuel du panneau
    final work = free.isEmpty ? const <String, PanelWork>{} : computeMachiningElements(panels, fittings: fittings, jointCuts: jointCuts, jointFits: jointFits).work;
    for (final p in free) {
      final dims = [p.w, p.h, p.d]..sort();
      final a = dims[2].round(), b = dims[1].round();
      if (a <= 0 || b <= 0) continue;
      final front = p.role.isFront || p.role == ArtRole.decor || p.role == ArtRole.plateau;
      final w = work[p.id];
      final manual = p.edgeLong > 0 || p.edgeShort > 0;
      final eLong = manual ? p.edgeLong : (w?.edgeLong ?? 0).clamp(0, 2);
      final eShort = manual ? p.edgeShort : (w?.edgeShort ?? 0).clamp(0, 2);
      final gLong = p.hasGroove ? math.max(1, p.grooveLong) : (w?.grooveLong ?? 0);
      final gShort = p.hasGroove ? p.grooveShort : (w?.grooveShort ?? 0);
      final cuts = [
        for (final e in jointCuts.entries)
          if (e.key.split('|').contains(p.id)) e.value == 'onglet' ? 'onglet 45°' : 'chanfrein',
      ];
      final c = CutPart(
        materialOf(p),
        [p.role.label, if (cuts.isNotEmpty) '(${cuts.toSet().join(', ')})', if (p.note != null) '(${p.note})'].join(' '),
        'Art',
        a,
        b,
        1,
        // matière choisie : seul son sens (décor, latté) interdit de tourner ; sinon, façades sans rotation
        canRotate: panelOf(p) != null ? !hasGrain(p) : !front,
        edgeLong: eLong,
        edgeShort: eShort,
        grooveLong: gLong,
        grooveShort: gShort,
      );
      parts.containsKey(c.key) ? parts[c.key]!.qty++ : parts[c.key] = c;
    }
    return parts.values.toList();
  }

  /// Contacts entre panneaux (faces qui se touchent) : longueur de la jonction (mm).
  List<(ArtPanel, ArtPanel, double)> joints() {
    final out = <(ArtPanel, ArtPanel, double)>[];
    double ov(double a0, double a1, double b0, double b1) => math.max(0, math.min(a1, b1) - math.max(a0, b0));
    bool touch(double a, double b) => (a - b).abs() < 1.5;
    final panels = free;
    for (var i = 0; i < panels.length; i++) {
      for (var j = i + 1; j < panels.length; j++) {
        final a = panels[i], b = panels[j];
        if (a.role.isFront || b.role.isFront) continue; // les façades se fixent par charnières / coulisses
        final ox = ov(a.x, a.right, b.x, b.right), oy = ov(a.y, a.top, b.y, b.top), oz = ov(a.z, a.back, b.z, b.back);
        double len = 0;
        if ((touch(a.right, b.x) || touch(b.right, a.x)) && oy > 0 && oz > 0) len = math.max(oy, oz);
        if ((touch(a.top, b.y) || touch(b.top, a.y)) && ox > 0 && oz > 0) len = math.max(len, math.max(ox, oz));
        if ((touch(a.back, b.z) || touch(b.back, a.z)) && ox > 0 && oy > 0) len = math.max(len, math.max(ox, oy));
        if (len > 30) out.add((a, b, len));
      }
    }
    return out;
  }

  /// Quincaillerie et visserie : (désignation, usage, quantité).
  List<(String, String, int)> hardware() {
    final out = <String, (String, double)>{};
    void add(String name, String usage, double q) {
      if (q > 0) out[name] = (out[name]?.$1 ?? usage, (out[name]?.$2 ?? 0) + q);
    }

    for (final bx in boxes) {
      for (final (name, usage, q) in bx.hardware()) {
        add(name, usage, q.toDouble());
      }
    }
    // panneaux libres : quincaillerie et visserie posées par l'usinage (jonctions, façades, pieds, taquets)
    if (free.isNotEmpty) {
      final ids = {for (final p in free) p.id};
      final els = computeMachiningElements(panels, fittings: fittings, jointCuts: jointCuts, jointFits: jointFits)
          .elements
          .where((e) => ids.contains(e.panelId) || ids.contains(e.partnerPanelId))
          .toList();
      for (final (name, usage, q) in machiningHardware(els, fittings: fittings)) {
        add(name, usage, q.toDouble());
      }
    }
    final pinned = free.isEmpty
        ? const <String>{}
        : {for (final e in computeMachiningElements(panels, fittings: fittings, jointCuts: jointCuts, jointFits: jointFits).elements) if (e.kind == MachiningKind.shelfPin) e.panelId};
    for (final p in free) {
      switch (p.role) {
        case ArtRole.tablette:
          // tablette libre (ne touche aucun montant, ni posée sur taquets) : fixation murale invisible
          if (!pinned.contains(p.id) && !joints().any((j) => identical(j.$1, p) || identical(j.$2, p))) {
            add('Tiges supports invisibles pour étagère flottante', 'tablettes fixées au mur', 2);
            add('Chevilles Ø8 + vis Ø6 x 80 mm', 'fixation murale des tablettes', 2);
          }
        default:
          break;
      }
    }
    final b = free.isEmpty ? null : bounds;
    if (b != null && b.$4 - b.$2 >= 1500) {
      add('Équerre anti-basculement + cheville Ø6', 'meuble haut fixé au mur', 2);
    }
    return [for (final e in out.entries) (e.key, e.value.$1, e.value.$2.ceil())];
  }

  CutPlan plan(CutSettings cs) => nest(cutParts(), cs);
}

/// Modèles de départ du mode Art.
class ArtStarter {
  final String name, description;
  final void Function(ArtProject p) build;
  const ArtStarter(this.name, this.description, this.build);
}

final artStarters = <ArtStarter>[
  ArtStarter('Étagère en escalier', 'Cinq tablettes décalées et trois montants, à poser contre le mur.', (p) {
    const d = 300.0, t = 18.0;
    for (var i = 0; i < 3; i++) {
      p.addDrawn(400.0 + i * 400, 0, t, 400.0 + i * 400, depth: d, role: ArtRole.montant, finish: 'chene');
    }
    for (var i = 0; i < 3; i++) {
      p.addDrawn(400.0 + t, 400.0 + i * 400 - t, 400.0 * (3 - i) - t, t, depth: d, role: ArtRole.tablette, finish: 'chene');
    }
  }),
  ArtStarter('Console d’entrée', 'Plateau suspendu de 1200, un tiroir, deux joues pleines.', (p) {
    const d = 350.0;
    p.addDrawn(600, 600, 18, 250, depth: d, role: ArtRole.montant, finish: 'noyer');
    p.addDrawn(600 + 1200 - 18, 600, 18, 250, depth: d, role: ArtRole.montant, finish: 'noyer');
    p.addDrawn(618, 832, 1164, 18, depth: d, role: ArtRole.plateau, finish: 'noyer');
    p.addDrawn(618, 600, 1164, 18, depth: d, role: ArtRole.tablette, finish: 'noyer');
    p.addDrawn(622, 622, 1156, 206, role: ArtRole.tiroir, finish: 'noyer');
  }),
  ArtStarter('Bibliothèque géométrique', 'Grille 3 x 4 de niches ouvertes, toute hauteur.', (p) {
    const d = 350.0, t = 18.0, cw = 400.0, ch = 450.0;
    for (var c = 0; c <= 3; c++) {
      p.addDrawn(300 + c * (cw + t), 0, t, 4 * (ch + t) + t, depth: d, role: ArtRole.montant, finish: 'blanc');
    }
    for (var r = 0; r <= 4; r++) {
      for (var c = 0; c < 3; c++) {
        p.addDrawn(300 + t + c * (cw + t), r * (ch + t), cw, t, depth: d, role: ArtRole.tablette, finish: 'blanc');
      }
    }
  }),
  ArtStarter('Banc à coffre', 'Banc de 1400 x 450, deux tiroirs, assise en 36 mm.', (p) {
    p.addBox(500, 0, 1400, 414, depth: 450, doors: 0, carcass: 'chene');
    p.addDrawn(500, 414, 1400, 36, depth: 450, role: ArtRole.plateau, finish: 'chene');
    p.addDrawn(502, 2, 696, 410, role: ArtRole.tiroir, finish: 'vert_sauge');
    p.addDrawn(1201, 2, 697, 410, role: ArtRole.tiroir, finish: 'vert_sauge');
  }),
  ArtStarter('Table de chevet suspendue', 'Caisson 500 x 250, une façade de tiroir, posé à 450 mm.', (p) {
    p.addBox(800, 450, 500, 250, depth: 380, doors: 0, carcass: 'blanc');
    p.addDrawn(802, 452, 496, 246, role: ArtRole.tiroir, finish: 'terracotta');
  }),
  ArtStarter('Buffet deux portes', 'Caisson 1200 x 800 sur socle, deux portes, une tablette.', (p) {
    p.addBox(600, 100, 1200, 750, depth: 450, doors: 2, carcass: 'blanc', front: 'bleu_nuit');
    p.addDrawn(618, 100 + 375, 1164, 18, depth: 430, role: ArtRole.tablette, finish: 'blanc');
    p.addDrawn(620, 0, 1160, 100, role: ArtRole.decor, finish: 'bleu_nuit');
  }),
];
