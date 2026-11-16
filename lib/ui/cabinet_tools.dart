// Outils de la fiche caisson et du style : remplacer un meuble, finition propre au caisson,
// composition de façade programmable, textures importées.
part of 'panels.dart';

// ------------------------------------------------------------------ remplacer

Future<void> showReplaceDialog(BuildContext context, AppState state, PlacedCabinet item, void Function(String) onMessage) async {
  final models = state.engine.replacementsFor(item);
  final current = state.engine.modelOf(item);
  final f = frontOfItem(state.project.style, item, current);
  final isSinkCurrent = current.id.contains('sink') || state.engine.isWashing(current);
  final byCat = <String, List<CabinetModel>>{};
  if (isSinkCurrent) {
    final sinkModels = models.where((m) => m.id.contains('sink') || state.engine.isWashing(m)).toList();
    if (sinkModels.isNotEmpty) {
      byCat['Sous-évier & Lavage'] = sinkModels;
    }
  }
  for (final m in models) {
    if (isSinkCurrent && (m.id.contains('sink') || state.engine.isWashing(m))) continue;
    byCat.putIfAbsent(m.categoryName, () => []).add(m);
  }
  final chosen = await showDialog<String>(
    context: context,
    builder: (ctx) {
      final t = Theme.of(ctx).textTheme;
      final scheme = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: Text(trp('Remplacer « {0} »', [tr(current.name)])),
        content: SizedBox(
          width: 640,
          child: models.isEmpty
              ? Text(tr('Aucun autre modèle compatible à cet emplacement.'))
              : ListView(
                  shrinkWrap: true,
                  children: [
                    Text(trp('Le nouvel élément prend la même place ({0} mm, ou la largeur catalogue la plus proche).', [item.width]), style: t.bodySmall),
                    for (final e in byCat.entries) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: Tokens.s4, bottom: Tokens.s2),
                        child: Text(
                          e.key,
                          style: t.labelLarge?.copyWith(color: scheme.primary, fontWeight: FontWeight.w800),
                        ),
                      ),
                      Wrap(
                        spacing: Tokens.s3,
                        runSpacing: Tokens.s3,
                        children: [
                          for (final m in e.value)
                            InkWell(
                              borderRadius: BorderRadius.circular(Tokens.radius),
                              onTap: () => Navigator.pop(ctx, m.id),
                              child: Container(
                                width: 140,
                                padding: const EdgeInsets.all(Tokens.s2),
                                decoration: BoxDecoration(
                                  border: Border.all(color: scheme.outlineVariant),
                                  borderRadius: BorderRadius.circular(Tokens.radius),
                                ),
                                child: Column(
                                  children: [
                                    SizedBox(
                                      height: 90,
                                      child: FrontThumb(model: m, fill: f.color, stroke: shade(f.color, -0.35), line: lineOn(f.color)),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(tr(m.name), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.labelMedium),
                                    Text(trp('L {0}', [shortSizes(m.widths)]), style: t.bodySmall),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Annuler')))],
      );
    },
  );
  if (chosen == null) return;
  final hadSink = state.engine.isWashing(current) || current.id.contains('sink') || (item.appliances?.any((a) => a.contains('sink')) ?? false);
  final hadHob = state.engine.isCooking(current) || current.id.contains('cooktop') || (item.appliances?.any((a) => a.contains('cooktop')) ?? false);
  final err = state.replaceItem(item.uid, chosen);
  if (err == null) {
    final newItem = state.project.byUid(item.uid);
    if (newItem != null) {
      final newM = state.catalog[chosen];
      if (hadSink && !newM.id.contains('sink')) {
        // Conserve l'évier sur ce nouveau caisson pour qu'il reste sur le plan
        final apps = [...(newItem.appliances ?? defaultAppliances(newM, newItem))];
        if (!apps.any((a) => a.contains('sink'))) apps.add('sink_1_bowl_drainer');
        newItem.appliances = apps;
      }
      if (hadHob && !newM.id.contains('cooktop') && !newM.id.contains('oven')) {
        // Conserve la plaque de cuisson sur ce nouveau caisson
        final apps = [...(newItem.appliances ?? defaultAppliances(newM, newItem))];
        if (!apps.any((a) => a.contains('cooktop'))) apps.add('cooktop_4_burners_60');
        newItem.appliances = apps;
      }
    }
  }
  onMessage(err ?? trp('{0} remplacé par {1}', [tr(current.name), tr(state.catalog[chosen].name)]));
}

// ------------------------------------------------------------------ finition propre au caisson

class _ItemFrontSection extends StatelessWidget {
  final AppState state;
  final PlacedCabinet item;
  const _ItemFrontSection({required this.state, required this.item});

  @override
  Widget build(BuildContext context) {
    final style = state.project.style;
    final m = state.engine.modelOf(item);
    final inherited = frontFinish(style, (m.kind.isHigh ? style.frontUpper : style.frontLower) ?? style.front);
    return _Section('Façade de cet élément', [
      Wrap(
        spacing: Tokens.s2,
        runSpacing: Tokens.s2,
        children: [
          ChoiceChip(
            label: Text(trp('Comme la cuisine ({0})', [tr(inherited.name)])),
            selected: item.front == null,
            onSelected: (_) => state.setItemFront(item.uid, null),
          ),
        ],
      ),
      const SizedBox(height: Tokens.s2),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final f in frontFinishes(style)) _MiniSwatch(finish: f, selected: item.front == f.id, onTap: () => state.setItemFront(item.uid, f.id)),
        ],
      ),
    ]);
  }
}

class _MiniSwatch extends StatelessWidget {
  final Finish finish;
  final bool selected;
  final VoidCallback onTap;
  const _MiniSwatch({required this.finish, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: finish.name,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 34,
          height: 34,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 2.5 : 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: CustomPaint(painter: _GrainPainter(finish)),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ composition de façade

class _FrontLayoutEditor extends StatelessWidget {
  final AppState state;
  final PlacedCabinet item;
  final CabinetModel model;
  const _FrontLayoutEditor({required this.state, required this.item, required this.model});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final rows = rowsOf(model, item);
    final custom = item.layout != null;
    void set(List<FrontRow> r) {
      final why = state.setItemLayout(item.uid, r);
      if (why != null) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(trp('Composition refusée : {0}', [why]))));
    }

    final (maxCases, _) = layoutLimits(model.kind);
    List<FrontRow> work() => [for (final r in (rows ?? seedRows(model, item))) r.copy()];
    final cells = rows == null ? null : cellsOf(rows, item.height);

    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.s3),
      child: Material(
        type: MaterialType.transparency,
        child: ExpansionTile(
          // pas de PageStorageKey : l'état « ouvert » (bool) serait relu par le défilement du champ H mm
          key: ValueKey('layout-${item.uid}'),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: Tokens.s2),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          initiallyExpanded: custom,
          title: Text(tr('Composition de la façade'), style: t.labelLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          subtitle: Text(
            rows == null ? tr('Modèle standard') : rows.map((r) => r.kind.label.toLowerCase()).join(' + '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.bodySmall,
          ),
          children: [
            Text(
              custom
                  ? tr('Composition personnalisée (du haut vers le bas). Hauteur 0 = le reste, partagé.')
                  : tr('Choisissez une composition ou personnalisez-la case par case.'),
              style: t.bodySmall,
            ),
            const SizedBox(height: Tokens.s2),
            Wrap(
              spacing: Tokens.s2,
              runSpacing: Tokens.s2,
              children: [
                for (final (name, preset) in frontPresets(model.kind, item.height))
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    labelStyle: t.labelMedium,
                    label: Text(name),
                    onPressed: () => set([for (final r in preset) r.copy()]),
                  ),
              ],
            ),
            const SizedBox(height: Tokens.s3),
            if (rows != null)
              for (var i = 0; i < rows.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: Tokens.s2),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: DropdownButtonFormField<CellKind>(
                          key: ValueKey('${item.uid}-row$i-${rows[i].kind.name}'),
                          isExpanded: true,
                          initialValue: rows[i].kind,
                          decoration: InputDecoration(border: const OutlineInputBorder(), isDense: true, labelText: trp('Case {0}', [i + 1])),
                          items: [
                    for (final k in {...allowedCellKinds(model.kind), rows[i].kind}) DropdownMenuItem(value: k, child: Text(tr(k.label))),
                  ],
                          onChanged: (k) {
                            final r = work();
                            r[i].kind = k!;
                            set(r);
                          },
                        ),
                      ),
                      const SizedBox(width: Tokens.s2),
                      Expanded(
                        flex: 3,
                        child: _RowHeight(
                          value: rows[i].h,
                          real: cells![i].h.round(),
                          max: item.height,
                          onSubmit: (v) {
                            final r = work();
                            r[i].h = v;
                            set(r);
                          },
                        ),
                      ),
                      IconButton(
                        tooltip: tr('Monter'),
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.arrow_upward, size: 18),
                        onPressed: i == 0
                            ? null
                            : () {
                                final r = work();
                                final x = r.removeAt(i);
                                r.insert(i - 1, x);
                                set(r);
                              },
                      ),
                      IconButton(
                        tooltip: tr('Supprimer la case'),
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: rows.length <= 1
                            ? null
                            : () {
                                final r = work()..removeAt(i);
                                set(r);
                              },
                      ),
                    ],
                  ),
                ),
            Wrap(
              spacing: Tokens.s2,
              runSpacing: Tokens.s2,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(rows == null ? tr('Personnaliser') : tr('Ajouter une case')),
                  onPressed: rows != null && rows.length >= maxCases
                      ? null
                      : () => set(rows == null ? work() : [...work(), FrontRow(model.kind.isLow ? CellKind.drawer : CellKind.door)]),
                ),
                if (custom)
                  TextButton.icon(
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: Text(tr('Composition du catalogue')),
                    onPressed: () => state.setItemLayout(item.uid, null),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RowHeight extends StatefulWidget {
  final int value, real, max;
  final String label;
  final void Function(int) onSubmit;
  const _RowHeight({required this.value, required this.real, required this.max, required this.onSubmit, this.label = 'H mm'});
  @override
  State<_RowHeight> createState() => _RowHeightState();
}

class _RowHeightState extends State<_RowHeight> {
  late final c = TextEditingController(text: '${widget.value}');

  @override
  void didUpdateWidget(covariant _RowHeight old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) c.text = '${widget.value}';
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  void _submit() {
    final v = int.tryParse(c.text.trim());
    if (v == null || v < 0 || v > widget.max) {
      c.text = '${widget.value}';
      return;
    }
    widget.onSubmit(v);
  }

  @override
  Widget build(BuildContext context) => Focus(
    onFocusChange: (f) {
      if (!f) _submit();
    },
    child: TextField(
      controller: c,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        isDense: true,
        labelText: widget.label,
        helperText: widget.value == 0 ? '= ${widget.real}' : null,
      ),
      onSubmitted: (_) => _submit(),
    ),
  );
}

// ------------------------------------------------------------------ textures importées

class _TextureLibrary extends StatelessWidget {
  final AppState state;
  final String target; // 'front' | 'worktop' | 'floor' | 'wall'
  const _TextureLibrary({required this.state, required this.target});
  bool get worktop => target == 'worktop';

  Future<void> _import(BuildContext context) async {
    final file = await pickFile(accept: 'image/png,image/jpeg,image/webp,.png,.jpg,.jpeg,.webp');
    if (file == null) return;
    ui.Image img;
    try {
      img = await TextureBank.decode(file.bytes);
    } catch (_) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(trp('Image illisible : {0}', [tr(file.name)]))));
      return;
    }
    // l'image est réduite (512 px) pour garder un projet léger
    final k = 512 / math.max(img.width, img.height);
    final small = k < 1 ? await _resize(img, (img.width * k).round(), (img.height * k).round()) : img;
    final png = await small.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) return;
    final color = await TextureBank.averageColor(small);
    final id = 't${DateTime.now().millisecondsSinceEpoch}';
    final name = file.name.replaceAll(RegExp(r'\.[A-Za-z]+$'), '');
    final t = CustomTexture(
      id: id,
      name: name,
      target: target,
      data: base64Encode(png.buffer.asUint8List()),
      tile: switch (target) { 'worktop' => 800, 'floor' => 1200, _ => 600 },
      color: color,
    );
    state.addTexture(t);
    await TextureBank.instance.syncCustom(state.project.style.textures);
    if (target == 'floor') {
      state.setRoomFinish(floor: 'tex:$id');
    } else if (target == 'wall') {
      state.setRoomFinish(splash: 'tex:$id');
    } else if (worktop) {
      state.setStyle(worktop: 'tex:$id');
    } else {
      state.setStyle(front: 'tex:$id');
    }
  }

  static Future<ui.Image> _resize(ui.Image img, int w, int h) async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..filterQuality = FilterQuality.high,
    );
    return rec.endRecording().toImage(w, h);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final list = [
      for (final x in state.project.style.textures)
        if (switch (target) { 'worktop' => x.forWorktop, 'floor' => x.forFloor, 'wall' => x.forWall, _ => x.forFront }) x,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('Mes textures'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(tr('Importez la photo d\'un échantillon (bois, pierre, laque...). Indiquez la largeur réelle qu\'elle représente pour la mettre à l\'échelle.'),
          style: t.bodySmall,
        ),
        SizedBox(height: Tokens.s3),
        for (final x in list)
          Padding(
            padding: EdgeInsets.only(bottom: Tokens.s3),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  height: 44,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: CustomPaint(
                      painter: _GrainPainter(Finish('tex:${x.id}', x.name, Color(x.color), tex: 'custom:${x.id}', tile: x.tile.toDouble())),
                    ),
                  ),
                ),
                SizedBox(width: Tokens.s2),
                Expanded(child: Text(tr(x.name), overflow: TextOverflow.ellipsis)),
                SizedBox(
                  width: 92,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: x.target,
                    decoration: InputDecoration(isDense: true, border: OutlineInputBorder()),
                    items: [
                      DropdownMenuItem(value: 'front', child: Text(tr('Façade'))),
                      DropdownMenuItem(value: 'worktop', child: Text(tr('Plan'))),
                  DropdownMenuItem(value: 'floor', child: Text(tr('Sol'))),
                  DropdownMenuItem(value: 'wall', child: Text(tr('Mur'))),
                      DropdownMenuItem(value: 'both', child: Text(tr('Les 2'))),
                    ],
                    onChanged: (v) {
                      x.target = v!;
                      state.refresh();
                    },
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 76,
                  child: _RowHeight(
                    value: x.tile,
                    real: x.tile,
                    max: 5000,
                    label: tr('L mm'),
                    onSubmit: (v) {
                      x.tile = math.max(50, v);
                      state.refresh();
                    },
                  ),
                ),
                IconButton(tooltip: tr('Retirer'), icon: const Icon(Icons.delete_outline), onPressed: () => state.removeTexture(x.id)),
              ],
            ),
          ),
        OutlinedButton.icon(
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: Text(switch (target) {
            'worktop' => tr('Importer une texture de plan'),
            'floor' => tr('Importer une texture de sol'),
            'wall' => tr('Importer une texture de mur / crédence'),
            _ => tr('Importer une texture de façade'),
          }),
          onPressed: () => _import(context),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ point de réseau

String netUseLabel(String use) => switch (use) {
      NetUse.plan => 'Prise du plan de travail',
      NetUse.sink => 'Évier',
      NetUse.dishwasher => 'Lave-vaisselle',
      NetUse.oven => 'Four',
      NetUse.hob => 'Plaque de cuisson',
      NetUse.fridge => 'Réfrigérateur',
      NetUse.hood => 'Hotte',
      NetUse.microwave => 'Micro-ondes',
      NetUse.lighting => 'Éclairage',
      NetUse.washer => 'Lave-linge',
      _ => 'Usage général',
    };

/// Repères de pose usuels affichés sous le formulaire.
String netHint(NetKind k, KitchenStandards std) => switch (k) {
      NetKind.socket || NetKind.socketDouble || NetKind.socketTriple || NetKind.socketQuad =>
        'Au-dessus du plan : ${std.worktopTop + 200} mm environ (8 cm au moins au-dessus du plan), jamais au-dessus de l\'évier ni de la plaque.',
      NetKind.socket20 => 'Circuit spécialisé 20 A. Lave-vaisselle et four : dans le meuble voisin, pas derrière l\'appareil.',
      NetKind.out32 => 'Sortie de câble 32 A (6 mm²) derrière le meuble de la plaque électrique.',
      NetKind.waterCold || NetKind.waterHot => 'Derrière le meuble évier, vers 500 à 600 mm du sol, avec robinet d\'arrêt.',
      NetKind.drain => 'Évacuation Ø40 vers 400 à 500 mm, pente de 1 à 3 cm par mètre.',
      NetKind.drainWc => 'Évacuation WC Ø100 : 230 mm du sol pour un WC suspendu, pente 1 à 3 %.',
      NetKind.cable => 'Sortie de câble 16 A : sèche-serviettes à 200 mm du sol, chauffe-eau au-dessus de l\'appareil, hors volumes 1 et 2.',
      NetKind.valveMachine => 'Robinet machine pour le lave-vaisselle, accessible dans le meuble voisin.',
      NetKind.gas => 'Robinet gaz accessible dans le meuble de la plaque, flexible à date de validité.',
      NetKind.duct => 'Sortie de hotte Ø125 au-dessus du meuble hotte.',
      NetKind.switch_ => 'Interrupteur simple (ou va-et-vient) près de la porte, vers 1100 mm.',
      NetKind.switchDouble => 'Interrupteur double (deux circuits) près de la porte, vers 1100 mm.',
      NetKind.switchTriple => 'Interrupteur triple (trois circuits) près de la porte, vers 1100 mm.',
      NetKind.usb => 'Prise chargeur USB-A + USB-C, vers 1100 mm (plan de travail, chevet, bureau).',
      NetKind.rj45 => 'Prise réseau RJ45 à 300 mm du sol (derrière le meuble TV, bureau).',
      NetKind.tvSat => 'Prise TV / satellite à 300 mm du sol, ou juste au-dessus du meuble TV.',
      NetKind.light => 'Point lumineux au plafond (position X / Y dans la pièce).',
      NetKind.led => 'Alimentation des LED sous les éléments hauts.',
    };

class _PointForm extends StatelessWidget {
  final AppState state;
  final NetPoint x;
  const _PointForm({required this.state, required this.x});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final room = state.project.room;
    final std = state.project.standards;
    final len = x.onCeiling ? room.width : (x.wallId == 'I' ? (room.island?.length ?? 0) : room.wall(x.wallId).length);
    final editable = state.step != PlanStep.summary;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _header(
          context,
          x.kind.label,
          '${netNetworkNames[x.kind.network]} · ${x.onCeiling ? 'Plafond' : Room.wallNames[x.wallId]} · ${x.auto ? 'automatique' : 'manuel'}',
          () => state.selectPoint(null)),
      Row(children: [
        SizedBox(width: 34, height: 34, child: CustomPaint(painter: _SymbolPainter(x.kind))),
        const SizedBox(width: Tokens.s2),
        Expanded(child: Text(netUseLabel(x.use), style: t.bodyMedium)),
      ]),
      const SizedBox(height: Tokens.s4),
      _Section('Type', [
        DropdownButtonFormField<NetKind>(
          key: ValueKey('${x.uid}-${x.kind.name}'),
          isExpanded: true,
          initialValue: x.kind,
          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
          items: [for (final k in NetKind.values) DropdownMenuItem(value: k, child: Text(tr(k.label)))],
          onChanged: editable ? (k) => state.updatePoint(x.uid, kind: k) : null,
        ),
      ]),
      if (x.kind == NetKind.socket || x.kind == NetKind.socketDouble || x.kind == NetKind.socketTriple || x.kind == NetKind.socketQuad)
        _Section('Nombre de prises', [
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 1, label: Text(tr('1 simple'))),
              ButtonSegment(value: 2, label: Text(tr('2 double'))),
              ButtonSegment(value: 3, label: Text(tr('3 triple'))),
              ButtonSegment(value: 4, label: Text(tr('4 quadruple'))),
            ],
            selected: {
              x.kind == NetKind.socket ? 1 : (x.kind == NetKind.socketDouble ? 2 : (x.kind == NetKind.socketTriple ? 3 : 4))
            },
            onSelectionChanged: editable
                ? (v) {
                    final target = switch (v.first) {
                      1 => NetKind.socket,
                      2 => NetKind.socketDouble,
                      3 => NetKind.socketTriple,
                      _ => NetKind.socketQuad,
                    };
                    state.updatePoint(x.uid, kind: target);
                  }
                : null,
          ),
        ]),
      if (x.kind == NetKind.switch_ || x.kind == NetKind.switchDouble || x.kind == NetKind.switchTriple)
        _Section('Nombre de touches', [
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 1, label: Text(tr('1 simple'))),
              ButtonSegment(value: 2, label: Text(tr('2 double'))),
              ButtonSegment(value: 3, label: Text(tr('3 triple'))),
            ],
            selected: {
              x.kind == NetKind.switch_ ? 1 : (x.kind == NetKind.switchDouble ? 2 : 3)
            },
            onSelectionChanged: editable
                ? (v) {
                    final target = switch (v.first) {
                      1 => NetKind.switch_,
                      2 => NetKind.switchDouble,
                      _ => NetKind.switchTriple,
                    };
                    state.updatePoint(x.uid, kind: target);
                  }
                : null,
          ),
        ]),
      if (!x.onCeiling)
        _Section('Mur', [
          _wallPicker(state, x.wallId, (w) {
            final l = w == 'I' ? (room.island?.length ?? 0) : room.wall(w).length;
            state.updatePoint(x.uid, wall: w, s: x.s.clamp(0, l).toDouble());
            state.setWall(w);
          }, onlyEnabled: false),
        ]),
      _Section('Position (mm)', [
        Wrap(spacing: Tokens.s3, runSpacing: Tokens.s3, children: [
          _MmBox(
              label: x.onCeiling ? tr('Depuis le mur gauche') : tr('Depuis la gauche'),
              value: x.s,
              min: 0,
              max: len,
              onSubmit: (v) => state.updatePoint(x.uid, s: v)),
          _MmBox(
              label: x.onCeiling ? tr('Depuis le mur du fond') : tr('Hauteur du sol'),
              value: x.z,
              min: 0,
              max: x.onCeiling ? room.depth : room.height,
              onSubmit: (v) => state.updatePoint(x.uid, z: v)),
        ]),
        const SizedBox(height: Tokens.s2),
        if (!x.onCeiling && x.z > std.worktopTop) Text(trp('{0} mm au-dessus du plan de travail', [(x.z - std.worktopTop).round()]), style: t.bodySmall),
        Text(x.onCeiling ? tr('Glissez le point en vue du dessus.') : tr('Glissez le point en vue de face pour le déplacer.'), style: t.bodySmall),
      ]),
      Container(
        padding: const EdgeInsets.all(Tokens.s3),
        margin: const EdgeInsets.only(bottom: Tokens.s4),
        decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(Tokens.radius)),
        child: Text(netHint(x.kind, std), style: t.bodySmall),
      ),
      if (editable)
        FilledButton.tonalIcon(
          style: FilledButton.styleFrom(foregroundColor: scheme.error, minimumSize: const Size(double.infinity, Tokens.minTarget)),
          onPressed: state.deleteSelected,
          icon: const Icon(Icons.delete_outline),
          label: Text(tr('Supprimer le point (Suppr)')),
        ),
    ]);
  }
}

