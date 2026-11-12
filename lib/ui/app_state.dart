// État de l'application : étapes, vue, sélection, catalogue, zoom, annuler/rétablir.

import 'app_settings.dart';
import 'i18n.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../engine/engine.dart';
import 'finishes.dart';
import 'nest_service.dart';
import 'tech_drawings.dart';

enum PlanStep {
  space('Votre espace', 'Forme, dimensions, portes et fenêtres'),
  layout('Implantation', 'Placez les caissons'),
  style('Style', 'Façades, plan de travail, poignées'),
  summary('Récapitulatif', 'Liste des éléments et export');

  final String label;
  final String hint;
  const PlanStep(this.label, this.hint);
}

enum ViewMode { plan, front, view3d }

/// Rayons du catalogue (menu en colonnes) : titre de colonne → catégories du JSON.
enum Shelf {
  base('Éléments bas', ['base_cabinets', 'corner_base_cabinets']),
  wall('Éléments hauts', ['wall_cabinets', 'corner_wall_cabinets']),
  tall('Colonnes', ['tall_cabinets']),
  finish('Fileurs et finitions', ['finishing_and_accessories']);

  final String label;
  final List<String> categoryIds;
  const Shelf(this.label, this.categoryIds);
}

/// Panneau latéral d'ajout ouvert sur une catégorie (ou sur une recherche).
class CatalogBrowse {
  final Shelf shelf;
  final String? categoryId; // null = toute la colonne
  const CatalogBrowse(this.shelf, [this.categoryId]);
}

class AppState extends ChangeNotifier {
  final Catalog catalog;
  final MaterialsDb? db; // électroménager, plans de travail, panneaux, quincaillerie
  Project project;
  late LayoutEngine engine;

  PlanStep step = PlanStep.space;
  ViewMode view = ViewMode.plan;
  String wallId = 'A';
  String? selected; // caisson
  String? selectedOpening;
  String? selectedPoint; // point de réseau

  /// Ouverture animée en 3D : progression actuelle (0..1) et éléments à ouvrir.
  final Map<String, double> openness = {};
  final Set<String> openTargets = {};
  bool get animating => [...openness.keys, ...openTargets].any((u) => (openness[u] ?? 0) != (openTargets.contains(u) ? 1.0 : 0.0));
  bool isOpen(String uid) => openTargets.contains(uid);
  bool get anyOpen => openTargets.isNotEmpty;

  void toggleOpen(String uid) {
    if (!openTargets.remove(uid)) openTargets.add(uid);
    notifyListeners();
  }

  /// Ouvre (ou ferme) tous les éléments.
  void openAll(bool open) {
    openTargets.clear();
    if (open) openTargets.addAll(project.items.map((c) => c.uid));
    notifyListeners();
  }

  /// Fait avancer l'animation de [dt] secondes ; renvoie vrai tant qu'elle n'est pas finie.
  bool stepOpen(double dt) {
    const speed = 1 / 0.6; // 0,6 s pour ouvrir
    var moving = false;
    for (final u in {...openness.keys, ...openTargets}) {
      final target = openTargets.contains(u) ? 1.0 : 0.0;
      final cur = openness[u] ?? 0;
      if (cur == target) continue;
      final next = target > cur ? (cur + dt * speed).clamp(0.0, target) : (cur - dt * speed).clamp(target, 1.0);
      if (next == 0) {
        openness.remove(u);
      } else {
        openness[u] = next;
      }
      moving = moving || next != target;
    }
    notifyListeners();
    return moving;
  }
  CatalogBrowse? browse;
  String search = '';
  bool megaMenu = false;

  // ---- guides d'alignement affichés pendant un glissement
  /// Guides : sur un mur (position s, vue de face et plan) ou dans la pièce (droite x = … ou y = …).
  final List<SnapGuide> guides = [];

  /// Aimante [v] sur la cible la plus proche (à [tol] mm près) ; renvoie la valeur et la cible retenue.
  static (double, (double, String)?) _snapTo(double v, List<(double, String)> targets, {double tol = 40}) {
    (double, String)? best;
    for (final t in targets) {
      if ((t.$1 - v).abs() <= tol && (best == null || (t.$1 - v).abs() < (best.$1 - v).abs())) best = t;
    }
    return (best?.$1 ?? v, best);
  }

  /// Repères d'alignement le long d'un mur pour un élément de largeur [width] : centre du mur, bords et
  /// centres des caissons et des ouvertures du même mur (valeurs = position du bord gauche de l'élément).
  List<(double, String)> _wallTargets(String wallId, double width, {String? skip}) {
    final len = wallId == 'I' ? (project.room.island?.length ?? 0) : project.room.wall(wallId).length;
    final out = <(double, String)>[((len - width) / 2, 'centré sur le mur')];
    for (final c in project.items.where((c) => c.wallId == wallId && c.uid != skip)) {
      final n = engine.modelOf(c).name.toLowerCase();
      out
        ..add((c.s + c.width / 2 - width / 2, 'centré sur $n'))
        ..add((c.s, 'aligné à gauche sur $n'))
        ..add((c.right - width, 'aligné à droite sur $n'));
    }
    for (final o in project.openings.where((o) => o.wallId == wallId && o.uid != skip)) {
      final n = openingName(o).toLowerCase();
      out
        ..add((o.s + o.width / 2 - width / 2, 'centré sur $n'))
        ..add((o.s, 'aligné à gauche sur $n'))
        ..add((o.right - width, 'aligné à droite sur $n'));
    }
    return out;
  }

  // ---- objets de la pièce (sanitaires, décoration)
  List<CatalogObject> objectCatalog = const []; // catalogue libre (CC0), chargé au démarrage (léger : liste seule)
  bool objectsPanel = false; // panneau « Objets » ouvert
  String? selectedObject;
  RoomObject? get selectedObjectObj => selectedObject == null ? null : project.objects.where((o) => o.uid == selectedObject).firstOrNull;

  void openObjects(bool open) {
    objectsPanel = open;
    if (open) {
      browse = null;
      megaMenu = false;
    }
    notifyListeners();
  }

  void selectObject(String? uid) {
    selectedObject = uid;
    if (uid != null) {
      selected = null;
      selectedOpening = null;
      selectedPoint = null;
      browse = null;
      megaMenu = false;
      objectsPanel = false;
    }
    notifyListeners();
  }

