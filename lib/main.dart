import 'dart:convert';

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'engine/engine.dart';
import 'engine/art_recipes.dart';
import 'engine/furniture_accessories.dart';
import 'engine/saved_projects.dart';
import 'ui/app_state.dart';
import 'ui/nest_service.dart';
import 'ui/session.dart';
import 'ui/busy.dart';
import 'ui/canvas_view.dart';
import 'ui/header.dart';
import 'ui/furniture_page.dart';
import 'ui/home_screen.dart';
import 'ui/manual_cut_page.dart';
import 'ui/objects_panel.dart';
import 'ui/panels.dart';
import 'ui/cut_pdf.dart';
import 'ui/labels_pdf.dart';
import 'ui/pdf_export.dart';
import 'ui/tech_preview.dart';
import 'ui/textures.dart';
import 'ui/theme.dart';
import 'ui/toolbar.dart';
import 'ui/web_io.dart';
import 'ui/i18n.dart';
import 'ui/app_settings.dart';
import 'ui/art_library.dart';
import 'ui/client_ui.dart';
import 'ui/excel_export.dart';
import 'ui/project_start_dialog.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // calculs lourds (débit) hors du fil de l'interface ; télémétrie de performance
  AppState.backgroundNest = true;
  await initPlatformIo(); // iPad : sauvegarde dans l'app, fichiers par le menu Partager
  onStoreFailure = (e) => Session.onFailure(trp('Enregistrement impossible sur l’appareil : {0}', [e]));
  AppSettings.instance.load(deviceLang: PlatformDispatcher.instance.locale.languageCode); // langue, unités, numérotation des plans
  translateHook = tr; // messages du moteur (contrôles, erreurs de pose) dans la langue choisie
  // app installée (iPad) : orientation verrouillée en paysage
  await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  // plein écran : ni barre d'état ni barre de navigation (elles réapparaissent d'un glissement du bord)
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  PerformanceProfiler.instance
    ..memoryBytes = currentMemoryBytes
    ..platformInfo = platformDescription;
  // erreur d'affichage : message lisible au lieu d'un rectangle gris (à copier pour le support)
  ErrorWidget.builder = (details) => Material(
        color: const Color(0xFFFFF3E0),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(trp('Erreur d’affichage : {0}', [details.exceptionAsString()]),
              maxLines: 8, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFB71C1C), fontSize: 12)),
        ),
      );
  final catalog = Catalog.parse(await rootBundle.loadString('assets/catalog.json'));
  final db = MaterialsDb.parse(
    appliances: await rootBundle.loadString('assets/data/appliances.json'),
    worktops: await rootBundle.loadString('assets/data/worktops.json'),
    panels: await rootBundle.loadString('assets/data/panels.json'),
    hardware: await rootBundle.loadString('assets/data/hardware.json'),
    handles: await rootBundle.loadString('assets/data/handles.json'),
  );
  // reprise du travail en cours (copie de travail sauvegardée automatiquement dans le navigateur)
  Session.setEmpty('cuisine', projectWorkJson(Project().toJson()));
  Session.setEmpty('art', jsonEncode(ArtProject().toJson()));
  Session.setEmpty('debit', jsonEncode(ManualCut().toJson()));
  Project? restored;
  try {
    final w = Session.work('cuisine');
    if (w != null && w.isNotEmpty) restored = Project.fromJson(jsonDecode(w) as Map<String, dynamic>);
    final a = Session.work('art');
    if (restored != null && a != null && a.isNotEmpty) restored.art = ArtProject.fromJson(jsonDecode(a) as Map<String, dynamic>);
    final d = Session.work('debit');
    if (restored != null && d != null && d.isNotEmpty) restored.manual = ManualCut.fromJson(jsonDecode(d) as Map<String, dynamic>);
  } catch (_) {
    restored = null; // copie illisible : on repart d'un projet neuf
  }
  final state = AppState(catalog,
      project: restored, db: db, supplier: SupplierTariff.parse(await rootBundle.loadString('assets/data/supplier_prices.json')));
  state.objectCatalog = CatalogObject.parse(await rootBundle.loadString('assets/data/objects.json'));
  // meubles de la bibliothèque de l'atelier : posables comme objets dans tous les modes
  ArtLibrary.instance
    ..load()
    ..attach(state.objectCatalog);
  OpeningModel.parse(await rootBundle.loadString('assets/data/openings.json')); // portes et fenêtres
  KitchenFixtures.parse(await rootBundle.loadString('assets/data/accessories.json')); // éviers, mitigeurs, appareillage
  BrandCatalog.parse(await rootBundle.loadString('assets/data/brands.json')); // marques et prix (Maroc)
  SizeCatalog.parse(await rootBundle.loadString('assets/data/sizes.json')); // dimensions types et normes
  FurnitureAccessories.parse(await rootBundle.loadString('assets/data/furniture_accessories.json')); // accessoires de meubles
  ArtRecipes.parse(await rootBundle.loadString('assets/data/art_recipes.json')); // recettes du mode Art
  PublicPrices.parse(await rootBundle.loadString('assets/data/public_prices.json')); // prix publics des panneaux
  state.addListener(() => Session.autosave('cuisine', () => projectWorkJson(state.project.toJson())));
  final bank = TextureBank.instance;
  bank.addListener(state.refresh);
  // textures générées à la demande (première vue qui en a besoin), pas au démarrage
  state.addListener(() => bank.syncCustom(state.project.style.textures));
  SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  runApp(KitchenApp(state: state, showHome: true));
}

const _kSheetPrice = "Prix d'une feuille (MAD)";

class KitchenApp extends StatefulWidget {
  final AppState state;
  final bool googleFonts;
  final bool showHome; // écran d'accueil (logo animé, univers, débitage) avant le planificateur
  const KitchenApp({super.key, required this.state, this.googleFonts = true, this.showHome = false});
  @override
  State<KitchenApp> createState() => _KitchenAppState();
}

class _KitchenAppState extends State<KitchenApp> {
  ThemeMode mode = ThemeMode.light;
  final _universes = <String, AppState>{}; // un projet par univers (dressing, bain, tv, intérieur)

