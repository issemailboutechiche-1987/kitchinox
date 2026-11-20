// Atelier Art : le meuble se construit sur la base universelle d'un caisson en panneaux de bois.
// À gauche, les réglages par étape (Caisson, Intérieur, Façades, Extérieur, Débit) ; au centre la 3D :
// un doigt tourne, deux doigts déplacent et zooment, toucher une zone la choisit pour régler sa façade.
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/engine.dart';
import '../engine/art_cad.dart';
import '../engine/art_machining.dart';
import 'app_state.dart';
import 'art_cad_toolbar.dart';
import 'art_library.dart';
import 'art_camera.dart';
import 'busy.dart';
import 'cut_pdf.dart';
import 'finishes.dart';
import 'logo.dart';
import 'manual_cut_page.dart';
import 'session.dart';
import 'theme.dart';
import 'web_io.dart';
import 'i18n.dart';

Future<void> openArt(BuildContext context, AppState state) {
  Session.route = 'art';
  return Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => LeaveGuard(
      id: 'art',
      current: () => jsonEncode(state.project.art.toJson()),
      revert: (saved) => state.project.art = saved == null || saved.isEmpty ? ArtProject() : ArtProject.fromJson(jsonDecode(saved) as Map<String, dynamic>),
      child: ArtPage(state: state),
    ),
  ));
}

/// Couleur d'une finition (façades ou caissons).
Color artColor(String id) =>
    (fronts.where((f) => f.id == id).firstOrNull ?? carcasses.where((f) => f.id == id).firstOrNull)?.color ?? const Color(0xFFE9E4DC);

const _orange = Color(0xFFF26A1B);

class ArtPage extends StatefulWidget {
  final AppState state;
  const ArtPage({super.key, required this.state});
  @override
  State<ArtPage> createState() => _ArtPageState();
}

class _ArtPageState extends State<ArtPage> {
  ArtProject get art => widget.state.project.art;
  final cam = ArtCamera();
  int boxIndex = 0;
  String? zoneId;
  int column = 0;
  String tab = 'caisson';
  bool showFronts = true;
  bool showDims = true;
  bool exploded = false; // vue éclatée : chaque composant écarté de sa place
  bool byComp = false; // couleurs par composant
  Comp? focus; // composant mis en avant (les autres en transparence)
  final _undo = <String>[], _redo = <String>[];
  Offset? _last;
  Offset? _downAt;
  bool _moved = false;
  double _lastScale = 1.0;

  ArtBox? get box => art.boxes.isEmpty ? null : art.boxes[boxIndex.clamp(0, art.boxes.length - 1)];

  // Outils CAO & Création libre (SketchUp style)
  CadTool activeTool = CadTool.select;
  String cadStatus = '';
  final List<V3> activePoints = [];
  CadShape? previewShape;
  CadTapeMeasure? activeTape;
  ArtPanel? selectedPanel;
  final Set<ArtPanel> selection = {};
  String? drawMaterial; // matière du tarif des prochains panneaux (null : selon le rôle) // Ctrl (ou Maj) + clic : plusieurs panneaux
  CadShape? selectedShape;
  Face? hoveredFace;
  double pushPullThickness = 18.0;
  double edgeThickness = 1.0;
  bool isMachiningMode = false;
  CadWorkPlane workPlane = CadWorkPlane.ground;
  bool orthoLock = true;
  bool autoExtrude = true;
  CadSnapTarget? activeSnapTarget;

  // plan de dessin, fixé au 1er point : la face touchée (dessin sur un panneau) ou le plan de travail
  int _drawAxis = 1;
  double _drawPlane = 0;
  double _drawSign = 1;
  bool _drawOnFront = false;
  V3? _hover; // dernier point survolé sur le plan de dessin (sens des cotes saisies)
  // cotes saisies au clavier (comme la boîte « Mesures » de SketchUp)
  final measure = TextEditingController();
  final measureFocus = FocusNode();
  // glisser : Pousser/Tirer une face, déplacer un panneau
  Face? _dragFace;
  ArtPanel? _dragPanel;
  List<double>? _dragOrig; // x, y, z, w, h, d au début du geste
  Map<ArtPanel, List<double>> _dragOthers = {}; // autres panneaux sélectionnés, déplacés ensemble
  String? _dragUndo;
  V3? _dragHit0;
  (Face, List<double>)? _lastPush;
  bool _pressPlaced = false; // le doigt a posé le 1er point en appuyant : glisser puis lâcher termine la forme // dernière face poussée : une cote tapée ensuite la règle exactement

  /// Point à l'écran (repère de la vue 3D) d'un point de l'espace : pour les tests.
  Offset screenOf(double x, double y, double z) => cam.project(V3(x, y, z)).$1;

  @override
  void dispose() {
    measure.dispose();
    measureFocus.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    cam.fit(art.panels);
    final b = box;
    if (b != null) zoneId = b.zones.first.id;
  }

  // ---------------------------------------------------------------- historique
  String _snap() => jsonEncode(art.toJson());

  void _restore(String s) {
    final a = ArtProject.fromJson(jsonDecode(s) as Map<String, dynamic>);
    art.boxes
      ..clear()
      ..addAll(a.boxes);
    art.free
      ..clear()
      ..addAll(a.free);
    art.sketches
      ..clear()
      ..addAll(a.sketches);
    art.dimensions
      ..clear()
      ..addAll(a.dimensions);
    boxIndex = boxIndex.clamp(0, math.max(0, art.boxes.length - 1));
  }

  /// Une modification : mémorisée pour Annuler, enregistrée, redessinée.
  void change(void Function() f) {
    _undo.add(_snap());
    if (_undo.length > 100) _undo.removeAt(0);
    _redo.clear();
    f();
    final b = box;
    if (b != null && !b.zones.any((z) => z.id == zoneId)) zoneId = b.zones.first.id;
    if (b != null) column = column.clamp(0, b.columns - 1);
    Session.autosave('art', () => jsonEncode(art.toJson()));
    widget.state.refresh();
    setState(() {});
  }

  void _undoOnce() {
    if (_undo.isEmpty) return;
    _redo.add(_snap());
    _restore(_undo.removeLast());
    setState(() {});
  }

  void _redoOnce() {
    if (_redo.isEmpty) return;
    _undo.add(_snap());
    _restore(_redo.removeLast());
    setState(() {});
  }

  void _fit() => setState(() => cam.fit(art.panels));

  // ---------------------------------------------------------------- caissons
  void _addBox(ArtBox b) {
    change(() {
      art.boxes.add(b);
      boxIndex = art.boxes.length - 1;
      zoneId = b.zones.first.id;
      column = 0;
    });
    _fit();
  }

  Future<void> _chooseBase() async {
    final b = await showDialog<ArtBox>(context: context, builder: (_) => const _PresetDialog());
    if (b != null) _addBox(b);
  }

  Future<void> _importJson() async {
    final f = await pickFile(accept: '.json');
    if (f == null) return;
    try {
      final j = jsonDecode(utf8.decode(f.bytes)) as Map<String, dynamic>;
      final b = j['model'] == 'universal_parametric_box' || j.containsKey('structure_envelope') ? ArtBox.fromUniversal(j) : ArtBox.fromJson(j);
      _addBox(b);
      _msg(trp('Caisson importé : {0} colonne(s), {1} zone(s)', [b.columns, b.zones.length]));
    } catch (_) {
      _msg(tr('Fichier JSON illisible'));
    }
  }

