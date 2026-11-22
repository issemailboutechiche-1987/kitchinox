/// Plan de travail : un seul choix. Chaque coloris (ce qu'on voit) appartient à une matière et à une ligne de prix
/// (ce qu'on facture) ; le devis, le rendu et les plans partent tous du coloris choisi.
library;

import 'project.dart';

/// Coloris → (matière du tarif, rang du prix dans cette matière).
const worktopLooks = <String, (String, int)>{
  'granit_gris': ('granit_naturel', 0),
  'granit_rose': ('granit_naturel', 1),
  'granit_zimbabwe': ('granit_naturel', 2),
  'granit_noir': ('granit_naturel', 3),
  'granit_labrador': ('granit_naturel', 4),
  'granit_cuir': ('granit_naturel', 5),
  'quartz_blanc': ('quartz_synthese', 0),
  'quartz_gris': ('quartz_synthese', 1),
  'quartz_anthracite': ('quartz_synthese', 1),
  'quartz_beige': ('quartz_synthese', 1),
  'silestone_veine': ('quartz_synthese', 2),
  'terrazzo': ('quartz_synthese', 3),
  'marbre': ('marbre_naturel', 0),
  'marbre_calacatta': ('marbre_naturel', 1),
  'marbre_noir': ('marbre_naturel', 2),
  'marbre_creme': ('marbre_naturel', 3),
  'marbre_emperador': ('marbre_naturel', 4),
  'marbre_vert': ('marbre_naturel', 5),
  'onyx_blanc': ('onyx_naturel', 0),
  'onyx_miel': ('onyx_naturel', 1),
  'onyx_vert': ('onyx_naturel', 2),
  'dekton_noir': ('ceramique_grands_formats', 0),
  'dekton_marbre': ('ceramique_grands_formats', 0),
  'beton': ('ceramique_grands_formats', 1),
  'hpl_noir': ('stratifie_compact_hpl', 0),
  'hpl_blanc': ('stratifie_compact_hpl', 0),
  'hpl_chene': ('stratifie_compact_hpl', 1),
  'hpl_beton': ('stratifie_compact_hpl', 1),
  'corian_blanc': ('solid_surface_corian', 0),
  'corian_gris': ('solid_surface_corian', 0),
};

/// Coloris d'une matière, dans l'ordre du tarif.
List<String> looksOf(String material) {
  final l = [for (final e in worktopLooks.entries) if (e.value.$1 == material) e.key];
  return l;
}

/// Coloris d'une ligne de prix (le premier, s'il y en a plusieurs).
String? lookFor(String material, int variant) {
  for (final e in worktopLooks.entries) {
    if (e.value.$1 == material && e.value.$2 == variant) return e.key;
  }
  return looksOf(material).firstOrNull;
}

/// Matière et prix du plan de travail du projet : ceux de son coloris ; photo importée : la matière choisie à part.
(String, int) worktopOf(Project p) => worktopLooks[p.style.worktop] ?? (p.specs.worktopMaterial, p.specs.worktopVariant);

/// Remet la matière et le prix enregistrés en accord avec le coloris (anciens projets).
void syncWorktop(Project p) {
  final l = worktopLooks[p.style.worktop];
  if (l == null) return;
  p.specs
    ..worktopMaterial = l.$1
    ..worktopVariant = l.$2;
}
