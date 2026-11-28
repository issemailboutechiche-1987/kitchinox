// Présentation : les meubles sur fond blanc, complets, avec leurs appareils ou seuls ; images à enregistrer.
// Décor du rendu : choix des objets, montrés ou cachés.
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../engine/engine.dart';
import 'app_state.dart';
import 'hd_render.dart';
import 'i18n.dart';
import 'kx_choices.dart';
import 'theme.dart';
import 'kx_section.dart';
import 'web_io.dart';

const studioModes = {'decor': 'Complet', 'appliances': 'Avec appareils', 'bare': 'Meubles seuls'};

/// Enregistre l'image de la vue 3D affichée.
Future<bool> _save(String name) async {
  final png = await photo3d();
  if (png == null) return false;
  await saveImages([(name, png)]);
  return true;
}

class PresentationBar extends StatefulWidget {
  final AppState state;
  final void Function(String) onMessage;
  const PresentationBar({super.key, required this.state, required this.onMessage});
  @override
  State<PresentationBar> createState() => _PresentationBarState();
}

class _PresentationBarState extends State<PresentationBar> {
  bool busy = false;

  /// Images prêtes : un bouton pour les mettre dans Photos (ou les télécharger).
  Future<void> _offer(List<(String, List<int>)> images) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(trp('{0} image(s) prête(s)', [images.length])),
          content: Text(tr('Sur iPad, choisissez « Enregistrer l’image » pour les mettre dans Photos.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Fermer'))),
            FilledButton.icon(
              key: const ValueKey('save_images'),
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: Text(tr('Enregistrer les images')),
              onPressed: () async {
                await saveImages(images);
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
          ],
        ),
      );

  /// Les trois niveaux, l'un après l'autre : images séparées, ou réunies sur une fiche.
  Future<void> _all({required bool sheet}) async {
    final st = widget.state;
    final was = st.studio;
    setState(() => busy = true);
    final shots = <Uint8List>[];
    final out = <(String, List<int>)>[];
    for (final m in studioModes.keys) {
      st.setStudio(m);
      await Future<void>.delayed(const Duration(milliseconds: 1400)); // la scène se reconstruit
      final png = await photo3d(); // image finale : lancer de rayons
      if (png == null) break;
      shots.add(png);
      if (!sheet) out.add(('${st.project.name}_${m == 'decor' ? 'complet' : m == 'bare' ? 'meubles' : 'appareils'}.png', png));
    }
    if (sheet && shots.length == 3) out.add(('${st.project.name}_fiche.png', await composeSheet(shots, title: st.project.name)));
    st.setStudio(was);
    if (mounted) setState(() => busy = false);
    // le navigateur n'accepte d'enregistrer dans Photos que juste après un toucher : on le demande
    if (out.isNotEmpty && mounted) await _offer(out);
    widget.onMessage(shots.length < 3 ? tr('Image impossible : ouvrez la vue 3D.') : trp('{0} image(s) enregistrée(s)', [sheet ? 1 : 3]));
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('presentation_bar'),
      color: scheme.surface,
      elevation: 4,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Tokens.s3, vertical: Tokens.s2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          KxChoices<String>(
            key: const ValueKey('studio_mode'),
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [for (final e in studioModes.entries) ButtonSegment(value: e.key, label: Text(tr(e.value)))],
            selected: {st.studio},
            onSelectionChanged: busy ? null : (v) => st.setStudio(v.first),
          ),
          const SizedBox(width: Tokens.s3),
          IconButton(
            tooltip: tr('Enregistrer cette image'),
            icon: const Icon(Icons.save_outlined),
            onPressed: busy
                ? null
                : () async {
                    final ok = await _save('${st.project.name}_presentation.png');
                    widget.onMessage(ok ? tr('Image enregistrée') : tr('Image impossible : ouvrez la vue 3D.'));
                  },
          ),
          TextButton.icon(
            key: const ValueKey('studio_sheet'),
            onPressed: busy ? null : () => _all(sheet: true),
            icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.photo_library_outlined, size: 18),
            label: Text(tr('Fiche 3 vues')),
          ),
          TextButton(key: const ValueKey('studio_all'), onPressed: busy ? null : () => _all(sheet: false), child: Text(tr('Les 3 images'))),
          FilledButton.icon(
            key: const ValueKey('studio_hd'),
            onPressed: busy ? null : () => showHdRender(context, st, widget.onMessage),
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: Text(tr('Rendu HD')),
          ),
          IconButton(key: const ValueKey('studio_close'), tooltip: tr('Revenir à la pièce'), icon: const Icon(Icons.close), onPressed: busy ? null : () => st.setStudio('')),
        ]),
      ),
    );
  }
}