  void _msg(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating, width: 420));

  /// Répartit [n] colonnes de même largeur.
  void _equalColumns(ArtBox b, int n) {
    final t = b.t;
    final cw = (b.w - 2 * t - (n - 1) * t) / n;
    b.seps
      ..clear()
      ..addAll([for (var k = 1; k < n; k++) (t + k * cw + (k - 1) * t).roundToDouble()]);
    b.shelves.removeWhere((c, _) => c >= n);
    b.covers.removeWhere((id, _) => (int.tryParse(id.substring(1, id.indexOf('z'))) ?? 0) >= n);
  }

  // ---------------------------------------------------------------- sélection et outils CAO
  void _selectTool(CadTool tool) {
    setState(() {
      activeTool = tool;
      activePoints.clear();
      previewShape = null;
      activeTape = null;
      hoveredFace = null;
      cadStatus = switch (tool) {
        CadTool.select => 'Sélectionnez un panneau ou une zone.',
        CadTool.line => 'Cliquez pour poser le 1er point de la ligne.',
        CadTool.freehand => 'Glissez pour dessiner à main levée.',
        CadTool.rectangle => 'Cliquez le 1er coin (au sol : tablette ; sur une face : panneau contre elle).',
        CadTool.rotatedRectangle => 'Point 1 : départ de la ligne de base.',
        CadTool.circle => 'Cliquez pour poser le centre du cercle.',
        CadTool.polygon => 'Cliquez pour poser le centre du polygone (6 côtés).',
        CadTool.arc => 'Point 1 : départ de l’arc.',
        CadTool.move => selectedPanel != null || selectedShape != null ? 'Glissez le panneau (il s’aimante aux autres) ou tapez dx;dy;dz.' : 'Sélectionnez d’abord un panneau ou une esquisse.',
        CadTool.rotate => selectedPanel != null || selectedShape != null ? 'Pivotez de 90° avec les boutons ci-dessous.' : 'Sélectionnez d’abord un panneau.',
        CadTool.scale => 'Redimensionnez l’élément sélectionné.',
        CadTool.symmetry => selectedPanel != null ? 'Choisissez l’axe du miroir (X, Y ou Z).' : 'Sélectionnez un panneau à reproduire en miroir.',
        CadTool.tape => 'Cliquez sur le point de départ de la mesure.',
        CadTool.dimension => 'Cliquez sur le premier point de la cote.',
        CadTool.pushPull => 'Glissez une face pour l’étirer, ou cliquez-la puis tapez la valeur.',
        CadTool.edgeBand => selectedPanel != null ? 'Choisissez l’épaisseur de chant à appliquer.' : 'Cliquez sur un panneau pour lui appliquer un chant.',
        CadTool.groove => selectedPanel != null ? 'Appliquez ou retirez la rainure pour fond.' : 'Cliquez sur un panneau pour configurer sa rainure.',
      };
    });
  }

  V3 _unproject(Offset px, {bool snap = true}) {
    final face = pickFace(cam, art.panels, px);
    V3 res;
    if (face != null) {
      hoveredFace = face;
      final hit = cam.hitPlane(px, face.axis, face.plane);
      res = hit ?? const V3(0, 0, 0);
    } else {
      hoveredFace = null;
      final hit = cam.hitPlane(px, workPlane.axis, workPlane.plane);
      if (hit != null) {
        res = hit;
      } else {
        final hitGround = cam.hitPlane(px, 1, 0);
        final hitFront = cam.hitPlane(px, 2, 0);
        res = hitGround ?? hitFront ?? const V3(0, 0, 0);
      }
    }
    return snap ? _snapGrid(res) : res;
  }

  V3 _snapGrid(V3 v, {double grid = 10.0}) {
    activeSnapTarget = null;

    // 1. Aimantation sur le 1er point de la ligne (Fermeture du polygone)
    if (activeTool == CadTool.line && activePoints.length >= 3) {
      final origin = activePoints.first;
      if ((v - origin).length < 32) {
        activeSnapTarget = CadSnapTarget(position: origin, label: 'Origine (Fermer)', isOrigin: true);
        return origin;
      }
    }

    // 2. Aimantation sur les sommets existants des esquisses
    for (final s in art.sketches) {
      for (final pt in s.vertices) {
        if ((v - pt).length < 24) {
          activeSnapTarget = CadSnapTarget(position: pt, label: 'Sommet');
          return pt;
        }
      }
    }

    // 3. Aimantation sur les coins des panneaux 3D existants
    for (final p in art.panels) {
      for (final c in boxCorners(p)) {
        if ((v - c).length < 24) {
          activeSnapTarget = CadSnapTarget(position: c, label: 'Coin');
          return c;
        }
      }
    }

    var pt = V3(
      (v.x / grid).round() * grid,
      (v.y / grid).round() * grid,
      (v.z / grid).round() * grid,
    );

    // 4. Verrouillage orthogonal strict à 90°
    if (orthoLock && activePoints.isNotEmpty && (activeTool == CadTool.line || activeTool == CadTool.tape || activeTool == CadTool.dimension)) {
      pt = snapOrtho(activePoints.last, pt, workPlane);
    }

    return pt;
  }

  /// Axes des cotes saisies dans le plan de dessin : sol → largeur (x) puis profondeur (z) ;
  /// face → largeur puis hauteur ; côté → profondeur puis hauteur.
  List<int> get _dimAxes => switch (_drawAxis) { 1 => const [0, 2], 2 => const [0, 1], _ => const [2, 1] };

  bool get _isPlanarTool =>
      activeTool == CadTool.line || activeTool == CadTool.rectangle || activeTool == CadTool.circle || activeTool == CadTool.polygon;

  /// Cote affichée à côté du doigt pendant le tracé.
  String? get _liveLabel {
    final h = _hover;
    if (h == null || activePoints.isEmpty) return null;
    final a = activePoints.last;
    String n(double v) => '${v.abs().round()}';
    return switch (activeTool) {
      CadTool.rectangle => '${n(h[_dimAxes[0]] - activePoints.first[_dimAxes[0]])} × ${n(h[_dimAxes[1]] - activePoints.first[_dimAxes[1]])} mm',
      CadTool.line => '${n((h - a).length)} mm',
      CadTool.circle || CadTool.polygon => 'R ${n((h - activePoints.first).length)} mm',
      _ => null,
    };
  }

  /// Fixe le plan de dessin au premier point.
  void _setDrawPlane(Offset px) {
    final f = pickFace(cam, art.panels, px);
    if (f != null) {
      _drawAxis = f.axis;
      _drawPlane = f.plane;
      _drawSign = f.sign.toDouble();
      _drawOnFront = f.axis == 2 && f.sign < 0;
    } else {
      _drawAxis = workPlane.axis;
      _drawPlane = workPlane.plane;
      _drawSign = 1;
      _drawOnFront = false;
    }
  }

  /// Point sous le doigt, sur le plan de dessin (aimanté à la grille et aux coins).
  V3 _onDrawPlane(Offset px) {
    final hit = cam.hitPlane(px, _drawAxis, _drawPlane) ?? (activePoints.isEmpty ? V3.zero : activePoints.last);
    final v = _snapGrid(hit).withAxis(_drawAxis, _drawPlane);
    _hover = v;
    return v;
  }

  /// Rectangle a–b du plan de dessin → panneau de l'épaisseur choisie, posé sur le plan, vers l'extérieur de la face.
  /// Le rôle suit l'orientation : au sol → tablette, de côté → montant, de face → porte (sur une façade) ou décor ; mince → fond.
  ArtPanel? _panelFromRect(V3 a, V3 b, double t) {
    final lo = <int, double>{}, hi = <int, double>{};
    for (final k in _dimAxes) {
      lo[k] = math.min(a[k], b[k]);
      hi[k] = math.max(a[k], b[k]);
      if (hi[k]! - lo[k]! < 1) return null;
    }
    if (_drawSign > 0) {
      lo[_drawAxis] = _drawPlane;
      hi[_drawAxis] = _drawPlane + t;
    } else {
      lo[_drawAxis] = _drawPlane - t;
      hi[_drawAxis] = _drawPlane;
    }
    final role = t < 10
        ? ArtRole.fond
        : switch (_drawAxis) {
            1 => ArtRole.tablette,
            0 => ArtRole.montant,
            _ => _drawOnFront ? ArtRole.porte : ArtRole.decor,
          };
    return ArtPanel(
      id: art.newId(),
      role: role,
      material: t < 10 && (PublicPrices.byId(drawMaterial ?? '')?.thickness ?? 0) >= 10 ? null : drawMaterial,
      x: lo[0]!,
      y: lo[1]!,
      z: lo[2]!,
      w: hi[0]! - lo[0]!,
      h: hi[1]! - lo[1]!,
      d: hi[2]! - lo[2]!,
      finish: role.isFront ? 'blanc_mat' : 'blanc',
    );
  }

  /// Contour du rectangle a–b dans le plan de dessin (aperçu).
  CadPolyline _rectOutline(V3 a, V3 b) {
    final (u, v) = (_dimAxes[0], _dimAxes[1]);
    return CadPolyline(id: 'preview', points: [a, a.withAxis(u, b[u]), b, a.withAxis(v, b[v])], closed: true);
  }

  /// Pose le panneau du rectangle (ou l'esquisse si l'extrusion automatique est coupée).
  void _finishRect(V3 a, V3 b) {
    if (autoExtrude) {
      final panel = _panelFromRect(a, b, pushPullThickness);
      if (panel != null) {
        change(() {
          art.free.add(panel);
          selectedPanel = panel;
        });
        _msg(trp('{0} posé : {1} × {2} × {3} mm', [tr(panel.role.label), panel.w.round(), panel.h.round(), panel.d.round()]));
      }
    } else {
      final o = _rectOutline(a, b);
      change(() => art.sketches.add(CadPolyline(id: 'r${DateTime.now().millisecondsSinceEpoch}', points: o.points, closed: true)));
      _msg(tr('Rectangle créé.'));
    }
    activePoints.clear();
    previewShape = null;
    cadStatus = 'Rectangle créé. Tapez les cotes (ex. 600;720) pour une taille exacte.';
    setState(() {});
  }

  /// Ajoute un sommet à la ligne ; ferme le contour s'il revient au départ.
  void _addLinePoint(V3 pt) {
    if (activePoints.isEmpty) {
      activePoints.add(pt);
      cadStatus = 'Point 1 posé. Tracez à 90°. Rejoignez le 1er point vert pour fermer la boucle.';
    } else {
      final isClosing = (pt - activePoints.first).length < 1e-3 || (activeSnapTarget?.isOrigin == true);
      if (isClosing && activePoints.length >= 3) {
        _closeLineLoop();
        return;
      }
      activePoints.add(pt);
      cadStatus = 'Sommet posé. Rejoignez le 1er point vert ou cliquez « Fermer ».';
    }
    previewShape = CadPolyline(id: 'preview', points: [...activePoints]);
    setState(() {});
  }

  /// Nombres d'une cote tapée : « 600;720 », « 600x720 », « 600 720 », « -50 ».
  List<double> _numbers(String raw) =>
      [for (final m in RegExp(r'-?\d+(?:\.\d+)?').allMatches(raw.replaceAll(',', '.'))) double.parse(m.group(0)!)];

  String get _measureHint => switch (activeTool) {
        CadTool.rectangle => activePoints.isEmpty ? tr('Cliquez le 1er coin') : tr('L;H ex. 600;720'),
        CadTool.line => tr('longueur, ex. 450'),
        CadTool.circle || CadTool.polygon => tr('rayon'),
        CadTool.pushPull => tr('épaisseur ou poussée, ex. 18'),
        CadTool.move => tr('dx;dy;dz ex. 0;0;600'),
        CadTool.rotate => tr('angle, ex. 90'),
        _ => selectedPanel != null ? tr('L;H;P ex. 600;720;18') : '',
      };

  /// Applique la cote tapée selon l'outil en cours.
  void _applyMeasure([String? raw]) {
    final v = _numbers(raw ?? measure.text);
    measure.clear();
    if (v.isEmpty) return;
    double dirOf(int k) {
      final a = activePoints.isEmpty ? null : activePoints.last;
      final h = _hover;
      if (a == null || h == null) return 1;
      return h[k] < a[k] - 0.5 ? -1 : 1;
    }

    switch (activeTool) {
      case CadTool.rectangle when activePoints.length == 1:
        final a = activePoints.first;
        final (u, w) = (_dimAxes[0], _dimAxes[1]);
        final du = v[0], dv = v.length > 1 ? v[1] : v[0];
        _finishRect(a, a.withAxis(u, a[u] + du * dirOf(u)).withAxis(w, a[w] + dv * dirOf(w)));
      case CadTool.line when activePoints.isNotEmpty:
        final a = activePoints.last;
        if (v.length >= 2) {
          _addLinePoint(a.withAxis(_dimAxes[0], a[_dimAxes[0]] + v[0]).withAxis(_dimAxes[1], a[_dimAxes[1]] + v[1]));
        } else {
          final h = _hover ?? a.withAxis(_dimAxes[0], a[_dimAxes[0]] + 1);
          var dir = h - a;
          if (orthoLock) dir = snapOrtho(a, h, workPlane) - a;
          if (dir.length < 1e-6) dir = V3(_dimAxes[0] == 0 ? 1 : 0, 0, _dimAxes[0] == 2 ? 1 : 0);
          _addLinePoint(a + dir.unit * v[0]);
        }
      case CadTool.pushPull:
        final last = _lastPush;
        if (last != null && art.free.contains(last.$1.panel)) {
          change(() => _pushFace(last.$1, last.$2, v[0]));
          _msg(trp('Face poussée de {0} mm', [v[0].round()]));
        } else {
          setState(() => pushPullThickness = v[0].abs().clamp(1, 2000).toDouble());
          _msg(trp('Épaisseur : {0} mm', [pushPullThickness.round()]));
        }
      case CadTool.move:
        if (v.length >= 3) {
          _applyTranslate(v[0], v[1], v[2]);
        } else {
          final ax = workPlane == CadWorkPlane.side ? 2 : 0;
          _applyTranslate(ax == 0 ? v[0] : 0, v.length > 1 ? v[1] : 0, ax == 2 ? v[0] : 0);
        }
      case CadTool.rotate:
        _applyRotate(v[0]);
      case CadTool.circle || CadTool.polygon when activePoints.length == 1:
        final c = activePoints.first;
        final r = v[0].abs();
        final (u, w) = (_dimAxes[0], _dimAxes[1]);
        _finishRect(c.withAxis(u, c[u] - r).withAxis(w, c[w] - r), c.withAxis(u, c[u] + r).withAxis(w, c[w] + r));
      default:
        final p = selectedPanel;
        if (p == null) return;
        if (!art.free.contains(p)) {
          _msg(tr('Ce panneau appartient à un caisson standard. Modifiez le caisson ou ses dimensions.'));
          return;
        }
        change(() {
          if (v.length >= 3) {
            p.w = v[0].clamp(1, 6000).toDouble();
            p.h = v[1].clamp(1, 6000).toDouble();
            p.d = v[2].clamp(1, 6000).toDouble();
          } else {
            // une seule valeur : l'épaisseur
            final t = v[0].clamp(1, 200).toDouble();
            if (p.w <= p.h && p.w <= p.d) {
              p.w = t;
            } else if (p.h <= p.d) {
              p.h = t;
            } else {
              p.d = t;
            }
          }
        });
        _msg(trp('Panneau : {0} × {1} × {2} mm', [p.w.round(), p.h.round(), p.d.round()]));
    }
  }

  /// Étire la face [f] de [amount] mm depuis la géométrie d'origine [o] (x, y, z, w, h, d) ; négatif : rentre.
  void _pushFace(Face f, List<double> o, double amount) {
    final p = f.panel;
    final ax = f.axis;
    final size = (o[3 + ax] + amount).clamp(1.0, 6000.0);
    final lo = f.sign > 0 ? o[ax] : o[ax] + o[3 + ax] - size;
    if (ax == 0) {
      p.x = lo;
      p.w = size;
    } else if (ax == 1) {
      p.y = lo;
      p.h = size;
    } else {
      p.z = lo;
      p.d = size;
    }
  }

  List<double> _geom(ArtPanel p) => [p.x, p.y, p.z, p.w, p.h, p.d];

  /// Début d'un glisser : Pousser/Tirer sur une face, ou Déplacer le panneau choisi.
  bool _dragStart(Offset px) {
    if (activeTool == CadTool.pushPull) {
      final f = pickFace(cam, art.panels, px);
      if (f == null || !art.free.contains(f.panel)) return false;
      _dragFace = f;
      _dragOrig = _geom(f.panel);
      _dragUndo = _snap();
      return true;
    }
    if (activeTool == CadTool.move) {
      final f = pickFace(cam, art.panels, px);
      final p = f?.panel ?? selectedPanel;
      if (p == null || !art.free.contains(p)) return false;
      if (!selection.contains(p)) {
        selection
          ..clear()
          ..add(p);
      }
      selectedPanel = p;
      _dragPanel = p;
      _dragOrig = _geom(p);
      _dragOthers = {for (final q in selection) if (!identical(q, p) && art.free.contains(q)) q: _geom(q)};
      _dragUndo = _snap();
      final ax = workPlane.axis;
      _dragHit0 = cam.hitPlane(px, ax, ax == 0 ? p.x : ax == 1 ? p.y : p.z);
      return _dragHit0 != null;
    }
    return false;
  }

  /// Aimante une coordonnée [lo] (taille [size]) aux faces des autres panneaux, à 15 mm près.
  double _snapTo(double lo, double size, int ax, ArtPanel self) {
    var best = (lo / 10).round() * 10.0, gap = 15.0;
    for (final o in art.panels) {
      if (identical(o, self)) continue;
      final cand = [ax == 0 ? o.x : ax == 1 ? o.y : o.z, ax == 0 ? o.right : ax == 1 ? o.top : o.back];
      for (final c in cand) {
        if ((lo - c).abs() < gap) {
          gap = (lo - c).abs();
          best = c;
        }
        if ((lo + size - c).abs() < gap) {
          gap = (lo + size - c).abs();
          best = c - size;
        }
      }
    }
    return best;
  }

  void _dragUpdate(Offset px) {
    final o = _dragOrig;
    if (o == null) return;
    final f = _dragFace;
    if (f != null) {
      final sd = cam.screenDir(f.center, f.normal);
      final l2 = sd.dx * sd.dx + sd.dy * sd.dy;
      if (l2 < 1e-6) return;
      final drag = px - (_downAt ?? px);
      var amount = (drag.dx * sd.dx + drag.dy * sd.dy) / l2 * 100;
      amount = (amount / 1).roundToDouble();
      // aimantation : la face s'arrête sur les faces des autres panneaux
      final ax = f.axis;
      final plane = (f.sign > 0 ? o[ax] + o[3 + ax] : o[ax]) + amount * f.sign;
      for (final other in art.panels) {
        if (identical(other, f.panel)) continue;
        for (final c in [ax == 0 ? other.x : ax == 1 ? other.y : other.z, ax == 0 ? other.right : ax == 1 ? other.top : other.back]) {
          if ((plane - c).abs() < 12) amount = (c - (f.sign > 0 ? o[ax] + o[3 + ax] : o[ax])) * f.sign;
        }
      }
      _pushFace(f, o, amount);
      cadStatus = trp('Pousser/Tirer : {0} mm (tapez une valeur pour être exact)', [amount.round()]);
      setState(() {});
      return;
    }
    final p = _dragPanel;
    final h0 = _dragHit0;
    if (p == null || h0 == null) return;
    final ax = workPlane.axis;
    final hit = cam.hitPlane(px, ax, ax == 0 ? o[0] : ax == 1 ? o[1] : o[2]);
    if (hit == null) return;
    final d = hit - h0;
    for (final k in [0, 1, 2]) {
      if (k == ax) continue;
      final lo = _snapTo(o[k] + d[k], o[3 + k], k, p);
      if (k == 0) p.x = lo;
      if (k == 1) p.y = math.max(0, lo);
      if (k == 2) p.z = lo;
    }
    final mx = p.x - o[0], my = p.y - o[1], mz = p.z - o[2];
    _dragOthers.forEach((q, g) {
      q.x = g[0] + mx;
      q.y = g[1] + my;
      q.z = g[2] + mz;
    });
    cadStatus = trp('Déplacement : {0} ; {1} ; {2} mm', [(p.x - o[0]).round(), (p.y - o[1]).round(), (p.z - o[2]).round()]);
    setState(() {});
  }

  void _dragEnd() {
    final u = _dragUndo;
    if (u != null && u != _snap()) {
      _undo.add(u);
      if (_undo.length > 100) _undo.removeAt(0);
      _redo.clear();
      Session.autosave('art', () => jsonEncode(art.toJson()));
      widget.state.refresh();
    }
    if (_dragFace != null && _dragOrig != null) _lastPush = (_dragFace!, _dragOrig!);
    _dragFace = null;
    _dragPanel = null;
    _dragOthers = {};
    _dragOrig = null;
    _dragUndo = null;
    _dragHit0 = null;
    setState(() {});
  }

  /// Raccourcis clavier façon SketchUp ; les chiffres tapés vont dans la boîte des cotes.
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (measureFocus.hasFocus) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    if (ctrl) {
      if (k == LogicalKeyboardKey.keyA) {
        setState(() {
          activeTool = CadTool.select;
          selection
            ..clear()
            ..addAll(art.free);
          selectedPanel = selection.isEmpty ? null : selection.last;
        });
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyD) {
        _duplicateSelected();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final ch = e.character;
    if (ch != null && RegExp(r'^[0-9.;x*\-]$').hasMatch(ch) && (activeTool != CadTool.select || selectedPanel != null)) {
      setState(() => measure.text += ch);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      if (measure.text.isNotEmpty) {
        _applyMeasure();
        return KeyEventResult.handled;
      }
      if (activeTool == CadTool.line && activePoints.length >= 3) {
        _closeLineLoop();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (k == LogicalKeyboardKey.backspace && measure.text.isNotEmpty) {
      setState(() => measure.text = measure.text.substring(0, measure.text.length - 1));
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      measure.clear();
      selection.clear();
      selectedPanel = null;
      _selectTool(CadTool.select);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) {
      if (selectedPanel != null || selection.isNotEmpty) {
        _deleteSelected();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final tool = switch (k) {
      LogicalKeyboardKey.space => CadTool.select,
      LogicalKeyboardKey.keyL => CadTool.line,
      LogicalKeyboardKey.keyR => CadTool.rectangle,
      LogicalKeyboardKey.keyC => CadTool.circle,
      LogicalKeyboardKey.keyP => CadTool.pushPull,
      LogicalKeyboardKey.keyM => CadTool.move,
      LogicalKeyboardKey.keyQ => CadTool.rotate,
      LogicalKeyboardKey.keyT => CadTool.tape,
      LogicalKeyboardKey.keyD => CadTool.dimension,
      LogicalKeyboardKey.keyB => CadTool.edgeBand,
      LogicalKeyboardKey.keyG => CadTool.groove,
      _ => null,
    };
    if (tool == null) return KeyEventResult.ignored;
    _selectTool(tool);
    return KeyEventResult.handled;
  }

  CadShape? _pickSketch(Offset px) {
    for (final s in art.sketches.reversed) {
      final pts = s.vertices.map((v) => cam.project(v).$1).toList();
      if (pts.length < 2) continue;
      if (s.isClosed) {
        final path = Path()..addPolygon(pts, true);
        if (path.contains(px)) return s;
      }
      for (var i = 0; i < pts.length - 1; i++) {
        if (_distToSegment(px, pts[i], pts[i + 1]) < 12) return s;
      }
    }
    return null;
  }

  double _distToSegment(Offset p, Offset a, Offset b) {
    final d = b - a;
    final l2 = d.dx * d.dx + d.dy * d.dy;
    if (l2 < 1e-4) return (p - a).distance;
    final t = math.max(0.0, math.min(1.0, ((p.dx - a.dx) * d.dx + (p.dy - a.dy) * d.dy) / l2));
    final proj = a + d * t;
    return (p - proj).distance;
  }

  void _updatePreview(Offset px) {
    final planar = activeTool == CadTool.line || activeTool == CadTool.rectangle || activeTool == CadTool.circle || activeTool == CadTool.polygon;
    final pt = planar && activePoints.isNotEmpty ? _onDrawPlane(px) : _unproject(px);
    if (activeTool == CadTool.rectangle && activePoints.isNotEmpty) {
      previewShape = _rectOutline(activePoints.first, pt);
      final a = activePoints.first;
      cadStatus = trp('{0} × {1} mm : cliquez ou tapez les cotes', [(pt[_dimAxes[0]] - a[_dimAxes[0]]).abs().round(), (pt[_dimAxes[1]] - a[_dimAxes[1]]).abs().round()]);
      setState(() {});
      return;
    }
    if (activeTool == CadTool.line && activePoints.isNotEmpty) {
      previewShape = CadPolyline(
        id: 'preview',
        points: [...activePoints, pt],
        closed: activeSnapTarget?.isOrigin == true,
      );
      setState(() {});
    } else if (activeTool == CadTool.rectangle && activePoints.isNotEmpty) {
      previewShape = CadRect.fromDiagonal('preview', activePoints.first, pt);
      setState(() {});
    } else if (activeTool == CadTool.rotatedRectangle && activePoints.length == 1) {
      previewShape = CadLine(id: 'preview', p1: activePoints.first, p2: pt);
      setState(() {});
    } else if (activeTool == CadTool.rotatedRectangle && activePoints.length == 2) {
      previewShape = CadRect.from3Points('preview', activePoints[0], activePoints[1], pt);
      setState(() {});
    } else if (activeTool == CadTool.circle && activePoints.isNotEmpty) {
      final r = (pt - activePoints.first).length;
      previewShape = CadCircle(id: 'preview', centerPt: activePoints.first, radius: r);
      setState(() {});
    } else if (activeTool == CadTool.polygon && activePoints.isNotEmpty) {
      final r = (pt - activePoints.first).length;
      previewShape = CadPolygon(id: 'preview', centerPt: activePoints.first, radius: r, sides: 6);
      setState(() {});
    } else if (activeTool == CadTool.arc && activePoints.length == 1) {
      previewShape = CadLine(id: 'preview', p1: activePoints.first, p2: pt);
      setState(() {});
    } else if (activeTool == CadTool.arc && activePoints.length == 2) {
      previewShape = CadArc(id: 'preview', startPt: activePoints[0], endPt: activePoints[1], controlPt: pt);
      setState(() {});
    } else if (activeTool == CadTool.tape && activePoints.isNotEmpty) {
      activeTape = CadTapeMeasure(activePoints.first, pt);
      setState(() {});
    }
  }

  void _closeLineLoop() {
    if (activePoints.length < 3) return;
    final poly = CadPolyline(
      id: 'poly_${DateTime.now().millisecondsSinceEpoch}',
      points: List.from(activePoints),
      closed: true,
    );
    final (bMin, bMax) = poly.bounds;
    final newPanel = autoExtrude ? _panelFromRect(bMin, bMax, math.max(1.0, pushPullThickness)) : null;
    if (newPanel != null) {
      change(() {
        art.free.add(newPanel);
        selectedPanel = newPanel;
      });
      _msg(trp('Contour fermé : panneau 3D créé ({0}×{1} mm, épaisseur {2} mm)', [newPanel.w.round(), newPanel.h.round(), newPanel.d.round()]));
    } else {
      change(() => art.sketches.add(poly));
      _msg(tr('Contour polygonal 2D créé.'));
    }
    activePoints.clear();
    previewShape = null;
    activeSnapTarget = null;
    cadStatus = 'Création terminée.';
    setState(() {});
  }

  void _handleTap(Offset px) {
    if (activeTool == CadTool.select) {
      _tap(px);
      final f = pickFace(cam, art.panels, px);
      final kb = HardwareKeyboard.instance;
      final add = kb.isControlPressed || kb.isMetaPressed || kb.isShiftPressed;
      if (f != null) {
        // les panneaux d'un caisson tout fait sont recréés à chaque rendu : on les retrouve par leur identifiant
        final hit = f.panel;
        if (add) {
          if (selection.any((q) => q.id == hit.id)) {
            selection.removeWhere((q) => q.id == hit.id);
          } else {
            selection.add(hit);
          }
          selectedPanel = selection.isEmpty ? null : selection.last;
        } else {
          selection
            ..clear()
            ..add(hit);
          selectedPanel = hit;
        }
        selectedShape = null;
      } else if (!add) {
        selectedShape = _pickSketch(px);
        selectedPanel = null;
        selection.clear();
      }
      setState(() {});
      return;
    }

    final planar = activeTool == CadTool.line || activeTool == CadTool.rectangle || activeTool == CadTool.circle || activeTool == CadTool.polygon;
    if (planar && activePoints.isEmpty) _setDrawPlane(px);
    final pt = planar ? _onDrawPlane(px) : _unproject(px);

    if (activeTool == CadTool.line) {
      _addLinePoint(pt);
      return;
    }
    if (activeTool == CadTool.rectangle) {
      if (activePoints.isEmpty) {
        activePoints.add(pt);
        cadStatus = 'Cliquez le coin opposé ou tapez les cotes (ex. 600;720).';
        setState(() {});
      } else {
        _finishRect(activePoints.first, pt);
      }
      return;
    }
    if (activeTool == CadTool.rotatedRectangle) {
      if (activePoints.isEmpty) {
        activePoints.add(pt);
        cadStatus = 'Point 2 : fin de la base (orientation).';
        setState(() {});
      } else if (activePoints.length == 1) {
        activePoints.add(pt);
        cadStatus = 'Point 3 : largeur / hauteur perpendiculaire.';
        setState(() {});
      } else {
        final r = CadRect.from3Points('rr${DateTime.now().millisecondsSinceEpoch}', activePoints[0], activePoints[1], pt);
        if (autoExtrude) {
          final p = r.extrude(art.newId(), pushPullThickness);
          if (p != null) {
            change(() {
              art.free.add(p);
              selectedPanel = p;
            });
            _msg(trp('Panneau 3D créé ({0}×{1} mm, épaisseur {2} mm)', [p.w.round(), p.h.round(), p.d.round()]));
          }
        } else {
          change(() => art.sketches.add(r));
          _msg(tr('Rectangle orienté créé.'));
        }
        activePoints.clear();
        previewShape = null;
        cadStatus = 'Rectangle orienté créé.';
      }
    } else if (activeTool == CadTool.circle) {
      if (activePoints.isEmpty) {
        activePoints.add(pt);
        cadStatus = 'Cliquez pour définir le rayon.';
        setState(() {});
      } else {
        final radius = math.max(10.0, (pt - activePoints.first).length);
        final c = CadCircle(id: 'c${DateTime.now().millisecondsSinceEpoch}', centerPt: activePoints.first, radius: radius);
        if (autoExtrude) {
          final o = activePoints.first;
          final (u, w) = (_dimAxes[0], _dimAxes[1]);
          final p = _panelFromRect(o.withAxis(u, o[u] - radius).withAxis(w, o[w] - radius), o.withAxis(u, o[u] + radius).withAxis(w, o[w] + radius), pushPullThickness);
          if (p != null) {
            change(() {
              art.free.add(p);
              selectedPanel = p;
            });
            _msg(trp('Panneau 3D créé (rayon {0} mm, épaisseur {1} mm)', [radius.round(), pushPullThickness.round()]));
          }
        } else {
          change(() => art.sketches.add(c));
          _msg(tr('Cercle créé.'));
        }
        activePoints.clear();
        previewShape = null;
        cadStatus = 'Cercle créé.';
      }
    } else if (activeTool == CadTool.polygon) {
      if (activePoints.isEmpty) {
        activePoints.add(pt);
        cadStatus = 'Cliquez pour définir le rayon du polygone.';
        setState(() {});
      } else {
        final radius = math.max(10.0, (pt - activePoints.first).length);
        final p = CadPolygon(id: 'p${DateTime.now().millisecondsSinceEpoch}', centerPt: activePoints.first, radius: radius, sides: 6);
        if (autoExtrude) {
          final o = activePoints.first;
          final (u, w) = (_dimAxes[0], _dimAxes[1]);
          final pan = _panelFromRect(o.withAxis(u, o[u] - radius).withAxis(w, o[w] - radius), o.withAxis(u, o[u] + radius).withAxis(w, o[w] + radius), pushPullThickness);
          if (pan != null) {
            change(() {
              art.free.add(pan);
              selectedPanel = pan;
            });
            _msg(trp('Panneau polygone créé ({0} côtés, épaisseur {1} mm)', [6, pushPullThickness.round()]));
          }
        } else {
          change(() => art.sketches.add(p));
          _msg(tr('Polygone régulier (6 côtés) créé.'));
        }
        activePoints.clear();
        previewShape = null;
        cadStatus = 'Polygone régulier (6 côtés) créé.';
      }
    } else if (activeTool == CadTool.arc) {
      if (activePoints.isEmpty) {
        activePoints.add(pt);
        cadStatus = 'Point 2 : fin de l’arc.';
        setState(() {});
      } else if (activePoints.length == 1) {
        activePoints.add(pt);
        cadStatus = 'Point 3 : flèche / courbure de l’arc.';
        setState(() {});
      } else {
        final a = CadArc(id: 'a${DateTime.now().millisecondsSinceEpoch}', startPt: activePoints[0], endPt: activePoints[1], controlPt: pt);
        change(() => art.sketches.add(a));
        activePoints.clear();
        previewShape = null;
        cadStatus = 'Arc créé.';
      }
    } else if (activeTool == CadTool.tape) {
      if (activePoints.isEmpty) {
        activePoints.add(pt);
        cadStatus = 'Cliquez sur le point d’arrivée de la mesure.';
        setState(() {});
      } else {
        final dist = (pt - activePoints.first).length.round();
        cadStatus = 'Distance : $dist mm (dx: ${(pt.x - activePoints.first.x).abs().round()}, dy: ${(pt.y - activePoints.first.y).abs().round()})';
        activeTape = CadTapeMeasure(activePoints.first, pt);
        activePoints.clear();
        setState(() {});
      }
    } else if (activeTool == CadTool.dimension) {
      if (activePoints.isEmpty) {
        activePoints.add(pt);
        cadStatus = 'Point 2 : fin de la cote.';
        setState(() {});
      } else {
        final dim = CadDimension(id: 'd${DateTime.now().millisecondsSinceEpoch}', p1: activePoints.first, p2: pt);
        change(() => art.dimensions.add(dim));
        activePoints.clear();
        cadStatus = 'Cote ajoutée (${dim.text}).';
      }
    } else if (activeTool == CadTool.pushPull) {
      final s = _pickSketch(px);
      if (s != null) {
        final newPanel = s.extrude(art.newId(), pushPullThickness);
        if (newPanel != null) {
          change(() {
            art.free.add(newPanel);
            art.sketches.remove(s);
            selectedPanel = newPanel;
          });
          _msg(trp('Esquisse 2D extrudée en panneau 3D ({0} mm)', [pushPullThickness.round()]));
        }
        return;
      }
      final f = pickFace(cam, art.panels, px);
      if (f != null && !art.free.contains(f.panel)) {
        _msg(tr('Ce panneau appartient à un caisson standard. Modifiez le caisson ou ses dimensions.'));
        return;
      }
      if (f != null) {
        final p = f.panel;
        _lastPush = (f, _geom(p));
        change(() {
          if (f.axis == 0) {
            if (f.sign > 0) {
              p.w += pushPullThickness;
            } else {
              p.x -= pushPullThickness;
              p.w += pushPullThickness;
            }
          } else if (f.axis == 1) {
            if (f.sign > 0) {
              p.h += pushPullThickness;
            } else {
              p.y -= pushPullThickness;
              p.h += pushPullThickness;
            }
          } else {
            if (f.sign > 0) {
              p.d += pushPullThickness;
            } else {
              p.z -= pushPullThickness;
              p.d += pushPullThickness;
            }
          }
        });
        _msg(trp('Face étirée de {0} mm', [pushPullThickness.round()]));
      }
    } else if (activeTool == CadTool.edgeBand) {
      final f = pickFace(cam, art.panels, px);
      if (f != null) {
        setState(() {
          selectedPanel = f.panel;
          cadStatus = 'Panneau sélectionné. Cliquez sur une épaisseur de chant.';
        });
      }
    } else if (activeTool == CadTool.groove) {
      final f = pickFace(cam, art.panels, px);
      if (f != null) {
        setState(() {
          selectedPanel = f.panel;
          cadStatus = 'Panneau sélectionné. Choisissez un preset de rainure.';
        });
      }
    }
  }

  void _applyEdgeBanding(double th) {
    final p = selectedPanel;
    if (p == null) {
      _msg(tr('Sélectionnez d’abord un panneau'));
      return;
    }
    change(() {
      if (th <= 0) {
        p.edgeLong = 0;
        p.edgeShort = 0;
      } else {
        p.edgeThickness = th;
        p.edgeLong = 2;
        p.edgeShort = 2;
      }
    });
    _msg(th <= 0 ? tr('Chants retirés') : trp('Chant {0} mm appliqué sur les 4 côtés', [th]));
  }

  void _applyGroove(double offset, double depth, double width) {
    final p = selectedPanel;
    if (p == null) {
      _msg(tr('Sélectionnez d’abord un panneau'));
      return;
    }
    change(() {
      if (depth <= 0) {
        p.hasGroove = false;
        p.grooveLong = 0;
        p.grooveShort = 0;
      } else {
        p.hasGroove = true;
        p.grooveOffset = offset;
        p.grooveDepth = depth;
        p.grooveWidth = width;
        p.grooveLong = 1;
      }
    });
    _msg(depth <= 0 ? tr('Rainure supprimée') : trp('Rainure {0}x{1} mm configurée', [offset.round(), depth.round()]));
  }

  void _applyMirror(String axis) {
    final p = selectedPanel;
    if (p != null) {
      change(() {
        final clone = p.copy(id: art.newId());
        if (axis == 'X') {
          clone.x = p.right + 20;
        } else if (axis == 'Y') {
          clone.y = p.top + 20;
        } else {
          clone.z = p.back + 20;
        }
        art.free.add(clone);
        selectedPanel = clone;
      });
      _msg(trp('Panneau dupliqué en symétrie selon l’axe {0}', [axis]));
    } else if (selectedShape != null) {
      change(() {
        final (bMin, bMax) = selectedShape!.bounds;
        final dx = (bMax.x - bMin.x) + 20;
        selectedShape!.translate(V3(dx, 0, 0));
      });
      _msg(tr('Esquisse déplacée en miroir'));
    } else {
      _msg(tr('Sélectionnez un panneau ou une esquisse'));
    }
  }

  void _applyTranslate(double dx, double dy, double dz) {
    final p = selectedPanel;
    if (p != null) {
      change(() {
        for (final q in _selected.where(art.free.contains)) {
          q.x += dx;
          q.y += dy;
          q.z += dz;
        }
      });
      _msg(trp('Déplacé de {0}, {1}, {2} mm', [dx.round(), dy.round(), dz.round()]));
    } else if (selectedShape != null) {
      change(() {
        selectedShape!.translate(V3(dx, dy, dz));
      });
    } else {
      _msg(tr('Sélectionnez un panneau'));
    }
  }

  void _applyRotate(double angleDeg) {
    final p = selectedPanel;
    if (p != null) {
      if (!art.free.contains(p)) {
        _msg(tr('Ce panneau appartient à un caisson standard. Modifiez le caisson ou ses dimensions.'));
        return;
      }
      if ((angleDeg.abs() % 180).round() == 0) {
        change(() => p.hinge = p.hinge == 'left' ? 'right' : 'left');
        _msg(trp('Panneau pivoté de {0}°', [angleDeg.round()]));
        return;
      }
      change(() {
        // quart de tour autour de l'axe perpendiculaire au plan de travail, centre conservé
        final cx = p.x + p.w / 2, cy = p.y + p.h / 2, cz = p.z + p.d / 2;
        switch (workPlane.axis) {
          case 1:
            final t = p.w;
            p.w = p.d;
            p.d = t;
          case 2:
            final t = p.w;
            p.w = p.h;
            p.h = t;
          default:
            final t = p.h;
            p.h = p.d;
            p.d = t;
        }
        p.x = cx - p.w / 2;
        p.y = math.max(0, cy - p.h / 2);
        p.z = cz - p.d / 2;
      });
      _msg(trp('Panneau pivoté de {0}°', [angleDeg.round()]));
    } else {
      _msg(tr('Sélectionnez un panneau'));
    }
  }

  void _executePushPull() {
    if (selectedShape != null) {
      final p = selectedShape!.extrude(art.newId(), pushPullThickness);
      if (p != null) {
        change(() {
          art.free.add(p);
          art.sketches.remove(selectedShape);
          selectedShape = null;
          selectedPanel = p;
        });
        _msg(trp('Panneau 3D créé avec succès ({0} mm)', [pushPullThickness.round()]));
      }
    } else if (selectedPanel != null) {
      change(() {
        selectedPanel!.d += pushPullThickness;
      });
      _msg(trp('Épaisseur augmentée de {0} mm', [pushPullThickness.round()]));
    } else {
      _msg(tr('Sélectionnez une esquisse ou un panneau'));
    }
  }

  /// Menu des matières du tarif, groupées par famille ; null = matière selon le rôle (MDF du projet).
  Widget _materialPicker(String? value, void Function(String?) onPick, {String? label}) {
    final list = PublicPrices.panels;
    return DropdownButtonFormField<String>(
      key: ValueKey('mat_${label ?? ''}_$value'),
      isExpanded: true,
      initialValue: value != null && list.any((q) => q.id == value) ? value : '',
      decoration: InputDecoration(labelText: tr(label ?? 'Matière'), isDense: true, border: const OutlineInputBorder()),
      items: [
        DropdownMenuItem(value: '', child: Text(tr('Selon le rôle (MDF du projet)'), overflow: TextOverflow.ellipsis)),
        for (final q in list)
          DropdownMenuItem(
            value: q.id,
            child: Text('${tr(q.family)} · ${tr(q.name)} ${q.thickness} mm · ${q.length}×${q.width}', overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) => onPick(v == null || v.isEmpty ? null : v),
    );
  }

  /// Donne la matière [id] aux panneaux [ps] ; leur épaisseur prend celle de la feuille.
  void _setMaterial(List<ArtPanel> ps, String? id) {
    final pp = id == null ? null : PublicPrices.byId(id);
    change(() {
      for (final p in ps.where(art.free.contains)) {
        p.material = id;
        if (pp == null) continue;
        final t = pp.thickness.toDouble();
        if (p.w <= p.h && p.w <= p.d) {
          p.w = t;
        } else if (p.h <= p.d) {
          p.h = t;
        } else {
          p.d = t;
        }
      }
    });
    if (pp != null) _msg(trp('{0} : {1} mm, feuille {2} × {3}', [tr(pp.name), pp.thickness, pp.length, pp.width]));
  }

  /// Panneaux choisis (la sélection multiple, sinon le panneau sélectionné).
  List<ArtPanel> get _selected => selection.isNotEmpty ? selection.toList() : [?selectedPanel];

  void _duplicateSelected() {
    final sel = _selected.where(art.free.contains).toList();
    if (sel.isEmpty) return;
    // la copie se pose à côté de l'ensemble, à droite
    final dx = sel.map((p) => p.right).reduce(math.max) - sel.map((p) => p.x).reduce(math.min) + 20;
    final clones = [for (final p in sel) p.copy(id: art.newId())..x = p.x + dx];
    change(() {
      art.free.addAll(clones);
      selection
        ..clear()
        ..addAll(clones);
      selectedPanel = clones.last;
    });
    _msg(trp('{0} panneau(x) dupliqué(s)', [clones.length]));
  }

  void _deleteSelected() {
    final sel = _selected;
    if (sel.isEmpty) return;
    final free = sel.where(art.free.contains).toList();
    if (free.isEmpty) {
      _msg(tr('Ce panneau appartient à un caisson standard. Modifiez le caisson ou ses dimensions.'));
      return;
    }
    change(() {
      art.free.removeWhere(free.contains);
      selection.clear();
      selectedPanel = null;
    });
    _msg(trp('{0} panneau(x) supprimé(s)', [free.length]));
  }

  /// Propriétés d'un panneau : dimensions, rôle, finition, chants, rainure, position, accessoires.
  Widget _panelProps(BuildContext ctx, ArtPanel p, StateSetter setDlg, {required VoidCallback close}) {
    return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 0. Matière du tarif : épaisseur et format de feuille du débit
                    _materialPicker(p.material, (v) {
                      _setMaterial([p], v);
                      setDlg(() {});
                    }),
                    if (ArtProject.hasGrain(p))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(tr('Matière à sens : la pièce garde son sens au débit (pas de rotation).'), style: const TextStyle(fontSize: 11)),
                      ),
                    const SizedBox(height: 12),
                    // 1. Dimensions
                    Text(tr('Dimensions (mm)'), style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: '${p.w.round()}',
                            decoration: const InputDecoration(labelText: 'Largeur (W)', isDense: true, border: OutlineInputBorder()),
                            keyboardType: TextInputType.number,
                            onChanged: (v) {
                              final val = double.tryParse(v);
                              if (val != null && val > 0) change(() => p.w = val);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            initialValue: '${p.h.round()}',
                            decoration: const InputDecoration(labelText: 'Hauteur (H)', isDense: true, border: OutlineInputBorder()),
                            keyboardType: TextInputType.number,
                            onChanged: (v) {
                              final val = double.tryParse(v);
                              if (val != null && val > 0) change(() => p.h = val);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            initialValue: '${p.d.round()}',
                            decoration: const InputDecoration(labelText: 'Épaisseur (D)', isDense: true, border: OutlineInputBorder()),
                            keyboardType: TextInputType.number,
                            onChanged: (v) {
                              final val = double.tryParse(v);
                              if (val != null && val > 0) change(() => p.d = val);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // 2. Rôle et Finition
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          child: DropdownButtonFormField<ArtRole>(
                            initialValue: p.role,
                            decoration: InputDecoration(labelText: tr('Rôle'), isDense: true, border: const OutlineInputBorder()),
                            items: [
                              for (final r in ArtRole.values)
                                DropdownMenuItem(value: r, child: Text(tr(r.label))),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                change(() => p.role = v);
                                setDlg(() {});
                              }
                            },
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          child: DropdownButtonFormField<String>(
                            initialValue: p.finish,
                            decoration: InputDecoration(labelText: tr('Finition'), isDense: true, border: const OutlineInputBorder()),
                            isExpanded: true,
                            // toutes les finitions (façades et caissons), plus celle du panneau si elle n'y est pas
                            items: [
                              for (final f in {for (final f in [...fronts, ...carcasses]) if (!f.id.startsWith('tex:')) f.id: f}.values)
                                DropdownMenuItem(value: f.id, child: Text(tr(f.name), overflow: TextOverflow.ellipsis)),
                              if (![...fronts, ...carcasses].any((f) => f.id == p.finish))
                                DropdownMenuItem(value: p.finish, child: Text(p.finish, overflow: TextOverflow.ellipsis)),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                change(() => p.finish = v);
                                setDlg(() {});
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // 3. Chants (Edging)
                    Text(tr('Bandes de chant'), style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      runSpacing: 4,
                      children: [
                        Text(tr('Épaisseur chant :'), style: const TextStyle(fontSize: 12)),
                        const SizedBox(width: 8),
                        for (final th in [0.4, 1.0, 2.0])
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text('$th mm'),
                              selected: (p.edgeThickness - th).abs() < 0.1,
                              onSelected: (_) {
                                change(() => p.edgeThickness = th);
                                setDlg(() {});
                              },
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 16,
                      children: [
                        SizedBox(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(tr('Chants Longs :'), style: const TextStyle(fontSize: 12)),
                              const SizedBox(width: 4),
                              DropdownButton<int>(
                                value: p.edgeLong,
                                items: const [
                                  DropdownMenuItem(value: 0, child: Text('0 côté')),
                                  DropdownMenuItem(value: 1, child: Text('1 côté')),
                                  DropdownMenuItem(value: 2, child: Text('2 côtés')),
                                ],
                                onChanged: (v) {
                                  if (v != null) {
                                    change(() => p.edgeLong = v);
                                    setDlg(() {});
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(tr('Chants Courts :'), style: const TextStyle(fontSize: 12)),
                              const SizedBox(width: 4),
                              DropdownButton<int>(
                                value: p.edgeShort,
                                items: const [
                                  DropdownMenuItem(value: 0, child: Text('0 côté')),
                                  DropdownMenuItem(value: 1, child: Text('1 côté')),
                                  DropdownMenuItem(value: 2, child: Text('2 côtés')),
                                ],
                                onChanged: (v) {
                                  if (v != null) {
                                    change(() => p.edgeShort = v);
                                    setDlg(() {});
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // 4. Rainures (Grooves)
                    Row(
                      children: [
                        Expanded(child: Text(tr('Rainure pour fond :'), style: const TextStyle(fontWeight: FontWeight.bold))),
                        Switch(
                          value: p.hasGroove,
                          onChanged: (v) {
                            change(() => p.hasGroove = v);
                            setDlg(() {});
                          },
                        ),
                      ],
                    ),
                    if (p.hasGroove) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: '${p.grooveOffset.round()}',
                              decoration: const InputDecoration(labelText: 'Retrait (mm)', isDense: true, border: OutlineInputBorder()),
                              keyboardType: TextInputType.number,
                              onChanged: (v) {
                                final val = double.tryParse(v);
                                if (val != null) change(() => p.grooveOffset = val);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              initialValue: '${p.grooveDepth.round()}',
                              decoration: const InputDecoration(labelText: 'Prof. (mm)', isDense: true, border: OutlineInputBorder()),
                              keyboardType: TextInputType.number,
                              onChanged: (v) {
                                final val = double.tryParse(v);
                                if (val != null) change(() => p.grooveDepth = val);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              initialValue: '${p.grooveWidth.round()}',
                              decoration: const InputDecoration(labelText: 'Larg. (mm)', isDense: true, border: OutlineInputBorder()),
                              keyboardType: TextInputType.number,
                              onChanged: (v) {
                                final val = double.tryParse(v);
                                if (val != null) change(() => p.grooveWidth = val);
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 14),

                    // 5. Positionnement & Accessoires
                    Text(tr('Positionnement & Alignement'), style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.align_horizontal_left, size: 14),
                          label: Text(tr('Aligner à gauche')),
                          onPressed: () => change(() => p.x = 0),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.vertical_align_bottom, size: 14),
                          label: Text(tr('Poser au sol')),
                          onPressed: () => change(() => p.y = 0),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.screen_rotation, size: 14),
                          label: Text(tr('Basculer plat/debout')),
                          onPressed: () => change(() {
                            final tmp = p.h;
                            p.h = p.d;
                            p.d = tmp;
                            setDlg(() {});
                          }),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.rotate_right, size: 14),
                          label: Text(tr('Pivoter 90°')),
                          onPressed: () => change(() {
                            final tmp = p.w;
                            p.w = p.d;
                            p.d = tmp;
                            setDlg(() {});
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(tr('Ajouter un accessoire :'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.table_rows, size: 14),
                          label: Text(tr('+ Tablette intérieure')),
                          onPressed: () {
                            final shelf = ArtPanel(
                              id: art.newId(),
                              role: ArtRole.tablette,
                              x: p.x,
                              y: p.y + p.h / 2,
                              z: p.z,
                              w: p.w,
                              h: 18,
                              d: p.d > 25 ? p.d : 540,
                            );
                            change(() => art.free.add(shelf));
                            close();
                            _msg(tr('Tablette intérieure ajoutée.'));
                          },
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.view_column, size: 14),
                          label: Text(tr('+ Séparation verticale')),
                          onPressed: () {
                            final sep = ArtPanel(
                              id: art.newId(),
                              role: ArtRole.montant,
                              x: p.x + p.w / 2,
                              y: p.y,
                              z: p.z,
                              w: 18,
                              h: p.h,
                              d: p.d > 25 ? p.d : 540,
                            );
                            change(() => art.free.add(sep));
                            close();
                            _msg(tr('Séparation verticale ajoutée.'));
                          },
                        ),
                      ],
                    ),
                  ],
                );
  }

  /// Panneau des propriétés, ancré à droite de la vue : s'ouvre quand un panneau est sélectionné.
  Widget _propsDock() {
    final p = selectedPanel;
    if (p == null || activeTool != CadTool.select) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    final multi = selection.length > 1;
    return Material(
      key: const ValueKey('art_props'),
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      color: Theme.of(context).colorScheme.surface,
      child: SizedBox(
        width: 390,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 4, 0),
            child: Row(children: [
              const Icon(Icons.tune, color: _orange, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(multi ? trp('{0} panneaux sélectionnés', [selection.length]) : '${tr('Propriétés')} : ${tr(p.role.label)}',
                    style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              ),
              IconButton(
                tooltip: tr('Supprimer (Suppr)'),
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: _deleteSelected,
              ),
              IconButton(
                tooltip: tr('Fermer'),
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  selection.clear();
                  selectedPanel = null;
                }),
              ),
            ]),
          ),
          const Divider(height: 8),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: !art.free.contains(p)
                  ? Text(tr('Ce panneau appartient à un caisson standard. Modifiez le caisson ou ses dimensions.'), style: t.bodySmall)
                  : multi
                      ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          _materialPicker(null, (v) => _setMaterial(selection.toList(), v), label: 'Matière de toute la sélection'),
                          const SizedBox(height: 10),
                          Text(tr('Ctrl + clic pour ajouter ou retirer un panneau. Glissez avec l’outil Déplacer pour bouger l’ensemble, Suppr pour tout supprimer.'),
                              style: t.bodySmall),
                        ])
                      : _panelProps(context, p, (f) => setState(f), close: () => setState(() {
                            selection.clear();
                            selectedPanel = null;
                          })),
            ),
          ),
        ]),
      ),
    );
  }

  void _showPanelInspector(ArtPanel p) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.tune, color: _orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${tr('Propriétés')} : ${tr(p.role.label)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: _panelProps(ctx, p, setDlg, close: () => Navigator.pop(ctx)),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr('Fermer')),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------- sélection dans la 3D
  void _tap(Offset px) {
    final xs = art.boxOrigins;
    for (var i = 0; i < art.boxes.length; i++) {
      final b = art.boxes[i];
      for (final z in b.zones) {
        final zf = -b.tFront;
        final pts = [
          V3(xs[i] + z.fx0, z.fy0, zf),
          V3(xs[i] + z.fx1, z.fy0, zf),
          V3(xs[i] + z.fx1, z.fy1, zf),
          V3(xs[i] + z.fx0, z.fy1, zf),
        ].map((v) => cam.project(v).$1).toList();
        if ((Path()..addPolygon(pts, true)).contains(px)) {
          setState(() {
            boxIndex = i;
            zoneId = z.id;
            column = z.col;
            if (tab == 'caisson' || tab == 'debit' || tab == 'exterieur') tab = 'facades';
          });
          return;
        }
      }
    }
  }

  // ---------------------------------------------------------------- débit
  Future<void> _pdf() async {
    final plan = art.plan(widget.state.project.cut);
    if (plan.parts.isEmpty) return;
    final e = LayoutEngine(widget.state.catalog, Project(name: art.name));
    downloadBytes('${art.name}_plan_de_decoupe.pdf', await runBusy(context, tr('Plan de coupe…'), () => buildCutPdf(e, plan)), mime: 'application/pdf');
  }

  /// Épaisseur d'une matière de débit : « Latté … 18 · 2440×1220 » → 18 ; « MDF 18 (caisson) » → 18.
  static String _thicknessOf(String m) {
    final dot = RegExp(r'(\d+(?:[.,]\d+)?)\s*·').firstMatch(m);
    if (dot != null) return dot.group(1)!;
    return RegExp(r'\d+').firstMatch(m)?.group(0) ?? '18';
  }

  void _sct() {
    final plan = art.plan(widget.state.project.cut);
    for (final m in plan.materials) {
      downloadBytes('${art.name}_${m.split(' ').take(2).join('_')}.sct', toSct(plan, m, order: art.name, thickness: _thicknessOf(m)).codeUnits);
    }
  }

  void _toManual() {
    final cs = widget.state.project.cut;
    final parts = art.cutParts();
    if (parts.isEmpty) return;
    final mats = {for (final p in parts) p.material}.toList();
    final mat = mats.firstWhere((m) => m.contains('caisson'), orElse: () => mats.first);
    final job = ManualCut(order: art.name, material: mat, sheetLength: cs.sheetLength, sheetWidth: cs.sheetWidth, kerf: cs.kerf, trim: cs.trim, method: cs.method);
    for (final x in parts.where((x) => x.material == mat)) {
      job.parts.add(ManualPart(length: x.length, width: x.width, qty: x.qty, rotate: x.canRotate, edgeLong: x.edgeLong, edgeShort: x.edgeShort, desc: '${x.name} · ${x.cabinet}'));
    }
    widget.state.project.manual = job;
    openManualCut(context, widget.state);
  }

  // ---------------------------------------------------------------- écran
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final side = MediaQuery.sizeOf(context).width < 1200 ? 340.0 : 380.0;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undoOnce,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): _redoOnce,
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(
          body: SafeArea(
            child: Column(children: [
              _topBar(t, scheme),
              Divider(height: 1, color: scheme.outlineVariant),
              Expanded(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SizedBox(width: side, child: _side(t, scheme)),
                  VerticalDivider(width: 1, color: scheme.outlineVariant),
                  Expanded(child: ClipRect(child: _viewport())),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  void _saveKin() {
    Session.autosave('art', () => jsonEncode(art.toJson()));
    final kinBytes = KinFormat.encode(widget.state.exportJson(), projectName: art.name);
    downloadBytes('${art.name}.kin', kinBytes, mime: 'application/octet-stream');
    _msg(trp('{0}.kin enregistré', [art.name]));
  }

  Widget _topBar(TextTheme t, ColorScheme scheme) {
    Widget view(String id, String label) => TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(44, 40), padding: const EdgeInsets.symmetric(horizontal: 10)),
          onPressed: () => setState(() {
            cam.view(id);
            cam.fit(art.panels);
          }),
          child: Text(label),
        );
    return Container(
      color: scheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: Tokens.s2, vertical: 4),
      child: Row(children: [
        IconButton(tooltip: tr('Accueil'), icon: const Icon(Icons.home_outlined), onPressed: () => Navigator.of(context).maybePop()),
        const SizedBox(width: 48, height: 40, child: LogoMark()),
        const SizedBox(width: 8),
        Text(tr('Atelier'), style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(width: 6),
        IconButton(
          tooltip: tr('Ajouter un caisson'),
          icon: const Icon(Icons.add_box_outlined),
          onPressed: _chooseBase,
        ),
        if (box != null)
          IconButton(
            tooltip: tr('Dupliquer le caisson vers la droite'),
            icon: const Icon(Icons.control_point_duplicate_outlined),
            onPressed: () {
              final b = box;
              if (b == null) return;
              final clone = b.copy();
              clone.name = '${b.name} (copie)';
              _addBox(clone);
              _msg(tr('Caisson dupliqué avec succès'));
            },
          ),
        IconButton(
          tooltip: tr('Enregistrer (.kin)'),
          icon: const Icon(Icons.save_outlined),
          onPressed: _saveKin,
        ),
        IconButton(
          key: const ValueKey('lib_save'),
          tooltip: tr('Enregistrer dans la bibliothèque'),
          icon: const Icon(Icons.bookmark_add_outlined),
          onPressed: _saveToLibrary,
        ),
        const Spacer(),
        Flexible(
          flex: 6,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: Row(children: [
              view('iso', tr('3D')),
              view('face', tr('Face')),
              view('dessus', tr('Dessus')),
              view('droite', tr('Côté')),
              const SizedBox(width: 6),
              FilterChip(label: Text(tr('Façades')), selected: showFronts, onSelected: (v) => setState(() => showFronts = v)),
              const SizedBox(width: 6),
              FilterChip(label: Text(tr('Cotes')), selected: showDims, onSelected: (v) => setState(() => showDims = v)),
              const SizedBox(width: 6),
              FilterChip(label: Text(tr('Éclaté')), selected: exploded, onSelected: (v) => setState(() => exploded = v)),
              const SizedBox(width: 6),
              FilterChip(label: Text(tr('Composants')), selected: byComp, onSelected: (v) => setState(() => byComp = v)),
              IconButton(tooltip: tr('Tout voir'), onPressed: _fit, icon: const Icon(Icons.fit_screen_outlined)),
              IconButton(tooltip: tr('Annuler'), onPressed: _undo.isEmpty ? null : _undoOnce, icon: const Icon(Icons.undo)),
              IconButton(tooltip: tr('Rétablir'), onPressed: _redo.isEmpty ? null : _redoOnce, icon: const Icon(Icons.redo)),
            ]),
          ),
        ),
      ]),
    );
  }

  // ---------------------------------------------------------------- 3D
  Widget _viewport() => LayoutBuilder(builder: (context, c) {
        cam.size = c.biggest;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Listener(
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) cam.zoomAt(e.scrollDelta.dy > 0 ? 1.12 : 0.89);
          },
          child: MouseRegion(
            onHover: (e) {
              if (activeTool == CadTool.pushPull || activeTool == CadTool.edgeBand || activeTool == CadTool.groove) {
                final f = pickFace(cam, art.panels, e.localPosition);
                if (f != hoveredFace) {
                  setState(() => hoveredFace = f);
                }
              } else if (activePoints.isNotEmpty) {
                _updatePreview(e.localPosition);
              }
            },
            child: GestureDetector(
              onScaleStart: (d) {
                _last = d.localFocalPoint;
                _downAt = d.localFocalPoint;
                _moved = false;
                _lastScale = 1.0;
                _pressPlaced = false;
                if (d.pointerCount == 1) _dragStart(d.localFocalPoint);
                if (d.pointerCount == 1 && _isPlanarTool && activePoints.isEmpty) {
                  _handleTap(d.localFocalPoint);
                  _pressPlaced = true;
                }
                if (activeTool == CadTool.freehand) {
                  final pt = _unproject(d.localFocalPoint);
                  activePoints.clear();
                  activePoints.add(pt);
                }
              },
              onScaleUpdate: (d) {
                final delta = d.localFocalPoint - (_last ?? d.localFocalPoint);
                _last = d.localFocalPoint;
                if ((d.localFocalPoint - (_downAt ?? d.localFocalPoint)).distance > 6) _moved = true;
                if (_dragOrig != null && d.pointerCount == 1) {
                  if (_moved) _dragUpdate(d.localFocalPoint);
                  return;
                }
                if (d.pointerCount >= 2 || (_moved && (activeTool == CadTool.select || activeTool == CadTool.move || activeTool == CadTool.pushPull || activeTool == CadTool.rotate))) {
                  if (d.pointerCount >= 2) {
                    cam.pan(delta);
                    if (d.scale != 1.0) {
                      final factor = d.scale / _lastScale;
                      _lastScale = d.scale;
                      if ((factor - 1.0).abs() > 0.0001) cam.zoomAt(1.0 / factor);
                    }
                  } else {
                    cam.orbit(delta);
                  }
                } else if (activeTool == CadTool.freehand) {
                  final pt = _unproject(d.localFocalPoint);
                  activePoints.add(pt);
                  previewShape = CadFreehand(id: 'temp', points: [...activePoints]);
                  setState(() {});
                } else if (activePoints.isNotEmpty) {
                  _updatePreview(d.localFocalPoint);
                }
              },
              onScaleEnd: (_) {
                if (_dragOrig != null) {
                  final dragged = _moved;
                  _dragEnd();
                  if (dragged) return;
                }
                if (_isPlanarTool && activePoints.isNotEmpty && _moved && _last != null) {
                  _handleTap(_last!);
                  _pressPlaced = false;
                  return;
                }
                if (_pressPlaced) {
                  _pressPlaced = false;
                  return;
                }
                if (activeTool == CadTool.freehand && activePoints.length >= 2) {
                  final fh = CadFreehand(id: 'f${DateTime.now().millisecondsSinceEpoch}', points: [...activePoints]);
                  change(() => art.sketches.add(fh));
                  activePoints.clear();
                  previewShape = null;
                  setState(() {});
                } else if (!_moved && _downAt != null) {
                  _handleTap(_downAt!);
                }
              },
              child: Stack(children: [
                CustomPaint(
                  key: const Key('art-viewport'),
                  size: c.biggest,
                  painter: _ScenePainter(
                    cam: cam,
                    art: art,
                    boxIndex: boxIndex,
                    zoneId: zoneId,
                    showFronts: showFronts,
                    showDims: showDims && !exploded,
                    exploded: exploded,
                    byComp: byComp || focus != null,
                    focus: focus,
                    isDark: isDark,
                    activeTool: activeTool,
                    previewShape: previewShape,
                    activeTape: activeTape,
                    hoveredFace: hoveredFace,
                    selectedPanel: selectedPanel,
                    selection: selection.map((q) => q.id).toSet(),
                    selectedShape: selectedShape,
                    isMachiningMode: isMachiningMode,
                    activeSnapTarget: activeSnapTarget,
                    points: List.of(activePoints),
                    cursor: activePoints.isEmpty ? null : _hover,
                    liveLabel: _liveLabel,
                  ),
                ),
                if (!art.isEmpty) Positioned(left: 12, top: 68, child: _legend()),
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Center(
                    child: ArtCadToolbar(
                      activeTool: activeTool,
                      onToolSelected: _selectTool,
                      onClearSketches: () => change(() {
                        art.sketches.clear();
                        art.dimensions.clear();
                        _msg(tr('Toutes les esquisses 2D ont été effacées'));
                      }),
                      sketchCount: art.sketches.length,
                      dimensionCount: art.dimensions.length,
                      isMachiningMode: isMachiningMode,
                      onToggleMachiningMode: () => setState(() => isMachiningMode = !isMachiningMode),
                      workPlane: workPlane,
                      onWorkPlaneChanged: (wp) => setState(() => workPlane = wp),
                      orthoLock: orthoLock,
                      onToggleOrtho: (val) => setState(() => orthoLock = val),
                      autoExtrude: autoExtrude,
                      onToggleAutoExtrude: (val) => setState(() => autoExtrude = val),
                    ),
                  ),
                ),
                if (selectedPanel != null && activeTool == CadTool.select)
                  Positioned(top: 76, right: 12, bottom: 120, child: Align(alignment: Alignment.topRight, child: _propsDock())),
                if (activeTool != CadTool.select || selectedPanel != null)
                  Positioned(
                    bottom: 14,
                    left: 14,
                    right: 14,
                    child: Center(
                      child: ArtCadContextHud(
                        activeTool: activeTool,
                        statusText: cadStatus,
                        selectedPanel: selectedPanel,
                        selectedShape: selectedShape,
                        pushPullThickness: pushPullThickness,
                        onPushPullThicknessChanged: (v) => setState(() => pushPullThickness = v),
                        onExecutePushPull: _executePushPull,
                        onApplyEdgeBanding: _applyEdgeBanding,
                        onApplyGroove: _applyGroove,
                        onApplyMirror: _applyMirror,
                        onApplyTranslate: _applyTranslate,
                        onApplyRotate: _applyRotate,
                        onCancel: () => _selectTool(CadTool.select),
                        linePointsCount: activePoints.length,
                        onCloseLoop: _closeLineLoop,
                        onInspectPanel: selectedPanel != null ? () => _showPanelInspector(selectedPanel!) : null,
                        onDuplicateSelected: selectedPanel != null ? _duplicateSelected : null,
                        onDeleteSelected: selectedPanel != null ? _deleteSelected : null,
                        extra: activeTool.isDrawing
                            ? SizedBox(width: 230, child: _materialPicker(drawMaterial, (v) {
                                setState(() {
                                  drawMaterial = v;
                                  final pp = v == null ? null : PublicPrices.byId(v);
                                  if (pp != null) pushPullThickness = pp.thickness.toDouble();
                                });
                              }, label: 'Matière des panneaux'))
                            : null,
                        measureController: measure,
                        measureFocus: measureFocus,
                        measureHint: _measureHint,
                        onMeasure: (v) => _applyMeasure(v),
                        onSetRole: selectedPanel != null && art.free.contains(selectedPanel)
                            ? (r) => change(() {
                                  final p = selectedPanel!;
                                  p.role = r;
                                  p.finish = r.isFront ? 'blanc_mat' : p.finish;
                                })
                            : null,
                        onToggleHinge: selectedPanel != null && art.free.contains(selectedPanel)
                            ? () => change(() => selectedPanel!.hinge = selectedPanel!.hinge == 'left' ? 'right' : 'left')
                            : null,
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        );
      });

  /// Les composants communs à tout meuble, avec leur nombre dans ce projet : toucher pour les mettre en avant.
  Widget _legend() {
    final t = Theme.of(context).textTheme;
    final counts = <Comp, int>{};
    for (final p in art.panels) {
      final c = p.comp;
      if (c == null) continue;
      // un tiroir = une façade (son caisson est compté avec)
      if (c == Comp.tiroir && p.role != ArtRole.tiroir) continue;
      counts[c] = (counts[c] ?? 0) + 1;
    }
    return Material(
      color: Colors.white.withValues(alpha: 0.94),
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 230),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(tr('Structure du meuble'), style: t.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            for (final c in Comp.values)
              if (counts[c] != null)
                InkWell(
                  onTap: () => setState(() => focus = focus == c ? null : c),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                    decoration: BoxDecoration(color: focus == c ? Color(c.color).withValues(alpha: 0.16) : null, borderRadius: BorderRadius.circular(6)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 12, height: 12, decoration: BoxDecoration(color: Color(c.color), borderRadius: BorderRadius.circular(3))),
                      const SizedBox(width: 8),
                      Flexible(child: Text(tr(c.label), style: t.bodySmall?.copyWith(fontWeight: focus == c ? FontWeight.w800 : FontWeight.w500))),
                      const SizedBox(width: 8),
                      Text('${counts[c]}', style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
            if (focus != null) ...[
              const SizedBox(height: 4),
              Text(focus!.hint, style: t.labelSmall),
            ],
          ]),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- panneau de réglages
  Widget _tabStrip(TextTheme t, ColorScheme scheme, List<(String, String)> tabs) => Row(children: [
        for (final (id, label) in tabs)
          Expanded(
            child: InkWell(
              key: ValueKey('art_tab_$id'),
              onTap: () => setState(() {
                tab = id;
                if (id == 'usinage') isMachiningMode = true;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: tab == id ? _orange : scheme.outlineVariant, width: tab == id ? 3 : 1))),
                child: Center(child: FittedBox(child: Text(tr(label), style: t.labelLarge?.copyWith(fontWeight: tab == id ? FontWeight.w800 : FontWeight.w500)))),
              ),
            ),
          ),
      ]);

  Widget _side(TextTheme t, ColorScheme scheme) {
    final b = box;
    if (b == null) {
      // dessin libre (sans caisson tout fait) : bases, usinage, débit et bibliothèque
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _tabStrip(t, scheme, const [('bases', 'Bases'), ('usinage', 'Usinage'), ('debit', 'Débit'), ('biblio', 'Bibliothèque')]),
        Expanded(
          child: switch (tab) {
            'usinage' => _machiningTab(t, scheme),
            'debit' => art.free.isEmpty ? _start(t, scheme) : _cut(t, scheme),
            'biblio' => _libraryTab(t, scheme),
            _ => _start(t, scheme),
          },
        ),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // caissons du meuble
      SizedBox(
        height: 52,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(Tokens.s3, 8, Tokens.s3, 4), children: [
          for (var i = 0; i < art.boxes.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text('${i + 1} · ${art.boxes[i].name}'),
                selected: i == boxIndex,
                onSelected: (_) => setState(() {
                  boxIndex = i;
                  zoneId = art.boxes[i].zones.first.id;
                  column = 0;
                }),
              ),
            ),
          ActionChip(avatar: const Icon(Icons.add, size: 18), label: Text(tr('Caisson')), onPressed: _chooseBase),
        ]),
      ),
      // étapes : 1 caisson, 2 intérieur, 3 façades, 4 extérieur, 5 débit, 6 usinage
      Row(children: [
        for (final (id, n, label) in const [
          ('caisson', 1, 'Caisson'),
          ('interieur', 2, 'Intérieur'),
          ('facades', 3, 'Façades'),
          ('exterieur', 4, 'Extérieur'),
          ('debit', 5, 'Débit'),
          ('usinage', 6, 'Usinage'),
          ('biblio', 7, 'Bibliothèque'),
        ])
          Expanded(
            child: InkWell(
              onTap: () => setState(() {
                tab = id;
                if (id == 'usinage') isMachiningMode = true;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: tab == id ? _orange : scheme.outlineVariant, width: tab == id ? 3 : 1))),
                child: Column(children: [
                  CircleAvatar(
                    radius: 11,
                    backgroundColor: tab == id ? _orange : scheme.surfaceContainerHighest,
                    child: Text('$n', style: t.labelSmall?.copyWith(color: tab == id ? Colors.white : scheme.onSurface, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(height: 3),
                  FittedBox(child: Text(label, style: t.labelMedium?.copyWith(fontWeight: tab == id ? FontWeight.w800 : FontWeight.w500))),
                ]),
              ),
            ),
          ),
      ]),
      Expanded(
        child: switch (tab) {
          'interieur' => _interior(b, t, scheme),
          'facades' => _fronts(b, t, scheme),
          'exterieur' => _exterior(b, t, scheme),
          'debit' => _cut(t, scheme),
          'usinage' => _machiningTab(t, scheme),
          'biblio' => _libraryTab(t, scheme),
          _ => _carcass(b, t, scheme),
        },
      ),
    ]);
  }

  /// Enregistre la sélection (ou tout le meuble) dans la bibliothèque, sous un nom.
  Future<void> _saveToLibrary() async {
    final sel = selection.length > 1 ? selection.toList() : art.panels;
    if (sel.isEmpty) {
      _msg(tr('Rien à enregistrer : dessinez ou choisissez un meuble.'));
      return;
    }
    final name = TextEditingController(text: art.boxes.isNotEmpty ? art.boxes.first.name : tr('Mon meuble'));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Enregistrer dans la bibliothèque')),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(selection.length > 1
                ? trp('{0} panneaux sélectionnés', [selection.length])
                : tr('Tout le meuble de l’atelier')),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('lib_name'),
              controller: name,
              autofocus: true,
              decoration: InputDecoration(labelText: tr('Nom du meuble'), border: const OutlineInputBorder()),
              onSubmitted: (_) => Navigator.pop(ctx, true),
            ),
            const SizedBox(height: 8),
            Text(tr('Il se pose ensuite comme un objet dans la cuisine, le dressing, la salle de bain, le meuble TV et l’intérieur (panneau Objets → Bibliothèque).'),
                style: Theme.of(ctx).textTheme.bodySmall),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Annuler'))),
          FilledButton(key: const ValueKey('lib_ok'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Enregistrer'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final item = ArtLibrary.instance.add(name.text, sel);
    setState(() => tab = 'biblio');
    _msg(trp('« {0} » ajouté à la bibliothèque ({1} × {2} × {3} mm)', [item.name, item.w, item.h, item.d]));
  }

  /// Insère un meuble de la bibliothèque à droite de ce qui est déjà dessiné.
  void _insertFromLibrary(LibraryItem it) {
    final b = art.bounds;
    final x = b == null ? 0.0 : b.$3 + 100;
    final ps = it.placedAt(x, 0, 0, art.newId);
    change(() {
      art.free.addAll(ps);
      selection
        ..clear()
        ..addAll(ps);
      selectedPanel = ps.last;
      activeTool = CadTool.select;
    });
    cam.fit(art.panels);
    _msg(trp('« {0} » inséré', [it.name]));
  }

  Widget _libraryTab(TextTheme t, ColorScheme scheme) => ListenableBuilder(
        listenable: ArtLibrary.instance,
        builder: (context, _) {
          final items = ArtLibrary.instance.items;
          return ListView(padding: const EdgeInsets.all(Tokens.s4), children: [
            Text(tr('Bibliothèque'), style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(tr('Vos meubles enregistrés : à réinsérer ici, ou à poser comme objet dans les autres modes (panneau Objets → Bibliothèque).'),
                style: t.bodySmall),
            const SizedBox(height: Tokens.s3),
            FilledButton.icon(
              onPressed: _saveToLibrary,
              icon: const Icon(Icons.bookmark_add_outlined),
              label: Text(selection.length > 1 ? tr('Enregistrer la sélection') : tr('Enregistrer ce meuble')),
            ),
            const SizedBox(height: Tokens.s3),
            if (items.isEmpty) Text(tr('La bibliothèque est vide.'), style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            for (final it in items.reversed)
              Card(
                margin: const EdgeInsets.only(bottom: Tokens.s2),
                child: ListTile(
                  leading: const Icon(Icons.inventory_2_outlined, color: _orange),
                  title: Text(it.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(trp('{0} × {1} × {2} mm · {3} panneaux', [it.w, it.h, it.d, it.panels.length])),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(tooltip: tr('Insérer'), icon: const Icon(Icons.add_box_outlined), onPressed: () => _insertFromLibrary(it)),
                    IconButton(
                      tooltip: tr('Retirer de la bibliothèque'),
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final yes = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(tr('Retirer de la bibliothèque ?')),
                            content: Text(trp('« {0} » ne sera plus proposé. Les projets où il est déjà posé le gardent tant que la bibliothèque le contient.', [it.name])),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Annuler'))),
                              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Retirer'))),
                            ],
                          ),
                        );
                        if (yes == true) ArtLibrary.instance.remove(it.id);
                      },
                    ),
                  ]),
                ),
              ),
          ]);
        },
      );

  Widget _start(TextTheme t, ColorScheme scheme) => ListView(padding: const EdgeInsets.all(Tokens.s4), children: [
        Text(tr('Choisissez une base'), style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(tr('Tout meuble en bois a la même structure : côtés, bas, haut, derrière, séparations, étagères, puis portes, tiroirs, pieds et joues. '
            'On choisit une base, on la divise en colonnes et en étagères, puis on habille chaque zone.'),
            style: t.bodySmall),
        const SizedBox(height: Tokens.s3),
        for (final p in artPresets) _presetTile(p, t, () => _addBox(p.build())),
        const SizedBox(height: Tokens.s2),
        OutlinedButton.icon(onPressed: () => _addBox(ArtBox(name: 'Caisson vide', covers: {})), icon: const Icon(Icons.crop_square), label: Text(tr('Caisson vide 800 x 720'))),
        const SizedBox(height: 6),
        OutlinedButton.icon(onPressed: _importJson, icon: const Icon(Icons.file_open_outlined), label: Text(tr('Importer un caisson (JSON)'))),
        if (art.free.isNotEmpty) ...[
          const SizedBox(height: Tokens.s3),
          Text(trp('{0} panneau(x) libre(s) d’un ancien dessin.', [art.free.length]), style: t.bodySmall),
          TextButton(onPressed: () => change(art.free.clear), child: Text(tr('Les effacer'))),
        ],
      ]);

  Widget _section(TextTheme t, String title, [String? hint]) => Padding(
        padding: const EdgeInsets.only(top: Tokens.s4, bottom: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: t.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
          if (hint != null) Text(hint, style: t.bodySmall),
        ]),
      );

  Widget _num(String label, double v, void Function(double) on, {double min = 0, double max = 4000, double width = 104, String suffix = 'mm'}) => SizedBox(
        width: width,
        child: TextFormField(
          key: ValueKey('$boxIndex-$label-${v.round()}'),
          initialValue: '${v.round()}',
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: label, suffixText: suffix, isDense: true, border: const OutlineInputBorder()),
          onFieldSubmitted: (s) {
            final n = double.tryParse(s);
            if (n == null) return;
            change(() => on(n.clamp(min, max).toDouble()));
          },
        ),
      );

  Widget _finishRow(TextTheme t, String label, String value, List<Finish> list, void Function(String) on) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: t.labelMedium),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final f in list)
            Tooltip(
              message: f.name,
              child: InkWell(
                onTap: () => change(() => on(f.id)),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: f.color,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: value == f.id ? _orange : const Color(0x33000000), width: value == f.id ? 3 : 1),
                  ),
                ),
              ),
            ),
        ]),
      ]);

  // ---- 1. caisson : dimensions, épaisseurs, dessus, fond, finitions
  Widget _carcass(ArtBox b, TextTheme t, ColorScheme scheme) {
    void resizeW(double nw) {
      final k = (nw - 2 * b.t) / (b.w - 2 * b.t);
      for (var i = 0; i < b.seps.length; i++) {
        b.seps[i] = (b.t + (b.seps[i] - b.t) * k).roundToDouble();
      }
      b.w = nw;
    }

    return ListView(padding: const EdgeInsets.fromLTRB(Tokens.s3, 0, Tokens.s3, Tokens.s4), children: [
      _section(t, 'Nom'),
      TextFormField(
        key: ValueKey('name-$boxIndex'),
        initialValue: b.name,
        decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
        onFieldSubmitted: (s) => change(() => b.name = s.trim().isEmpty ? b.name : s.trim()),
      ),
      _section(t, 'Dimensions hors-tout', 'Sans pieds ni façade.'),
      Wrap(spacing: 8, runSpacing: 10, children: [
        _num('Largeur', b.w, resizeW, min: 150, max: 3000),
        _num('Hauteur', b.h, (v) {
          b.h = v;
          final n = b.pruneShelves();
          if (n > 0) WidgetsBinding.instance.addPostFrameCallback((_) => _msg(trp('{0} étagère(s) au-dessus de la nouvelle hauteur retirée(s)', [n])));
        }, min: 150, max: 2800),
        _num('Profondeur', b.d, (v) => b.d = v, min: 150, max: 900),
      ]),
      _section(t, 'Épaisseurs'),
      Wrap(spacing: 8, runSpacing: 10, children: [
        _num('Structure', b.t, (v) => b.t = v, min: 10, max: 40),
        _num('Fond', b.tBack, (v) => b.tBack = v, min: 3, max: 22),
        _num('Façade', b.tFront, (v) => b.tFront = v, min: 10, max: 40),
      ]),
      _section(t, 'Dessus', 'Traverses pour un bas de cuisine (sous plan de travail), panneau plein pour un haut ou un dressing.'),
      SegmentedButton<TopType>(
        showSelectedIcon: false,
        segments: [for (final x in TopType.values) ButtonSegment(value: x, label: Text(tr(x.label)))],
        selected: {b.top},
        onSelectionChanged: (v) => change(() => b.top = v.first),
      ),
      if (b.top == TopType.stretchers) ...[
        const SizedBox(height: 8),
        _num('Traverses', b.stretcher, (v) => b.stretcher = v, min: 50, max: 200),
      ],
      _section(t, 'Fond'),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final x in BackType.values) ChoiceChip(label: Text(tr(x.label)), selected: b.back == x, onSelected: (_) => change(() {
              b.back = x;
              if (x == BackType.screwed) b.tBack = 18;
              if (x != BackType.screwed && b.tBack == 18) b.tBack = 6;
            })),
      ]),
      if (b.back == BackType.groove) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 10, children: [
          _num('Retrait', b.backRecess, (v) => b.backRecess = v, max: 60),
          _num('Rainure', b.groove, (v) => b.groove = v, max: 15),
        ]),
      ],
      _section(t, 'Finitions'),
      _finishRow(t, 'Caisson', b.carcass, carcasses, (id) => b.carcass = id),
      const SizedBox(height: Tokens.s3),
      _finishRow(t, 'Façades', b.front, fronts.where((f) => !f.id.startsWith('tex:')).toList(), (id) => b.front = id),
      const SizedBox(height: Tokens.s4),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
            onPressed: () => change(() {
                  art.boxes.insert(boxIndex + 1, b.copy()..name = '${b.name} (copie)');
                  boxIndex++;
                }),
            icon: const Icon(Icons.copy, size: 18),
            label: Text(tr('Dupliquer'))),
        TextButton.icon(
            onPressed: () => change(() {
                  art.boxes.removeAt(boxIndex);
                  boxIndex = math.max(0, boxIndex - 1);
                  zoneId = box?.zones.first.id;
                }),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text(tr('Supprimer'))),
      ]),
    ]);
  }

  // ---- 2. intérieur : colonnes et tablettes
  Widget _interior(ArtBox b, TextTheme t, ColorScheme scheme) {
    final spans = b.columnSpans;
    final col = column.clamp(0, b.columns - 1);
    final (x0, x1) = spans[col];
    final shelves = b.shelvesOf(col);
    final innerH = b.innerTop - b.innerBottom;
    return ListView(padding: const EdgeInsets.fromLTRB(Tokens.s3, 0, Tokens.s3, Tokens.s4), children: [
      _section(t, 'Colonnes', 'Séparations verticales, du dessous au dessus.'),
      Row(children: [
        IconButton.outlined(onPressed: b.columns <= 1 ? null : () => change(() => _equalColumns(b, b.columns - 1)), icon: const Icon(Icons.remove)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('${b.columns}', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
        IconButton.outlined(onPressed: b.columns >= 8 ? null : () => change(() => _equalColumns(b, b.columns + 1)), icon: const Icon(Icons.add)),
        const SizedBox(width: 10),
        Expanded(child: Text(tr('largeurs égales'), style: t.bodySmall)),
      ]),
      if (b.seps.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 10, children: [
          for (var i = 0; i < b.seps.length; i++)
            _num('Séparation ${i + 1}', b.seps[i], (v) => b.seps[i] = v, min: b.t + 50, max: b.w - b.t - 50, width: 130),
        ]),
        Text(tr('Position de la face gauche, depuis le bord gauche du caisson.'), style: t.bodySmall),
      ],
      _section(t, 'Étagères de la colonne'),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (var c = 0; c < b.columns; c++)
          ChoiceChip(label: Text(trp('Col. {0} · {1}', [c + 1, (spans[c].$2 - spans[c].$1).round()])), selected: col == c, onSelected: (_) => setState(() => column = c)),
      ]),
      const SizedBox(height: 8),
      Text(trp('Hauteur intérieure {0} mm · largeur {1} mm. Une étagère fixe sépare deux zones de façade ; une mobile reste dans la zone (taquets).', [innerH.round(), (x1 - x0).round()]),
          style: t.bodySmall),
      const SizedBox(height: 8),
      for (final s in shelves)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            _num('Hauteur', s.y, (v) => s.y = v, min: 40, max: innerH - b.t - 40, width: 110),
            const SizedBox(width: 8),
            Expanded(
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                style: ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [ButtonSegment(value: true, label: Text(tr('Fixe'))), ButtonSegment(value: false, label: Text(tr('Mobile')))],
                selected: {s.fixed},
                onSelectionChanged: (v) => change(() => s.fixed = v.first),
              ),
            ),
            IconButton(tooltip: tr('Retirer'), onPressed: () => change(() => b.shelves[col]?.remove(s)), icon: const Icon(Icons.close)),
          ]),
        ),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
          onPressed: () => change(() {
            // au milieu du plus grand vide
            final ys = [0.0, for (final s in shelves) ...[s.y, s.y + b.t], innerH];
            var best = 0.0, at = innerH / 2;
            for (var i = 0; i + 1 < ys.length; i += 2) {
              if (ys[i + 1] - ys[i] > best) {
                best = ys[i + 1] - ys[i];
                at = (ys[i] + ys[i + 1] - b.t) / 2;
              }
            }
            (b.shelves[col] ??= []).add(ArtShelf(at.roundToDouble()));
          }),
          icon: const Icon(Icons.add),
          label: Text(tr('Étagère')),
        ),
        for (final n in const [2, 3, 4])
          TextButton(
            onPressed: () => change(() {
              final fixed = shelves.where((s) => s.fixed).toList();
              final step = (innerH - n * b.t) / (n + 1);
              b.shelves[col] = [...fixed, for (var k = 1; k <= n; k++) ArtShelf((k * step + (k - 1) * b.t).roundToDouble())];
            }),
            child: Text(trp('{0} mobiles réparties', [n])),
          ),
        TextButton(onPressed: () => change(() => b.shelves[col] = []), child: Text(tr('Vider'))),
        if (b.columns > 1)
          TextButton(
            onPressed: () => change(() {
              for (var c = 0; c < b.columns; c++) {
                b.shelves[c] = [for (final s in shelves) ArtShelf(s.y, fixed: s.fixed)];
              }
            }),
            child: Text(tr('Copier sur toutes les colonnes')),
          ),
      ]),
    ]);
  }

  // ---- 3. façades par zone
  Widget _fronts(ArtBox b, TextTheme t, ColorScheme scheme) {
    final zones = b.zones;
    final z = zones.where((x) => x.id == zoneId).firstOrNull ?? zones.first;
    final cv = b.covers[z.id];
    final type = cv?.type ?? CoverType.open;
    final fw = z.fx1 - z.fx0, fh = z.fy1 - z.fy0;
    ArtCover cover() => b.covers.putIfAbsent(z.id, () => ArtCover(type: CoverType.open));
    String zoneName(ArtZone x) {
      final rows = zones.where((y) => y.col == x.col).length;
      final pos = rows == 1 ? '' : (x.row == 0 ? ' · bas' : (x.row == rows - 1 ? ' · haut' : ' · milieu ${x.row}'));
      return b.columns == 1 ? 'Zone ${x.row + 1}$pos' : 'Col. ${x.col + 1}$pos';
    }

    return ListView(padding: EdgeInsets.fromLTRB(Tokens.s3, 0, Tokens.s3, Tokens.s4), children: [
      _section(t, 'Zone', 'Touchez une zone dans la 3D, ou choisissez-la ici.'),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final x in zones) ChoiceChip(label: Text(zoneName(x)), selected: x.id == z.id, onSelected: (_) => setState(() => zoneId = x.id)),
      ]),
      SizedBox(height: 6),
      Text(trp('Façade {0} x {1} mm · intérieur {2} x {3} mm', [fw.round(), fh.round(), z.width.round(), z.height.round()]), style: t.bodySmall),
      _section(t, 'Habillage'),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final x in CoverType.values)
          ChoiceChip(
            label: Text(tr(x.label)),
            selected: type == x,
            onSelected: (_) => change(() {
              cover().type = x;
              if (x == CoverType.door && fw > 600) cover().hinge = 'double';
            }),
          ),
      ]),
      if (type == CoverType.door) ...[
        _section(t, 'Ouverture'),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: 'left', label: Text(tr('Gauche'))),
            ButtonSegment(value: 'right', label: Text(tr('Droite'))),
            ButtonSegment(value: 'double', label: Text(tr('Deux portes'))),
          ],
          selected: {cv!.hinge},
          onSelectionChanged: (v) => change(() => cv.hinge = v.first),
        ),
        const SizedBox(height: 6),
        Text(trp('{0} charnière(s) par porte pour {1} mm de haut.', [ArtBox.hingesFor(fh), fh.round()]), style: t.bodySmall),
      ],
      if (type == CoverType.drawers) ...[
        _section(t, 'Nombre de tiroirs'),
        Row(children: [
          IconButton.outlined(onPressed: cv!.count <= 1 ? null : () => change(() => cv.count--), icon: const Icon(Icons.remove)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('${cv.count}', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
          IconButton.outlined(onPressed: cv.count >= 8 ? null : () => change(() => cv.count++), icon: const Icon(Icons.add)),
          SizedBox(width: 10),
          Expanded(child: Text(trp('façades de {0} mm', [((fh - b.gap * (cv.count - 1)) / cv.count).round()]), style: t.bodySmall)),
        ]),
        _section(t, 'Caisson de tiroir'),
        SegmentedButton<DrawerBox>(
          showSelectedIcon: false,
          segments: [ButtonSegment(value: DrawerBox.metal, label: Text(tr('Double paroi métal'))), ButtonSegment(value: DrawerBox.wood, label: Text(tr('Bois')))],
          selected: {b.drawerBox},
          onSelectionChanged: (v) => change(() => b.drawerBox = v.first),
        ),
        const SizedBox(height: 6),
        Text(trp('Coulisses {0} mm (profondeur utile {1} mm).', [b.slideLength, b.innerDepth.round()]), style: t.bodySmall),
      ],
      _section(t, 'Accessoires de la zone'),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final e in accessoryNames.entries)
          FilterChip(
            label: Text(e.value),
            selected: cv?.accessories.contains(e.key) ?? false,
            onSelected: (on) => change(() => on ? cover().accessories.add(e.key) : cover().accessories.remove(e.key)),
          ),
      ]),
      _section(t, 'Pour toutes les façades'),
      Text(tr('Ouverture'), style: t.labelMedium),
      const SizedBox(height: 4),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final (id, label) in const [('bar', 'Poignée barre'), ('knob', 'Bouton'), ('gola', 'Profil Gola'), ('push', 'Pousser-lâcher')])
          ChoiceChip(label: Text(label), selected: b.handle == id, onSelected: (_) => change(() => b.handle = id)),
      ]),
      const SizedBox(height: 10),
      _num('Jeu autour', b.gap, (v) => b.gap = v, min: 1, max: 6),
    ]);
  }

  // ---- 4. extérieur : base, joues, fileurs, corniche
  Widget _exterior(ArtBox b, TextTheme t, ColorScheme scheme) => ListView(padding: const EdgeInsets.fromLTRB(Tokens.s3, 0, Tokens.s3, Tokens.s4), children: [
        _section(t, 'Base'),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final x in BaseType.values)
            ChoiceChip(
              label: Text(tr(x.label)),
              selected: b.base == x,
              onSelected: (_) => change(() {
                b.base = x;
                if (x == BaseType.wall && b.baseH < 300) b.baseH = 1450;
                if (x != BaseType.wall && b.baseH > 300) b.baseH = 100;
              }),
            ),
        ]),
        if (b.base != BaseType.none) ...[
          const SizedBox(height: 10),
          _num(b.base == BaseType.wall ? 'Bas du meuble depuis le sol' : 'Hauteur', b.baseH, (v) => b.baseH = v, max: 2400, width: 220),
        ],
        _section(t, 'Joues de finition', 'Panneau de façade qui cache le côté du caisson et affleure la porte.'),
        Wrap(spacing: 6, children: [
          FilterChip(label: Text(tr('Gauche')), selected: b.cheekLeft, onSelected: (v) => change(() => b.cheekLeft = v)),
          FilterChip(label: Text(tr('Droite')), selected: b.cheekRight, onSelected: (v) => change(() => b.cheekRight = v)),
        ]),
        _section(t, 'Fileurs', 'Bandes d’ajustement contre un mur.'),
        Wrap(spacing: 8, runSpacing: 10, children: [
          _num('Gauche', b.fillerLeft, (v) => b.fillerLeft = v, max: 200),
          _num('Droite', b.fillerRight, (v) => b.fillerRight = v, max: 200),
        ]),
        _section(t, 'Corniche et cache-lumière'),
        Wrap(spacing: 6, children: [
          FilterChip(label: Text(tr('Corniche en haut')), selected: b.cornice, onSelected: (v) => change(() => b.cornice = v)),
          FilterChip(label: Text(tr('Cache-lumière en bas')), selected: b.valance, onSelected: (v) => change(() => b.valance = v)),
        ]),
      ]);

  // ---- 5. débit et quincaillerie (tout le meuble)
  Widget _cut(TextTheme t, ColorScheme scheme) {
    final parts = art.cutParts();
    final plan = nestCached(parts, widget.state.project.cut);
    final sp = widget.state.project.specs;
    final edge = parts.fold<double>(0, (a, p) => a + p.edgeLength * p.qty) / 1000;
    final mdf = plan.sheets.where((s) => !s.material.startsWith('HDF')).length;
    final warn = [for (final b in art.boxes) ...b.warnings()];
    final checks = artChecks(art.free.isEmpty ? const [] : art.panels, widget.state.project.cut);
    // prix des feuilles : celui du tarif pour les matières choisies, sinon le prix atelier du projet
    final sheetCost = plan.sheets.fold<double>(0, (a, sh) {
      final pp = PublicPrices.panels.where((q) => sh.material.startsWith('${q.name} ${q.thickness} ·')).firstOrNull;
      if (pp != null) return a + pp.price;
      return sh.material.startsWith('HDF') ? a : a + (sp.sheetPrice ?? 850);
    });
    assert(mdf >= 0);
    final cost = sheetCost + plan.sheets.length * sp.cuttingPerSheet + edge * (sp.edgePriceMin ?? 9);
    final byMat = <String, List<CutPart>>{};
    for (final p in parts) {
      (byMat[p.material] ??= []).add(p);
    }
    return ListView(padding: const EdgeInsets.fromLTRB(Tokens.s3, Tokens.s3, Tokens.s3, Tokens.s4), children: [
      Text(trp('{0} caisson(s) · {1} pièces · {2} feuille(s)', [art.boxes.length, parts.fold<int>(0, (a, p) => a + p.qty), plan.sheets.length]), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
      Text(trp('Chant {0} m · panneaux + chant + découpe ≈ {1} MAD', [edge.toStringAsFixed(1), cost.round()]), style: t.bodySmall),
      for (final ck in checks)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(ck.error ? Icons.error_outline : Icons.warning_amber_rounded, size: 18, color: ck.error ? scheme.error : const Color(0xFFD97706)),
            const SizedBox(width: 6),
            Expanded(
              child: InkWell(
                // toucher le contrôle sélectionne les panneaux en cause
                onTap: () => setState(() {
                  selection
                    ..clear()
                    ..addAll(art.panels.where((q) => ck.panelIds.contains(q.id) && art.free.contains(q)));
                  selectedPanel = selection.isEmpty ? null : selection.last;
                  activeTool = CadTool.select;
                }),
                child: Text(ck.message, style: t.bodySmall),
              ),
            ),
          ]),
        ),
      if (art.free.isNotEmpty && checks.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            const Icon(Icons.check_circle_outline, size: 18, color: Color(0xFF16A34A)),
            const SizedBox(width: 6),
            Expanded(child: Text(tr('Contrôles : rien à signaler, prêt à débiter.'), style: t.bodySmall)),
          ]),
        ),
      for (final w in warn)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.warning_amber_rounded, size: 18, color: scheme.error),
            const SizedBox(width: 6),
            Expanded(child: Text(w, style: t.bodySmall)),
          ]),
        ),
      const SizedBox(height: Tokens.s3),
      FilledButton.icon(onPressed: parts.isEmpty ? null : _pdf, icon: const Icon(Icons.picture_as_pdf_outlined), label: Text(tr('Plan de coupe (PDF)'))),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(child: OutlinedButton.icon(onPressed: parts.isEmpty ? null : _sct, icon: const Icon(Icons.content_cut), label: Text(tr('.sct')))),
        const SizedBox(width: 6),
        Expanded(child: OutlinedButton.icon(onPressed: parts.isEmpty ? null : _toManual, icon: const Icon(Icons.edit_note), label: Text(tr('Débit manuel')))),
      ]),
      for (final e in byMat.entries) ...[
        _section(t, e.key),
        for (final p in e.value)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(children: [
              SizedBox(width: 34, child: Text(trp('{0} ×', [p.qty]), style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700))),
              Expanded(child: Text(tr(p.name), style: t.bodySmall)),
              Text(trp('{0} x {1}', [p.length, p.width]), style: t.bodySmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ),
      ],
      _section(t, 'Quincaillerie et visserie'),
      for (final (name, usage, q) in art.hardware())
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 40, child: Text(trp('{0} ×', [q]), style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700))),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: t.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                Text(usage, style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
              ]),
            ),
          ]),
        ),
    ]);
  }

  Widget _presetTile(ArtPreset p, TextTheme t, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: Tokens.s2),
        child: Card(
          margin: EdgeInsets.zero,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(Tokens.s2),
              child: Row(children: [
                SizedBox(width: 76, height: 64, child: CustomPaint(painter: _PresetPainter(p))),
                const SizedBox(width: Tokens.s2),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr(p.name), style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Text(tr(p.description), style: t.labelSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      );

  Widget _machiningTab(TextTheme t, ColorScheme scheme) {
    final m = computeMachiningElements(art.panels);
    String m2(double v) => '${v.toStringAsFixed(2).replaceAll('.', ',')} m';
    String pcs(int n) => trp('{0} pcs', [n]);
    final rows = <(IconData, Color, String, String)>[
      (Icons.circle, const Color(0xFFD97706), tr('Tourillons Ø8 x 35 mm'), pcs(m.dowelsCount)),
      (Icons.add_circle_outline, const Color(0xFF64748B), tr('Vis Confirmat Ø7 x 50 mm'), pcs(m.screwsCount)),
      (Icons.adjust, const Color(0xFFEF4444), tr('Boîtiers de charnière Ø35'), pcs(m.hingeCupsCount)),
      (Icons.view_agenda_outlined, const Color(0xFF16A34A), tr('Coulisses de tiroir'), pcs(m.count(MachiningKind.slide))),
      (Icons.drag_handle, const Color(0xFF1E293B), tr('Poignées'), pcs(m.count(MachiningKind.handle))),
      (Icons.more_vert, const Color(0xFF0284C7), tr('Perçages taquets Ø5 (système 32)'), pcs(m.shelfHolesCount)),
      (Icons.height, const Color(0xFF334155), tr('Pieds réglables'), pcs(m.count(MachiningKind.foot))),
      (Icons.line_style, const Color(0xFF334155), tr('Rainures pour fond'), m2(m.totalGrooveMeters)),
      for (final e in m.edgeByThickness.entries)
        (Icons.border_all, const Color(0xFFF26522), trp('Chant {0} mm', [e.key == e.key.roundToDouble() ? e.key.round() : e.key]), m2(e.value)),
    ];
    return ListView(
      padding: const EdgeInsets.all(Tokens.s4),
      children: [
        Row(children: [
          const Icon(Icons.precision_manufacturing, color: Color(0xFFD97706), size: 24),
          const SizedBox(width: 8),
          Expanded(child: Text(tr('Usinages & Perçages'), style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 6),
        Text(
          tr('Calculé automatiquement d’après les panneaux qui se touchent : assemblages, fonds, façades, tablettes mobiles, pieds et chants visibles.'),
          style: t.bodySmall,
        ),
        const SizedBox(height: Tokens.s3),
        FilledButton.icon(
          key: const ValueKey('machining_toggle'),
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD97706)),
          icon: Icon(isMachiningMode ? Icons.visibility_off : Icons.visibility),
          label: Text(isMachiningMode ? tr('Masquer les usinages 3D') : tr('Afficher les usinages 3D')),
          onPressed: () => setState(() => isMachiningMode = !isMachiningMode),
        ),
        const SizedBox(height: Tokens.s3),
        Card(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 14),
                _machiningRow(rows[i].$1, rows[i].$2, rows[i].$3, rows[i].$4),
              ],
            ]),
          ),
        ),
        const SizedBox(height: Tokens.s4),
        Text(tr('Quincaillerie à commander'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: Tokens.s2),
        if (m.hardware.isEmpty) Text(tr('Posez des panneaux qui se touchent pour voir les assemblages.'), style: t.bodySmall),
        for (final (name, usage, q) in m.hardware)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 44, child: Text('$q×', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr(name), style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  Text(tr(usage), style: t.bodySmall),
                ]),
              ),
            ]),
          ),
      ],
    );
  }

  Widget _machiningRow(IconData icon, Color color, String title, String value) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }
}

