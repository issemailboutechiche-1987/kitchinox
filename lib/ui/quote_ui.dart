// Devis final : tous les prix du projet réunis en un devis. Avant de valider, chaque poste se règle :
// gamme (économique, standard, premium), type de produit (panneau, matière du plan de travail, marque de
// quincaillerie, gamme d'électroménager), prix saisi, ligne hors devis, remise et TVA.
// La validation fige le devis et lui attribue un numéro ; il peut être rouvert.
import 'package:flutter/material.dart';

import '../engine/engine.dart';
import 'app_settings.dart';
import 'app_state.dart';
import 'busy.dart';
import 'i18n.dart';
import 'quote_pdf.dart';
import 'brands_ui.dart';
import 'finishes.dart';
import 'kx_choices.dart';
import 'theme.dart';
import 'web_io.dart';

String _today() {
  final n = DateTime.now();
  return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

double? _num(String s) => double.tryParse(s.trim().replaceAll(' ', '').replaceAll(',', '.'));

Future<void> showQuoteDialog(BuildContext context, AppState st, void Function(String) onMessage) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(Tokens.s4),
      child: SizedBox(width: 1080, height: 720, child: ListenableBuilder(listenable: st, builder: (ctx, _) => _QuoteView(st: st, onMessage: onMessage))),
    ),
  );
}

class _QuoteView extends StatelessWidget {
  final AppState st;
  final void Function(String) onMessage;
  const _QuoteView({required this.st, required this.onMessage});

  Future<void> _pdf(BuildContext context) async {
    final v = st.project.quote.validated;
    final q = st.quote;
    final bytes = await runBusy(
        context,
        tr('Devis…'),
        () => inPdfLanguage(
            () => buildQuotePdf(st.project, q, number: v?.number, date: v?.date ?? _today(), validated: v != null)));
    downloadBytes('${v?.number == null ? '' : '${v!.number}_'}${st.project.name}_devis.pdf', bytes, mime: 'application/pdf');
    onMessage(tr('Devis téléchargé (PDF)'));
  }

  void _validate(BuildContext context) {
    final q = st.liveQuote;
    if (q.lines.isEmpty) {
      onMessage(tr('Aucune ligne à chiffrer : posez d\'abord des éléments.'));
      return;
    }
    final number = AppSettings.instance.numberFor(st.project, DocKind.quote);
    st.validateQuote(number, DateTime.now());
    onMessage(number == null ? tr('Devis validé') : trp('Devis {0} validé', [number]));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final q = st.quote;
    final v = st.project.quote.validated;
    final locked = v != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s3, Tokens.s3, Tokens.s2),
        child: Row(children: [
          Text(tr('Devis final'), style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(width: Tokens.s3),
          Chip(
            visualDensity: VisualDensity.compact,
            avatar: Icon(locked ? Icons.lock_outline : Icons.edit_outlined, size: 16),
            label: Text(locked ? (v.number == null ? tr('Validé') : trp('Validé · {0}', [v.number])) : tr('Provisoire, modifiable')),
            backgroundColor: locked ? scheme.primary.withValues(alpha: 0.15) : null,
          ),
          const Spacer(),
          IconButton(tooltip: tr('Fermer'), onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: q.lines.isEmpty
                ? Center(child: Text(tr('Aucune ligne à chiffrer : posez d\'abord des éléments.'), style: t.bodyLarge))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(Tokens.s4),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (st.quoteStale)
                      Container(
                        margin: const EdgeInsets.only(bottom: Tokens.s3),
                        padding: const EdgeInsets.all(Tokens.s3),
                        decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(Tokens.radius)),
                        child: Row(children: [
                          Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
                          const SizedBox(width: Tokens.s2),
                          Expanded(
                              child: Text(
                                  trp('Le projet a changé depuis la validation : le devis recalculé ferait {0} MAD TTC. Rouvrez le devis pour le mettre à jour.',
                                      [money(st.liveQuote.total)]),
                                  style: t.bodySmall?.copyWith(color: scheme.onErrorContainer))),
                        ]),
                      ),
                    if (!locked && st.supplier != null) ...[
                      Text(tr('Gamme des meubles'), style: t.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: Tokens.s1),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: KxChoices<String>(
                          key: const ValueKey('quote_gamme'),
                          showSelectedIcon: false,
                          segments: [
                            ButtonSegment(value: 'standard', label: Text(tr('Standard · MDF')), icon: const Icon(Icons.view_module_outlined)),
                            if (MediaProgetti.instance != null) ButtonSegment(value: 'moyen', label: Text(tr('Moyenne · Alvic')), icon: const Icon(Icons.kitchen_outlined)),
                            ButtonSegment(value: 'luxe', label: Text(tr('Luxe · latté')), icon: const Icon(Icons.diamond_outlined)),
                          ],
                          selected: {st.project.specs.gamme},
                          onSelectionChanged: (s) => st.setGamme(s.first),
                        ),
                      ),
                      if (st.project.specs.gamme == 'moyen') ...[
                        const SizedBox(height: Tokens.s3),
                        MediaProgettiChoices(state: st),
                      ],
                      const SizedBox(height: Tokens.s3),
                    ],
                    for (final s in q.sections) _Section(st: st, quote: q, section: s, locked: locked),
                  ])),
          ),
          const VerticalDivider(width: 1),
          SizedBox(width: 300, child: _Totals(st: st, quote: q, locked: locked, onPdf: () => _pdf(context), onValidate: () => _validate(context))),
        ]),
      ),
    ]);
  }
}