  /// Pose un objet au milieu de la pièce (plaqué au mur le plus proche s'il se pose contre un mur).
  String addObject(String ref) {
    final fx = ref.startsWith('fixture:') ? fixtureById(ref.substring(8)) : null;
    final cat = fx == null ? objectCatalog.where((o) => o.id == ref).firstOrNull : null;
    final (w, d) = fx != null ? fx.sizes.first : (cat?.w ?? 600, cat?.d ?? 600);
    final h = fx?.h ?? cat?.h ?? 600;
    final r = project.room;
    // suspension : accrochée au plafond
    final z = cat?.ceiling ?? false ? math.max(0, r.height - h).toDouble() : (fx?.z ?? 0).toDouble();
    final o = RoomObject(uid: project.newUid(), ref: ref, x: r.width / 2, y: r.depth / 2, z: z, w: w, h: h, d: d);
    edit(() {
      if (fx != null || (cat?.wall ?? false)) {
        // contre le mur affiché (vue de face) ou le mur A
        final wall = view == ViewMode.front ? wallId : 'A';
        o.rot = r.wall(wall).rot;
        switch (wall) {
          case 'B':
            o.x = r.width;
          case 'D':
            o.y = r.depth;
          case 'C':
            o.x = 0;
          default:
            o.y = 0;
        }
        snapToWall(r, o);
      }
      project.objects.add(o);
    });
    selectedObject = o.uid;
    selected = null;
    objectsPanel = false; // posé et sélectionné : la fiche remplace le panneau
    notifyListeners();
    return trp('{0} posé', [tr(fx?.name ?? cat?.name ?? 'Objet')]);
  }

  void dragObjectTo(String uid, double x, double y) {
    final o = project.objects.where((x) => x.uid == uid).firstOrNull;
    if (o == null) return;
    final r = project.room;
    final (x0, y0, x1, y1) = o.footprint;
    final hw = (x1 - x0) / 2, hd = (y1 - y0) / 2;
    // guides : centre de la pièce, centres et bords des autres objets
    guides.clear();
    final tx = <(double, String)>[(r.width / 2, 'centre de la pièce')], ty = <(double, String)>[(r.depth / 2, 'centre de la pièce')];
    for (final q in project.objects.where((q) => q.uid != uid)) {
      final (a0, b0, a1, b1) = q.footprint;
      final n = objectName(q).toLowerCase();
      tx.addAll([(q.x, 'aligné sur $n'), (a0 - hw, 'contre $n'), (a1 + hw, 'contre $n')]);
      ty.addAll([(q.y, 'aligné sur $n'), (b0 - hd, 'contre $n'), (b1 + hd, 'contre $n')]);
    }
    final (sx, gx) = _snapTo(x, tx);
    final (sy, gy) = _snapTo(y, ty);
    if (gx != null) guides.add(SnapGuide.plan(true, sx, gx.$2));
    if (gy != null) guides.add(SnapGuide.plan(false, sy, gy.$2));
    o.x = (gx != null ? sx : (x / 10).round() * 10.0).clamp(hw, math.max(hw, r.width - hw));
    o.y = (gy != null ? sy : (y / 10).round() * 10.0).clamp(hd, math.max(hd, r.depth - hd));
    // à moins de 150 mm d'un mur : plaqué contre lui (dos au mur)
    final (_, _, dist) = nearestWallFor(r, o.x, o.y);
    final f = o.fixture;
    final wallish = f != null || (objectCatalog.where((c) => c.id == o.ref).firstOrNull?.wall ?? false);
    if (wallish && dist - math.min(hw, hd) < 150) snapToWall(r, o);
    notifyListeners();
  }

  void editObject(String uid, void Function(RoomObject o) change) {
    final o = project.objects.where((x) => x.uid == uid).firstOrNull;
    if (o == null) return;
    edit(() => change(o));
  }

  void rotateObject(String uid, int delta) => editObject(uid, (o) => o.rot = (o.rot + delta) % 360);

  void deleteObject(String uid) {
    edit(() => project.objects.removeWhere((o) => o.uid == uid));
    if (selectedObject == uid) selectedObject = null;
    notifyListeners();
  }

  void duplicateObject(String uid) {
    final o = project.objects.where((x) => x.uid == uid).firstOrNull;
    if (o == null) return;
    final c = o.copy(uid: project.newUid());
    final (x0, _, x1, _) = o.footprint;
    c.x = math.min(project.room.width - (x1 - x0) / 2, o.x + (x1 - x0) + 50);
    edit(() => project.objects.add(c));
    selectedObject = c.uid;
    notifyListeners();
  }

  /// Zoom / déplacement de la vue (1 = tout visible).
  double zoom = 1;
  double panX = 0, panY = 0;

  /// Rotation de la vue 3D (radians).
  double yaw = -0.6;

  final List<String> _undo = [];
  final List<String> _redo = [];

  SupplierTariff? supplier; // tarif d'un fournisseur de caissons usinés (comparaison)

  /// Prix de la cuisine chez le fournisseur ; façades brillantes si la finition des bas l'est.
  SupplierQuote? get supplierEstimate => supplier == null ? null : _cached('supplier', () => supplierQuote(engine, supplier!, gloss: frontsGloss));

  AppState(this.catalog, {Project? project, this.db, this.supplier}) : project = project ?? Project() {
    installCutHooks();
    engine = LayoutEngine(catalog, this.project);
  }

  // ---- lecture

  List<CabinetCategory> categoriesOf(Shelf s) => [
        for (final c in catalog.categories)
          if (s.categoryIds.contains(c.id)) c,
      ];

  List<CabinetModel> browseModels() {
    final q = search.trim().toLowerCase();
    if (q.isNotEmpty) {
      return catalog.models.where((m) => m.name.toLowerCase().contains(q) || m.categoryName.toLowerCase().contains(q)).toList();
    }
    final b = browse;
    if (b == null) return const [];
    return [
      for (final c in categoriesOf(b.shelf))
        if (b.categoryId == null || b.categoryId == c.id) ...c.items,
    ];
  }

  PlacedCabinet? get selectedItem => selected == null ? null : project.byUid(selected!);
  CabinetModel? get selectedModel => selectedItem == null ? null : engine.modelOf(selectedItem!);
  Opening? get selectedOpeningObj => selectedOpening == null ? null : project.openingByUid(selectedOpening!);
  NetPoint? get selectedPointObj => selectedPoint == null ? null : project.pointByUid(selectedPoint!);
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  // ---- calculs mis en cache : refaits seulement quand le projet change (pas à chaque sélection ou survol)
  /// Empreinte du projet (sans les images de textures importées, trop lourdes).
  /// Calculée une fois par rafraîchissement : chaque modification passe par [notifyListeners] ou [edit],
  /// qui l'effacent ; elle est aussi effacée à la fin de la tâche en cours.
  String get fingerprint => _fp ??= _fingerprint();
  String? _fp;
  var _fpClear = false;

  void _forgetFingerprint() => _fp = null;

  @override
  void notifyListeners() {
    _fp = null;
    super.notifyListeners();
  }