/// Choix de la base d'un nouveau caisson.
class _PresetDialog extends StatelessWidget {
  const _PresetDialog();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text(tr('Nouveau caisson')),
      content: SizedBox(
        width: 520,
        height: 460,
        child: GridView.extent(
          maxCrossAxisExtent: 250,
          childAspectRatio: 1.25,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            for (final p in artPresets)
              Card(
                margin: EdgeInsets.zero,
                child: InkWell(
                  onTap: () => Navigator.of(context).pop(p.build()),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(children: [
                      Expanded(child: CustomPaint(painter: _PresetPainter(p), size: Size.infinite)),
                      Text(tr(p.name), style: t.labelLarge?.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('Annuler')))],
    );
  }
}

// ------------------------------------------------------------------ rendu 3D

void _paintPanels(Canvas c, ArtCamera cam, List<ArtPanel> panels, {double edge = 1, bool byComp = false, Comp? focus, bool isDark = false, double opacity = 1}) {
  final faces = <(double, Face)>[];
  for (final panel in panels) {
    for (final f in facesOf(panel)) {
      final toCam = cam.ortho ? cam.forward * -1 : (cam.eye - f.center);
      if (f.normal.dot(toCam) <= 0) continue;
      faces.add((cam.project(f.center).$2, f));
    }
  }
  faces.sort((a, b) => b.$1.compareTo(a.$1));
  final light = const V3(-0.35, 0.85, -0.4).unit;
  final fillLight = const V3(0.4, 0.3, 0.5).unit;
  for (final (_, f) in faces) {
    final cs = f.corners.map((v) => cam.project(v).$1).toList();
    final path = Path()..addPolygon(cs, true);
    final comp = f.panel.comp;
    final base = byComp && comp != null ? Color(comp.color) : artColor(f.panel.finish);
    final hsl = HSLColor.fromColor(base);
    final direct = math.max(0.0, f.normal.dot(light));
    final fill = math.max(0.0, f.normal.dot(fillLight)) * 0.15;
    final lum = 0.58 + 0.34 * direct + fill;
    final ghost = focus != null && comp != focus;
    final fillColor = hsl.withLightness((hsl.lightness * lum + 0.03).clamp(0.0, 1.0)).toColor();
    c.drawPath(path, Paint()..color = ghost ? fillColor.withValues(alpha: 0.12) : fillColor.withValues(alpha: opacity));
    c.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = edge
      ..color = ghost
          ? (isDark ? const Color(0x22FFFFFF) : const Color(0x221F1A17))
          : (isDark ? const Color(0x77FFFFFF) : const Color(0xBB1F1A17)));
  }
}

class _ScenePainter extends CustomPainter {
  final ArtCamera cam;
  final ArtProject art;
  final int boxIndex;
  final String? zoneId;
  final bool showFronts, showDims, exploded, byComp, isDark;
  final Comp? focus;
  final CadTool activeTool;
  final CadShape? previewShape;
  final CadTapeMeasure? activeTape;
  final Face? hoveredFace;
  final ArtPanel? selectedPanel;
  final Set<String> selection;
  final CadShape? selectedShape;
  final bool isMachiningMode;
  final CadSnapTarget? activeSnapTarget;
  final List<V3> points; // points déjà posés de la forme en cours
  final V3? cursor; // point sous le doigt / la souris
  final String? liveLabel; // cote affichée à côté du curseur