  @override
  void initState() {
    super.initState();
    AppSettings.instance.addListener(_onSettings);
    // contenu « vide » de chaque espace : rien à enregistrer tant qu'on n'a rien changé
    Session.setEmpty('cuisine', projectWorkJson(Project().toJson()));
    Session.setEmpty('art', jsonEncode(ArtProject().toJson()));
    Session.setEmpty('debit', jsonEncode(ManualCut().toJson()));
  }

  @override
  void dispose() {
    AppSettings.instance.removeListener(_onSettings);
    super.dispose();
  }

  /// Langue ou unité changée : tout l'écran se redessine (pages ouvertes comprises), plans et cotes aussi.
  void _onSettings() {
    if (!mounted) return;
    setState(() {});
    void rebuild(Element e) {
      e.markNeedsBuild();
      e.visitChildren(rebuild);
    }

    (context as Element).visitChildren(rebuild);
    widget.state.refresh();
    for (final s in _universes.values) {
      s.refresh();
    }
  }

  Future<void> _openKitchen(BuildContext ctx) async {
    final s = widget.state;
    final hasWork = s.project.items.isNotEmpty;
    await ProjectStartDialog.show(
      context: ctx,
      universeId: 'cuisine',
      universeTitle: tr('Cuisine'),
      universeIcon: Icons.kitchen_outlined,
      state: s,
      hasWorkInProgress: hasWork,
      currentProjectName: s.project.name,
      currentCabinetCount: s.project.items.length,
      onNewProject: (fresh) {
        s.project = fresh;
        s.engine = LayoutEngine(s.catalog, fresh);
        s.step = PlanStep.space;
        s.refresh();
        Session.resetEmpty('cuisine', projectWorkJson(fresh.toJson()));
        Session.route = 'cuisine';
        Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => _guarded('cuisine', s)));
      },
      onOpenKin: (kinJson) {
        s.importJson(kinJson);
        s.refresh();
        Session.route = 'cuisine';
        Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => _guarded('cuisine', s)));
      },
      onResume: () {
        Session.route = 'cuisine';
        Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => _guarded('cuisine', s)));
      },
    );
  }

  /// Ouvre un univers dans le même planificateur que la cuisine, avec son catalogue.
  Future<void> _openUniverse(BuildContext ctx, String id) async {
    var ust = _universes[id];
    if (ust == null) {
      final u = await runBusy(ctx, trp('Ouverture de l’univers {0}…', [FurnitureUniverse.names[id] ?? id]), () => loadUniverse(id));
      Project fresh() => Project(name: FurnitureUniverse.names[id] ?? id, universe: id, room: Room(width: 3600, depth: 3000, height: 2600));
      Session.setEmpty(id, projectWorkJson(fresh().toJson()));
      Project? restored;
      try {
        final w = Session.work(id);
        if (w != null && w.isNotEmpty) restored = Project.fromJson(jsonDecode(w) as Map<String, dynamic>);
      } catch (_) {}
      final st = AppState(universeCatalog(u), db: widget.state.db, project: restored ?? fresh())..objectCatalog = widget.state.objectCatalog;
      TextureBank.instance.addListener(st.refresh);
      st.addListener(() => Session.autosave(id, () => projectWorkJson(st.project.toJson())));
      _universes[id] = ust = st;
      _fresh[id] = fresh;
    }
    if (!ctx.mounted) return;
    final s = ust;
    final uTitle = FurnitureUniverse.names[id] ?? (id == 'interieur' ? 'Intérieur' : id);
    final uIcon = switch (id) {
      'dressing' => Icons.checkroom_outlined,
      'bain' => Icons.wc_outlined,
      'tv' => Icons.tv_outlined,
      'interieur' => Icons.weekend_outlined,
      'buanderie' => Icons.local_laundry_service_outlined,
      _ => Icons.home_outlined,
    };
    final hasWork = s.project.items.isNotEmpty || s.project.furniture.isNotEmpty;

    await ProjectStartDialog.show(
      context: ctx,
      universeId: id,
      universeTitle: tr(uTitle),
      universeIcon: uIcon,
      state: s,
      hasWorkInProgress: hasWork,
      currentProjectName: s.project.name,
      currentCabinetCount: s.project.items.length + s.project.furniture.length,
      onNewProject: (fresh) {
        s.project = fresh;
        s.engine = LayoutEngine(s.catalog, fresh);
        s.step = PlanStep.space;
        s.refresh();
        Session.resetEmpty(id, projectWorkJson(fresh.toJson()));
        Session.route = id;
        Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => _guarded(id, s)));
      },
      onOpenKin: (kinJson) {
        s.importJson(kinJson);
        s.refresh();
        Session.route = id;
        Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => _guarded(id, s)));
      },
      onResume: () {
        Session.route = id;
        Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => _guarded(id, s)));
      },
    );
  }

  final _fresh = <String, Project Function()>{};

  /// Planificateur avec la question « enregistrer ou quitter » en sortant.
  Widget _guarded(String id, AppState s) => LeaveGuard(
        id: id,
        current: () => projectWorkJson(s.project.toJson()),
        revert: (saved) {
          // l'atelier Art et le débit manuel ont leur propre enregistrement : ils ne sont pas touchés
          final art = s.project.art, manual = s.project.manual, furniture = {...s.project.furniture};
          s.importJson(saved ?? jsonEncode((_fresh[id]?.call() ?? Project(universe: id)).toJson()));
          s.project.art = art;
          s.project.manual = manual;
          s.project.furniture.addAll(furniture);
        },
        child: PlannerScreen(state: s, themeMode: mode, onThemeMode: (m) => setState(() => mode = m)),
      );

  /// Au démarrage de l'app : toujours afficher l'écran d'accueil avec les univers (Cuisine, Dressing, Buanderie, etc.)
  void _resume(BuildContext ctx) {
    // Ne pas forcer l'ouverture automatique d'une cuisine en cours au démarrage
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        scaffoldMessengerKey: appMessenger,
        title: 'kitchinox · Conception de cuisine',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light, googleFonts: widget.googleFonts),
        darkTheme: buildTheme(Brightness.dark, googleFonts: widget.googleFonts),
        themeMode: mode,
        // langue de l'interface (l'arabe se lit de droite à gauche)
        locale: Locale(AppSettings.instance.lang.code),
        supportedLocales: const [Locale('fr'), Locale('en'), Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        // toujours en paysage : écran tenu droit → affichage tourné, jamais de message
        builder: (context, child) => LandscapeLock(child: child ?? const SizedBox()),

        home: widget.showHome
            ? Builder(
                builder: (ctx) {
                  _resume(ctx);
                  return HomeScreen(
                    state: widget.state,
                    themeMode: mode,
                    onThemeMode: (m) => setState(() => mode = m),
                    onKitchen: () => _openKitchen(ctx),
                    onUniverse: (id) => _openUniverse(ctx, id),
                    onSettings: () => showAppSettings(ctx, (msg) {
                      final sm = ScaffoldMessenger.maybeOf(ctx);
                      if (sm != null) {
                        sm.hideCurrentSnackBar();
                        sm.showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2), behavior: SnackBarBehavior.floating));
                      }
                    }),
                  );
                },
              )
            : PlannerScreen(state: widget.state, themeMode: mode, onThemeMode: (m) => setState(() => mode = m)),
      );
}

