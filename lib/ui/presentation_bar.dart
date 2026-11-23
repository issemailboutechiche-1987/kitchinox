// Présentation : les meubles sur fond blanc, complets, avec leurs appareils ou seuls ; images à enregistrer.
// Décor du rendu : choix des objets, montrés ou cachés.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../engine/engine.dart';
import 'app_state.dart';
import 'hd_render.dart';
import 'i18n.dart';
import 'kx_choices.dart';
import 'theme.dart';
import 'view3d.dart';
import 'web_io.dart';

const studioModes = {'decor': 'Complet', 'appliances': 'Avec appareils', 'bare': 'Meubles seuls'};

/// Enregistre l'image de la vue 3D affichée.
Future<bool> _save(String name) async {
  final url = await getWeb3dSnapshotPng();
  if (url == null || !url.contains(',')) return false;
  await saveImages([(name, base64Decode(url.split(',').last))]);
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
      final png = pngOf(await getWeb3dSnapshotPng());
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

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final st = state.project.style;
    final items = decorFor(state.project.universe);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SwitchListTile(
        key: const ValueKey('decor_show'),
        contentPadding: EdgeInsets.zero,
        title: Text(tr('Montrer le décor')),
        subtitle: Text(tr('Il n’entre ni dans le débit, ni dans le devis.')),
        value: st.showDecor && st.decor.isNotEmpty,
        onChanged: (_) => state.toggleDecor(),
      ),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
          key: const ValueKey('decor_auto'),
          onPressed: () => state.edit(() => st
            ..decor.clear()
            ..decor.addAll(defaultDecor(state.project.universe))
            ..showDecor = true),
          icon: const Icon(Icons.auto_awesome, size: 18),
          label: Text(tr('Décorer automatiquement')),
        ),
        if (st.decor.isNotEmpty) TextButton(onPressed: () => state.edit(st.decor.clear), child: Text(tr('Tout retirer'))),
      ]),
      for (final (spots, title) in _groups)
        if (items.any((it) => spots.contains(it.spot))) ...[
        Padding(padding: const EdgeInsets.only(top: Tokens.s4, bottom: 6), child: Text(tr(title), style: t.labelLarge?.copyWith(fontWeight: FontWeight.w800))),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final it in items)
            if (spots.contains(it.spot))
              FilterChip(
                key: ValueKey('decor_${it.id}'),
                label: Text(tr(it.name)),
                selected: st.decor.contains(it.id),
                onSelected: (v) => state.edit(() {
                  v ? st.decor.add(it.id) : st.decor.remove(it.id);
                  // rideaux ou stores, pas les deux
                  if (v && it.id == 'rideau') st.decor.remove('store');
                  if (v && it.id == 'store') st.decor.remove('rideau');
                  if (v) st.showDecor = true;
                }),
              ),
        ]),
      ],
      const SizedBox(height: Tokens.s4),
      Text(tr('Les objets se placent tout seuls aux places libres. Pour poser et déplacer un objet à la main : menu Insertion, « Objets ».'), style: t.bodySmall),
    ]);
  }
}