  _ScenePainter({
    required this.cam,
    required this.art,
    required this.boxIndex,
    required this.zoneId,
    required this.showFronts,
    required this.showDims,
    this.exploded = false,
    this.byComp = false,
    this.focus,
    this.isDark = false,
    this.activeTool = CadTool.select,
    this.previewShape,
    this.activeTape,
    this.hoveredFace,
    this.selectedPanel,
    this.selection = const {},
    this.selectedShape,
    this.isMachiningMode = false,
    this.activeSnapTarget,
    this.points = const [],
    this.cursor,
    this.liveLabel,
  }) : super(repaint: cam);

  /// Vue éclatée : chaque composant s'écarte du centre de son caisson dans sa direction naturelle.
  List<ArtPanel> _explode(List<ArtPanel> ps) {
    final xs = art.boxOrigins;
    final out = <ArtPanel>[];
    // panneaux dessinés librement : chacun s'éloigne du centre de l'ensemble, le long de son épaisseur surtout
    final free = ps.where((p) => p.comp == null).toList();
    final gx = free.isEmpty ? 0.0 : free.map((p) => p.x + p.w / 2).reduce((a, b) => a + b) / free.length;
    final gy = free.isEmpty ? 0.0 : free.map((p) => p.y + p.h / 2).reduce((a, b) => a + b) / free.length;
    final gz = free.isEmpty ? 0.0 : free.map((p) => p.z + p.d / 2).reduce((a, b) => a + b) / free.length;
    for (final p in ps) {
      final c = p.comp;
      final i = p.id.startsWith('b') ? int.tryParse(p.id.substring(1, p.id.indexOf('_'))) : null;
      if (c == null || i == null || i >= art.boxes.length) {
        if (c != null) {
          out.add(p);
          continue;
        }
        final q = p.copy();
        final ta = thicknessAxis(p);
        double push(double off, int ax) => off.abs() < 1 ? 0 : off.sign * (ax == ta ? 160.0 : 40.0) + off * 0.15;
        q.x += push(p.x + p.w / 2 - gx, 0);
        q.y += push(p.y + p.h / 2 - gy, 1);
        q.z += push(p.z + p.d / 2 - gz, 2);
        out.add(q);
        continue;
      }
      final cx = xs[i] + art.boxes[i].w / 2;
      final side = (p.x + p.w / 2) < cx ? -1.0 : 1.0;
      final q = p.copy();
      switch (c) {
        case Comp.cote:
          q.x += side * 260;
        case Comp.joue:
          q.x += side * 480;
        case Comp.fileur:
          q.x += side * 620;
        case Comp.dessus || Comp.traverse:
          q.y += 260;
        case Comp.corniche:
          q.y += 420;
        case Comp.dessous:
          q.y -= 120;
        case Comp.pied:
          q.y -= 300;
        case Comp.fond:
          q.z += 420;
        case Comp.etagere:
          q.z -= 160;
        case Comp.porte || Comp.abattant || Comp.tiroir:
          q.z -= 520;
        case Comp.separation:
          break;
      }
      out.add(q);
    }
    return out;
  }

