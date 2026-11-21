// Jetons de design : charte kitchinox (orange du logo #F26522, neutres chauds), Flat Design, Plus Jakarta Sans.
// Toutes les couleurs de l'interface passent par ce fichier : aucun code couleur en dur ailleurs.

import 'package:flutter/material.dart';

import '../engine/engine.dart';

/// Charte : orange du logo et ses déclinaisons.
class Brand {
  static const orange = Color(0xFFF26522); // logo
  static const orangeDark = Color(0xFFC94A10); // textes et traits sur fond clair (contraste)
  static const orangeLight = Color(0xFFFF8A4C); // sur fond sombre
  static const ink = Color(0xFF2E2420); // texte principal, brun très foncé
}

class Tokens {
  // rythme d'espacement 4/8
  static const s1 = 4.0, s2 = 8.0, s3 = 12.0, s4 = 16.0, s5 = 24.0, s6 = 32.0;
  static const radius = 10.0;
  static const minTarget = 44.0;
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 200);
}

/// Couleurs propres au plan (caissons, cotes, sol...), déclinées clair / sombre.
@immutable
class PlannerColors extends ThemeExtension<PlannerColors> {
  final Color canvas, room, wallLine, floor, worktop, plinth, dimension, grid;
  final Color base, wall, tall, corner, finish, cabinetStroke, frontLine, selected, gap, profile;
  final Color wallBand, floorWood, floorLine;

  const PlannerColors({
    required this.canvas,
    required this.room,
    required this.wallLine,
    required this.floor,
    required this.worktop,
    required this.plinth,
    required this.dimension,
    required this.grid,
    required this.base,
    required this.wall,
    required this.tall,
    required this.corner,
    required this.finish,
    required this.cabinetStroke,
    required this.frontLine,
    required this.selected,
    required this.gap,
    required this.profile,
    required this.wallBand,
    required this.floorWood,
    required this.floorLine,
  });

  static const light = PlannerColors(
    canvas: Color(0xFFF7F4F1),
    room: Color(0xFFFFFFFF),
    wallLine: Color(0xFF3B2E27),
    floor: Color(0xFFA8A29E),
    worktop: Color(0xFF57534E),
    plinth: Color(0xFF78716C),
    dimension: Color(0xFF57534E),
    grid: Color(0xFFEDE7E2),
    base: Color(0xFFFDE4D3),
    wall: Color(0xFFFFF1E7),
    tall: Color(0xFFF4E3D7),
    corner: Color(0xFFFEF0C7),
    finish: Color(0xFFF5F2EF),
    cabinetStroke: Color(0xFF3B2E27),
    frontLine: Color(0xFFC94A10),
    selected: Color(0xFF1D4ED8),
    gap: Color(0xFFF26522),
    profile: Color(0xFFD6D0CB),
    wallBand: Color(0xFFD6D1CC),
    floorWood: Color(0xFFEBCFA6),
    floorLine: Color(0xFFDDBD90),
  );

  static const dark = PlannerColors(
    canvas: Color(0xFF14100E),
    room: Color(0xFF1E1916),
    wallLine: Color(0xFFFFD6BF),
    floor: Color(0xFF78716C),
    worktop: Color(0xFFA8A29E),
    plinth: Color(0xFF57534E),
    dimension: Color(0xFFD6D3D1),
    grid: Color(0xFF2A221E),
    base: Color(0xFF5A2A12),
    wall: Color(0xFF3F2618),
    tall: Color(0xFF3A2B23),
    corner: Color(0xFF6B4A12),
    finish: Color(0xFF3A3431),
    cabinetStroke: Color(0xFFFFD6BF),
    frontLine: Color(0xFFFF8A4C),
    selected: Color(0xFF60A5FA),
    gap: Color(0xFFFF8A4C),
    profile: Color(0xFF3A3431),
    wallBand: Color(0xFF4A423D),
    floorWood: Color(0xFFB99A72),
    floorLine: Color(0xFFA5865F),
  );

  Color fill(CabinetKind k) {
    switch (k) {
      case CabinetKind.base:
        return base;
      case CabinetKind.wall:
        return wall;
      case CabinetKind.tall:
        return tall;
      case CabinetKind.cornerBase:
      case CabinetKind.cornerWall:
      case CabinetKind.cornerTall:
        return corner;
      case CabinetKind.fillerBase:
      case CabinetKind.fillerWall:
      case CabinetKind.coverPanel:
      case CabinetKind.islandPanel:
        return finish;
    }
  }

  @override
  PlannerColors copyWith() => this;

  @override
  PlannerColors lerp(ThemeExtension<PlannerColors>? other, double t) =>
      (other is PlannerColors && t >= 0.5) ? other : this;
}

ThemeData buildTheme(Brightness b, {bool googleFonts = true}) {
  final isLight = b == Brightness.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.orange,
    brightness: b,
  ).copyWith(
    // orange du logo pour les boutons pleins ; version foncée pour les textes et contours (lisibilité)
    primary: isLight ? Brand.orange : Brand.orangeLight,
    onPrimary: isLight ? Colors.white : const Color(0xFF2A1205),
    primaryContainer: isLight ? const Color(0xFFFDE4D3) : const Color(0xFF5A2A12),
    onPrimaryContainer: isLight ? const Color(0xFF5A2208) : const Color(0xFFFFD6BF),
    secondary: isLight ? Brand.orangeDark : const Color(0xFFFFB38A),
    secondaryContainer: isLight ? const Color(0xFFFFEDE2) : const Color(0xFF4A2A1A),
    onSecondaryContainer: isLight ? const Color(0xFF5A2208) : const Color(0xFFFFE3D3),
    tertiary: isLight ? const Color(0xFFB45309) : const Color(0xFFFBBF24), // avertissements : ambre
    onTertiary: isLight ? Colors.white : const Color(0xFF3A2003),
    error: isLight ? const Color(0xFFDC2626) : const Color(0xFFF87171),
    surface: isLight ? Colors.white : const Color(0xFF1A1513),
    onSurface: isLight ? Brand.ink : const Color(0xFFF5EDE8),
    onSurfaceVariant: isLight ? const Color(0xFF6B5E57) : const Color(0xFFD6CCC6),
    outline: isLight ? const Color(0xFFB9ABA3) : const Color(0xFF7A6D66),
    outlineVariant: isLight ? const Color(0xFFEBDDD3) : const Color(0xFF3D332E),
  );
  final baseText = ThemeData(brightness: b).textTheme;
  // police intégrée à l'app (hors tests : police de test par défaut)
  final text = googleFonts ? baseText.apply(fontFamily: 'Jakarta', fontFamilyFallback: const ['JakartaExt']) : baseText;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: text,
    scaffoldBackgroundColor: isLight ? const Color(0xFFF7F4F1) : const Color(0xFF14100E),
    extensions: [isLight ? PlannerColors.light : PlannerColors.dark],
    // Flat : pas d'ombres
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radius),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      elevation: 0,
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primary.withValues(alpha: 0.16),
      height: 64,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStatePropertyAll(
        (text.labelSmall ?? const TextStyle()).copyWith(fontSize: 12, letterSpacing: 0, fontWeight: FontWeight.w600),
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1),
    tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 400)),
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );
}

extension PlannerTheme on BuildContext {
  PlannerColors get pc =>
      Theme.of(this).extension<PlannerColors>() ?? (Theme.of(this).brightness == Brightness.dark ? PlannerColors.dark : PlannerColors.light);
}
