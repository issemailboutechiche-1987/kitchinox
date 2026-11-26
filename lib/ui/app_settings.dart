// Paramètres de l'application (gardés d'une session à l'autre, pour tous les projets) :
// langue de l'interface, unité des cotes, numérotation automatique des plans.
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../engine/engine.dart';
import 'web_io.dart';

enum AppLang {
  fr('Français', 'fr'),
  en('English', 'en'),
  ar('العربية', 'ar');

  final String label, code;
  const AppLang(this.label, this.code);
  bool get rtl => this == AppLang.ar;
  String get localizedName => switch (this) {
    AppLang.fr => 'Français',
    AppLang.en => 'English',
    AppLang.ar => 'العربية',
  };
}

enum LenUnit {
  mm('mm', 'millimètres'),
  cm('cm', 'centimètres'),
  inch('"', 'pouces');

  final String symbol, name;
  const LenUnit(this.symbol, this.name);
}

/// Type de document numéroté.
enum DocKind {
  exec('PE', "plan d'exécution"),
  cut('PD', 'plan de découpe'),
  quote('DV', 'devis');

  final String defaultPrefix, label;
  const DocKind(this.defaultPrefix, this.label);
}

class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final instance = AppSettings._();
  static const _key = 'kitchinox.settings';

  AppLang lang = AppLang.fr;

  /// Langue des documents (PDF) ; null : celle de l'interface.
  AppLang? docLang;
  LenUnit unit = LenUnit.mm;

  // numérotation automatique : PE-2026-0001, PD-2026-0001…
  bool numbering = true;
  bool withYear = true;
  int digits = 4;
  final Map<DocKind, String> prefix = {for (final k in DocKind.values) k: k.defaultPrefix};
  final Map<DocKind, int> next = {for (final k in DocKind.values) k: 1};
  int counterYear = DateTime.now().year;

  /// Vue 3D : fond de scène, mode d'affichage ('real' réaliste, 'sketch' croquis), réseaux tracés.
  String sceneBg = 'clair';
  String look3d = 'real';
  bool nets3d = false;
  bool shadows3d = true; // ombres de la vue 3D
  bool reflect3d = true; // reflets de la vue 3D
  String rayLight = 'mixte'; // lancer de rayons : soleil, plafonnier ou mixte
  String hdri = 'studio'; // environnement des reflets : studio, interieur, exterieur (HDRI)

  /// [deviceLang] : langue de l'appareil (« fr », « en », « ar »), prise au premier lancement.
  void load({String? deviceLang}) {
    final raw = storeGet(_key);
    if (raw == null) {
      lang = AppLang.values.firstWhere((l) => l.code == deviceLang, orElse: () => AppLang.fr);
      return;
    }
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      lang = AppLang.values.firstWhere((l) => l.code == j['lang'], orElse: () => AppLang.fr);
      docLang = AppLang.values.where((l) => l.code == j['doc_lang']).firstOrNull;
      unit = LenUnit.values.firstWhere((u) => u.name == j['unit'] || u.symbol == j['unit'], orElse: () => LenUnit.mm);
      numbering = j['numbering'] as bool? ?? true;
      withYear = j['with_year'] as bool? ?? true;
      digits = (j['digits'] as num?)?.toInt() ?? 4;
      counterYear = (j['year'] as num?)?.toInt() ?? DateTime.now().year;
      sceneBg = j['scene_bg'] as String? ?? 'clair';
      look3d = j['look3d'] as String? ?? 'real';
      nets3d = j['nets3d'] as bool? ?? false;
      shadows3d = j['shadows3d'] as bool? ?? true;
      reflect3d = j['reflect3d'] as bool? ?? true;
      rayLight = j['ray_light'] as String? ?? 'mixte';
      hdri = j['hdri'] as String? ?? 'studio';
      for (final k in DocKind.values) {
        prefix[k] = (j['prefix'] as Map?)?[k.name] as String? ?? k.defaultPrefix;
        next[k] = ((j['next'] as Map?)?[k.name] as num?)?.toInt() ?? 1;
      }
    } catch (_) {
      // réglages illisibles : valeurs par défaut
    }
  }

  void save() {
    storeSet(
        _key,
        jsonEncode({
          'lang': lang.code,
          if (docLang != null) 'doc_lang': docLang!.code,
          'unit': unit.name,
          'numbering': numbering,
          'with_year': withYear,
          'digits': digits,
          'year': counterYear,
          'scene_bg': sceneBg,
          'look3d': look3d,
          'nets3d': nets3d,
          'shadows3d': shadows3d,
          'reflect3d': reflect3d,
          'ray_light': rayLight,
          'hdri': hdri,
          'prefix': {for (final e in prefix.entries) e.key.name: e.value},
          'next': {for (final e in next.entries) e.key.name: e.value},
        }));
    notifyListeners();
  }

  void update(void Function(AppSettings s) change) {
    change(this);
    save();
  }

  /// Numéro tel qu'il sera attribué (sans le consommer).
  String preview(DocKind k, [int? n]) {
    final parts = [
      if (prefix[k]!.trim().isNotEmpty) prefix[k]!.trim(),
      if (withYear) '${DateTime.now().year}',
      '${n ?? next[k]}'.padLeft(math.max(1, digits), '0'),
    ];
    return parts.join('-');
  }

  /// Numéro du document [k] pour [p] : celui déjà attribué au projet (réédition), sinon le suivant.
  /// Null si la numérotation est désactivée.
  String? numberFor(Project p, DocKind k) {
    if (!numbering) return null;
    final have = p.client.numbers[k.name];
    if (have != null && have.isNotEmpty) return have;
    // nouvelle année : la série repart à 1
    if (withYear && counterYear != DateTime.now().year) {
      counterYear = DateTime.now().year;
      for (final kk in DocKind.values) {
        next[kk] = 1;
      }
    }
    final n = preview(k);
    next[k] = next[k]! + 1;
    p.client.numbers[k.name] = n;
    save();
    return n;
  }
}