  Offset p(V3 v) => cam.project(v).$1;

  @override
  void paint(Canvas c, Size size) {
    // Fond adapté au thème
    final bgColors = isDark
        ? const [Color(0xFF1E222A), Color(0xFF121418)]
        : const [Color(0xFFEDEFF1), Color(0xFFF8F5F1)];
    c.drawRect(
      Offset.zero & size,
      Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: bgColors).createShader(Offset.zero & size),
    );

    // Sol : grille
    final gridColor = isDark ? const Color(0x1FFFFFFF) : const Color(0x18000000);
    final g = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    const ext = 4000.0;
    for (var v = -ext; v <= ext; v += 500) {
      c.drawLine(p(V3(v, 0, -ext)), p(V3(v, 0, ext)), g);
      c.drawLine(p(V3(-ext, 0, v)), p(V3(ext, 0, v)), g);
    }

    // Ombres de contact au sol sous les caissons
    if (!art.isEmpty && !exploded) {
      final xs = art.boxOrigins;
      for (var i = 0; i < art.boxes.length; i++) {
        final b = art.boxes[i];
        final ox = xs[i];
        // Passes douces d'ombre de contact au sol
        for (var pass = 1; pass <= 3; pass++) {
          final pad = pass * 14.0;
          final shadowPts = [
            V3(ox - pad, 0, -pad),
            V3(ox + b.w + pad, 0, -pad),
            V3(ox + b.w + pad, 0, b.d + pad),
            V3(ox - pad, 0, b.d + pad),
          ].map(p).toList();
          final sPath = Path()..addPolygon(shadowPts, true);
          final opacity = isDark ? 0.09 / pass : 0.05 / pass;
          c.drawPath(sPath, Paint()..color = (isDark ? Colors.black : const Color(0xFF1B2028)).withValues(alpha: opacity));
        }
      }
    }

