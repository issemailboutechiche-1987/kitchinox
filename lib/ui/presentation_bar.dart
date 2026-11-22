// Présentation : les meubles sur fond blanc, complets, avec leurs appareils ou seuls ; images à enregistrer.
// Décor du rendu : choix des objets, montrés ou cachés.
import 'dart:convert';

import 'package:flutter/material.dart';

import '../engine/engine.dart';
import 'app_state.dart';
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
  await saveToKitchinox(name, base64Decode(url.split(',').last));
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

  Future<void> _all() async {
    final st = widget.state;
    final was = st.studio;
    setState(() => busy = true);
    var n = 0;
    for (final m in studioModes.keys) {
      st.setStudio(m);
      await Future<void>.delayed(const Duration(milliseconds: 1400)); // la scène se reconstruit
      if (await _save('${st.project.name}_${m == 'decor' ? 'complet' : m == 'bare' ? 'meubles' : 'appareils'}.png')) n++;
    }
    st.setStudio(was);
    if (mounted) setState(() => busy = false);
    widget.onMessage(n == 0 ? tr('Image impossible : ouvrez la vue 3D.') : trp('{0} image(s) enregistrée(s)', [n]));
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
            key: const ValueKey('studio_all'),
            onPressed: busy ? null : _all,
            icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.download, size: 18),
            label: Text(tr('Les 3 images')),
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

  static const _groups = [('plan', 'Sur le plan de travail'), ('ilot', 'Sur l’îlot ou le meuble'), ('plaque', 'Sur la plaque'), ('fenetre', 'Aux fenêtres'), ('sol', 'Au sol')];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final st = state.project.style;
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
      for (final (spot, title) in _groups) ...[
        Padding(padding: const EdgeInsets.only(top: Tokens.s4, bottom: 6), child: Text(tr(title), style: t.labelLarge?.copyWith(fontWeight: FontWeight.w800))),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final it in decorItems)
            if (it.spot == spot)
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
