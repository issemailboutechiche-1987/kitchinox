// Fiche client du projet et paramètres de l'application (langue, unités, numérotation des plans).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/engine.dart';
import 'app_settings.dart';
import 'app_state.dart';
import 'i18n.dart';
import 'kx_choices.dart';
import 'theme.dart';

/// Fiche client : nom du client ou société, ICE. Imprimée sur les plans d'exécution et de découpe.
Future<void> showClientDialog(BuildContext context, AppState st, void Function(String) onMessage) {
  final c = st.project.client;
  final name = TextEditingController(text: c.name);
  final company = TextEditingController(text: c.company);
  final ice = TextEditingController(text: c.ice);
  String? iceError;
  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text(tr('Fiche client')),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('Particulier : son nom. Entreprise : la raison sociale et son ICE.'), style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: Tokens.s3),
            TextField(
              key: const ValueKey('client_name'),
              controller: name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: tr('Nom du client'), border: const OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: Tokens.s3),
            TextField(
              key: const ValueKey('client_company'),
              controller: company,
              decoration: InputDecoration(labelText: tr('Société'), border: const OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: Tokens.s3),
            TextField(
              key: const ValueKey('client_ice'),
              controller: ice,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')), LengthLimitingTextInputFormatter(19)],
              decoration: InputDecoration(
                labelText: tr('ICE (15 chiffres)'),
                border: const OutlineInputBorder(),
                isDense: true,
                errorText: iceError,
              ),
            ),
            if (c.numbers.isNotEmpty) ...[
              const SizedBox(height: Tokens.s3),
              Text(
                [for (final k in DocKind.values) if (c.numbers[k.name] != null) '${tr(k.label)} : ${c.numbers[k.name]}'].join('\n'),
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Annuler'))),
          FilledButton(
            onPressed: () {
              final v = ice.text.replaceAll(' ', '');
              if (v.isNotEmpty && !ClientInfo.validIce(v)) {
                setD(() => iceError = tr("L'ICE compte 15 chiffres"));
                return;
              }
              st.edit(() {
                c
                  ..name = name.text.trim()
                  ..company = company.text.trim()
                  ..ice = v;
              });
              Navigator.pop(ctx);
              onMessage(tr('Fiche client enregistrée'));
            },
            child: Text(tr('Enregistrer')),
          ),
        ],
      ),
    ),
  );
}