    // projet vide : on invite à commencer, sans s'arrêter là (la forme en cours de tracé doit se voir)
    if (art.isEmpty && points.isEmpty && previewShape == null) {
      final tp = TextPainter(
          text: TextSpan(text: tr(activeTool.isDrawing ? 'Dessinez au sol, ou choisissez une base à gauche' : 'Choisissez une base à gauche'), style: TextStyle(fontSize: 16, color: isDark ? const Color(0xFF9EABB8) : const Color(0xFF6B7178), fontWeight: FontWeight.w600)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(c, size.center(Offset(-tp.width / 2, -tp.height / 2)));
    }
    var panels = art.panels.where((x) => showFronts || exploded || !(x.comp?.isFront ?? x.role.isFront)).toList();
    final assembled = panels;
    if (exploded) panels = _explode(panels);
    // décalage de chaque panneau dans la vue éclatée (tourillons et vis suivent leur panneau)
    final shift = <String, V3>{
      for (var i = 0; i < panels.length; i++) assembled[i].id: V3(panels[i].x - assembled[i].x, panels[i].y - assembled[i].y, panels[i].z - assembled[i].z),
    };
    // usinage : panneaux en transparence pour voir les perçages et la quincaillerie à l'intérieur
    _paintPanels(c, cam, panels, byComp: byComp, focus: focus, isDark: isDark, opacity: isMachiningMode ? 0.45 : 1);

    // Surbrillance du caisson actif ou de la zone sélectionnée en 3D
    final frontNormal = const V3(0, 0, -1);
    final xs = art.boxOrigins;
    if (!exploded && focus == null && boxIndex < art.boxes.length) {
      final b = art.boxes[boxIndex];
      final ox = xs[boxIndex];
      final zFront = showFronts ? -b.tFront - 1 : 0.0;
      final toCam = cam.ortho ? cam.forward * -1 : (cam.eye - V3(ox + b.w / 2, b.y0 + b.h / 2, zFront));
      final isFacingFront = frontNormal.dot(toCam) > 0;

      // On n'affiche le contour de façade que si la face avant fait face à la caméra (backface culling)
      if (isFacingFront) {
        if (zoneId != null) {
          final z = b.zones.where((x) => x.id == zoneId).firstOrNull;
          if (z != null) {
            final pts = [
              V3(ox + z.fx0, z.fy0, zFront),
              V3(ox + z.fx1, z.fy0, zFront),
              V3(ox + z.fx1, z.fy1, zFront),
              V3(ox + z.fx0, z.fy1, zFront),
            ].map(p).toList();
            final path = Path()..addPolygon(pts, true);
            c.drawPath(path, Paint()..color = _orange.withValues(alpha: 0.12));
            c.drawPath(path, Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.2
              ..color = _orange);
          }
        } else {
          final boxFrontPts = [
            V3(ox, b.y0, zFront),
            V3(ox + b.w, b.y0, zFront),
            V3(ox + b.w, b.y0 + b.h, zFront),
            V3(ox, b.y0 + b.h, zFront),
          ].map(p).toList();
          final bPath = Path()..addPolygon(boxFrontPts, true);
          c.drawPath(bPath, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0
            ..color = _orange.withValues(alpha: 0.5));
        }
      }
    }
    // poignées
    if (showFronts && !exploded && focus == null) {
      for (var i = 0; i < art.boxes.length; i++) {
        final b = art.boxes[i];
        if (b.handle == 'push') continue;
        final ox = xs[i];
        final zFront = -b.tFront;
        final toCam = cam.ortho ? cam.forward * -1 : (cam.eye - V3(ox + b.w / 2, b.y0 + b.h / 2, zFront));
        if (frontNormal.dot(toCam) <= 0) continue; // Face cachée par l'arrière ou côté du caisson

        for (final pn in panels.where((x) => x.id.startsWith('b${i}_') && x.role.isFront)) {
          final z = pn.z - 1;
          if (b.handle == 'gola') {
            c.drawLine(p(V3(pn.x, pn.top - 4, z)), p(V3(pn.right, pn.top - 4, z)), Paint()
              ..color = const Color(0xFF3C4148)
              ..strokeWidth = 2.5);
            continue;
          }
          final door = pn.role == ArtRole.porte;
          final hx = door ? (pn.hinge == 'left' ? pn.right - 40 : pn.x + 40) : pn.x + pn.w / 2;
          final double cy;
          if (door) {
            if (b.base == BaseType.wall) {
              // Meuble haut : poignée en bas de porte
              cy = pn.y + math.min(90.0, pn.h / 3);
            } else if (pn.top <= 1200) {
              // Meuble bas ou sous-bac : poignée en haut de porte
              cy = pn.top - math.min(90.0, pn.h / 3);
            } else {
              // Armoire / dressing pleine hauteur : hauteur de préhension (~1050 mm)
              cy = math.max(pn.y + 80, math.min(pn.top - 80, 1050.0));
            }
          } else {
            // Tiroir : centré
            cy = pn.top - math.min(50.0, pn.h / 2);
          }
          if (b.handle == 'knob') {
            c.drawCircle(p(V3(hx, cy, z)), 3.5, Paint()..color = const Color(0xFF6B7178));
          } else {
            final a = door ? V3(hx, cy - 60, z) : V3(hx - 60, cy, z);
            final e = door ? V3(hx, cy + 60, z) : V3(hx + 60, cy, z);
            c.drawLine(p(a), p(e), Paint()
              ..color = const Color(0xFF6B7178)
              ..strokeWidth = 3
              ..strokeCap = StrokeCap.round);
          }
        }
      }
    }
    // tringles
    for (var i = 0; i < art.boxes.length; i++) {
      final b = art.boxes[i];
      for (final z in b.zones) {
        final cv = b.coverOf(z);
        if (!cv.accessories.contains('rod') || (showFronts && cv.type != CoverType.open)) continue;
        final y = z.y1 - 60, dz = b.innerDepth / 2;
        c.drawLine(p(V3(xs[i] + z.x0, y, dz)), p(V3(xs[i] + z.x1, y, dz)), Paint()
          ..color = const Color(0xFF8A9096)
          ..strokeWidth = 3);
      }
    }
    // cotes du caisson choisi
    if (showDims && boxIndex < art.boxes.length) {
      final b = art.boxes[boxIndex];
      final ox = xs[boxIndex];
      const col = Color(0xFF1D4ED8);
      final zFront = showFronts ? -b.tFront : 0.0;
      // Largeur (width) avec lignes de rappel vers les angles
      _dim(c, V3(ox, b.y0, zFront - 60), V3(ox + b.w, b.y0, zFront - 60), '${b.w.round()}', col,
          anchorA: V3(ox, b.y0, zFront), anchorB: V3(ox + b.w, b.y0, zFront));
      // Hauteur (height) avec lignes de rappel
      _dim(c, V3(ox - 60, b.y0, zFront), V3(ox - 60, b.y0 + b.h, zFront), '${b.h.round()}', col,
          anchorA: V3(ox, b.y0, zFront), anchorB: V3(ox, b.y0 + b.h, zFront));
      // Profondeur (depth) avec lignes de rappel
      _dim(c, V3(ox + b.w + 60, b.y0, 0), V3(ox + b.w + 60, b.y0, b.d), '${b.d.round()}', col,
          anchorA: V3(ox + b.w, b.y0, 0), anchorB: V3(ox + b.w, b.y0, b.d));
      if (b.y0 > 0) {
        _dim(c, V3(ox - 60, 0, zFront), V3(ox - 60, b.y0, zFront), '${b.y0.round()}', const Color(0xFF6B7178),
            anchorA: V3(ox, 0, zFront), anchorB: V3(ox, b.y0, zFront));
      }
    }

    // ---------------------------------------------------------------- CAO & Menuiserie (Chants, Rainures, Esquisses)
    // 1. Chants sur les arêtes des panneaux
    for (final pn in panels) {
      if (pn.edgeLong > 0 || pn.edgeShort > 0) {
        final col = pn.edgeThickness >= 2.0
            ? const Color(0xFFEF4444)
            : (pn.edgeThickness >= 1.0 ? _orange : const Color(0xFFF59E0B));
        final chantPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(3.0, pn.edgeThickness * 2.2)
          ..strokeCap = StrokeCap.round
          ..color = col;
        final c1 = p(V3(pn.x, pn.y, pn.z));
        final c2 = p(V3(pn.right, pn.y, pn.z));
        final c3 = p(V3(pn.right, pn.top, pn.z));
        final c4 = p(V3(pn.x, pn.top, pn.z));
        if (pn.edgeLong >= 1) c.drawLine(c1, c2, chantPaint);
        if (pn.edgeLong >= 2) c.drawLine(c4, c3, chantPaint);
        if (pn.edgeShort >= 1) c.drawLine(c1, c4, chantPaint);
        if (pn.edgeShort >= 2) c.drawLine(c2, c3, chantPaint);
      }

      // 2. Rainures (Grooves)
      if (pn.hasGroove) {
        final groovePaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..color = const Color(0xFF334155);
        final g1 = p(V3(pn.x + pn.grooveOffset, pn.y + pn.grooveOffset, pn.z));
        final g2 = p(V3(pn.right - pn.grooveOffset, pn.y + pn.grooveOffset, pn.z));
        c.drawLine(g1, g2, groovePaint);
      }
    }

    // 3. Panneaux sélectionnés : les 12 arêtes en orange vif
    final chosen = {...selection, if (selectedPanel != null) selectedPanel!.id};
    for (final sp in panels.where((q) => chosen.contains(q.id))) {
      final k = [for (final x in [sp.x, sp.right]) for (final y in [sp.y, sp.top]) for (final z in [sp.z, sp.back]) p(V3(x, y, z))];
      const edges = [(0, 1), (2, 3), (4, 5), (6, 7), (0, 2), (1, 3), (4, 6), (5, 7), (0, 4), (1, 5), (2, 6), (3, 7)];
      final sel = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..color = _orange;
      for (final (a, b) in edges) {
        c.drawLine(k[a], k[b], sel);
      }
    }

    // 3 ter. Vis et tourillons : têtes de vis visibles sur les faces ; en vue éclatée, le tourillon dépasse
    // du chant de la pièce qui le reçoit et la vis traverse la pièce qui la porte, prêts à l'assemblage.
    if (!isMachiningMode && assembled.isNotEmpty) {
      final m = computeMachiningElements(assembled);
      final byId = {for (final q in assembled) q.id: q};
      double px(V3 at, double mm) => (p(at + cam.right * mm) - p(at)).distance; // largeur à l'écran de mm millimètres
      for (final el in m.elements) {
        if (el.kind != MachiningKind.dowel && el.kind != MachiningKind.screw) continue;
        final host = byId[el.panelId], guest = byId[el.partnerPanelId];
        if (host == null || guest == null) continue;
        final n = el.normal; // de la pièce hôte (face) vers la pièce invitée (chant)
        final ht = host.thickness;
        if (!exploded) {
          if (el.kind != MachiningKind.screw) continue; // le tourillon est caché dans le joint
          // tête de vis sur la face extérieure de l'hôte, si cette face se voit
          final head = el.position - n * ht;
          final f = pickFace(cam, panels, p(head));
          if (f == null || f.panel.id != host.id) continue;
          final r = px(head, 5.5).clamp(2.0, 9.0);
          c.drawCircle(p(head), r, Paint()..color = const Color(0xFF94A3B8));
          c.drawCircle(p(head), r, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0xFF334155));
          final k = r * 0.55;
          final cross = Paint()
            ..color = const Color(0xFF1E293B)
            ..strokeWidth = 1.2;
          c.drawLine(p(head) - Offset(k, 0), p(head) + Offset(k, 0), cross);
          c.drawLine(p(head) - Offset(0, k), p(head) + Offset(0, k), cross);
          continue;
        }
        final gs = shift[guest.id] ?? V3.zero, hs = shift[host.id] ?? V3.zero;
        if (el.kind == MachiningKind.dowel) {
          // perçage dans la face de l'hôte, tourillon planté dans le chant de l'invité (moitié dehors)
          final hole = el.position + hs;
          c.drawCircle(p(hole), px(hole, 4).clamp(1.5, 6.0), Paint()..color = const Color(0xFF3F2A14));
          final a = el.position + gs, b = el.position - n * 17.5 + gs;
          final w = px(a, 8).clamp(4.5, 14.0);
          c.drawLine(p(a), p(b), Paint()
            ..strokeWidth = w
            ..strokeCap = StrokeCap.round
            ..color = const Color(0xFFD9A15B));
          c.drawLine(p(a), p(b), Paint()
            ..strokeWidth = w * 0.35
            ..strokeCap = StrokeCap.round
            ..color = const Color(0xFFF3D19C));
        } else {
          // vis Confirmat : traverse l'hôte et dépasse vers le chant de l'invité, où l'avant-trou l'attend
          final pilot = el.position + gs;
          c.drawCircle(p(pilot), px(pilot, 2.5).clamp(1.2, 4.0), Paint()..color = const Color(0xFF1E293B));
          final head = el.position - n * ht + hs, tip = el.position + n * (50 - ht) + hs;
          final w = px(head, 6).clamp(3.5, 10.0);
          c.drawLine(p(head), p(tip), Paint()
            ..strokeWidth = w * 0.6
            ..strokeCap = StrokeCap.round
            ..color = const Color(0xFF64748B));
          c.drawCircle(p(head), w * 0.9, Paint()..color = const Color(0xFF94A3B8));
          c.drawCircle(p(head), w * 0.9, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0xFF1E293B));
        }
      }
    }