class PlannerScreen extends StatefulWidget {
  final AppState state;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeMode;
  const PlannerScreen({super.key, required this.state, required this.themeMode, required this.onThemeMode});
  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _SctChoice {
  final String material;
  final String categoryKey;
  final String categoryTitle;
  final IconData icon;
  final int sheetL;
  final int sheetW;
  final int thickness;
  final int partCount;
  final int sheetCount;
  bool selected;

  _SctChoice({
    required this.material,
    required this.categoryKey,
    required this.categoryTitle,
    required this.icon,
    required this.sheetL,
    required this.sheetW,
    required this.thickness,
    required this.partCount,
    required this.sheetCount,
    this.selected = true,
  });
}

class _PlannerScreenState extends State<PlannerScreen> {
  final _scaffold = GlobalKey<ScaffoldState>();
  final _canvasFocus = FocusNode(debugLabel: 'canvas');
  StyleSection _styleSection = StyleSection.fronts;

  AppState get st => widget.state;

  void _msg(String m) {
    if (m.isEmpty) return;
    final sm = ScaffoldMessenger.of(context);
    sm.hideCurrentSnackBar();
    // au-dessus de la barre des vues (plan, face, 3D), centré : il ne la cache plus
    final w = MediaQuery.sizeOf(context).width;
    final side = ((w - 420) / 2).clamp(12.0, double.infinity);
    sm.showSnackBar(SnackBar(
      content: Text(m),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.fromLTRB(side, 0, side, 84),
    ));
  }

  void _nudge(double ds, double dz) {
    final r = st.nudge(ds, dz);
    if (r != null) _msg(r);
  }

