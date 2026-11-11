// Langues (français, anglais, arabe), unités (mm, cm, pouces), fiche client (ICE), numérotation des plans.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_planner/engine/engine.dart';
import 'package:kitchen_planner/main.dart';
import 'package:kitchen_planner/ui/app_settings.dart';
import 'package:kitchen_planner/ui/app_state.dart';
import 'package:kitchen_planner/ui/i18n.dart';
import 'package:kitchen_planner/ui/i18n_dict.dart';
import 'package:kitchen_planner/ui/cut_pdf.dart';
import 'package:kitchen_planner/ui/tech_drawings.dart';

void main() {
  final s = AppSettings.instance;
  tearDown(() {
    s
      ..lang = AppLang.fr
      ..unit = LenUnit.mm
      ..numbering = true
      ..withYear = true
      ..digits = 4;
    for (final k in DocKind.values) {
      s.prefix[k] = k.defaultPrefix;
      s.next[k] = 1;
    }
  });

  test('unités : affichage et saisie en mm, cm, pouces (fractions au 1/16)', () {
    expect(lenText(600, unit: LenUnit.mm), '600 mm');
    expect(lenText(600, unit: LenUnit.cm), '60 cm');
    expect(lenValue(605, unit: LenUnit.cm), '60,5');
    expect(lenText(600, unit: LenUnit.inch), '23 5/8"');
    expect(lenValue(25.4, unit: LenUnit.inch), '1');
    expect(lenValue(12.7, unit: LenUnit.inch), '1/2');
    expect(parseLen('60,5', unit: LenUnit.cm), closeTo(605, 1e-9));
    expect(parseLen('23 5/8', unit: LenUnit.inch), closeTo(600.075, 1e-6));
    expect(parseLen('3/4"', unit: LenUnit.inch), closeTo(19.05, 1e-9));
    expect(parseLen('720', unit: LenUnit.mm), 720);
    expect(parseLen('abc', unit: LenUnit.mm), isNull);
    expect(parseLen('1/0', unit: LenUnit.inch), isNull);
  });

  test('numérotation : PE-année-0001, suite, réédition = même numéro, désactivable', () {
    final y = DateTime.now().year;
    final p1 = Project(), p2 = Project();
    expect(s.preview(DocKind.exec), 'PE-$y-0001');
    expect(s.numberFor(p1, DocKind.exec), 'PE-$y-0001');
    expect(s.numberFor(p1, DocKind.exec), 'PE-$y-0001', reason: 'réédition du même projet');
    expect(s.numberFor(p2, DocKind.exec), 'PE-$y-0002');
    expect(s.numberFor(p1, DocKind.cut), 'PD-$y-0001', reason: 'série propre au plan de découpe');
    s
      ..withYear = false
      ..digits = 3
      ..prefix[DocKind.cut] = 'DEC';
    expect(s.preview(DocKind.cut), 'DEC-002');
    s.numbering = false;
    expect(s.numberFor(Project(), DocKind.exec), isNull);
    // le numéro attribué voyage avec le projet
    final back = Project.fromJson(jsonDecode(jsonEncode(p1.toJson())) as Map<String, dynamic>);
    expect(back.client.numbers['exec'], 'PE-$y-0001');
  });

  test('fiche client : société ou particulier, ICE à 15 chiffres, enregistrée avec le projet', () {
    final p = Project();
    p.client
      ..name = 'Karim Alaoui'
      ..company = 'Atlas Bois SARL'
      ..ice = '001234567000089';
    expect(p.client.label, 'Atlas Bois SARL (Karim Alaoui)');
    expect(ClientInfo.validIce('001234567000089'), isTrue);
    expect(ClientInfo.validIce('001 234 567 000 089'), isTrue);
    expect(ClientInfo.validIce('12345'), isFalse);
    final back = Project.fromJson(jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>);
    expect((back.client.name, back.client.company, back.client.ice), ('Karim Alaoui', 'Atlas Bois SARL', '001234567000089'));
    expect(Project().toJson().containsKey('client'), isFalse, reason: 'rien d\'écrit si la fiche est vide');
  });

  test('traductions : chaque texte de l\'interface a son anglais et son arabe', () {
    // écran (tr, trf, trp) et messages du moteur (L)
    final lit = RegExp(r"""\b(?:tr[fp]?|L)\((\s*(?:'(?:[^'\\\n]|\\.)*'|"(?:[^"\\\n]|\\.)*")\s*)+[,)]""");
    final part = RegExp(r"'((?:[^'\\\n]|\\.)*)'" '|' r'"((?:[^"\\\n]|\\.)*)"');
    final missing = <String>{};
    final files = [
      File('lib/main.dart'),
      for (final d in ['lib/ui', 'lib/engine']) ...Directory(d).listSync().whereType<File>().where((f) => f.path.endsWith('.dart')),
    ];
    for (final f in files) {
      for (final m in lit.allMatches(f.readAsStringSync())) {
        final key = part
            .allMatches(m.group(0)!.substring(m.group(0)!.indexOf('(') + 1))
            .map((p) => (p.group(1) ?? p.group(2)!).replaceAllMapped(RegExp(r'\\(.)'), (e) => e.group(1) == 'n' ? '\n' : e.group(1)!))
            .join();
        // rien à traduire : symboles, valeurs seules (« {0} x {1} »), noms propres
        if (!RegExp('[A-Za-zÀ-ÿ]{2,}').hasMatch(key.replaceAll(RegExp(r'\{\d+\}'), '')) || const {'.sct', 'kitchinox'}.contains(key)) continue;
        if (!enDict.containsKey(key) || !arDict.containsKey(key)) missing.add(key);
      }
    }
    expect(missing, isEmpty);
    s.lang = AppLang.en;
    expect(tr('Fiche client'), 'Client details');
    expect(trf('{n} chiffres', {'n': 4}), '4 digits');
    s.lang = AppLang.ar;
    expect(tr('Paramètres'), 'الإعدادات');
    expect(tr('Texte sans traduction'), 'Texte sans traduction');
  });

  test('messages du moteur traduits (contrôles) une fois branchés sur le dictionnaire', () {
    translateHook = tr;
    addTearDown(() => translateHook = (s) => s);
    final st = AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()));
    st.updateRoom(width: 3600, depth: 3000);
    st.engine.applyShape(RoomShape.linear);
    st.engine.add('base_sink', 'A', s: 0, width: 800);
    st.engine.add('base_cooktop_oven', 'A', s: 1000, width: 600);
    SizeCatalog.parse(File('assets/data/sizes.json').readAsStringSync());
    s.update((s) => s.lang = AppLang.en);
    final en = st.issues.firstWhere((i) => i.code == 'sink_hob_close').message;
    expect(en, startsWith('Sink and hob'));
    s.update((s) => s.lang = AppLang.ar);
    st.refresh();
    final ar = st.issues.firstWhere((i) => i.code == 'sink_hob_close').message;
    expect(ar, contains('المغسلة'), reason: 'le changement de langue recalcule les contrôles');
  });

  testWidgets('PDF en arabe : police Noto Sans Arabic intégrée, textes arabes, lecture de droite à gauche', (t) async {
    final e = LayoutEngine(Catalog.parse(File('assets/catalog.json').readAsStringSync()), Project(room: Room(width: 3600, depth: 3000)));
    e.applyShape(RoomShape.linear);
    e.add('base_sink', 'A', s: 0, width: 800);
    e.add('base_drawers_multi', 'A', s: 800, width: 600);
    final plan = nest(cutList(e, e.project.cut, repereNumbers(e)), e.project.cut);
    s.lang = AppLang.ar;
    final bytes = await t.runAsync(() => buildCutPdf(e, plan, now: DateTime(2026, 11, 10), number: 'PD-2026-0001'));
    final raw = latin1.decode(bytes!, allowInvalid: true);
    expect(raw, contains('NotoSansArabic'), reason: 'police arabe embarquée');
    s.lang = AppLang.fr;
    final fr = await t.runAsync(() => buildCutPdf(e, plan, now: DateTime(2026, 11, 10)));
    expect(latin1.decode(fr!, allowInvalid: true), isNot(contains('NotoSansArabic')), reason: 'en français, rien de plus');
  });

  testWidgets('langue arabe : interface de droite à gauche, textes traduits ; retour au français', (t) async {
    t.view.physicalSize = const Size(1366, 1024);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final st = AppState(Catalog.parse(File('assets/catalog.json').readAsStringSync()));
    await t.pumpWidget(KitchenApp(state: st, googleFonts: false));
    await t.pumpAndSettle();
    expect(find.text('Votre espace'), findsWidgets);
    s.update((s) => s.lang = AppLang.ar);
    await t.pumpAndSettle();
    expect(find.text('مساحتك'), findsWidgets);
    expect(Directionality.of(t.element(find.text('مساحتك').first)), TextDirection.rtl);
    s.update((s) => s.lang = AppLang.en);
    await t.pumpAndSettle();
    expect(find.text('Your space'), findsWidgets);
    expect(Directionality.of(t.element(find.text('Your space').first)), TextDirection.ltr);
    s.update((s) => s.lang = AppLang.fr);
    await t.pumpAndSettle();
    expect(find.text('Votre espace'), findsWidgets);
    expect(t.takeException(), isNull);
  });
}