    // 3 bis. Chants et rainures visibles sur les pièces (hors vue usinage, qui les montre déjà)
    if (!isMachiningMode && !exploded && panels.isNotEmpty) {
      final work = computeMachiningElements(panels);
      for (final el in work.elements) {
        if (el.kind != MachiningKind.edge && el.kind != MachiningKind.groove) continue;
        final mid = el.position + el.normal * (el.length / 2);
        final f = pickFace(cam, panels, p(mid));
        if (f == null || (f.panel.id != el.panelId && f.panel.id != el.partnerPanelId)) continue; // caché derrière un autre panneau
        if (el.kind == MachiningKind.edge) {
          c.drawLine(p(el.position), p(el.end), Paint()
            ..strokeWidth = el.diameter >= 2 ? 3.2 : 2.2
            ..strokeCap = StrokeCap.round
            ..color = el.diameter >= 2 ? const Color(0xFFF26522) : const Color(0xFFF59E0B));
        } else {
          c.drawLine(p(el.position), p(el.end), Paint()
            ..strokeWidth = 3.4
            ..strokeCap = StrokeCap.butt
            ..color = const Color(0xFF334155));
          c.drawLine(p(el.position), p(el.end), Paint()
            ..strokeWidth = 1.2
            ..color = const Color(0xFFCBD5E1));
        }
      }
    }

