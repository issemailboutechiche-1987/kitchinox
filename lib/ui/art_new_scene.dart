// Nouvelle scène du mode Art : feuille au format standard, feuille personnalisée, caisson de base ou scène vide.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'i18n.dart';

class NewArtScene {
  final String kind; // sheet | box | empty
  final double? length, width, thickness;
  const NewArtScene(this.kind, {this.length, this.width, this.thickness});
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
  const NewArtSceneDialog({super.key});
  @override
  State<NewArtSceneDialog> createState() => _NewArtSceneDialogState();
}

class _NewArtSceneDialogState extends State<NewArtSceneDialog> {
  String kind = 'sheet';
  int preset = 0; // index de standardSheets, -1 : personnalisée
  double thickness = 18;
  final l = TextEditingController(text: '2000'), w = TextEditingController(text: '1000');

  @override
  void dispose() {
    l.dispose();
    w.dispose();
    super.dispose();
  }

  NewArtScene? get _result {
    if (kind != 'sheet') return NewArtScene(kind);
    if (preset >= 0) return NewArtScene('sheet', length: standardSheets[preset].$2, width: standardSheets[preset].$3, thickness: thickness);
    final ll = double.tryParse(l.text.trim()), ww = double.tryParse(w.text.trim());
    if (ll == null || ww == null || ll < 100 || ww < 100 || ll > 5000 || ww > 3000) return null;
    return NewArtScene('sheet', length: ll, width: ww, thickness: thickness);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget num(String label, TextEditingController c, String key) => Expanded(
          child: TextField(
            key: ValueKey(key),
            controller: c,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: tr(label), suffixText: 'mm', isDense: true, border: const OutlineInputBorder()),
          ),
        );
    return AlertDialog(
      title: Text(tr('Nouvelle création')),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SegmentedButton<String>(
              key: const ValueKey('new_kind'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 'sheet', label: Text(tr('Feuille')), icon: const Icon(Icons.crop_landscape, size: 16)),
                ButtonSegment(value: 'box', label: Text(tr('Caisson de base')), icon: const Icon(Icons.kitchen_outlined, size: 16)),
                ButtonSegment(value: 'empty', label: Text(tr('Scène vide')), icon: const Icon(Icons.crop_free, size: 16)),
              ],
              selected: {kind},
              onSelectionChanged: (v) => setState(() => kind = v.first),
            ),
            const SizedBox(height: 14),
            if (kind == 'sheet') ...[
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
                Row(children: [num('Longueur', l, 'new_l'), const SizedBox(width: 8), num('Largeur', w, 'new_w')]),
              ],
              const SizedBox(height: 12),
              Text(tr('Épaisseur'), style: t.labelLarge),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final th in standardThicknesses)
                  ChoiceChip(label: Text('${th.round()} mm'), selected: thickness == th, onSelected: (_) => setState(() => thickness = th)),
              ]),
              const SizedBox(height: 10),
              Text(tr('La feuille se pose à plat en vue de dessus : coupez-la en X ou en Y, puis liez les chants des pièces et usinez.'), style: t.bodySmall),
            ] else if (kind == 'box')
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
          child: Text(tr('Créer')),
        ),
      ],
    );
  }
}
