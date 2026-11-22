// Caisson personnalisé : bas, haut, colonne ou niche ouverte ; largeur, hauteur et profondeur libres ;
// sans fond arrière ou sans porte au choix. Posé sur le mur affiché, à la première place libre.
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'i18n.dart';
import 'kx_choices.dart';
import 'theme.dart';

Future<void> showCustomCabinetDialog(BuildContext context, AppState st, void Function(String) onMessage) async {
  var type = 'base';
  var noBack = false, noDoor = false;
  final w = TextEditingController(text: '600'), h = TextEditingController(text: '720'), d = TextEditingController(text: '560');
  // dimensions proposées selon le type
  void defaults(String t) {
    final (ww, hh, dd) = switch (t) { 'wall' => (600, 720, 350), 'tall' => (600, 2100, 560), 'niche' => (600, 400, 350), _ => (600, 720, 560) };
    w.text = '$ww';
    h.text = '$hh';
    d.text = '$dd';
  }

  int? n(TextEditingController c, int lo, int hi) {
    return int.tryParse(c.text.trim())?.clamp(lo, hi);
  }

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        Widget field(String label, TextEditingController c, String key) => Expanded(
              child: TextField(
                key: ValueKey(key),
                controller: c,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: tr(label), suffixText: 'mm', border: const OutlineInputBorder(), isDense: true),
              ),
            );
        return AlertDialog(
          title: Text(tr('Caisson personnalisé')),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              KxChoices<String>(
                key: const ValueKey('custom_type'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'base', label: Text(tr('Bas')), icon: const Icon(Icons.kitchen_outlined, size: 16)),
                  ButtonSegment(value: 'wall', label: Text(tr('Haut')), icon: const Icon(Icons.vertical_align_top, size: 16)),
                  ButtonSegment(value: 'tall', label: Text(tr('Colonne')), icon: const Icon(Icons.door_sliding_outlined, size: 16)),
                  ButtonSegment(value: 'niche', label: Text(tr('Niche')), icon: const Icon(Icons.crop_square, size: 16)),
                ],
                selected: {type},
                onSelectionChanged: (v) => set(() {
                  type = v.first;
                  defaults(type);
                  if (type == 'niche') noDoor = true;
                }),
              ),
              const SizedBox(height: Tokens.s3),
              Row(children: [
                field('Largeur', w, 'custom_w'),
                const SizedBox(width: 8),
                field('Hauteur', h, 'custom_h'),
                const SizedBox(width: 8),
                field('Profondeur', d, 'custom_d'),
              ]),
              const SizedBox(height: Tokens.s2),
              SwitchListTile(
                key: const ValueKey('custom_noback'),
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Sans fond arrière')),
                subtitle: Text(tr('Caisson ouvert derrière (passage de tuyaux, mur apparent).')),
                value: noBack,
                onChanged: (v) => set(() => noBack = v),
              ),
              SwitchListTile(
                key: const ValueKey('custom_nodoor'),
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Sans porte (niche ouverte)')),
                value: noDoor,
                onChanged: (v) => set(() => noDoor = v),
              ),
              Text(tr('Largeur de 150 à 1200 mm ; hauteur libre (bas de 300 à 1000, haut jusqu’à 1200, colonne de 1200 à 2700). Composition des façades modifiable ensuite.'),
                  style: Theme.of(ctx).textTheme.bodySmall),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Annuler'))),
            FilledButton(
              key: const ValueKey('custom_ok'),
              onPressed: () {
                final kind = type == 'niche' ? 'wall' : type;
                final hiH = kind == 'tall' ? 2700 : kind == 'wall' ? 1200 : 1000;
                final loH = kind == 'tall' ? 1200 : kind == 'base' ? 300 : 200;
                final ww = n(w, 150, 1200), hh = n(h, loH, hiH), dd = n(d, 100, 800);
                if (ww == null || hh == null || dd == null) {
                  onMessage(tr('Dimensions invalides'));
                  return;
                }
                final err = st.addCustomCabinet(type: kind, width: ww, height: hh, depth: dd, noBack: noBack, noDoor: noDoor);
                Navigator.pop(ctx);
                onMessage(err ?? trp('Caisson personnalisé posé : {0} × {1} × {2} mm', [ww, hh, dd]));
              },
              child: Text(tr('Poser')),
            ),
          ],
        );
      },
    ),
  );
}