    // 4. Esquisses 2D enregistrées
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..color = const Color(0xFF0284C7);
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0x330284C7);

    for (final s in art.sketches) {
      final pts = s.vertices.map(p).toList();
      if (pts.isEmpty) continue;
      final path = Path();
      path.moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      if (s.isClosed) path.close();

      if (s.isClosed) c.drawPath(path, fillPaint);
      c.drawPath(path, strokePaint);

      for (final pt in pts) {
        c.drawCircle(pt, 3.5, Paint()..color = const Color(0xFF0284C7));
        c.drawCircle(pt, 2.0, Paint()..color = Colors.white);
      }
    }

    // 5. Esquisse 2D en cours (Ghost preview)
    if (previewShape != null) {
      final pts = previewShape!.vertices.map(p).toList();
      if (pts.isNotEmpty) {
        final previewPath = Path();
        previewPath.moveTo(pts.first.dx, pts.first.dy);
        for (var i = 1; i < pts.length; i++) {
          previewPath.lineTo(pts[i].dx, pts[i].dy);
        }
        if (previewShape!.isClosed) previewPath.close();
        final ghostPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..color = _orange;
        c.drawPath(previewPath, ghostPaint);
      }
    }

    // 5 bis. Points posés (le 1er en vert : y revenir ferme le contour), curseur et cote en direct
    if (activeTool.isDrawing && (points.isNotEmpty || cursor != null)) {
      final fillPreview = previewShape;
      if (fillPreview != null && fillPreview.isClosed) {
        final pts = fillPreview.vertices.map(p).toList();
        if (pts.length >= 3) c.drawPath(Path()..addPolygon(pts, true), Paint()..color = const Color(0x33F26522));
      }
      for (var i = 0; i < points.length; i++) {
        final q = p(points[i]);
        final col = i == 0 ? const Color(0xFF16A34A) : const Color(0xFFF26522);
        c.drawCircle(q, 7, Paint()..color = Colors.white);
        c.drawCircle(q, 5, Paint()..color = col);
      }
      final cur = cursor;
      if (cur != null) {
        final q = p(cur);
        final cross = Paint()
          ..color = const Color(0xFF0F172A)
          ..strokeWidth = 1.4;
        c.drawLine(q - const Offset(10, 0), q + const Offset(10, 0), cross);
        c.drawLine(q - const Offset(0, 10), q + const Offset(0, 10), cross);
        c.drawCircle(q, 4, Paint()..color = const Color(0xFFF26522));
        final label = liveLabel;
        if (label != null && label.isNotEmpty) {
          final tp = TextPainter(
            text: TextSpan(text: label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
            textDirection: TextDirection.ltr,
          )..layout();
          final r = Rect.fromLTWH(q.dx + 14, q.dy - 30, tp.width + 14, tp.height + 8);
          c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(6)), Paint()..color = const Color(0xE60F172A));
          tp.paint(c, Offset(r.left + 7, r.top + 4));
        }
      }
    }

    // 6. Ruban à mesurer temporaire
    if (activeTape != null) {
      final t1 = p(activeTape!.p1), t2 = p(activeTape!.p2);
      final tapePaint = Paint()
        ..color = const Color(0xFF0284C7)
        ..strokeWidth = 2.0;
      c.drawLine(t1, t2, tapePaint);
      c.drawCircle(t1, 4.0, Paint()..color = const Color(0xFF0284C7));
      c.drawCircle(t2, 4.0, Paint()..color = const Color(0xFF0284C7));
      final distStr = '${activeTape!.distance.round()} mm';
      final tp = TextPainter(
        text: TextSpan(text: distStr, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      )..layout();
      final mid = (t1 + t2) / 2;
      final badgeRect = Rect.fromCenter(center: mid, width: tp.width + 12, height: tp.height + 6);
      c.drawRRect(RRect.fromRectAndRadius(badgeRect, const Radius.circular(6)), Paint()..color = const Color(0xFF0284C7));
      tp.paint(c, mid - Offset(tp.width / 2, tp.height / 2));
    }

    // 7. Lignes de cotation permanentes
    for (final dim in art.dimensions) {
      _dim(c, dim.p1, dim.p2, dim.text, const Color(0xFF0284C7));
    }

    // 8. Face survolée pour Pousser / Tirer
    if (hoveredFace != null && activeTool == CadTool.pushPull) {
      final cs = hoveredFace!.corners.map(p).toList();
      final facePath = Path()..addPolygon(cs, true);
      c.drawPath(facePath, Paint()..color = const Color(0x550284C7));
      c.drawPath(facePath, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.5..color = const Color(0xFF0284C7));
      final fc = p(hoveredFace!.center);
      final fNormEnd = p(hoveredFace!.center + hoveredFace!.normal * 80);
      c.drawLine(fc, fNormEnd, Paint()..color = const Color(0xFFEF4444)..strokeWidth = 3.0..strokeCap = StrokeCap.round);
      c.drawCircle(fNormEnd, 4.5, Paint()..color = const Color(0xFFEF4444));
    }

    // 9. Mode Usinage (Tourillons, Vis, Perçages système 32, Boîtiers charnières)
    if (isMachiningMode) {
      final summary = computeMachiningElements(panels);
      Paint stroke(Color c, double w) => Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round
        ..color = c;
      for (final el in summary.elements) {
        final pt = p(el.position);
        switch (el.kind) {
          case MachiningKind.dowel:
            c.drawCircle(pt, 4.5, Paint()..color = const Color(0xFFD97706));
            c.drawCircle(pt, 4.5, stroke(const Color(0xFF78350F), 1.2));
          case MachiningKind.screw:
            c.drawCircle(pt, 4.5, Paint()..color = const Color(0xFF94A3B8));
            c.drawCircle(pt, 4.5, stroke(const Color(0xFF334155), 1.2));
            final cross = Paint()
              ..color = const Color(0xFF1E293B)
              ..strokeWidth = 1.3;
            c.drawLine(pt - const Offset(2.8, 0), pt + const Offset(2.8, 0), cross);
            c.drawLine(pt - const Offset(0, 2.8), pt + const Offset(0, 2.8), cross);
          case MachiningKind.nail:
            c.drawCircle(pt, 1.6, Paint()..color = const Color(0xFF475569));
          case MachiningKind.shelfHole:
            c.drawCircle(pt, 2.2, Paint()..color = const Color(0xFF0284C7));
          case MachiningKind.shelfPin:
            c.drawCircle(pt, 3.6, Paint()..color = const Color(0xFF0369A1));
            c.drawCircle(pt, 3.6, stroke(Colors.white, 1));
          case MachiningKind.hingeCup:
            final r = (p(el.position + const V3(17.5, 0, 0)) - pt).distance.clamp(4.0, 30.0);
            c.drawCircle(pt, r, Paint()..color = const Color(0x55EF4444));
            c.drawCircle(pt, r, stroke(const Color(0xFFEF4444), 1.8));
          case MachiningKind.hingePlate:
            final rect = Rect.fromCenter(center: pt, width: 9, height: 14);
            c.drawRect(rect, Paint()..color = const Color(0xFF64748B));
            c.drawRect(rect, stroke(const Color(0xFF1E293B), 1));
          case MachiningKind.groove:
            c.drawLine(pt, p(el.end), stroke(const Color(0xFF334155), 3.2));
            c.drawLine(pt, p(el.end), stroke(const Color(0xFF94A3B8), 1.2));
          case MachiningKind.edge:
            c.drawLine(pt, p(el.end), stroke(el.diameter >= 2 ? const Color(0xFFF26522) : const Color(0xFFF59E0B), el.diameter >= 2 ? 3 : 2));
          case MachiningKind.slide:
            c.drawLine(pt, p(el.end), stroke(const Color(0xFF16A34A), 4));
            c.drawLine(pt, p(el.end), stroke(const Color(0xFFBBF7D0), 1.2));
          case MachiningKind.flapStay:
            c.drawLine(pt, p(el.end), stroke(const Color(0xFF7C3AED), 3));
          case MachiningKind.handle:
            c.drawLine(pt, p(el.end), stroke(isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B), 4));
          case MachiningKind.foot:
            final floor = p(V3(el.position.x, 0, el.position.z));
            c.drawLine(pt, floor, stroke(const Color(0xFF334155), 5));
            c.drawCircle(floor, 4, Paint()..color = const Color(0xFF0F172A));
        }
      }
    }

    // 10. Indicateur d'accrochage magnétique (Snap magnet)
    if (activeSnapTarget != null) {
      final sp = p(activeSnapTarget!.position);
      final col = activeSnapTarget!.isOrigin ? const Color(0xFF16A34A) : const Color(0xFF0284C7);
      c.drawCircle(sp, 9.0, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.5..color = col);
      c.drawCircle(sp, 3.5, Paint()..color = col);
      final tp = TextPainter(
        text: TextSpan(
          text: activeSnapTarget!.label,
          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final bgRect = Rect.fromLTWH(sp.dx + 12, sp.dy - 10, tp.width + 10, tp.height + 4);
      c.drawRRect(RRect.fromRectAndRadius(bgRect, const Radius.circular(4)), Paint()..color = col);
      tp.paint(c, Offset(sp.dx + 17, sp.dy - 8));
    }
  }

  void _dim(Canvas c, V3 a, V3 b, String text, Color col, {V3? anchorA, V3? anchorB}) {
    final pa = p(a), pb = p(b);
    final paint = Paint()
      ..color = col
      ..strokeWidth = 1.4;
    // Lignes de rappel (witness lines) vers les angles réels du meuble
    if (anchorA != null) {
      final pAnchor = p(anchorA);
      c.drawLine(pAnchor, pa, Paint()..color = col.withValues(alpha: 0.35)..strokeWidth = 1);
    }
    if (anchorB != null) {
      final pAnchor = p(anchorB);
      c.drawLine(pAnchor, pb, Paint()..color = col.withValues(alpha: 0.35)..strokeWidth = 1);
    }
    c.drawLine(pa, pb, paint);
    final dir = pb - pa;
    final n = dir.distance == 0 ? Offset.zero : Offset(-dir.dy, dir.dx) / dir.distance * 5;
    c.drawLine(pa - n, pa + n, paint);
    c.drawLine(pb - n, pb + n, paint);
    final tp = TextPainter(text: TextSpan(text: text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: col)), textDirection: TextDirection.ltr)
      ..layout();
    final at = Offset.lerp(pa, pb, 0.5)! - Offset(tp.width / 2, tp.height / 2);
    c.drawRRect(RRect.fromRectAndRadius((at & tp.size).inflate(3), const Radius.circular(4)), Paint()..color = Colors.white.withValues(alpha: 0.92));
    tp.paint(c, at);
  }

  @override
  bool shouldRepaint(_ScenePainter o) => true;
}

class _PresetPainter extends CustomPainter {
  final ArtPreset preset;
  _PresetPainter(this.preset);
  @override
  void paint(Canvas c, Size size) {
    final b = preset.build();
    var k = 0;
    final panels = b.panels(() => 'p${k++}');
    final cam = ArtCamera()..size = size;
    cam.fit(panels);
    _paintPanels(c, cam, panels, edge: 0.5);
  }

  @override
  bool shouldRepaint(_PresetPainter o) => o.preset != preset;
}
