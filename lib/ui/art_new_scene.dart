// Nouvelle scène du mode Art : feuille au format standard ou personnalisée, meuble depuis une feuille (recette
// paramétrique : caisson bas, haut, colonne, étagère…), caisson de base ou scène vide.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/art_recipes.dart';
import 'i18n.dart';

class NewArtScene {
  final String kind; // sheet | recipe | box | empty
  final double? length, width, thickness;
  final String? recipe; // recette choisie
  final Map<String, double> params; // ses paramètres
  const NewArtScene(this.kind, {this.length, this.width, this.thickness, this.recipe, this.params = const {}});
}

/// Formats de feuilles courants (mm) : MDF, mélaminé, contreplaqué, latté.
const standardSheets = <(String, double, double)>[
  ('2800 × 2070 (mélaminé, MDF)', 2800, 2070),
  ('2750 × 1830 (MDF, aggloméré)', 2750, 1830),
  ('2440 × 1220 (contreplaqué, MDF)', 2440, 1220),
  ('2500 × 1250 (latté, contreplaqué)', 2500, 1250),
  ('3050 × 1220 (MDF long)', 3050, 1220),
  ('2800 × 2100 (mélaminé)', 2800, 2100),
  ('1220 × 610 (demi-feuille)', 1220, 610),
];
const standardThicknesses = [8.0, 10.0, 12.0, 16.0, 18.0, 19.0, 22.0, 25.0, 30.0];

class NewArtSceneDialog extends StatefulWidget {
  /// Seulement le choix d'un meuble (la feuille est déjà posée) : pas de format ni d'épaisseur.
  final bool recipeOnly;
  final String? initialRecipe;

  /// Type déjà choisi (« sheet », « recipe ») : le dialogue ne le redemande pas.
  final String? fixedKind;
  const NewArtSceneDialog({super.key, this.recipeOnly = false, this.initialRecipe, this.fixedKind});
  @override
  State<NewArtSceneDialog> createState() => _NewArtSceneDialogState();
}

class _NewArtSceneDialogState extends State<NewArtSceneDialog> {
  late String kind = widget.recipeOnly ? 'recipe' : widget.fixedKind ?? 'sheet';
  int preset = 0; // index de standardSheets, -1 : personnalisée
  double thickness = 18;
  final l = TextEditingController(text: '2000'), w = TextEditingController(text: '1000');
  late String? recipeId = ArtRecipes.all.isEmpty ? null : (ArtRecipes.byId(widget.initialRecipe ?? 'bas_1p') ?? ArtRecipes.all.first).id;
  final fields = <String, TextEditingController>{}; // paramètres de la recette choisie

  @override
  void initState() {
    super.initState();
    _loadParams();
  }

  void _loadParams() {
    for (final c in fields.values) {
      c.dispose();
    }
    fields.clear();
    final r = recipeId == null ? null : ArtRecipes.byId(recipeId!);
    if (r == null) return;
    for (final p in r.params) {
      fields[p.id] = TextEditingController(text: '${p.value.round()}');
    }
  }

  @override
  void dispose() {
    for (final c in [l, w, ...fields.values]) {
      c.dispose();
    }
    super.dispose();
  }