class _Section extends StatelessWidget {
  final AppState st;
  final Quote quote;
  final String section;
  final bool locked;
  const _Section({required this.st, required this.quote, required this.section, required this.locked});

  /// Choix du type de produit propres au poste.
  List<Widget> _typeChoices(BuildContext context) {
    final sp = st.project.specs;
    final db = st.db;
    InputDecoration deco(String label) => InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true);
    Widget box(Widget w, [double width = 250]) => SizedBox(width: width, child: w);
    switch (section) {
      case 'Panneaux':
        final cs = st.project.cut;
        final carcassCategory = cs.carcassMaterial.contains('Latté')
            ? 'Latté (Blockboard)'
            : cs.carcassMaterial.contains('Stratifié')
                ? 'Stratifié / Mélaminé'
                : 'MDF';
        final carcassPresets = woodSheetPresets[carcassCategory] ?? woodSheetPresets['MDF']!;
        final curCarcassPreset = carcassPresets
            .where((p) => p.length == cs.sheetLength && p.width == cs.sheetWidth)
            .firstOrNull ?? carcassPresets.first;

        final frontCategory = cs.frontMaterial.contains('High Gloss') ||
                cs.frontMaterial.contains('Acrylique') ||
                cs.frontMaterial.contains('PET')
            ? 'High Gloss / Acrylique'
            : 'MDF';
        final (fL, fW) = cs.sheetDimensionsFor(cs.frontMaterial);
        final frontPresets = woodSheetPresets[frontCategory] ?? woodSheetPresets['High Gloss / Acrylique']!;
        final curFrontPreset = frontPresets
            .where((p) => p.length == fL && p.width == fW)
            .firstOrNull ?? frontPresets.first;

        final list = PublicPrices.structural;
        final curPublic = (sp.gamme != 'luxe' && list.isNotEmpty)
            ? list.where((p) => p.price == sp.sheetPrice && p.length == cs.sheetLength && p.width == cs.sheetWidth && p.thickness == cs.carcassThickness).firstOrNull
            : null;

        return [
          box(
            DropdownButtonFormField<String>(
              key: ValueKey('quote_carcass_mat_${cs.carcassMaterial}'),
              isExpanded: true,
              initialValue: cs.carcassMaterial, // matière du projet, même hors de la liste type
              decoration: deco(tr('Caissons (Matière)')),
              items: [
                for (final m in {cs.carcassMaterial, ...carcassMaterialChoices}) DropdownMenuItem(value: m, child: Text(tr(m), overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) {
                if (v == null) return;
                st.edit(() {
                  cs.carcassMaterial = v;
                  if (v.contains('Latté')) {
                    st.project.specs.gamme = 'luxe';
                  } else if (st.project.specs.gamme == 'luxe') {
                    st.project.specs.gamme = 'standard';
                  }
                  final cat = v.contains('Latté')
                      ? 'Latté (Blockboard)'
                      : v.contains('Stratifié')
                          ? 'Stratifié / Mélaminé'
                          : 'MDF';
                  final p0 = woodSheetPresets[cat]?.first;
                  if (p0 != null) {
                    cs.sheetLength = p0.length;
                    cs.sheetWidth = p0.width;
                  }
                });
              },
            ),
            240,
          ),
          box(
            DropdownButtonFormField<SheetPreset>(
              key: ValueKey('quote_carcass_preset_${cs.sheetLength}_${cs.sheetWidth}'),
              isExpanded: true,
              initialValue: curCarcassPreset,
              decoration: deco(tr('Format feuille caissons')),
              items: [
                for (final p in carcassPresets) DropdownMenuItem(value: p, child: Text(p.label, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (p) {
                if (p == null) return;
                st.edit(() {
                  cs.sheetLength = p.length;
                  cs.sheetWidth = p.width;
                });
              },
            ),
            260,
          ),
          box(
            DropdownButtonFormField<String>(
              key: ValueKey('quote_front_mat_${cs.frontMaterial}'),
              isExpanded: true,
              initialValue: cs.frontMaterial, // matière du projet, même hors de la liste type
              decoration: deco(tr('Façades (Matière)')),
              items: [
                for (final m in {cs.frontMaterial, ...frontMaterialChoices}) DropdownMenuItem(value: m, child: Text(tr(m), overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) {
                if (v == null) return;
                st.edit(() {
                  cs.frontMaterial = v;
                  final cat = v.contains('High Gloss') || v.contains('Acrylique') || v.contains('PET')
                      ? 'High Gloss / Acrylique'
                      : 'MDF';
                  final p0 = woodSheetPresets[cat]?.first;
                  if (p0 != null) {
                    cs.frontSheetLength = p0.length;
                    cs.frontSheetWidth = p0.width;
                  }
                });
              },
            ),
            240,
          ),
          box(
            DropdownButtonFormField<SheetPreset>(
              key: ValueKey('quote_front_preset_${fL}_$fW'),
              isExpanded: true,
              initialValue: curFrontPreset,
              decoration: deco(tr('Format feuille façades')),
              items: [
                for (final p in frontPresets) DropdownMenuItem(value: p, child: Text(p.label, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (p) {
                if (p == null) return;
                st.edit(() {
                  cs.frontSheetLength = p.length;
                  cs.frontSheetWidth = p.width;
                });
              },
            ),
            260,
          ),
          if (list.isNotEmpty && sp.gamme != 'luxe')
            box(
              DropdownButtonFormField<String>(
                key: ValueKey('quote_panel_${curPublic?.id}'),
                isExpanded: true,
                initialValue: curPublic?.id,
                hint: Text(tr('Tarif de l\'atelier')),
                decoration: deco(tr('Tarif public panneau')),
                items: [
                  for (final p in list)
                    DropdownMenuItem(value: p.id, child: Text('${tr(p.name)} · ${p.price.round()} MAD', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (id) {
                  if (id != null) st.applyPublicPanel(PublicPrices.byId(id)!);
                },
              ),
              260,
            ),
        ];
      case 'Plan de travail':
        if (db == null || db.worktops.isEmpty) return const [];
        // le même choix qu'à l'étape Style : matière, puis coloris (rendu et prix ensemble)
        final mat = db.worktop(worktopOf(st.project).$1) ?? db.worktops.first;
        final looks = looksOf(mat.id);
        final cur = looks.contains(st.project.style.worktop) ? st.project.style.worktop : null;
        return [
          box(DropdownButtonFormField<String>(
            key: ValueKey('quote_wt_${mat.id}'),
            isExpanded: true,
            initialValue: mat.id,
            decoration: deco(tr('Matière')),
            items: [for (final w in db.worktops) DropdownMenuItem(value: w.id, child: Text(tr(w.name), overflow: TextOverflow.ellipsis))],
            onChanged: (id) => st.setWorktopMaterial(id!),
          )),
          if (looks.length > 1)
            box(DropdownButtonFormField<String>(
              key: ValueKey('quote_wtv_${mat.id}_$cur'),
              isExpanded: true,
              initialValue: cur,
              hint: Text(tr('Photo importée')),
              decoration: deco(tr('Coloris')),
              items: [for (final id in looks) DropdownMenuItem(value: id, child: Text(tr(finishById(worktops, id).name), overflow: TextOverflow.ellipsis))],
              onChanged: (id) => st.setStyle(worktop: id),
            )),
        ];
      case 'Quincaillerie':
        if (db == null) return const [];
        final brands = {...BrandCatalog.hardwareBrands, ...db.hardwareBrands}.toList();
        if (brands.isEmpty) return const [];
        return [
          box(DropdownButtonFormField<String>(
            key: ValueKey('quote_hw_${sp.hardwareBrand}'),
            isExpanded: true,
            initialValue: brands.contains(sp.hardwareBrand) ? sp.hardwareBrand : null,
            decoration: deco(tr('Marque de quincaillerie')),
            items: [for (final b in brands) DropdownMenuItem(value: b, child: Text(b))],
            onChanged: (b) => st.setHardwareBrand(b!),
          )),
        ];
      case 'Électroménager':
        return [
          box(DropdownButtonFormField<int>(
            key: ValueKey('quote_tier_${sp.applianceTier}'),
            isExpanded: true,
            initialValue: sp.applianceTier.clamp(0, 2),
            decoration: deco(tr('Gamme d\'électroménager')),
            items: [
              DropdownMenuItem(value: 0, child: Text(tr('Entrée de gamme'))),
              DropdownMenuItem(value: 1, child: Text(tr('Milieu de gamme'))),
              DropdownMenuItem(value: 2, child: Text(tr('Haut de gamme'))),
            ],
            onChanged: (v) => st.setApplianceTier(v!),
          )),
        ];
    }
    return const [];
  }

  Future<void> _editPrice(BuildContext context, QuoteLine l) async {
    final c = TextEditingController(text: l.unitPrice == 0 ? '' : quoteQty(l.unitPrice));
    final r = await showDialog<Object>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(l.name)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (l.ranged) Text(trp('Fourchette du catalogue : {0} à {1} MAD', [l.min.round(), l.max.round()])),
          const SizedBox(height: Tokens.s3),
          TextField(
            key: const ValueKey('quote_price_field'),
            controller: c,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: trp('Prix unitaire (MAD / {0})', [tr(l.unit)]), border: const OutlineInputBorder()),
            onSubmitted: (s) => Navigator.pop(ctx, _num(s) ?? 'x'),
          ),
        ]),
        actions: [
          if (l.edited) TextButton(onPressed: () => Navigator.pop(ctx, 'reset'), child: Text(tr('Prix du catalogue'))),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Annuler'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, _num(c.text) ?? 'x'), child: Text(tr('Appliquer'))),
        ],
      ),
    );
    if (r == 'reset') {
      st.setQuotePrice(l.key, null);
    } else if (r is double && r >= 0) {
      st.setQuotePrice(l.key, r);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final lines = quote.of(section);
    final choices = locked ? const <Widget>[] : _typeChoices(context);
    final ranged = lines.any((l) => l.ranged && !l.edited);
    final allIncluded = lines.isNotEmpty && lines.every((l) => l.included);
    final noneIncluded = lines.isNotEmpty && lines.every((l) => !l.included);
    final bool? masterVal = allIncluded ? true : (noneIncluded ? false : null);

    return Container(
      margin: const EdgeInsets.only(bottom: Tokens.s4),
      decoration: BoxDecoration(border: Border.all(color: scheme.outlineVariant), borderRadius: BorderRadius.circular(Tokens.radius)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: Tokens.s3, vertical: Tokens.s2),
          decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.08), borderRadius: const BorderRadius.vertical(top: Radius.circular(Tokens.radius))),
          child: Row(children: [
            if (!locked && lines.isNotEmpty) ...[
              Checkbox(
                tristate: true,
                value: masterVal,
                onChanged: (v) => st.setQuoteSectionIncluded(section, v == true),
              ),
              const SizedBox(width: Tokens.s1),
            ],
            Expanded(child: Text(tr(section), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: scheme.primary))),
            Text('${money(quote.sectionTotal(section))} MAD', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          ]),
        ),
        if (!locked && (ranged || choices.isNotEmpty))
          Padding(
            padding: const EdgeInsets.fromLTRB(Tokens.s3, Tokens.s3, Tokens.s3, Tokens.s1),
            child: Wrap(spacing: Tokens.s3, runSpacing: Tokens.s2, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (ranged)
                KxChoices<int>(
                  key: ValueKey('quote_level_$section'),
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: [for (var i = 0; i < quoteLevels.length; i++) ButtonSegment(value: i, label: Text(tr(quoteLevels[i])))],
                  selected: {st.project.quote.levelOf(section)},
                  onSelectionChanged: (s) => st.setQuoteLevel(section, s.first),
                ),
              ...choices,
            ]),
          ),
        for (final l in lines)
          Opacity(
            opacity: l.included ? 1 : 0.45,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: Tokens.s2, vertical: 2),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: scheme.outlineVariant))),
              child: Row(children: [
                Checkbox(
                  value: l.included,
                  onChanged: locked ? null : (v) => st.setQuoteIncluded(l.key, v ?? true),
                ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr(l.name), style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    if (l.detail.isNotEmpty) Text(trParts(l.detail), style: t.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ]),
                ),
                SizedBox(width: 84, child: Text('${quoteQty(l.qty)} ${tr(l.unit)}', textAlign: TextAlign.end, style: t.bodySmall)),
                SizedBox(
                  width: 118,
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      key: ValueKey('quote_price_${l.key}'),
                      onPressed: locked || !l.included ? null : () => _editPrice(context, l),
                      icon: Icon(l.edited ? Icons.edit : Icons.edit_outlined, size: 14),
                      label: Text(l.unitPrice == 0 ? tr('à chiffrer') : money(l.unitPrice),
                          style: TextStyle(fontWeight: l.edited ? FontWeight.w800 : null, color: l.unpriced ? scheme.error : null)),
                    ),
                  ),
                ),
                SizedBox(
                    width: 104,
                    child: Text(l.included ? money(l.total) : tr('hors devis'),
                        textAlign: TextAlign.end, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
                const SizedBox(width: Tokens.s2),
              ]),
            ),
          ),
      ]),
    );
  }
}