  Map<ShortcutActivator, VoidCallback> get _shortcuts => {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): st.undo,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): st.redo,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): st.redo,
        const SingleActivator(LogicalKeyboardKey.delete): st.deleteSelected,
        const SingleActivator(LogicalKeyboardKey.keyD, control: true): () {
          final err = st.duplicateSelected();
          _msg(err ?? tr('Élément dupliqué'));
        },
        const SingleActivator(LogicalKeyboardKey.backspace): st.deleteSelected,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (st.armedModel != null) {
            st.arm(null); // Échap arrête d'abord la pose en série
            return;
          }
          st.select(null);
          st.selectOpening(null);
          st.selectPoint(null);
          st.toggleMegaMenu(false);
        },
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _nudge(-10, 0),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _nudge(10, 0),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true): () => _nudge(-100, 0),
        const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true): () => _nudge(100, 0),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _nudge(0, 10),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _nudge(0, -10),
        const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true): () => _nudge(0, 100),
        const SingleActivator(LogicalKeyboardKey.arrowDown, shift: true): () => _nudge(0, -100),
        const SingleActivator(LogicalKeyboardKey.tab): () => _cycle(1),
        const SingleActivator(LogicalKeyboardKey.tab, shift: true): () => _cycle(-1),
      };

  /// Tab / Maj+Tab : sélection au clavier des éléments.
  void _cycle(int dir) {
    if (st.step == PlanStep.space) {
      final os = st.project.openings;
      if (os.isEmpty) return;
      final i = os.indexWhere((o) => o.uid == st.selectedOpening);
      st.selectOpening(os[(i + dir + os.length) % os.length].uid);
      return;
    }
    final items = [
      for (final c in st.project.items)
        if (st.view != ViewMode.front || c.wallId == st.wallId) c
    ]..sort((a, b) => a.wallId == b.wallId ? a.s.compareTo(b.s) : a.wallId.compareTo(b.wallId));
    if (items.isEmpty) return;
    final i = items.indexWhere((c) => c.uid == st.selected);
    st.select(items[(i + dir + items.length) % items.length].uid);
  }

  /// Ouvrir : un projet kitchinox (.kin) ou un débit SketchCut (.sct, ouvert dans le Débitage).
  Future<void> _open() async {
    final f = await pickFile(accept: '.kin,.sct');
    if (f == null) return;
    if (f.name.toLowerCase().endsWith('.sct')) {
      final r = manualCutFromFile(f.name, f.bytes, st);
      if (r == null || !mounted) {
        _msg(trp('Fichier non reconnu : {0}', [f.name]));
        return;
      }
      st.project.manual = r.$1;
      await openManualCut(context, st);
      return;
    }
    try {
      final jsonStr = KinFormat.decode(f.bytes);
      st.importJson(jsonStr);
      _msg(trp('{0} ouvert', [tr(f.name)]));
    } catch (e) {
      _msg(trp('Fichier illisible : {0}', [e]));
    }
  }

  void _newProjectWithClient() {
    ProjectStartDialog.show(
      context: context,
      universeId: st.project.universe,
      universeTitle: FurnitureUniverse.names[st.project.universe] ?? (st.project.universe == 'cuisine' ? 'Cuisine' : st.project.universe),
      universeIcon: st.project.universe == 'cuisine' ? Icons.kitchen_outlined : Icons.folder_open_outlined,
      state: st,
      hasWorkInProgress: false,
      currentProjectName: st.project.name,
      currentCabinetCount: st.project.items.length,
      onNewProject: (fresh) {
        st.project = fresh;
        st.engine = LayoutEngine(st.catalog, fresh);
        st.step = PlanStep.space;
        st.refresh();
        _msg(trp('Nouveau projet « {0} » créé', [fresh.name]));
      },
      onOpenKin: (kinJson) {
        st.importJson(kinJson);
        st.refresh();
        _msg(tr('Projet ouvert avec succès'));
      },
      onResume: () {},
    );
  }

  Future<void> _saveAs() async {
    final controller = TextEditingController(text: st.project.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Enregistrer sous')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: tr('Nom du projet'),
            suffixText: '.kin',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(tr('Annuler'))),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(tr('Enregistrer'))),
        ],
      ),
    );
    if (ok == true && controller.text.trim().isNotEmpty) {
      final newName = controller.text.trim();
      st.project.name = newName;
      st.refresh();
      _save();
    }
  }

  /// Enregistre le travail dans l'app et le fichier crypté .kin, sous le nom donné à la création du projet,
  /// dans Kitchinox/projets (iPad : sans menu Partager ; navigateur : téléchargement).
  Future<void> _save() async {
    Session.commit(st.project.universe, projectWorkJson(st.project.toJson()));
    SavedProjectsManager.saveProject(st.project, universe: st.project.universe);
    final kinBytes = KinFormat.encode(st.exportJson(), projectName: st.project.name);
    final path = await saveToKitchinox('${st.project.name}.kin', kinBytes);
    _msg(path == null ? tr('Projet enregistré et horodaté (.kin)') : trp('Projet enregistré : {0}', [path]));
  }

  void _download() {
    final kinBytes = KinFormat.encode(st.exportJson(), projectName: st.project.name);
    downloadBytes('${st.project.name}.kin', kinBytes, mime: 'application/octet-stream');
    _msg(tr('Fichier .kin téléchargé'));
  }

  void _exportCsv() {
    downloadBytes('${st.project.name}_liste.csv', utf8.encode(st.bom.toCsv()), mime: 'text/csv');
    _msg(tr('Liste exportée (CSV)'));
  }

  void _exportExcel() {
    final bytes = buildExcelExport(st);
    downloadBytes(
      '${st.project.name}_export.xlsx',
      bytes,
      mime: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    _msg(tr('Classeur Excel (.xlsx) téléchargé avec succès'));
  }

  bool _pdfBusy = false;

  Future<void> _exportPdf() async {
    if (_pdfBusy) return;
    setState(() => _pdfBusy = true);
    _msg(tr("Préparation du plan d'exécution…"));
    try {
      // barre de progression au centre ; résolution un peu réduite : moins de mémoire sur tablette
      final progress = BusyProgress();
      final bytes = await runBusy(context, tr('Préparation du plan d’exécution…'), () async {
        progress.set(0.01, tr('Optimisation du débit'));
        final plan = await st.cutPlanReady();
        final number = AppSettings.instance.numberFor(st.project, DocKind.exec);
        st.refresh(); // le numéro attribué est gardé dans le projet (réédition = même numéro)
        final pdf = await PerformanceProfiler.instance.measureAsync('pdf_execution',
            () => inPdfLanguage(() => buildExecutionPdf(st.engine, db: st.db, supplier: st.supplier, pixelRatio: 2, plan: plan, number: number, onProgress: progress.set)),
            info: {'caissons': st.project.items.length});
        return (pdf, number);
      }, progress: progress);
      progress.dispose();
      final (pdfBytes, number) = bytes;
      downloadBytes('${number == null ? '' : '${number}_'}${st.project.name}_plan_execution.pdf', pdfBytes, mime: 'application/pdf');
      _msg(trp('Plan d\'exécution {0} téléchargé ({1} Ko)', [number ?? '', pdfBytes.length ~/ 1024]));
    } catch (e, st) {
      // ignore: avoid_print
      print('PDF exécution ERREUR: $e\n$st');
      _msg(trp('Échec de la génération du PDF : {0}', [e]));
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  Future<CutPlan> _plan() => st.cutPlanReady(); // en cache ; attend la fin d'un calcul en cours

  Future<void> _cutPdf() async {
    if (_pdfBusy) return;
    setState(() => _pdfBusy = true);
    _msg(tr('Calcul du plan de découpe…'));
    try {
      final plan = await _plan();
      if (plan.parts.isEmpty) {
        _msg(tr('Aucune pièce à débiter'));
        return;
      }
      if (!mounted) return;
      final progress = BusyProgress();
      final number = AppSettings.instance.numberFor(st.project, DocKind.cut);
      st.refresh();
      final bytes = await runBusy(
          context,
          tr('Plan de coupe…'),
          () => PerformanceProfiler.instance.measureAsync(
              'pdf_debit', () => inPdfLanguage(() => buildCutPdf(st.engine, plan, db: st.db, number: number, onProgress: progress.set)),
              info: {'feuilles': plan.sheets.length}),
          progress: progress);
      progress.dispose();
      downloadBytes('${number == null ? '' : '${number}_'}${st.project.name}_plan_de_decoupe.pdf', bytes, mime: 'application/pdf');
      _msg(trp('Plan de découpe : {0} pièces sur {1} panneau(x)', [plan.partCount, plan.sheets.length]));
    } catch (e, st) {
      // ignore: avoid_print
      print('PDF découpe ERREUR: $e\n$st');
      _msg(trp('Échec du plan de découpe : {0}', [e]));
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  Future<void> _generateCodes() async {
    if (_pdfBusy) return;
    setState(() => _pdfBusy = true);
    _msg(tr('Génération des codes et étiquettes…'));
    try {
      final progress = BusyProgress();
      final bytes = await runBusy(
        context,
        tr('Génération des codes…'),
        () => inPdfLanguage(() => buildLabelsPdf(st, onProgress: progress.set)),
        progress: progress,
      );
      progress.dispose();
      final numSetting = AppSettings.instance.numberFor(st.project, DocKind.exec);
      final digitsOnly = (numSetting ?? '').replaceAll(RegExp(r'\D'), '');
      final projId = digitsOnly.length >= 4
          ? digitsOnly.substring(digitsOnly.length - 4)
          : (st.project.name.hashCode.abs() % 9000 + 1000).toString();
      downloadBytes('etiquettes_$projId.pdf', bytes, mime: 'application/pdf');
      _msg(tr('Étiquettes et codes-barres générés (PDF)'));
    } catch (e) {
      _msg(trp('Échec de génération des codes : {0}', [e]));
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  Future<void> _sct() async {
    final plan = await _plan();
    if (plan.parts.isEmpty) {
      _msg(tr('Aucune pièce à débiter'));
      return;
    }
    final cs = st.project.cut;

    bool isFrontMat(String m) =>
        m == cs.frontMaterial ||
        m.contains('Façade') ||
        m.contains('Porte') ||
        m.contains('High Gloss') ||
        m.contains('Acrylique') ||
        m.contains('PET') ||
        m.contains('Laqué');

    bool isBackMat(String m) =>
        m == cs.backMaterial ||
        m.contains('HDF') ||
        m.contains('Fond') ||
        m.contains('fond') ||
        m.contains('6 mm') ||
        m.contains('3 mm');

    final choices = <_SctChoice>[];
    for (final mat in plan.materials) {
      final isF = isFrontMat(mat);
      final isB = isBackMat(mat);
      final key = isF ? 'Facades' : (isB ? 'Fonds' : 'Caissons');
      final title = isF
          ? tr('Façades (Portes & tiroirs)')
          : (isB ? tr('Fonds / Dos (Derrière rainuré)') : tr('Caissons (Corps de meuble)'));
      final icon = isF
          ? Icons.door_front_door_outlined
          : (isB ? Icons.flip_to_back : Icons.kitchen);
      final t = isF ? cs.doorThickness : (isB ? cs.backThickness : cs.carcassThickness);
      final (sL, sW) = cs.sheetDimensionsFor(mat);
      final parts = plan.parts.where((p) => p.material == mat).toList();
      final partQty = parts.fold<int>(0, (sum, p) => sum + p.qty);
      final sheetQty = plan.sheets.where((s) => s.material == mat).length;

      choices.add(_SctChoice(
        material: mat,
        categoryKey: key,
        categoryTitle: title,
        icon: icon,
        sheetL: sL,
        sheetW: sW,
        thickness: t,
        partCount: partQty,
        sheetCount: sheetQty,
        selected: true,
      ));
    }

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final t = Theme.of(ctx).textTheme;
          final scheme = Theme.of(ctx).colorScheme;
          final selectedCount = choices.where((c) => c.selected).length;

          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.content_cut, color: Color(0xFFF26522)),
                const SizedBox(width: Tokens.s2),
                Text(tr('Export SketchCut PRO (.sct)')),
              ],
            ),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    tr('Sélectionnez les catégories de panneaux à exporter :'),
                    style: t.bodyMedium,
                  ),
                  const SizedBox(height: Tokens.s2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => setD(() {
                          for (final c in choices) {
                            c.selected = true;
                          }
                        }),
                        child: Text(tr('Tout cocher')),
                      ),
                      TextButton(
                        onPressed: () => setD(() {
                          for (final c in choices) {
                            c.selected = false;
                          }
                        }),
                        child: Text(tr('Tout décocher')),
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  const SizedBox(height: Tokens.s1),
                  for (final c in choices)
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: c.selected
                            ? const Color(0xFFF26522).withValues(alpha: 0.08)
                            : scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: c.selected ? const Color(0xFFF26522) : scheme.outlineVariant,
                          width: c.selected ? 1.5 : 1.0,
                        ),
                      ),
                      child: CheckboxListTile(
                        value: c.selected,
                        onChanged: (v) => setD(() => c.selected = v ?? false),
                        secondary: Icon(c.icon, color: const Color(0xFFF26522)),
                        title: Text(c.categoryTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Text(
                          '${c.material} · ${c.sheetL} × ${c.sheetW} × ${c.thickness} mm\n${c.partCount} pièces · ${c.sheetCount} feuille(s)',
                          style: const TextStyle(fontSize: 11),
                        ),
                        isThreeLine: true,
                        activeColor: const Color(0xFFF26522),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('Annuler')),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF26522)),
                icon: const Icon(Icons.download, size: 18),
                onPressed: selectedCount == 0 ? null : () => Navigator.pop(ctx, true),
                label: Text(
                  selectedCount <= 1
                      ? tr('Exporter 1 fichier .sct')
                      : trp('Exporter {0} fichiers .sct', [selectedCount]),
                ),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) return;

    var exported = 0;
    for (final c in choices.where((x) => x.selected)) {
      final file = toSct(plan, c.material, order: '${st.project.name}_${c.categoryKey}', thickness: '${c.thickness}');
      final safe = c.material.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
      final filename = '${st.project.name}_${c.categoryKey}_${safe}_${c.sheetL}x${c.sheetW}_${c.thickness}mm.sct';
      downloadBytes(filename, utf8.encode(file), mime: 'text/plain');
      exported++;
    }
    _msg(exported == 1
        ? tr('1 fichier .sct exporté pour SketchCut PRO')
        : trp('{0} fichiers .sct exportés pour SketchCut PRO', [exported]));
  }

  Future<void> _cutSettings() async {
    final cs = st.project.cut;
    final (fL, fW) = cs.sheetDimensionsFor(cs.frontMaterial);
    final fields = <String, TextEditingController>{
      'Longueur feuille caissons (mm)': TextEditingController(text: '${cs.sheetLength}'),
      'Largeur feuille caissons (mm)': TextEditingController(text: '${cs.sheetWidth}'),
      'Longueur feuille façades (mm)': TextEditingController(text: '$fL'),
      'Largeur feuille façades (mm)': TextEditingController(text: '$fW'),
      'Trait de scie (mm)': TextEditingController(text: '${cs.kerf}'),
      'Recoupe des bords (mm)': TextEditingController(text: '${cs.trim}'),
      'Épaisseur caisson (mm)': TextEditingController(text: '${cs.carcassThickness}'),
      'Épaisseur porte MDF (mm)': TextEditingController(text: '${cs.doorThickness}'),
      'Jeu vertical des façades (mm)': TextEditingController(text: '${cs.frontGap}'),
      'Jeu horizontal des façades (mm)': TextEditingController(text: '${cs.gapH}'),
      'Jeu entre deux portes (mm)': TextEditingController(text: '${cs.gapBetween}'),
      'Retrait Gola, façade du haut (mm)': TextEditingController(text: '${cs.golaTop}'),
      'Retrait Gola, façades suivantes (mm)': TextEditingController(text: '${cs.golaMid}'),
      'Épaisseur du fond arrière (mm)': TextEditingController(text: '${cs.backThickness}'),
      'Profondeur de rainure du fond (mm)': TextEditingController(text: '${cs.grooveDepth}'),
    };
    var backPanel = cs.backPanel, rails = cs.includeRails, shelves = cs.includeShelves, drawers = cs.drawerSystem;
    var machine = cs.machine, method = cs.method;
    final sp = st.project.specs;
    final prices = <String, TextEditingController>{
      'Prix d\'une feuille (MAD)': TextEditingController(text: sp.sheetPrice?.round().toString() ?? ''),
      'Chant posé, min (MAD/m)': TextEditingController(text: sp.edgePriceMin?.toString() ?? ''),
      'Chant posé, max (MAD/m)': TextEditingController(text: sp.edgePriceMax?.toString() ?? ''),
      'Découpe par feuille (MAD)': TextEditingController(text: sp.cuttingPerSheet.toString()),
    };
    var brand = sp.hardwareBrand;
    var tier = sp.applianceTier;
    var panel = sp.carcassPanel;
    var carcassMat = cs.carcassMaterial;
    var frontMat = cs.frontMaterial;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Réglages du débit et tarifs')),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.only(bottom: Tokens.s3),
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: carcassMaterialChoices.contains(carcassMat) ? carcassMat : carcassMaterialChoices.first,
                  decoration: InputDecoration(labelText: tr('Matériau des caissons'), border: const OutlineInputBorder(), isDense: true),
                  items: [for (final m in carcassMaterialChoices) DropdownMenuItem(value: m, child: Text(tr(m), overflow: TextOverflow.ellipsis))],
                  onChanged: (v) {
                    if (v == null) return;
                    carcassMat = v;
                    final cat = v.contains('Latté') ? 'Latté (Blockboard)' : v.contains('Stratifié') ? 'Stratifié / Mélaminé' : 'MDF';
                    final p = woodSheetPresets[cat]?.first;
                    if (p != null) {
                      fields['Longueur feuille caissons (mm)']!.text = '${p.length}';
                      fields['Largeur feuille caissons (mm)']!.text = '${p.width}';
                    }
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: Tokens.s3),
                child: DropdownButtonFormField<SheetPreset>(
                  isExpanded: true,
                  hint: Text(tr('Choisir un format prédéfini de caisson')),
                  decoration: InputDecoration(labelText: tr('Presets feuille caissons'), border: const OutlineInputBorder(), isDense: true),
                  items: [
                    for (final entry in woodSheetPresets.entries)
                      ...entry.value.map((p) => DropdownMenuItem(value: p, child: Text('${entry.key}: ${p.label}', overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (p) {
                    if (p != null) {
                      fields['Longueur feuille caissons (mm)']!.text = '${p.length}';
                      fields['Largeur feuille caissons (mm)']!.text = '${p.width}';
                    }
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: Tokens.s3),
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: frontMaterialChoices.contains(frontMat) ? frontMat : frontMaterialChoices.first,
                  decoration: InputDecoration(labelText: tr('Matériau des façades'), border: const OutlineInputBorder(), isDense: true),
                  items: [for (final m in frontMaterialChoices) DropdownMenuItem(value: m, child: Text(tr(m), overflow: TextOverflow.ellipsis))],
                  onChanged: (v) {
                    if (v == null) return;
                    frontMat = v;
                    final cat = v.contains('High Gloss') || v.contains('Acrylique') || v.contains('PET') ? 'High Gloss / Acrylique' : 'MDF';
                    final p = woodSheetPresets[cat]?.first;
                    if (p != null) {
                      fields['Longueur feuille façades (mm)']!.text = '${p.length}';
                      fields['Largeur feuille façades (mm)']!.text = '${p.width}';
                    }
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: Tokens.s3),
                child: DropdownButtonFormField<SheetPreset>(
                  isExpanded: true,
                  hint: Text(tr('Choisir un format prédéfini de façade')),
                  decoration: InputDecoration(labelText: tr('Presets feuille façades'), border: const OutlineInputBorder(), isDense: true),
                  items: [
                    for (final entry in woodSheetPresets.entries)
                      ...entry.value.map((p) => DropdownMenuItem(value: p, child: Text('${entry.key}: ${p.label}', overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (p) {
                    if (p != null) {
                      fields['Longueur feuille façades (mm)']!.text = '${p.length}';
                      fields['Largeur feuille façades (mm)']!.text = '${p.width}';
                    }
                  },
                ),
              ),
              for (final e in fields.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: Tokens.s3),
                  child: TextField(
                    controller: e.value,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(labelText: e.key, border: const OutlineInputBorder(), isDense: true),
                  ),
                ),
              if (st.db != null) ...[
                const SizedBox(height: Tokens.s4),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: panel,
                  decoration: InputDecoration(labelText: tr('Type de panneau (catalogue)'), border: OutlineInputBorder(), isDense: true),
                  items: [for (final pt in st.db!.panels) DropdownMenuItem(value: pt.id, child: Text(tr(pt.name), overflow: TextOverflow.ellipsis))],
                  onChanged: (v) {
                    panel = v!;
                    final pt = st.db!.panel(v)!;
                    // format proposé : 2800 x 2100 si le panneau existe dans ce format, sinon le premier
                    final sheet = pt.sheets.contains((2800, 2100)) ? (2800, 2100) : pt.sheets.first;
                    fields['Longueur feuille caissons (mm)']!.text = '${sheet.$1}';
                    fields['Largeur feuille caissons (mm)']!.text = '${sheet.$2}';
                  },
                ),
                const SizedBox(height: Tokens.s3),
                if (PublicPrices.structural.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    key: const ValueKey('public_panel'),
                    isExpanded: true,
                    decoration: InputDecoration(
                        labelText: tr('Panneau au prix public'),
                        helperText: tr('remplit le prix, le format de la feuille et l’épaisseur'),
                        border: const OutlineInputBorder(),
                        isDense: true),
                    items: [
                      for (final p in PublicPrices.structural)
                        DropdownMenuItem(value: p.id, child: Text('${tr(p.name)} · ${p.length ~/ 10} x ${p.width ~/ 10} · ${p.price.round()} MAD', overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) {
                      final p = PublicPrices.byId(v ?? '');
                      if (p == null) return;
                      prices[_kSheetPrice]!.text = '${p.price.round()}';
                      fields['Longueur feuille caissons (mm)']!.text = '${p.length}';
                      fields['Largeur feuille caissons (mm)']!.text = '${p.width}';
                      fields['Épaisseur caisson (mm)']!.text = '${p.thickness}';
                      final e = PublicPrices.edgeRange;
                      if (e != null) {
                        prices['Chant posé, min (MAD/m)']!.text = '${e.$1}';
                        prices['Chant posé, max (MAD/m)']!.text = '${e.$2}';
                      }
                    },
                  ),
                  const SizedBox(height: Tokens.s3),
                ],
                for (final e in prices.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Tokens.s3),
                    child: TextField(
                      controller: e.value,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: e.key, border: OutlineInputBorder(), isDense: true, helperText: e.key.startsWith('Prix') ? tr('vide = fourchette du catalogue') : null),
                    ),
                  ),
                DropdownButtonFormField<String>(
                  initialValue: {...st.db!.hardwareBrands, ...BrandCatalog.hardwareBrands}.contains(brand) ? brand : st.db!.hardwareBrands.first,
                  decoration: InputDecoration(labelText: tr('Marque de quincaillerie'), border: OutlineInputBorder(), isDense: true),
                  items: [for (final b in {...BrandCatalog.hardwareBrands, ...st.db!.hardwareBrands}) DropdownMenuItem(value: b, child: Text(b))],
                  onChanged: (v) => brand = v!,
                ),
                SizedBox(height: Tokens.s3),
                DropdownButtonFormField<int>(
                  initialValue: tier,
                  decoration: InputDecoration(labelText: tr('Gamme d\'électroménager'), border: OutlineInputBorder(), isDense: true),
                  items: [
                    DropdownMenuItem(value: 0, child: Text(tr('Entrée de gamme'))),
                    DropdownMenuItem(value: 1, child: Text(tr('Milieu de gamme'))),
                    DropdownMenuItem(value: 2, child: Text(tr('Haut de gamme'))),
                  ],
                  onChanged: (v) => tier = v!,
                ),
              ],
              SizedBox(height: Tokens.s3),
              StatefulBuilder(
                builder: (ctx, setS) => Column(children: [
                  DropdownButtonFormField<String>(
                    initialValue: machine,
                    decoration: InputDecoration(labelText: tr('Machine'), border: OutlineInputBorder(), isDense: true),
                    items: [
                      DropdownMenuItem(value: 'scie', child: Text(tr('Scie à panneaux (bandes, tronçons, recoupes)'))),
                      DropdownMenuItem(value: 'cnc', child: Text(tr('CNC (imbrication libre)'))),
                    ],
                    onChanged: (v) => setS(() => machine = v!),
                  ),
                  const SizedBox(height: Tokens.s3),
Align(alignment: Alignment.centerLeft, child: Text(tr('Méthode de débit'), style: Theme.of(ctx).textTheme.labelLarge)),
                  const SizedBox(height: Tokens.s2),
                  CutModePicker(method: method, onChanged: (m) => setS(() => method = m)),
                  SizedBox(height: Tokens.s2),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(tr('Fond arrière rainuré (panneau mince)')),
                    subtitle: Text(tr('sinon : caisson sans fond, comme à l’atelier')),
                    value: backPanel,
                    onChanged: (v) => setS(() => backPanel = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(tr('Traverses hautes au lieu d’un dessus plein (bas)')),
                    value: rails,
                    onChanged: (v) => setS(() => rails = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(tr('Étagères dans le débit')),
                    value: shelves,
                    onChanged: (v) => setS(() => shelves = v),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: drawers,
                    decoration: InputDecoration(labelText: tr('Tiroirs'), border: OutlineInputBorder(), isDense: true),
                    items: [
                      DropdownMenuItem(value: 'bois', child: Text(tr('Caisson de tiroir en panneaux'))),
                      DropdownMenuItem(value: 'metal', child: Text(tr('Côtés métal (fond et dos bois 16 mm)'))),
                    ],
                    onChanged: (v) => setS(() => drawers = v!),
                  ),
                ]),
              ),
              const SizedBox(height: Tokens.s3),
              Text(tr('La profondeur des pièces du caisson est égale à la profondeur du meuble moins l\'épaisseur de la porte.'),
                  style: Theme.of(ctx).textTheme.bodySmall),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Annuler'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Enregistrer'))),
        ],
      ),
    );
    if (ok != true) return;
    int v(String k, int d) {
      final x = int.tryParse(fields[k]!.text);
      return x == null || x <= 0 ? d : x;
    }

    st.edit(() {
      cs
        ..sheetLength = v('Longueur feuille caissons (mm)', cs.sheetLength)
        ..sheetWidth = v('Largeur feuille caissons (mm)', cs.sheetWidth)
        ..frontSheetLength = v('Longueur feuille façades (mm)', fL)
        ..frontSheetWidth = v('Largeur feuille façades (mm)', fW)
        ..kerf = v('Trait de scie (mm)', cs.kerf)
        ..trim = int.tryParse(fields['Recoupe des bords (mm)']!.text) ?? cs.trim
        ..carcassThickness = v('Épaisseur caisson (mm)', cs.carcassThickness)
        ..doorThickness = v('Épaisseur porte MDF (mm)', cs.doorThickness)
        ..frontGap = int.tryParse(fields['Jeu vertical des façades (mm)']!.text) ?? cs.frontGap
        ..gapH = int.tryParse(fields['Jeu horizontal des façades (mm)']!.text) ?? cs.gapH
        ..gapBetween = int.tryParse(fields['Jeu entre deux portes (mm)']!.text) ?? cs.gapBetween
        ..golaTop = int.tryParse(fields['Retrait Gola, façade du haut (mm)']!.text) ?? cs.golaTop
        ..golaMid = int.tryParse(fields['Retrait Gola, façades suivantes (mm)']!.text) ?? cs.golaMid
        ..backThickness = v('Épaisseur du fond arrière (mm)', cs.backThickness)
        ..grooveDepth = int.tryParse(fields['Profondeur de rainure du fond (mm)']!.text) ?? cs.grooveDepth
        ..backMaterial = 'HDF ${v('Épaisseur du fond arrière (mm)', cs.backThickness)} mm'
        ..backPanel = backPanel
        ..includeRails = rails
        ..includeShelves = shelves
        ..drawerSystem = drawers
        ..machine = machine
        ..method = method
        ..carcassMaterial = carcassMat
        ..frontMaterial = frontMat;
      double? pv(String k) => double.tryParse(prices[k]!.text.replaceAll(',', '.'));
      sp
        ..carcassPanel = panel
        ..frontPanel = panel
        ..sheetPrice = pv('Prix d\'une feuille (MAD)')
        ..edgePriceMin = pv('Chant posé, min (MAD/m)')
        ..edgePriceMax = pv('Chant posé, max (MAD/m)')
        ..cuttingPerSheet = pv('Découpe par feuille (MAD)') ?? 0
        ..hardwareBrand = brand
        ..applianceTier = tier;
    });
    _msg(tr('Réglages du débit enregistrés'));
  }

  void _issues() => _scaffold.currentState?.openEndDrawer();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: st,
      builder: (context, _) {
        final width = MediaQuery.sizeOf(context).width;
        final narrow = width < 900;
        final scheme = Theme.of(context).colorScheme;

        final hasSelection = st.selectedItem != null || st.selectedOpeningObj != null || st.selectedPointObj != null || st.selectedObjectObj != null;
        // un seul panneau à la fois : catalogue ou finitions à gauche, sinon la fiche de l'élément choisi
        Widget? leftPanel;
        if (st.step != PlanStep.summary && st.objectsPanel) {
          leftPanel = ObjectsPanel(key: const ValueKey('objects'), state: st, onMessage: _msg);
        } else if (st.step == PlanStep.layout && st.browse != null) {
          leftPanel = CatalogPanel(key: const ValueKey('catalog'), state: st, onMessage: _msg);
        } else if (st.step == PlanStep.style && !hasSelection) {
          leftPanel = StylePanel(state: st, section: _styleSection);
        }

        final canvas = CallbackShortcuts(
          bindings: _shortcuts,
          child: Focus(
            focusNode: _canvasFocus,
            autofocus: true,
            child: Listener(
              onPointerDown: (_) {
                _canvasFocus.requestFocus();
                if (st.megaMenu) st.toggleMegaMenu(false);
              },
              child: PlannerCanvas(state: st, onMessage: _msg),
            ),
          ),
        );

        // tablette et écran moyen : la fiche de l'élément prend sa place à droite au lieu de cacher le plan
        // panneau d'ajout épinglé : la fiche du meuble touché s'ouvre à droite, le panneau reste à gauche
        final inspectorOpen = hasSelection && !st.megaMenu && (leftPanel == null || (st.browsePinned && leftPanel is CatalogPanel));
        final side = inspectorOpen && width < 1300 ? 380 + Tokens.s3 * 2 : 0.0;
        final stage = Stack(children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            right: side,
            child: st.step == PlanStep.summary ? TechPreview(state: st, real3dView: canvas) : canvas,
          ),
          if (narrow && leftPanel != null)
            Positioned(left: 0, top: 0, bottom: 0, width: width.clamp(0, 380).toDouble(), child: leftPanel),
          if (st.megaMenu)
            Positioned(
                left: Tokens.s3, top: Tokens.s2, right: Tokens.s3, child: Align(alignment: Alignment.topLeft, child: MegaMenu(state: st, onMessage: _msg))),
          if (inspectorOpen)
            Positioned(
                right: Tokens.s3,
                top: Tokens.s3,
                bottom: Tokens.s3,
                child: st.selectedObjectObj != null ? ObjectCard(state: st, onMessage: _msg) : InspectorCard(state: st, onMessage: _msg)),
          if (st.step != PlanStep.summary)
            Positioned(
                left: Tokens.s3,
                right: side + (narrow ? Tokens.s3 : 90),
                bottom: Tokens.s4,
                child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: ViewSwitcher(state: st)))),
          if (!narrow && st.step != PlanStep.summary)
            Positioned(right: inspectorOpen ? 380 + Tokens.s3 * 2 : Tokens.s4, bottom: Tokens.s4, child: ZoomControls(state: st)),
          if (st.project.items.isEmpty && st.step == PlanStep.layout && st.browse == null && !st.megaMenu)
            Positioned(
              top: Tokens.s4,
              left: 0,
              right: 0,
              child: Center(
                child: Material(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(24),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Tokens.s4, vertical: Tokens.s2),
                    child: Text(
                        st.engine.kitchen
                            ? tr('Ouvrez « Ajouter des meubles » ou « Propositions / remplir » pour commencer')
                            : tr('Ouvrez « Ajouter des meubles » pour poser vos meubles'),
                        style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ),
        ]);

        return Scaffold(
        // tablette : le clavier passe par-dessus la scène, il ne la rétrécit pas
        resizeToAvoidBottomInset: false,
          key: _scaffold,
          endDrawer: Drawer(
            width: 400,
            child: SafeArea(
              child: ListView(padding: const EdgeInsets.all(Tokens.s4), children: [
                Text(tr('Contrôles'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: Tokens.s3),
                IssuesList(state: st, onPick: () => Navigator.of(context).maybePop()),
              ]),
            ),
          ),
          body: SafeArea(
            child: Column(children: [
              StepHeader(
                state: st,
                onOpen: _open,
                onSave: _save,
                onSaveAs: _saveAs,
                onNew: _newProjectWithClient,
                onQuit: () => Navigator.of(context).maybePop(),
                onDownload: _download,
                onClient: () => showClientDialog(context, st, _msg),
                onIssues: _issues,
                themeMode: widget.themeMode,
                onThemeMode: widget.onThemeMode,
              ),
              const Divider(),
              StepToolbar(
                state: st,
                onMessage: _msg,
                styleSection: _styleSection,
                onStyleSection: (s) {
                  st.select(null); // rouvre le panneau des finitions
                  setState(() => _styleSection = s);
                },
                onExportCsv: _exportCsv,
                onExportExcel: _exportExcel,
                onExportPdf: _exportPdf,
                onCutPdf: _cutPdf,
                onGenerateCodes: _generateCodes,
                onSct: _sct,
                onManualCut: () => openManualCut(context, st),
                onCutSettings: _cutSettings,
                onSave: _save,
                onIssues: _issues,
              ),
              const Divider(),
              Expanded(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (!narrow && leftPanel != null) ...[
                    SizedBox(width: 380, child: leftPanel),
                    const VerticalDivider(width: 1),
                  ],
                  Expanded(child: stage),
                  if (st.step == PlanStep.summary) ...[
                    const VerticalDivider(width: 1),
                    SizedBox(width: narrow ? width * 0.55 : 460, child: SummaryPanel(state: st)),
                  ],
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }
}