  String _fingerprint() {
    if (!_fpClear) {
      _fpClear = true;
      scheduleMicrotask(() {
        _fp = null;
        _fpClear = false;
      });
    }
    final st = project.style.toJson()..remove('textures');
    return jsonEncode([
      AppSettings.instance.lang.code, // messages des contrôles dans la langue choisie
      project.universe,
      project.room.toJson(),
      st,
      project.cut.toJson(),
      project.specs.toJson(),
      [for (final c in project.items) c.toJson()],
      [for (final o in project.objects) o.toJson()],
      [for (final o in project.openings) o.toJson()],
      project.networks,
      [for (final x in project.points) x.toJson()],
    ]);
  }

  final Map<String, Object?> _memo = {};
  String? _memoKey;
  T _cached<T>(String name, T Function() compute) {
    final fp = fingerprint;
    if (fp != _memoKey) {
      _memo.clear();
      _memoKey = fp;
    }
    return _memo.putIfAbsent(name, compute) as T;
  }

  List<Issue> get issues => List.of(_cached('issues', () => [
        ...engine.validate(),
        if (db != null) ...applianceChecks(engine, db!),
        if (project.networks) ...networkChecks(engine),
        ...openingChecks(engine),
        ...accessChecks(engine),
        ...objectChecks(engine),
        ...sizeChecks(engine),
        ...designChecks(engine),
        ...waterChecks(engine),
      ]));

  /// Débit optimisé de la cuisine (même calcul que le plan de découpe).
  CutPlan get cutPlan => _cached('cutPlan', _computeCutPlan);

  /// Débit en arrière-plan (Web Worker dans le navigateur, Isolate ailleurs) : activé par l'application,
  /// éteint dans les tests (calcul immédiat, résultats identiques).
  static bool backgroundNest = false;

  /// En dessous de ce nombre de pièces le débit est assez rapide pour être calculé tout de suite.
  static int backgroundFrom = 40;

  /// Optimisation du débit en cours : le plan affiché est le précédent.
  bool get cutPending => _wantKey != null && _wantKey != _cutKey;

  CutPlan _computeCutPlan() {
    final e = engine;
    final prof = PerformanceProfiler.instance;
    final parts = prof.measure('debit_liste', () => cutList(e, project.cut, repereNumbers(e)));
    // l'optimisation est coûteuse : recalculée seulement si les pièces ou les réglages changent
    final key = nestKey(parts, project.cut);
    if (key == _cutKey && _cutPlan != null) return _cutPlan!;
    final hit = nestPeek(key);
    if (hit != null) return _useCut(key, hit);
    final n = parts.fold<int>(0, (a, p) => a + p.qty);
    // pendant un glisser : le débit attend la fin du geste (les pièces ne changent que par les repères)
    if (_dragBefore != null && _cutPlan != null) {
      _wantKey = key;
      return _cutPlan!;
    }
    if (!backgroundNest || n < backgroundFrom) {
      final plan = prof.measure('nesting', () => nest(parts, project.cut), info: {'pieces': n, 'mode': 'direct'});
      nestRemember(key, plan);
      return _useCut(key, plan);
    }
    _launchCut(key, parts, CutSettings.fromJson(project.cut.toJson()), n);
    return _cutPlan ?? CutPlan(project.cut, parts, const [], const []);
  }

  CutPlan _useCut(String key, CutPlan plan) {
    _cutPlan = plan;
    _cutKey = key;
    if (_wantKey == key) _wantKey = null;
    return plan;
  }

  CutPlan? _cutPlan;
  String? _cutKey;
  String? _wantKey; // débit demandé, pas encore prêt
  Timer? _cutTimer;

  /// Lance l'optimisation en arrière-plan, 150 ms après la dernière modification (saisie, curseur...).
  void _launchCut(String key, List<CutPart> parts, CutSettings cs, int n) {
    if (_wantKey == key && _cutTimer != null) return;
    _wantKey = key;
    _cutTimer?.cancel();
    _cutTimer = Timer(const Duration(milliseconds: 150), () async {
      _cutTimer = null;
      if (_wantKey != key) return;
      final plan = await _nestAway(key, parts, cs, n);
      if (_wantKey != key) return; // le projet a encore changé : un autre calcul suit
      _useCut(key, plan);
      _memo.remove('cutPlan');
      _memo.remove('estimate');
      _memo.remove('supplier');
      notifyListeners();
    });
  }

  final Map<String, Future<CutPlan>> _nestJobs = {}; // calculs en cours, par clé

  Future<CutPlan> _nestAway(String key, List<CutPart> parts, CutSettings cs, int n) {
    final hit = nestPeek(key);
    if (hit != null) return Future.value(hit);
    // même débit déjà en cours de calcul : on attend celui-là au lieu d'en relancer un
    return _nestJobs[key] ??= _nestRun(key, parts, cs, n).whenComplete(() {
      _nestJobs.remove(key); // bloc sans valeur de retour : renvoyer le calcul lui-même le ferait s'attendre sans fin
    });
  }

  Future<CutPlan> _nestRun(String key, List<CutPart> parts, CutSettings cs, int n) async {
    CutPlan plan;
    try {
      plan = await PerformanceProfiler.instance
          .measureAsync('nesting', () => nestInBackground(parts, cs), info: {'pieces': n, 'mode': 'arriere_plan'});
    } catch (_) {
      plan = nest(parts, cs);
    }
    nestRemember(key, plan);
    return plan;
  }

  /// Débit à jour, en attendant la fin du calcul s'il est en cours (exports PDF, SketchCut).
  Future<CutPlan> cutPlanReady() async {
    final plan = cutPlan;
    final e = engine;
    final parts = cutList(e, project.cut, repereNumbers(e));
    final key = nestKey(parts, project.cut);
    if (key == _cutKey) return plan;
    _cutTimer?.cancel();
    _cutTimer = null;
    _wantKey = key;
    final ready = await _nestAway(key, parts, CutSettings.fromJson(project.cut.toJson()), parts.fold<int>(0, (a, p) => a + p.qty));
    if (_wantKey == key) {
      _useCut(key, ready);
      _memo.remove('cutPlan');
      _memo.remove('estimate');
      notifyListeners();
    }
    return ready;
  }

  /// Estimation : panneaux, découpe, chants, plan de travail, quincaillerie, électroménager.
  bool get frontsGloss => frontFinish(project.style, project.style.frontLower ?? project.style.front).gloss;
  List<SupplyLine> get estimateLines =>
      db == null ? const [] : _cached('estimate', () => quoteLines(engine, db!, project.specs, cutPlan, bom, supplier, gloss: frontsGloss));
  void setGamme(String g) => edit(() => project.specs.gamme = g);
  Bom get bom => _cached('bom', () => buildBom(engine));

  // ---- historique