class _Totals extends StatelessWidget {
  final AppState st;
  final Quote quote;
  final bool locked;
  final VoidCallback onPdf, onValidate;
  const _Totals({required this.st, required this.quote, required this.locked, required this.onPdf, required this.onValidate});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final c = st.project.client;
    Widget row(String a, String b, {bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(a, style: strong ? t.titleMedium?.copyWith(fontWeight: FontWeight.w800) : t.bodyMedium)),
            Text(b, style: strong ? t.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: scheme.primary) : t.bodyMedium),
          ]),
        );
    Widget pct(String label, double value, String key, void Function(double) apply) => SizedBox(
          width: 126,
          child: TextFormField(
            key: ValueKey(key),
            initialValue: quoteQty(value),
            enabled: !locked,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: label, suffixText: '%', border: const OutlineInputBorder(), isDense: true),
            onFieldSubmitted: (s) {
              final v = _num(s);
              if (v != null) apply(v);
            },
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            onChanged: (s) {
              final v = _num(s);
              if (v != null && v >= 0 && v <= 100) apply(v);
            },
          ),
        );
    return SingleChildScrollView(padding: const EdgeInsets.all(Tokens.s4), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(tr('Client'), style: t.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
      Text(c.label.isEmpty ? tr('Fiche client à remplir') : c.label, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      if (c.ice.trim().isNotEmpty) Text(trp('ICE {0}', [c.ice.trim()]), style: t.bodySmall),
      const SizedBox(height: Tokens.s4),
      Wrap(spacing: Tokens.s2, runSpacing: Tokens.s2, children: [
        pct(tr('Remise'), quote.discount, 'quote_discount', (v) => st.setQuoteTerms(discount: v)),
        pct(tr('TVA'), quote.vat, 'quote_vat', (v) => st.setQuoteTerms(vat: v)),
      ]),
      const SizedBox(height: Tokens.s4),
      for (final s in quote.sections) row(tr(s), money(quote.sectionTotal(s))),
      const Divider(),
      row(tr('Total HT'), '${money(quote.subtotal)} MAD'),
      if (quote.discount > 0) ...[
        row(trp('Remise {0} %', [quoteQty(quote.discount)]), '- ${money(quote.discountAmount)} MAD'),
        row(tr('Net HT'), '${money(quote.net)} MAD'),
      ],
      row(trp('TVA {0} %', [quoteQty(quote.vat)]), '${money(quote.vatAmount)} MAD'),
      const SizedBox(height: Tokens.s2),
      Container(
        padding: const EdgeInsets.all(Tokens.s3),
        decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(Tokens.radius)),
        child: row(tr('Total TTC'), '${money(quote.total)} MAD', strong: true),
      ),
      if (quote.unpriced > 0)
        Padding(
          padding: const EdgeInsets.only(top: Tokens.s2),
          child: Text(trp('{0} ligne(s) restent à chiffrer.', [quote.unpriced]), style: t.bodySmall?.copyWith(color: scheme.error)),
        ),
      const SizedBox(height: Tokens.s4),
      if (!locked)
        FilledButton.icon(
          key: const ValueKey('quote_validate'),
          onPressed: quote.lines.isEmpty ? null : onValidate,
          icon: const Icon(Icons.verified_outlined),
          label: Text(tr('Valider le devis')),
        )
      else
        OutlinedButton.icon(
          key: const ValueKey('quote_reopen'),
          onPressed: st.reopenQuote,
          icon: const Icon(Icons.lock_open_outlined),
          label: Text(tr('Rouvrir pour modifier')),
        ),
      const SizedBox(height: Tokens.s2),
      OutlinedButton.icon(
        key: const ValueKey('quote_pdf'),
        onPressed: quote.lines.isEmpty ? null : onPdf,
        icon: const Icon(Icons.picture_as_pdf_outlined),
        label: Text(locked ? tr('Devis (PDF)') : tr('Devis provisoire (PDF)')),
      ),
      const SizedBox(height: Tokens.s3),
      Text(
          locked
              ? trp('Validé le {0}. Les prix sont figés ; rouvrez le devis pour changer une gamme ou un produit.', [st.project.quote.validated!.date.split('-').reversed.join('/')])
              : tr('Changez la gamme ou le type de produit de chaque poste, touchez un prix pour le saisir, décochez ce que le client fournit. Puis validez.'),
          style: t.bodySmall),
    ]));
  }
}