  NewArtScene? get _result {
    if (kind != 'sheet' && kind != 'recipe') return NewArtScene(kind);
    double? ll, ww;
    if (preset >= 0) {
      (ll, ww) = (standardSheets[preset].$2, standardSheets[preset].$3);
    } else {
      ll = double.tryParse(l.text.trim());
      ww = double.tryParse(w.text.trim());
      if (ll == null || ww == null || ll < 100 || ww < 100 || ll > 5000 || ww > 3000) return null;
    }
    if (kind == 'sheet') return NewArtScene('sheet', length: ll, width: ww, thickness: thickness);
    final r = recipeId == null ? null : ArtRecipes.byId(recipeId!);
    if (r == null) return null;
    final params = <String, double>{};
    for (final p in r.params) {
      final v = double.tryParse(fields[p.id]?.text.trim() ?? '');
      if (v == null || v < p.min || v > p.max) return null;
      params[p.id] = v;
    }
    return NewArtScene('recipe', length: ll, width: ww, thickness: thickness, recipe: r.id, params: params);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    Widget num(String label, TextEditingController c, String key, {String? help}) => SizedBox(
          width: 150,
          child: TextField(
            key: ValueKey(key),
            controller: c,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: tr(label), helperText: help, suffixText: 'mm', isDense: true, border: const OutlineInputBorder()),
          ),
        );
    final recipe = recipeId == null ? null : ArtRecipes.byId(recipeId!);
    return AlertDialog(
      title: Text(tr(switch (widget.fixedKind) { 'recipe' => 'Meuble à vos mesures', 'sheet' => 'Feuille à découper', _ => widget.recipeOnly ? 'Meuble depuis cette feuille' : 'Nouvelle création' })),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (!widget.recipeOnly && widget.fixedKind == null) ...[
              SegmentedButton<String>(
                key: const ValueKey('new_kind'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'sheet', label: Text(tr('Feuille')), icon: const Icon(Icons.crop_landscape, size: 16)),
                  ButtonSegment(value: 'recipe', label: Text(tr('Meuble')), icon: const Icon(Icons.door_front_door_outlined, size: 16)),
                  ButtonSegment(value: 'box', label: Text(tr('Caisson de base')), icon: const Icon(Icons.kitchen_outlined, size: 16)),
                  ButtonSegment(value: 'empty', label: Text(tr('Scène vide')), icon: const Icon(Icons.crop_free, size: 16)),
                ],
                selected: {kind},
                onSelectionChanged: (v) => setState(() => kind = v.first),
              ),
              const SizedBox(height: 14),
            ],
            if (kind == 'recipe') ...[
              if (ArtRecipes.all.isEmpty) Text(tr('Aucune recette disponible'), style: t.bodySmall),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final r in ArtRecipes.all)
                  ChoiceChip(
                    key: ValueKey('recipe_${r.id}'),
                    label: Text(tr(r.name)),
                    selected: recipeId == r.id,
                    onSelected: (_) => setState(() {
                      recipeId = r.id;
                      _loadParams();
                    }),
                  ),
              ]),
              if (recipe != null) ...[
                const SizedBox(height: 8),
                Text(tr(recipe.description), style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 12, children: [
                  for (final p in recipe.params) num(p.name, fields[p.id]!, 'param_${p.id}', help: '${p.min.round()} – ${p.max.round()}'),
                ]),
                const SizedBox(height: 14),
              ],
            ],
            if (!widget.recipeOnly && (kind == 'sheet' || kind == 'recipe')) ...[
              Text(tr('Format de la feuille'), style: t.labelLarge),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (var i = 0; i < standardSheets.length; i++)
                  ChoiceChip(
                    key: ValueKey('new_sheet_$i'),
                    label: Text(tr(standardSheets[i].$1)),
                    selected: preset == i,
                    onSelected: (_) => setState(() => preset = i),
                  ),
                ChoiceChip(
                  key: const ValueKey('new_sheet_custom'),
                  label: Text(tr('Personnalisée')),
                  selected: preset < 0,
                  onSelected: (_) => setState(() => preset = -1),
                ),
              ]),
              if (preset < 0) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 8, children: [num('Longueur', l, 'new_l'), num('Largeur', w, 'new_w')]),
              ],
              const SizedBox(height: 12),
              Text(tr('Épaisseur'), style: t.labelLarge),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final th in standardThicknesses)
                  ChoiceChip(label: Text('${th.round()} mm'), selected: thickness == th, onSelected: (_) => setState(() => thickness = th)),
              ]),
              const SizedBox(height: 10),
            ],
            if (kind == 'recipe')
              Text(tr('Les pièces sont coupées à la guillotine (une feuille de plus si besoin) et les liaisons notées : vérifiez l’aperçu 3D, puis « Monter le meuble » pose vis, tourillons, charnières, pieds et plinthe.'),
                  style: t.bodySmall)
            else if (kind == 'sheet')
              Text(tr('La feuille se pose à plat en vue de dessus : coupez-la en X ou en Y, puis liez les chants des pièces et usinez.'), style: t.bodySmall)
            else if (kind == 'box')
              Text(tr('Choisissez une base (caisson, colonne, étagère…), puis divisez-la en colonnes et en étagères.'), style: t.bodySmall)
            else
              Text(tr('Une scène vide : dessinez des panneaux librement avec les outils.'), style: t.bodySmall),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Annuler'))),
        FilledButton(
          key: const ValueKey('new_ok'),
          onPressed: _result == null ? null : () => Navigator.pop(context, _result),
          child: Text(tr(widget.recipeOnly ? 'Couper et lier' : 'Créer')),
        ),
      ],
    );
  }
}