/// Paramètres de l'application : langue, unité des cotes, numérotation automatique des plans.
Future<void> showAppSettings(BuildContext context, void Function(String) onMessage) {
  final s = AppSettings.instance;
  final prefixes = {for (final k in DocKind.values) k: TextEditingController(text: s.prefix[k])};
  final nexts = {for (final k in DocKind.values) k: TextEditingController(text: '${s.next[k]}')};
  AppLang? docLang = s.docLang;
  var lang = s.lang, unit = s.unit, numbering = s.numbering, withYear = s.withYear, digits = s.digits;
  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
      final t = Theme.of(ctx).textTheme;
      String example(DocKind k) {
        final saved = (s.prefix[k], s.next[k], s.withYear, s.digits);
        s
          ..prefix[k] = prefixes[k]!.text
          ..withYear = withYear
          ..digits = digits;
        final out = s.preview(k, int.tryParse(nexts[k]!.text) ?? 1);
        s
          ..prefix[k] = saved.$1!
          ..withYear = saved.$3
          ..digits = saved.$4;
        return out;
      }

      return AlertDialog(
        title: Text(tr('Paramètres')),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Langue'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              KxChoices<AppLang>(
                segments: [for (final l in AppLang.values) ButtonSegment(value: l, label: Text(tr(l.localizedName)))],
                selected: {lang},
                onSelectionChanged: (v) => setD(() => lang = v.first),
              ),
              const SizedBox(height: Tokens.s3),
              Text(tr('Langue des documents (PDF)'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              KxChoices<String>(
                key: const ValueKey('doc_lang'),
                segments: [
                  ButtonSegment(value: '', label: Text(tr("Comme l'interface"))),
                  for (final l in AppLang.values) ButtonSegment(value: l.code, label: Text(tr(l.localizedName))),
                ],
                selected: {docLang?.code ?? ''},
                onSelectionChanged: (v) => setD(() => docLang = AppLang.values.where((l) => l.code == v.first).firstOrNull),
              ),
              const SizedBox(height: 4),
              Text(tr("Plans d'exécution, plans de découpe et devis : par exemple une interface en arabe et des documents en français pour le client."), style: t.bodySmall),
              const SizedBox(height: Tokens.s4),
              Text(tr('Unité des cotes'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              KxChoices<LenUnit>(
                segments: [
                  ButtonSegment(value: LenUnit.mm, label: Text(tr('mm'))),
                  ButtonSegment(value: LenUnit.cm, label: Text(tr('cm'))),
                  ButtonSegment(value: LenUnit.inch, label: Text(tr('pouces (")'))),
                ],
                selected: {unit},
                onSelectionChanged: (v) => setD(() => unit = v.first),
              ),
              const SizedBox(height: 4),
              Text(tr("À l'écran et à la saisie. Les plans de découpe et les fichiers SketchCut restent en mm (atelier)."), style: t.bodySmall),
              const SizedBox(height: Tokens.s4),
              Text(tr('Numérotation des plans'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: numbering,
                onChanged: (v) => setD(() => numbering = v),
                title: Text(tr('Numéro automatique sur chaque plan')),
                subtitle: Text(tr('Un projet garde son numéro quand le plan est réédité.')),
              ),
              if (numbering) ...[
                Row(children: [
                  Expanded(
                    child: CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: withYear,
                      onChanged: (v) => setD(() => withYear = v ?? true),
                      title: Text(tr("Avec l'année (repart à 1 chaque année)")),
                    ),
                  ),
                  DropdownButton<int>(
                    value: digits,
                    items: [for (final d in [3, 4, 5]) DropdownMenuItem(value: d, child: Text(trf('{n} chiffres', {'n': d})))],
                    onChanged: (v) => setD(() => digits = v ?? 4),
                  ),
                ]),
                for (final k in DocKind.values)
                  Padding(
                    padding: const EdgeInsets.only(top: Tokens.s2),
                    child: Row(children: [
                      SizedBox(width: 150, child: Text(tr(_cap(k.label)), style: t.bodyMedium)),
                      SizedBox(
                        width: 90,
                        child: TextField(
                          key: ValueKey('prefix_${k.name}'),
                          controller: prefixes[k],
                          onChanged: (_) => setD(() {}),
                          decoration: InputDecoration(labelText: tr('Préfixe'), isDense: true, border: const OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: Tokens.s2),
                      SizedBox(
                        width: 100,
                        child: TextField(
                          key: ValueKey('next_${k.name}'),
                          controller: nexts[k],
                          onChanged: (_) => setD(() {}),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(labelText: tr('Prochain'), isDense: true, border: const OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: Tokens.s3),
                      Expanded(child: Text(example(k), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                    ]),
                  ),
              ],
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Annuler'))),
          FilledButton(
            onPressed: () {
              s.update((s) {
                s
                  ..lang = lang
                  ..docLang = docLang
                  ..unit = unit
                  ..numbering = numbering
                  ..withYear = withYear
                  ..digits = digits;
                for (final k in DocKind.values) {
                  s.prefix[k] = prefixes[k]!.text.trim();
                  s.next[k] = (int.tryParse(nexts[k]!.text) ?? 1).clamp(1, 999999);
                }
              });
              Navigator.pop(ctx);
              onMessage(tr('Paramètres enregistrés'));
            },
            child: Text(tr('Enregistrer')),
          ),
        ],
      );
    }),
  );
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