/// Fiche « Décor » de l'étape Style.
class DecorPanel extends StatelessWidget {
  final AppState state;
  const DecorPanel({super.key, required this.state});

  /// Emplacements proposés, selon la pièce : avec ou sans plan de travail.
  List<(Set<String>, String)> get _groups => [
        if (state.engine.hasWorktop) (const {'plan'}, 'Sur le plan de travail') else (const {'plan', 'ilot'}, 'Sur le meuble'),
        (const {'niche'}, 'Dans les niches et les vitrines'),
        if (state.engine.hasWorktop) (const {'ilot'}, 'Sur l’îlot ou le meuble'),
        (const {'plaque'}, 'Sur la plaque'),
        (const {'fenetre'}, 'Aux fenêtres'),
        (const {'sol', 'tapis'}, 'Au sol'),
      ];

  /// Vignette d'un objet : l'image du modèle 3D quand il en a une, sinon une icône parlante.
  static Widget _thumb(DecorItem it, ColorScheme scheme) {
    final m = it.model;
    String? img;
    if (m != null && m.startsWith('kenney_')) img = 'web/objects/kenney/thumbs/${m.substring(7)}.png';
    if (m != null && m.startsWith('ph_')) img = 'web/objects/polyhaven/thumbs/${m.substring(3)}.png';
    final icon = switch (it.id) {
      'bouilloire' => Icons.coffee_maker_outlined,
      'planches' => Icons.table_restaurant_outlined,
      'bouteilles' => Icons.liquor_outlined,
      'vaisselle' => Icons.dinner_dining_outlined,
      'fruits' => Icons.shopping_basket_outlined,
      'casserole' => Icons.soup_kitchen_outlined,
      'lessive' => Icons.local_laundry_service_outlined,
      'panier' || 'panier_linge' => Icons.shopping_basket_outlined,
      'savon' => Icons.soap_outlined,
      'serviettes' || 'linge' => Icons.dry_cleaning_outlined,
      'bougies' => Icons.local_fire_department_outlined,
      'vetements' => Icons.checkroom_outlined,
      'livres_niche' => Icons.menu_book_outlined,
      'rideau' => Icons.curtains_outlined,
      'store' => Icons.blinds_outlined,
      _ => Icons.category_outlined,
    };
    final fallback = Icon(icon, size: 30, color: scheme.primary);
    return img == null ? fallback : Image.asset(img, fit: BoxFit.contain, errorBuilder: (_, _, _) => fallback);
  }