  // les textures importées (images) restent hors de l'historique : trop lourdes
  String _snap() {
    final j = project.toJson();
    (j['style'] as Map).remove('textures');
    return jsonEncode(j);
  }

  void _load(String snap) {
    final tex = [...project.style.textures];
    // un numéro de plan déjà attribué (PDF émis) ne se perd pas en annulant : sinon le projet en reprendrait un autre
    final numbers = {...project.client.numbers};
    project = Project.fromJson(jsonDecode(snap) as Map<String, dynamic>);
    numbers.forEach((k, v) => project.client.numbers.putIfAbsent(k, () => v));
    project.style.textures
      ..clear()
      ..addAll(tex);
    engine = LayoutEngine(catalog, project);
    if (selected != null && project.byUid(selected!) == null) selected = null;
    if (selectedOpening != null && project.openingByUid(selectedOpening!) == null) selectedOpening = null;
  }

  /// Modification avec point d'annulation. Renvoie le message d'erreur éventuel.
  String? edit(void Function() action) {
    final before = _snap();
    _forgetFingerprint();
    try {
      action();
      _forgetFingerprint();
      if (project.networks) applyNetworks(engine);
    } on PlacementException catch (e) {
      _load(before);
      notifyListeners();
      return e.message;
    }
    if (_snap() != before) {
      _undo.add(before);
      if (_undo.length > 100) _undo.removeAt(0);
      _redo.clear();
    }
    notifyListeners();
    return null;
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_snap());
    _load(_undo.removeLast());
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_snap());
    _load(_redo.removeLast());
    notifyListeners();
  }

  // ---- glisser : un seul point d'annulation pour tout le geste

  String? _dragBefore;
  void beginDrag() => _dragBefore = _snap();

  MoveResult dragTo(String uid, {String? wallId, double? s, double? z}) {
    final c = project.byUid(uid);
    guides.clear();
    if (c != null && s != null) {
      final wid = wallId ?? c.wallId;
      final (ss, g) = _snapTo(s, [
        for (final t in _wallTargets(wid, c.width.toDouble(), skip: uid))
          if (!t.$2.contains('gauche') && !t.$2.contains('droite')) t, // caissons : centres seulement (les bords se calent déjà)
      ]);
      if (g != null) {
        s = ss;
        guides.add(SnapGuide.wall(wid, ss + c.width / 2, g.$2));
      }
    }
    // glisser sur le voisin : échange des places
    if (c != null && s != null && (wallId == null || wallId == c.wallId)) {
      final sw = engine.trySwap(uid, s);
      if (sw != null) {
        notifyListeners();
        return sw;
      }
    }
    final r = engine.move(uid, wallId: wallId, s: s, z: z);
    notifyListeners();
    return r;
  }

  String? addIsland() {
    final err = edit(() => engine.addIsland());
    if (err == null) wallId = 'I';
    notifyListeners();
    return err;
  }

  /// Dimensions d'une pièce type (et, en cuisine, la disposition des meubles qui va avec).
  String applyRoomPreset(RoomPreset pr) {
    edit(() {
      project.room.clearOutline();
      project.room.resize(width: pr.width, depth: pr.depth);
      final shape = project.universe == 'cuisine' ? pr.kitchenShape : null;
      if (shape != null) engine.applyShape(shape);
    });
    notifyListeners();
    return trp('{0} : {1} x {2} mm', [tr(pr.name), pr.width.round(), pr.depth.round()]);
  }

  /// Marque de quincaillerie du devis.
  void setHardwareBrand(String brand) => edit(() => project.specs.hardwareBrand = brand);

  /// Replace l'îlot au meilleur endroit libre (passages de 1 m).
  String? replaceIsland() {
    final isl = project.room.island;
    if (isl == null) return tr('Pas d\'îlot');
    final spot = engine.bestIslandSpot();
    if (spot == null) return tr('Aucun emplacement avec 1 m de passage tout autour : réduisez l\'îlot ou retirez-le');
    return edit(() => engine.setIsland(x0: spot.x0, y0: spot.y0, length: math.min(isl.length, spot.length)));
  }

  String? setIsland({double? x0, double? y0, double? length, double? overhang}) =>
      edit(() => engine.setIsland(x0: x0, y0: y0, length: length, overhang: overhang));

  void removeIsland() {
    edit(engine.removeIsland);
    if (wallId == 'I') wallId = 'A';
    notifyListeners();
  }

  /// Déplacement de l'îlot pendant un glisser (point d'annulation : beginDrag / endDrag).
  String? moveIsland(double x0, double y0) {
    try {
      engine.setIsland(x0: x0, y0: y0);
    } on PlacementException catch (e) {
      return e.message;
    }
    notifyListeners();
    return null;
  }

  /// Déplacement d'un mur pendant un glisser (sans point d'annulation propre : voir beginDrag).
  String? moveWall(String wallId, double delta) {
    try {
      engine.moveWall(wallId, delta);
    } on PlacementException catch (e) {
      return e.message;
    }
    notifyListeners();
    return null;
  }

  /// Change le modèle d'une ouverture ; ses cotes prennent les valeurs standard du modèle si elles n'en font pas partie.
  void setOpeningModel(String uid, String model) {
    final o = project.openingByUid(uid);
    final m = OpeningModel.byId[model];
    if (o == null || m == null) return;
    edit(() {
      o.model = model;
      if (m.widths.isNotEmpty && !m.widths.contains(o.width.round())) o.width = m.defaultWidth.toDouble();
      if (m.heights.isNotEmpty && !m.heights.contains(o.height.round())) o.height = m.defaultHeight.toDouble();
      if (!m.door && o.z == 1050 && m.defaultSill != 1050) o.z = m.defaultSill.toDouble();
      engine.moveOpening(uid);
    });
  }

  void setOpeningHinge(String uid, String hinge) {
    final o = project.openingByUid(uid);
    if (o != null) edit(() => o.hinge = hinge);
  }

  /// Glisse une ouverture : elle ne se pose jamais sur un espace occupé (elle s'arrête au bord de l'obstacle).
  void dragOpeningTo(String uid, {String? wallId, double? s}) {
    final o = project.openingByUid(uid);
    if (o == null) return;
    final wid = wallId ?? o.wallId;
    guides.clear();
    final (snapped, g) = _snapTo(s ?? o.s, _wallTargets(wid, o.width, skip: uid));
    final want = snapped;
    if (g != null) guides.add(SnapGuide.wall(wid, g.$2.contains('gauche') ? snapped : (g.$2.contains('droite') ? snapped + o.width : snapped + o.width / 2), g.$2));
    final occ = engine.occupiedOnWall(wid, o.z, o.z + o.height, skip: uid);
    final len = project.room.wall(wid).length;
    final target = want.clamp(0.0, math.max(0.0, len - o.width)).toDouble();
    final blocked = occ.any((r) => target < r.$2 - 0.5 && target + o.width > r.$1 + 0.5);
    if (blocked) {
      // place libre la plus proche du doigt sur ce mur, sinon on ne bouge pas
      final spot = engine.freeOpeningSpot(wid, o.width, o.z, o.z + o.height, want: target, skip: uid);
      if (spot == null || (spot - target).abs() > o.width) return;
      engine.moveOpening(uid, wallId: wid, s: spot);
    } else {
      engine.moveOpening(uid, wallId: wid, s: target);
    }
    notifyListeners();
  }

  void endDrag() {
    guides.clear();
    if (project.networks) applyNetworks(engine);
    final before = _dragBefore;
    _dragBefore = null;
    _memo.remove('cutPlan'); // le débit mis en attente pendant le geste est recalculé
    _memo.remove('estimate');
    if (before != null && before != _snap()) {
      _undo.add(before);
      _redo.clear();
    }
    notifyListeners();
  }

  // ---- navigation

  void goTo(PlanStep s) {
    step = s;
    megaMenu = false;
    if (s != PlanStep.layout) browse = null;
    if (s == PlanStep.style || s == PlanStep.summary) {
      view = ViewMode.view3d;
      resetZoom(notify: false);
    }
    if (s == PlanStep.space) view = ViewMode.plan;
    selectedOpening = s == PlanStep.space ? selectedOpening : null;
    notifyListeners();
  }

  /// La pièce a-t-elle besoin d'eau (cuisine, salle de bain) ?
  bool get needsWater => project.universe == 'cuisine' || project.universe == 'bain';

  /// Arrivées d'eau et évacuations existantes placées dans la pièce.
  int existingCount(bool drain) => project.points
      .where((x) => x.use == existingUse && (drain ? x.kind == NetKind.drain : (x.kind == NetKind.waterCold || x.kind == NetKind.waterHot)))
      .length;

  /// Ce qui manque pour quitter l'étape « Votre espace » (null : rien).
  String? get spaceMissing => needsWater && existingCount(false) == 0
      ? 'Placez au moins une arrivée d’eau existante (bouton « Point d’eau ») avant de passer à l’implantation.'
      : null;

  /// Étape suivante ; renvoie le message qui l'empêche, le cas échéant.
  String? next() {
    if (step == PlanStep.space && spaceMissing != null) return spaceMissing;
    if (step.index < PlanStep.values.length - 1) goTo(PlanStep.values[step.index + 1]);
    return null;
  }

  void setView(ViewMode v) {
    view = v;
    resetZoom(notify: false);
    notifyListeners();
  }

  void setWall(String id) {
    wallId = id;
    notifyListeners();
  }

  void select(String? uid) {
    selected = uid;
    if (uid != null) selectedObject = null;
    if (uid != null) {
      selectedOpening = null;
      selectedPoint = null;
      browse = null;
      megaMenu = false;
    }
    final it = selectedItem;
    if (it != null && view == ViewMode.front && it.wallId != wallId) wallId = it.wallId;
    notifyListeners();
  }

  void selectOpening(String? uid) {
    selectedOpening = uid;
    if (uid != null) {
      selected = null;
      selectedPoint = null;
      selectedObject = null;
    }
    notifyListeners();
  }

  // ---- réseaux (électricité, eau, évacuations, gaz)

  void selectPoint(String? uid) {
    selectedPoint = uid;
    if (uid != null) {
      selected = null;
      selectedOpening = null;
      selectedObject = null;
      final x = selectedPointObj;
      if (x != null && !x.onCeiling && view == ViewMode.front && x.wallId != wallId) wallId = x.wallId;
    }
    notifyListeners();
  }

  /// Affiche les réseaux et les tient à jour (les points automatiques suivent l'implantation).
  void setNetworks(bool on) {
    edit(() {
      project.networks = on;
      if (on) applyNetworks(engine);
    });
    if (!on) selectedPoint = null;
    notifyListeners();
  }

  /// Repart des points automatiques : les points déplacés ou ajoutés à la main sont remplacés aussi si [all].
  void regenerateNetworks({bool all = false}) => edit(() {
        if (all) project.points.clear();
        project.networks = true;
        applyNetworks(engine);
      });

  void setHobEnergy(String energy) => edit(() => project.specs.hobEnergy = energy);

  /// Ajoute un point à la main sur le mur affiché (au milieu, à la hauteur usuelle du type).
  void addPoint(NetKind kind) {
    final std = project.standards;
    final w = wallId == 'I' && project.room.island != null ? 'I' : (project.room.isWallEnabled(wallId) ? wallId : 'A');
    final len = w == 'I' ? project.room.island!.length : project.room.wall(w).length;
    final z = switch (kind) {
      // prises : au-dessus du plan en cuisine, à 300 mm du sol dans les autres pièces
      NetKind.socketDouble || NetKind.socket => engine.kitchen ? std.worktopTop + NetHeights.aboveWorktop : 300,
      NetKind.switch_ || NetKind.switchDouble || NetKind.usb => NetHeights.switchZ,
      NetKind.rj45 || NetKind.tvSat => 300,
      NetKind.waterCold || NetKind.waterHot => NetHeights.waterSupply,
      NetKind.drain => NetHeights.drain,
      NetKind.drainWc => 230,
      NetKind.cable => 200,
      NetKind.gas => NetHeights.gasTap,
      NetKind.out32 => NetHeights.hob32,
      NetKind.light => project.room.height - 20,
      NetKind.duct => project.room.height - 250,
      _ => NetHeights.machine,
    };
    final uid = project.newUid('n');
    edit(() {
      project.networks = true;
      project.points.add(NetPoint(uid: uid, kind: kind, wallId: w, s: len / 2, z: z.toDouble(), auto: false));
    });
    selectPoint(uid);
  }

  /// Déplace un point (il devient « manuel » : la régénération ne le touche plus).
  void dragPointTo(String uid, {double? s, double? z}) {
    final x = project.pointByUid(uid);
    if (x == null) return;
    final len = x.onCeiling ? project.room.width : (x.wallId == 'I' ? (project.room.island?.length ?? 0) : project.room.wall(x.wallId).length);
    final maxZ = x.onCeiling ? project.room.depth : project.room.height;
    if (s != null) x.s = ((s / 10).round() * 10.0).clamp(0.0, len);
    if (z != null) x.z = ((z / 10).round() * 10.0).clamp(0.0, maxZ);
    x.auto = false;
    notifyListeners();
  }

  void updatePoint(String uid, {NetKind? kind, String? wall, double? s, double? z}) => edit(() {
        final x = project.pointByUid(uid);
        if (x == null) return;
        if (kind != null) x.kind = kind;
        if (wall != null) x.wallId = wall;
        if (s != null) x.s = s;
        if (z != null) x.z = z;
        x.auto = false;
      });

  void toggleMegaMenu([bool? open]) {
    megaMenu = open ?? !megaMenu;
    if (megaMenu) {
      browse = null; // un seul menu ouvert à la fois
      objectsPanel = false;
    }
    notifyListeners();
  }

  void openBrowse(CatalogBrowse? b) {
    browse = b;
    megaMenu = false;
    if (b != null) objectsPanel = false;
    search = '';
    notifyListeners();
  }

  void setSearch(String q) {
    search = q;
    if (q.isNotEmpty && browse == null) browse = const CatalogBrowse(Shelf.base);
    notifyListeners();
  }

  void setZoom(double z, {double? px, double? py}) {
    zoom = z.clamp(0.4, 6.0);
    if (px != null) panX = px;
    if (py != null) panY = py;
    notifyListeners();
  }

  void pan(double dx, double dy) {
    panX += dx;
    panY += dy;
    notifyListeners();
  }

  void resetZoom({bool notify = true}) {
    zoom = 1;
    panX = 0;
    panY = 0;
    if (notify) notifyListeners();
  }

  void rotate3d(double d) {
    yaw += d;
    notifyListeners();
  }

  // ---- actions

  String? addModel(String modelId, {String? wall, double? s, double? z}) {
    PlacedCabinet? added;
    final err = edit(() => added = engine.add(modelId, wall ?? wallId, s: s, z: z));
    if (added != null) {
      selected = added!.uid;
      selectedOpening = null;
      notifyListeners();
    }
    return err;
  }

  /// Pose une porte ou une fenêtre sur un espace libre du mur affiché (sinon d'un autre mur), jamais sur un
  /// caisson, un objet ou une autre ouverture. Renvoie le message d'erreur éventuel.
  String? addOpening(String type, {String? wall, String? model}) {
    final mdl = model == null ? null : OpeningModel.byId[model];
    final door = type == 'door';
    final width = (mdl?.defaultWidth ?? (door ? 830 : 1000)).toDouble();
    final z0 = (mdl?.defaultSill ?? (door ? 0 : 1050)).toDouble();
    final z1 = z0 + (mdl?.defaultHeight ?? (door ? 2040 : 1150));
    final first = wall ?? (wallId == 'I' ? 'A' : wallId);
    final order = [first, ...project.room.order.where((w) => w != first)];
    for (final w in order) {
      final s = engine.freeOpeningSpot(w, width, z0, z1);
      if (s == null) continue;
      Opening? o;
      final err = edit(() => o = engine.addOpening(type, w, s: s + width / 2, model: model));
      if (o != null) {
        selectOpening(o!.uid);
        if (w != first) return trp('{0} posée sur {1} : {2} est occupé', [door ? tr('Porte') : tr('Fenêtre'), tr(Room.wallNames[w] ?? w).toLowerCase(), tr(Room.wallNames[first] ?? first).toLowerCase()]);
      }
      return err;
    }
    return trp('Aucun espace libre de {0} mm sur les murs : libérez de la place d’abord', [width.round()]);
  }

  String? nudge(double ds, double dz) {
    final o = selectedOpeningObj;
    if (o != null) {
      edit(() => engine.moveOpening(o.uid, s: o.s + ds));
      return null;
    }
    final it = selectedItem;
    if (it == null) return null;
    String? reason;
    edit(() {
      final r = engine.move(it.uid, s: it.s + ds, z: dz == 0 ? null : it.z + dz);
      if (!r.moved) reason = r.reason;
    });
    return reason;
  }

  /// Applique la correction proposée pour un problème ; renvoie le message à afficher.
  String applyFix(Issue i) {
    final f = fixFor(engine, i, db: db);
    if (f.apply == null) return f.hint;
    var ok = false;
    final err = edit(() => ok = f.apply!());
    return err ?? (ok ? trp('Corrigé : {0}', [f.label ?? '']) : trp('Correction impossible : {0}', [f.hint]));
  }

  /// Applique toutes les corrections automatiques possibles (une passe).
  int fixAll() {
    var n = 0;
    edit(() {
      for (final i in [...issues]) {
        if (i.severity == Severity.info) continue;
        final f = fixFor(engine, i, db: db);
        if (f.apply == null) continue;
        try {
          if (f.apply!()) n++;
        } on PlacementException {
          // correction impossible ici : on passe à la suivante
        }
      }
    });
    return n;
  }

  /// Ajoute l'arrivée d'eau ou l'évacuation existante de la pièce (sur le mur affiché).
  void addExistingWater(NetKind kind) {
    addPoint(kind);
    final x = selectedPointObj;
    if (x == null) return;
    edit(() {
      x
        ..use = existingUse
        ..z = kind == NetKind.drain ? 400 : 500;
    });
  }

  /// Duplique l'élément sélectionné (la copie devient la sélection).
  String? duplicateSelected() {
    final uid = selected;
    if (uid == null) return tr('Sélectionnez un élément à dupliquer');
    String? newUid;
    final err = edit(() => newUid = engine.duplicate(uid).uid);
    if (err != null) return err;
    select(newUid);
    return null;
  }

  void deleteSelected() {
    final uid = selected, ou = selectedOpening, pu = selectedPoint;
    if (pu != null) {
      edit(() {
        final x = project.pointByUid(pu);
        if (x == null) return;
        if (x.auto || x.use != NetUse.general || x.uid.startsWith('na')) {
          // point automatique : on le masque pour qu'il ne revienne pas à la mise à jour
          x
            ..auto = false
            ..hidden = true;
        } else if (!x.hidden) {
          project.points.remove(x);
        }
      });
      selectedPoint = null;
    }
    if (uid != null) edit(() => engine.remove(uid));
    if (ou != null) edit(() => engine.removeOpening(ou));
    selected = null;
    selectedOpening = null;
    notifyListeners();
  }

  String? autoFill(Band band) {
    var n = 0;
    final err = edit(() {
      n = engine.autoFillWall(wallId, band);
      improveHinges(engine);
    });
    return err ?? (n == 0 ? tr('Aucun espace libre sur ce mur') : trp('{0} élément(s) ajouté(s) sur {1}', [n, Room.wallNames[wallId]?.toLowerCase()]));
  }

  /// Cuisine complète : trio de travail et électroménager, puis tous les murs équipés et l'îlot.
  String? autoKitchen() {
    var n = 0;
    final err = edit(() {
      final runs = project.room.runIds.where(project.room.isWallEnabled).toList();
      for (final id in runs) {
        n += engine.autoFillWall(id, Band.low);
      }
      for (final id in runs.where((id) => id != 'I')) {
        n += engine.autoFillWall(id, Band.high);
      }
      improveHinges(engine);
    });
    if (err != null) return err;
    final legs = engine.triangleLegs();
    final tri = legs == null ? '' : ' · triangle ${(legs.$1 + legs.$2 + legs.$3).round()} mm';
    return n == 0 ? tr('Cuisine déjà complète') : trp('{0} élément(s) posé(s){1}', [n, tri]);
  }

  /// Applique une proposition d'implantation (remplace les éléments posés).
  String? applyLayoutProposal(LayoutProposal pr, {bool withStyle = false}) {
    final err = edit(() {
      applyProposal(engine, pr);
      if (withStyle) {
        // modèle de la collection : son style complet (façades, plan, poignées, sol, murs, crédence)
        final src = pr.project.style, dst = project.style;
        dst
          ..front = src.front
          ..frontUpper = src.frontUpper
          ..frontLower = src.frontLower
          ..worktop = src.worktop
          ..handle = src.handle
          ..handleId = src.handleId
          ..handleFinish = src.handleFinish
          ..handleSize = src.handleSize
          ..floor = src.floor
          ..wall = src.wall
          ..splash = src.splash;
        for (final c in project.items) {
          c.front = null;
        }
      }
    });
    if (err == null && !project.room.isWallEnabled(wallId)) wallId = project.room.order.firstWhere(project.room.isWallEnabled, orElse: () => 'A');
    notifyListeners();
    return err;
  }

  void applyShape(RoomShape s) {
    edit(() => engine.applyShape(s));
    if (!project.room.isWallEnabled(wallId)) wallId = s.walls.first;
    notifyListeners();
  }

  /// Redessine (textures chargées...).
  void refresh() => notifyListeners();

  /// Remplace le caisson sélectionné par un autre modèle du catalogue, au même endroit.
  String? replaceItem(String uid, String modelId) {
    String? reason;
    final err = edit(() {
      final r = engine.replace(uid, modelId);
      if (!r.moved) reason = r.reason;
    });
    return err ?? reason;
  }

  /// Finition de façade propre à un caisson (null = style de la cuisine).
  void setItemFront(String uid, String? front) => edit(() => project.byUid(uid)?.front = front);

  /// Composition de façade d'un caisson (null = celle du modèle).
  /// Format d'un meuble d'angle (W1 / W2) : le bras reste dans l'angle ; refusé s'il chevauche un voisin.
  String? setCornerSize(String uid, CornerSize size) {
    final c = project.byUid(uid);
    if (c == null) return tr('Élément introuvable');
    final m = engine.modelOf(c);
    return edit(() {
      final w = project.room.wall(c.wallId);
      final newW = size.carcass ?? size.w1;
      final atEnd = c.right >= w.length - 60;
      c.width = newW;
      if (m.shape != CabinetShape.blind) c.widthRight = size.w2;
      if (atEnd) c.s = w.length - newW;
      if (engine.validate().any((i) => i.code == 'overlap' && i.uids.contains(uid))) {
        throw PlacementException(trp('Format {0} : pas la place sans chevaucher un voisin', [size.code]));
      }
    });
  }

  String? setItemLayout(String uid, List<FrontRow>? rows) {
    final c = project.byUid(uid);
    if (c == null) return null;
    if (rows != null) {
      final why = layoutProblem(engine.modelOf(c).kind, rows, c.height);
      if (why != null) return why;
    }
    return edit(() => c.layout = rows);
  }

  /// Façades des hauts / des bas (null = comme la finition générale).
  void setFrontScope({String? upper, String? lower, bool clearUpper = false, bool clearLower = false}) {
    edit(() {
      final st = project.style;
      if (upper != null || clearUpper) st.frontUpper = upper;
      if (lower != null || clearLower) st.frontLower = lower;
    });
  }

  /// Retire les finitions propres à chaque caisson (tout suit le style général).
  void clearItemFronts() => edit(() {
        for (final c in project.items) {
          c.front = null;
        }
      });

  void addTexture(CustomTexture t) {
    project.style.textures.add(t);
    notifyListeners();
  }

  void removeTexture(String id) {
    project.style.textures.removeWhere((t) => t.id == id);
    final key = 'tex:$id';
    edit(() {
      final st = project.style;
      if (st.front == key) st.front = 'blanc_mat';
      if (st.frontUpper == key) st.frontUpper = null;
      if (st.frontLower == key) st.frontLower = null;
      if (st.worktop == key) st.worktop = 'quartz_blanc';
      for (final c in project.items) {
        if (c.front == key) c.front = null;
      }
    });
  }

  /// Choix d'un appareil : la largeur du caisson suit l'appareil (lave-vaisselle 45 / 60, évier 2 bacs...).
  String? setAppliance(String uid, int index, String applianceId) {
    final c = project.byUid(uid);
    if (c == null) return null;
    final m = engine.modelOf(c);
    final a = db?.appliances[applianceId];
    String? msg;
    final err = edit(() {
      final next = [...appliancesOf(m, c)];
      next[index] = applianceId;
      c.appliances = next;
      if (a == null) return;
      int? target;
      if (a.category == 'dishwashers' && a.niche != null) {
        target = a.niche!.$1;
      } else if (a.cabinetWidth != null && a.category != 'cooktops' && a.category != 'hoods') {
        target = a.cabinetWidth;
      }
      if (a.minCabinetWidth != null && c.width < a.minCabinetWidth!) target = math.max(target ?? 0, a.minCabinetWidth!);
      if (target != null && target != c.width && m.widths.allows(m.widths.nearest(target))) {
        final r = engine.resize(uid, width: target);
        if (!r.moved) {
          msg = 'Pas de place pour élargir à $target mm : ${r.reason}';
        } else if (c.width != target) {
          msg = 'Largeur ${c.width} mm (la plus proche de $target mm dans le catalogue)';
        } else {
          msg = 'Caisson ajusté à $target mm pour ${a.name}';
        }
      }
    });
    return err ?? msg;
  }

  /// Choix d'une poignée du catalogue (avec son entraxe / sa longueur et sa finition).
  void setHandle(HandleModel h, {int? size, String? finish}) => edit(() {
        final st = project.style;
        if (st.handleId != h.id) {
          st.handleSize = null;
          st.handleFinish = null;
        }
        st.handleId = h.id;
        st.handle = switch (h.render) {
          HandleRender.bar || HandleRender.xxl => h.render == HandleRender.xxl ? 'xxl' : 'bar',
          HandleRender.knob => 'knob',
          HandleRender.gola => 'gola',
          _ => h.render.name,
        };
        if (size != null) st.handleSize = size;
        if (finish != null) st.handleFinish = finish;
      });

  void setTallXxl(bool v) => edit(() => project.style.tallXxl = v);

  /// Sol, murs et crédence ([clearSplash] : crédence comme les murs).
  void setFinishOptions({bool? endPanels, String? lighting}) => edit(() {
        final st = project.style;
        if (endPanels != null) st.endPanels = endPanels;
        if (lighting != null) st.lighting = lighting;
      });

  void setRoomFinish({String? floor, String? wall, String? splash, bool clearSplash = false}) => edit(() {
        final st = project.style;
        if (floor != null) st.floor = floor;
        if (wall != null) st.wall = wall;
        if (splash != null || clearSplash) st.splash = splash;
      });

  void setStyle({String? front, String? worktop, String? handle, String? carcass}) {
    edit(() {
      final st = project.style;
      if (front != null) st.front = front;
      if (worktop != null) st.worktop = worktop;
      if (handle != null) st.handle = handle;
      if (carcass != null) st.carcass = carcass;
    });
  }

  void newProject() {
    edit(() {
      project.items.clear();
      project.openings.clear();
    });
    selected = null;
    selectedOpening = null;
    notifyListeners();
  }

  String exportJson() => const JsonEncoder.withIndent('  ').convert(project.toJson());

  void importJson(String text) {
    final before = _snap();
    final p = Project.fromJson(jsonDecode(text) as Map<String, dynamic>);
    _undo.add(before);
    _redo.clear();
    project = p;
    engine = LayoutEngine(catalog, project);
    selected = null;
    selectedOpening = null;
    notifyListeners();
  }

  /// Nouvelle forme de la pièce (contour libre, ou rectangle s'il en a la forme). Les caissons, ouvertures et
  /// points de réseau suivent le mur sur lequel ils étaient (même droite) ; ceux dont le mur a disparu sont retirés.
  String setRoomOutline(List<RoomVertex> pts) {
    final old = Room.fromJson(project.room.toJson());
    var removed = 0;
    edit(() {
      final r = project.room;
      // rectangle droit : on garde la pièce rectangulaire (murs A, B, C, D habituels)
      final xs = {for (final p in pts) p.x.round()}, ys = {for (final p in pts) p.y.round()};
      final rect = pts.length == 4 && pts.every((p) => p.bulge.abs() < 0.5) && xs.length == 2 && ys.length == 2;
      double ox = 0, oy = 0;
      if (rect) {
        ox = xs.reduce(math.min).toDouble();
        oy = ys.reduce(math.min).toDouble();
        r.clearOutline();
        r.width = (xs.reduce(math.max) - xs.reduce(math.min)).toDouble();
        r.depth = (ys.reduce(math.max) - ys.reduce(math.min)).toDouble();
      } else {
        (ox, oy) = r.setOutline(pts);
      }
      // ancien point (repère de l'ancienne pièce) → nouveau repère
      (double, double) shift(double x, double y) => (x - ox, y - oy);
      // mur de la nouvelle pièce qui porte le point (x, y) avec la même direction ; position le long du mur
      (String, double)? onNew(Wall ow, double s) {
        final (px, py) = shift(ow.toPlan(s, 0).$1, ow.toPlan(s, 0).$2);
        for (final w in r.walls.where((w) => w.straight)) {
          if ((w.dx - ow.dx).abs() > 1e-6 || (w.dy - ow.dy).abs() > 1e-6) continue;
          final (ns, nt) = w.toWall(px, py);
          if (nt.abs() < 2 && ns >= -2 && ns <= w.length + 2) return (w.id, ns);
        }
        return null;
      }

      for (final c in [...project.items]) {
        if (c.wallId == 'I') continue;
        final m = onNew(old.wall(c.wallId), c.s);
        final w = m == null ? null : r.wall(m.$1);
        if (m == null || !w!.orthogonal || m.$2 + c.width > w.length + 2) {
          project.items.remove(c);
          removed++;
        } else {
          c
            ..wallId = m.$1
            ..s = m.$2;
        }
      }
      for (final o in [...project.openings]) {
        final m = onNew(old.wall(o.wallId), o.s);
        final w = m == null ? null : r.wall(m.$1);
        if (m == null || !w!.orthogonal || m.$2 + o.width > w.length + 2) {
          project.openings.remove(o);
          removed++;
        } else {
          o
            ..wallId = m.$1
            ..s = m.$2;
        }
      }
      for (final x in [...project.points]) {
        if (x.wallId == 'I') continue;
        if (x.onCeiling) {
          final (nx, ny) = shift(x.s, x.z);
          x
            ..s = nx
            ..z = ny;
          continue;
        }
        if (!old.order.contains(x.wallId)) continue;
        final m = onNew(old.wall(x.wallId), x.s);
        if (m == null) {
          project.points.remove(x);
        } else {
          x
            ..wallId = m.$1
            ..s = m.$2;
        }
      }
      for (final o in project.objects) {
        final (nx, ny) = shift(o.x, o.y);
        o
          ..x = nx
          ..y = ny;
      }
      final isl = r.island;
      if (isl != null) {
        isl
          ..x0 -= ox
          ..y0 -= oy;
      }
    });
    if (!project.room.isWallEnabled(wallId)) wallId = project.room.order.firstWhere(project.room.isWallEnabled, orElse: () => project.room.order.first);
    notifyListeners();
    final shape = project.room.outline == null ? 'Pièce rectangulaire' : 'Nouvelle forme : ${project.room.order.length} murs';
    return trp('{0}, {1} m²{2}', [shape, project.room.area.toStringAsFixed(1).replaceAll('.', ','), removed > 0 ? trp(' · {0} élément(s) retiré(s) (mur supprimé ou trop court)', [removed]) : '']);
  }

  void updateRoom({double? width, double? depth, double? height, Map<String, bool>? walls}) {
    edit(() {
      final r = project.room;
      final flush = {for (final o in project.objects) o.uid: onItsWall(r, o)};
      if (width != null || depth != null) r.resize(width: width, depth: depth); // contour libre : mis à l'échelle
      if (height != null) r.height = height;
      walls?.forEach(r.setWallEnabled);
      // sanitaires et objets : ramenés dans la pièce, toujours plaqués à leur mur
      for (final o in project.objects) {
        keepInRoom(r, o, wasOnWall: flush[o.uid] ?? false);
      }
    });
    if (!project.room.isWallEnabled(wallId)) {
      wallId = project.room.order.firstWhere(project.room.isWallEnabled, orElse: () => 'A');
    }
    notifyListeners();
  }
}

/// Guide d'alignement : position [at] le long du mur [wall] (vue de face : verticale ; plan : repère sur le mur),
/// ou droite x = [at] (vertical) / y = [at] dans la pièce.
class SnapGuide {
  final String? wall;
  final bool vertical;
  final double at;
  final String label;
  const SnapGuide.wall(String this.wall, this.at, this.label) : vertical = true;
  const SnapGuide.plan(this.vertical, this.at, this.label) : wall = null;
}