// ---------------------------------------------------------------- unités

/// Cote [mm] dans l'unité choisie, sans symbole (« 600 », « 60 », « 23 5/8 »).
String lenValue(num mm, {LenUnit? unit}) {
  final u = unit ?? AppSettings.instance.unit;
  switch (u) {
    case LenUnit.mm:
      return '${mm.round()}';
    case LenUnit.cm:
      final v = mm / 10;
      return (v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1)).replaceAll('.', ',');
    case LenUnit.inch:
      // pouces au 1/16 près, comme sur un mètre ruban
      final sixteenths = (mm / 25.4 * 16).round();
      final whole = sixteenths ~/ 16;
      var frac = sixteenths.abs() % 16;
      if (frac == 0) return '$whole';
      var den = 16;
      while (frac.isEven) {
        frac ~/= 2;
        den ~/= 2;
      }
      return whole == 0 ? '$frac/$den' : '$whole $frac/$den';
  }
}

/// Cote avec son unité (« 600 mm », « 60 cm », « 23 5/8" »).
String lenText(num mm, {LenUnit? unit}) {
  final u = unit ?? AppSettings.instance.unit;
  return u == LenUnit.inch ? '${lenValue(mm, unit: u)}"' : '${lenValue(mm, unit: u)} ${u.symbol}';
}

/// Lit une saisie dans l'unité choisie (virgule, point, fractions « 23 5/8 ») ; renvoie des mm.
double? parseLen(String s, {LenUnit? unit}) {
  final u = unit ?? AppSettings.instance.unit;
  var t = s.trim().replaceAll(',', '.').replaceAll('"', '').replaceAll(RegExp(r'\s+'), ' ');
  if (t.isEmpty) return null;
  double? v;
  final frac = RegExp(r'^(?:(\d+(?:\.\d+)?) )?(\d+)/(\d+)$').firstMatch(t);
  if (frac != null) {
    final den = double.parse(frac[3]!);
    if (den == 0) return null;
    v = (frac[1] == null ? 0 : double.parse(frac[1]!)) + double.parse(frac[2]!) / den;
  } else {
    v = double.tryParse(t);
  }
  if (v == null) return null;
  return switch (u) { LenUnit.mm => v, LenUnit.cm => v * 10, LenUnit.inch => v * 25.4 };
}

/// Symbole de l'unité pour un champ de saisie (« mm », « cm », « " »).
String get lenSuffix => AppSettings.instance.unit.symbol;

/// Caractères acceptés dans un champ de cote : chiffres, virgule, point, fractions de pouce.
final lenInputPattern = RegExp(r'[0-9.,/ ]');

/// Plage autorisée, dans l'unité choisie (« 1000 – 15000 mm »).
String lenRange(num min, num max) => '${lenValue(min)} – ${lenText(max)}';

/// Valeur saisie dans un champ de cote, en mm. Si le texte est resté tel qu'affiché, la cote ne change pas :
/// en pouces l'affichage est arrondi au 1/16 (601 mm → « 23 11/16 » → 602 mm), le relire décalerait la pièce.
double? editedLen(String text, num current) => text.trim() == lenValue(current) ? current.toDouble() : parseLen(text);