  /// Ambiances toutes faites : des listes d'objets (seuls ceux de la pièce sont posés).
  static const _moods = <(String, String, IconData, Set<String>)>[
    ('epure', 'Épurée', Icons.spa_outlined, {'plante', 'fruits', 'vase', 'store', 'serviettes', 'bougies', 'livres'}),
    ('cosy', 'Chaleureuse', Icons.local_cafe_outlined,
        {'cafe', 'planches', 'bouteilles', 'vaisselle', 'fruits', 'plante', 'rideau', 'plante_sol', 'bougies', 'serviettes', 'savon', 'tapis_bain', 'lampe', 'livres', 'livres_niche', 'tapis', 'pouf', 'linge', 'vetements', 'panier', 'lessive'}),
    ('chef', 'Cuisine de chef', Icons.restaurant_outlined, {'cafe', 'blender', 'toaster', 'bouilloire', 'planches', 'bouteilles', 'casserole', 'vaisselle', 'store'}),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final st = state.project.style;
    final items = decorFor(state.project.universe);
    final ids = {for (final it in items) it.id};
    void toggle(DecorItem it, bool v) => state.edit(() {
          v ? st.decor.add(it.id) : st.decor.remove(it.id);
          // rideaux ou stores, pas les deux
          if (v && it.id == 'rideau') st.decor.remove('store');
          if (v && it.id == 'store') st.decor.remove('rideau');
          if (v) st.showDecor = true;
        });
    void mood(Set<String> set) => state.edit(() {
          st.decor
            ..clear()
            ..addAll(set.intersection(ids));
          if (st.decor.contains('rideau') && st.decor.contains('store')) st.decor.remove('rideau');
          st.showDecor = true;
        });
    final on = st.showDecor && st.decor.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // en-tête : afficher, nombre d'objets
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Montrer le décor'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            Text(st.decor.isEmpty ? tr('Il n’entre ni dans le débit, ni dans le devis.') : trp('{0} objet(s) · hors débit et devis', [st.decor.length]),
                style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ]),
        ),
        Switch(key: const ValueKey('decor_show'), value: on, onChanged: (_) => state.toggleDecor()),
      ]),
      const SizedBox(height: Tokens.s2),
      // ambiances en un toucher
      Text(tr('Ambiance'), style: t.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (id, name, icon, set) in _moods)
          if (set.intersection(ids).isNotEmpty)
            () {
              final sel = on && st.decor.isNotEmpty && st.decor.containsAll(set.intersection(ids)) && set.intersection(ids).containsAll(st.decor);
              return InkWell(
                key: ValueKey('decor_mood_$id'),
                borderRadius: BorderRadius.circular(12),
                onTap: () => mood(set),
                child: AnimatedContainer(
                  duration: Tokens.fast,
                  width: 96,
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: sel ? scheme.primary.withValues(alpha: 0.1) : scheme.surfaceContainerLow,
                    border: Border.all(color: sel ? scheme.primary : scheme.outlineVariant, width: sel ? 2 : 1),
                  ),
                  child: Column(children: [
                    Icon(icon, color: scheme.primary),
                    const SizedBox(height: 4),
                    Text(tr(name), textAlign: TextAlign.center, style: t.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
                  ]),
                ),
              );
            }(),
        InkWell(
          key: const ValueKey('decor_auto'),
          borderRadius: BorderRadius.circular(12),
          onTap: () => mood(defaultDecor(state.project.universe)),
          child: Container(
            width: 96,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: scheme.surfaceContainerLow, border: Border.all(color: scheme.outlineVariant)),
            child: Column(children: [
              Icon(Icons.auto_awesome, color: scheme.primary),
              const SizedBox(height: 4),
              Text(tr('Automatique'), textAlign: TextAlign.center, style: t.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
        if (st.decor.isNotEmpty)
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => state.edit(st.decor.clear),
            child: Container(
              width: 96,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: scheme.outlineVariant)),
              child: Column(children: [
                Icon(Icons.layers_clear_outlined, color: scheme.error),
                const SizedBox(height: 4),
                Text(tr('Tout retirer'), textAlign: TextAlign.center, style: t.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
      ]),
      // objets par emplacement : vignettes cochées
      for (final (spots, title) in _groups)
        if (items.any((it) => spots.contains(it.spot)))
          KxSection(
            initiallyOpen: true,
            title: tr(title),
            value: trp('{0} / {1}', [items.where((it) => spots.contains(it.spot) && st.decor.contains(it.id)).length, items.where((it) => spots.contains(it.spot)).length]),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final it in items)
                if (spots.contains(it.spot))
                  () {
                    final sel = st.decor.contains(it.id);
                    return Tooltip(
                      message: it.w > 0 ? '${tr(it.name)} · ${it.w}×${it.d}×${it.h} mm' : tr(it.name),
                      child: InkWell(
                        key: ValueKey('decor_${it.id}'),
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => toggle(it, !sel),
                        child: AnimatedContainer(
                          duration: Tokens.fast,
                          width: 88,
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: sel ? scheme.primary.withValues(alpha: 0.08) : scheme.surface,
                            border: Border.all(color: sel ? scheme.primary : scheme.outlineVariant, width: sel ? 2 : 1),
                          ),
                          child: Stack(children: [
                            Column(children: [
                              SizedBox(height: 46, child: Center(child: _thumb(it, scheme))),
                              const SizedBox(height: 4),
                              Text(tr(it.name), maxLines: 2, textAlign: TextAlign.center, style: t.labelSmall?.copyWith(fontWeight: sel ? FontWeight.w800 : FontWeight.w600)),
                            ]),
                            if (sel)
                              Positioned(
                                right: 0,
                                top: 0,
                                child: CircleAvatar(radius: 9, backgroundColor: scheme.primary, child: const Icon(Icons.check, size: 12, color: Colors.white)),
                              ),
                          ]),
                        ),
                      ),
                    );
                  }(),
            ]),
          ),
      const SizedBox(height: Tokens.s2),
      Text(tr('Les objets se placent tout seuls aux places libres. Pour poser et déplacer un objet à la main : menu Insertion, « Objets ».'), style: t.bodySmall),
    ]);
  }
}