class _SymbolPainter extends CustomPainter {
  final NetKind k;
  _SymbolPainter(this.k);
  @override
  void paint(Canvas canvas, Size size) => paintNetSymbol(canvas, size.center(Offset.zero), k, size.shortestSide * 0.42);
  @override
  bool shouldRepaint(covariant _SymbolPainter o) => o.k != k;
}

// ------------------------------------------------------------------ poignées du catalogue

class _HandlePicker extends StatelessWidget {
  final AppState state;
  final HandleCatalog cat;
  const _HandlePicker({required this.state, required this.cat});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final st = state.project.style;
    final cur = cat.byId(st.handleId);
    String mad(PriceRange p) => p.max == 0 ? 'usinage inclus' : '${p.min.round()} - ${p.max.round()} MAD';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (cur != null && cur.render != HandleRender.gola) ...[
        Container(
          padding: const EdgeInsets.all(Tokens.s3),
          decoration: BoxDecoration(color: scheme.primaryContainer.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(Tokens.radius)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(cur.name), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: Tokens.s2),
            if (cur.sizes.isNotEmpty) ...[
              Text(trp('{0} (mm)', [cur.sizeLabel]), style: t.labelMedium),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final v in cur.sizes)
                  ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      label: Text('$v'),
                      selected: (st.handleSize ?? cur.defaultSize) == v,
                      onSelected: (_) => state.setHandle(cur, size: v)),
              ]),
              const SizedBox(height: Tokens.s2),
            ],
            if (cur.finishes.isNotEmpty) ...[
              Text(tr('Finition'), style: t.labelMedium),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final f in cur.finishes)
                  ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    avatar: CircleAvatar(backgroundColor: handleFinishColor(f), radius: 7),
                    label: Text(f),
                    selected: (st.handleFinish ?? cur.finishes.first) == f,
                    onSelected: (_) => state.setHandle(cur, finish: f),
                  ),
              ]),
              const SizedBox(height: Tokens.s2),
            ],
            Text(
                '${mad(cur.price)} ${cur.perBar ? 'la barre de 3 m' : cur.perDoorMilling ? 'par façade (usinage)' : 'pièce'}'
                '${cur.drillingText(st.handleSize ?? cur.defaultSize).isEmpty ? '' : ' · ${cur.drillingText(st.handleSize ?? cur.defaultSize)}'}',
                style: t.bodySmall),
          ]),
        ),
        const SizedBox(height: Tokens.s3),
      ],
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(tr('Barres XXL verticales sur les colonnes')),
        value: st.tallXxl,
        onChanged: (v) => state.setTallXxl(v),
      ),
      for (final (_, fname, list) in cat.families) ...[
        Padding(
          padding: const EdgeInsets.only(top: Tokens.s3, bottom: Tokens.s2),
          child: Text(fname, style: t.labelLarge?.copyWith(color: scheme.primary, fontWeight: FontWeight.w800)),
        ),
        for (final h in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _ChoiceRow(
              icon: switch (h.render) {
                HandleRender.knob || HandleRender.recessRound => Icons.circle_outlined,
                HandleRender.gola || HandleRender.groove || HandleRender.chamfer => Icons.space_bar,
                HandleRender.edge || HandleRender.edgeFull || HandleRender.jProfile => Icons.border_top,
                HandleRender.xxl => Icons.vertical_align_center,
                _ => Icons.horizontal_rule,
              },
              label: h.render == HandleRender.gola ? h.name : '${h.name}\n${mad(h.price)}${h.perBar ? ' / barre 3 m' : h.perDoorMilling ? ' / façade' : ''}',
              selected: st.handleId == h.id || (st.handleId == null && h.render == HandleRender.gola && st.handle == 'gola'),
              onTap: () => state.setHandle(h),
            ),
          ),
      ],
    ]);
  }
}
