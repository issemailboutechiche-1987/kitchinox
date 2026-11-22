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
            label: Text(trp(state.engine.kitchen ? 'Comme la cuisine ({0})' : 'Comme le projet ({0})', [tr(inherited.name)])),
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
          KxChoices<int>(
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
          KxChoices<int>(
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

class _HandlePicker extends StatefulWidget {
  final AppState state;
  final HandleCatalog cat;
  const _HandlePicker({required this.state, required this.cat});
  @override
  State<_HandlePicker> createState() => _HandlePickerState();
}

class _HandlePickerState extends State<_HandlePicker> {
  String? zone; // nul : partout
  String? family;

  AppState get state => widget.state;
  HandleCatalog get cat => widget.cat;

  static String _mad(PriceRange p) => p.max == 0 ? tr('usinage inclus') : '${p.min.round()} - ${p.max.round()} MAD';
  static String _unit(HandleModel h) => tr(h.perBar ? 'la barre de 3 m' : (h.perDoorMilling ? 'par façade' : 'pièce'));
  static const _famIcons = {
    'gola': 'Sans poignée',
  };

  static String _famShort(String id, String name) => switch (id) {
        'knobs' => 'Boutons',
        'gola' => 'Sans poignée',
        'appliance_and_oversized_pulls' => 'XXL',
        _ => name.startsWith('Poignées Barres')
            ? 'Barres'
            : name.startsWith('Poignées Profilées')
                ? 'Sur chant'
                : name.startsWith('Poignées Encastrées')
                    ? 'Encastrées'
                    : name.startsWith('Prises de Main')
                        ? 'Usinées'
                        : name.startsWith('Poignées Coquilles')
                            ? 'Coquilles'
                            : _famIcons[id] ?? name,
      };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final st = state.project.style;
    final present = <String>{
      for (final c in state.project.items) ...[
        if (state.engine.modelOf(c).isCarcass) LayoutEngine.handleZone(state.engine.modelOf(c).kind),
        if (openableCells(state.engine.modelOf(c), c).any((x) => x.kind == CellKind.drawer)) 'tiroir',
      ],
    };
    // avec le profil Gola (dans les caissons bas), seuls les hauts peuvent être différents
    final zones = [for (final z in handleZones.keys) if (present.contains(z) && (st.handle != 'gola' || z == 'haut')) z];
    if (zone != null && !zones.contains(zone)) zone = null;
    final choice = zone == null ? st.handleChoice : st.handleAt(zone!);
    final own = zone != null && st.handleByZone.containsKey(zone);
    final cur = cat.byId(choice.id) ?? (choice.kind == 'gola' ? HandleCatalog.gola : choice.kind == 'push' ? HandleCatalog.push : null);
    final fam = family ?? cur?.familyId ?? cat.families.first.$1;
    final drawerOnly = zone == 'tiroir';
    final front = frontFinish(st, zone == 'haut' ? (st.frontUpper ?? st.front) : (st.frontLower ?? st.front));
    HandleLook lookOf(HandleModel h, {HandleChoice? c}) => h.render == HandleRender.gola
        ? HandleLook('gola', 160, golaColor(st, front.color))
        : lookOfChoice(HandleChoice(kind: h.render.kind, id: h.id, size: c?.size, finish: c?.finish, orient: c?.orient ?? 'auto', pos: c?.pos ?? 'auto', pair: c?.pair ?? false), cat, front: front.color);
    final look = cur == null ? HandleLook(choice.kind, 160, handleFinishColor(choice.finish), orient: choice.orient, pos: choice.pos, pair: choice.pair) : lookOf(cur, c: choice);
    final canTurn = const {'bar', 'recess', 'pocket', 'xxl'}.contains(choice.kind) && !drawerOnly;
    final canPlace = !const {'gola', 'push', 'edge', 'edgeFull', 'jProfile', 'groove', 'chamfer'}.contains(choice.kind);
    Widget label(String s) => Padding(padding: const EdgeInsets.only(top: Tokens.s3, bottom: 6), child: Text(tr(s), style: t.labelLarge?.copyWith(fontWeight: FontWeight.w800)));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // où
      if (zones.length > 1 || (st.handle == 'gola' && zones.isNotEmpty)) ...[
        KxChoices<String>(
          key: const ValueKey('handle_zone'),
          segments: [
            ButtonSegment(value: '', label: Text(tr('Partout'))),
            for (final z in zones) ButtonSegment(value: z, label: Text('${tr(handleZones[z]!)}${st.handleByZone.containsKey(z) ? ' •' : ''}')),
          ],
          selected: {zone ?? ''},
          onSelectionChanged: (v) => setState(() {
            zone = v.first.isEmpty ? null : v.first;
            family = null;
          }),
        ),
        const SizedBox(height: Tokens.s2),
        if (zone != null)
          Row(children: [
            Expanded(child: Text(tr(own ? 'Poignée propre à cet endroit.' : 'Comme partout. Choisissez un modèle pour le changer ici.'), style: t.bodySmall)),
            if (own) TextButton(key: const ValueKey('handle_like_all'), onPressed: () => state.clearHandleZone(zone!), child: Text(tr('Comme partout'))),
          ]),
      ],
      // aperçu et réglages du modèle choisi
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(Tokens.s3),
        decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(Tokens.radius), border: Border.all(color: scheme.outlineVariant)),
        child: Material(
          type: MaterialType.transparency,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: 150,
            width: double.infinity,
            child: CustomPaint(key: const ValueKey('handle_preview'), painter: _HandlePainter(state.catalog, look, front, zone: zone ?? 'bas', big: true, profile: st.frontProfile)),
          ),
          const SizedBox(height: Tokens.s2),
          Text(tr(cur?.name ?? 'Poignée standard'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          if (cur != null && cur.render != HandleRender.gola && cur.render != HandleRender.push)
            Text(
                '${_mad(cur.price)} ${_unit(cur)}'
                '${cur.drillingText(choice.size ?? cur.defaultSize).isEmpty ? '' : ' · ${tr(cur.drillingText(choice.size ?? cur.defaultSize))}'}',
                style: t.bodySmall),
          if (cur != null && cur.sizes.length > 1) ...[
            label(trp('{0} (mm)', [tr(cur.sizeLabel)])),
            KxChoices<int>(
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [for (final v in cur.sizes) ButtonSegment(value: v, label: Text('$v'))],
              selected: {choice.size ?? cur.defaultSize},
              onSelectionChanged: (v) => state.setHandle(cur, size: v.first, zone: zone),
            ),
          ],
          if (cur != null && cur.finishes.isNotEmpty) ...[
            label(cur.render == HandleRender.gola ? 'Couleur du profil' : 'Finition'),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final f in cur.finishes)
                () {
                  final on = (choice.finish ?? cur.finishes.first) == f;
                  final color = cur.render == HandleRender.gola
                      ? golaColor(KitchenStyle(handle: 'gola', handleFinish: f), front.color)
                      : handleFinishColor(f);
                  return InkWell(
                    key: ValueKey('handle_finish_$f'),
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => state.setHandle(cur, finish: f, zone: zone),
                    child: SizedBox(
                      width: 76,
                      child: Column(children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color.lerp(color, Colors.white, 0.35)!, color, Color.lerp(color, Colors.black, 0.2)!]),
                            border: Border.all(color: on ? scheme.primary : scheme.outlineVariant, width: on ? 3 : 1),
                          ),
                          child: on ? Icon(Icons.check, size: 20, color: color.computeLuminance() > 0.5 ? Colors.black87 : Colors.white) : null,
                        ),
                        const SizedBox(height: 4),
                        Text(tr(f), textAlign: TextAlign.center, style: t.labelSmall?.copyWith(fontWeight: on ? FontWeight.w800 : null)),
                      ]),
                    ),
                  );
                }(),
            ]),
          ],
          if (canTurn) ...[
            label('Sens sur les portes'),
            KxChoices<String>(
              key: const ValueKey('handle_orient'),
              segments: [
                ButtonSegment(value: 'auto', label: Text(tr('Verticale')), icon: const Icon(Icons.more_vert)),
                ButtonSegment(value: 'h', label: Text(tr('Horizontale')), icon: const Icon(Icons.more_horiz)),
              ],
              selected: {choice.orient == 'h' ? 'h' : 'auto'},
              onSelectionChanged: (v) => state.editHandle((c) => c.orient = v.first, zone: zone),
            ),
          ],
          if (canPlace) ...[
            label('Place'),
            KxChoices<String>(
              key: const ValueKey('handle_pos'),
              segments: [
                ButtonSegment(value: 'auto', label: Text(tr('Près du bord'))),
                ButtonSegment(value: 'centre', label: Text(tr('Au centre'))),
              ],
              selected: {choice.pos},
              onSelectionChanged: (v) => state.editHandle((c) => c.pos = v.first, zone: zone),
            ),
            if (zone == null || drawerOnly)
              SwitchListTile(
                key: const ValueKey('handle_pair'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(tr('Deux poignées sur les tiroirs de 80 cm et plus')),
                value: choice.pair,
                onChanged: (v) => state.editHandle((c) => c.pair = v, zone: zone),
              ),
          ],
          if (zone == null && st.handle != 'gola' && present.contains('colonne'))
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(tr('Barres XXL verticales sur les colonnes')),
              value: st.tallXxl,
              onChanged: (v) => state.setTallXxl(v),
            ),
        ]),
        ),
      ),
      // modèles
      const SizedBox(height: Tokens.s4),
      KxChoices<String>(
        key: const ValueKey('handle_family'),
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: [for (final (id, name, _) in cat.families) ButtonSegment(value: id, label: Text(tr(_famShort(id, name))))],
        selected: {fam},
        onSelectionChanged: (v) => setState(() => family = v.first),
      ),
      const SizedBox(height: Tokens.s3),
      LayoutBuilder(builder: (context, box) {
        const gap = 10.0;
        final cols = box.maxWidth > 520 ? 3 : 2;
        final w = (box.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (final (id, _, list) in cat.families)
            if (id == fam)
              for (final h in list)
                // le profil Gola se règle pour toute la cuisine (il est dans les caissons)
                if (h.render != HandleRender.gola || zone == null)
                  () {
                    final on = cur?.id == h.id && (zone == null || own);
                    return InkWell(
                      key: ValueKey('handle_${h.id}'),
                      borderRadius: BorderRadius.circular(Tokens.radius),
                      onTap: () => state.setHandle(h, zone: zone),
                      child: Container(
                        width: w,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: on ? scheme.primary.withValues(alpha: 0.08) : scheme.surface,
                          borderRadius: BorderRadius.circular(Tokens.radius),
                          border: Border.all(color: on ? scheme.primary : scheme.outlineVariant, width: on ? 2 : 1),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SizedBox(height: 92, width: double.infinity, child: CustomPaint(painter: _HandlePainter(state.catalog, lookOf(h, c: cur?.id == h.id ? choice : null), front, zone: zone ?? 'bas', profile: st.frontProfile))),
                          const SizedBox(height: 6),
                          Text(tr(h.name), maxLines: 3, overflow: TextOverflow.ellipsis, style: t.labelMedium?.copyWith(fontWeight: FontWeight.w700, color: on ? scheme.primary : null)),
                          if (h.render != HandleRender.gola && h.render != HandleRender.push) Text('${_mad(h.price)} ${_unit(h)}', style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                        ]),
                      ),
                    );
                  }(),
        ]);
      }),
    ]);
  }
}

/// La poignée dessinée sur une vraie façade (porte et tiroir en grand, angle de porte en vignette).
class _HandlePainter extends CustomPainter {
  final Catalog catalog;
  final HandleLook look;
  final Finish front;
  final String zone;
  final bool big;
  final String profile;
  _HandlePainter(this.catalog, this.look, this.front, {required this.zone, this.big = false, this.profile = 'lisse'});

  @override
  void paint(Canvas canvas, Size size) {
    final m = catalog.models.where((m) => m.isCarcass && !m.kind.isCorner && LayoutEngine.handleZone(m.kind) == (zone == 'tiroir' ? 'bas' : zone)).firstOrNull ??
        catalog.models.where((m) => m.isCarcass && !m.kind.isCorner).firstOrNull;
    if (m == null) return;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)));
    canvas.drawRect(Offset.zero & size, Paint()..color = shade(front.color, -0.18));
    void face(Rect px, double wMm, double hMm, CellKind kind) {
      final k = px.width / wMm;
      canvas.save();
      canvas.translate(px.left, px.top);
      canvas.scale(k);
      paintFront(canvas, Rect.fromLTWH(0, 0, wMm, hMm), m,
          fill: front.color,
          stroke: shade(front.color, -0.3),
          line: lineOn(front.color),
          fillPaint: front.paint(vertical: true),
          handles: (door: look, drawer: look),
          profile: profile,
          cells: [FrontCell(kind, 0, hMm, 'left', -1)],
          realistic: true,
          pxPerMm: 1,
          opening: 'hinged_left',
          gloss: front.gloss);
      canvas.restore();
    }

    if (big) {
      // une porte et un tiroir large, en entier
      const gap = 10.0;
      final high = zone == 'haut';
      if (zone == 'tiroir') {
        final h = size.height - 16;
        face(Rect.fromLTWH(8, 8, size.width - 16, h), (size.width - 16) / h * 300, 300, CellKind.drawer);
      } else {
        final dh = size.height - 16;
        final dw = dh * 600 / 750;
        face(Rect.fromLTWH(8, 8, dw, dh), 600, 750, CellKind.door);
        if (!high) {
          final left = 8 + dw + gap, rw = size.width - left - 8;
          if (rw > 40) {
            final k = dh / 750, hMm = 250.0;
            for (var i = 0; i < 3; i++) {
              face(Rect.fromLTWH(left, 8 + i * hMm * k, rw, hMm * k), rw / k, hMm - 3, CellKind.drawer);
            }
          }
        } else {
          final left = 8 + dw + gap;
          if (size.width - left - 8 >= dw) face(Rect.fromLTWH(left, 8, dw, dh), 600, 750, CellKind.door);
        }
      }
    } else {
      // l'angle de la porte, agrandi, là où est la poignée
      final drawer = zone == 'tiroir';
      final wMm = drawer ? 420.0 : 330.0;
      final hMm = wMm * size.height / size.width;
      final k = size.width / wMm;
      canvas.save();
      if (drawer) {
        face(Rect.fromLTWH(0, 0, size.width, size.height), wMm, hMm, CellKind.drawer);
      } else {
        const dw = 500.0, dh = 720.0;
        // portion de porte : coin haut droit (bas pour les hauts)
        final top = zone != 'haut' || look.kind == 'gola';
        canvas.translate(size.width - dw * k - 6, top ? 6 : size.height - dh * k - 6);
        face(Rect.fromLTWH(0, 0, dw * k, dh * k), dw, dh, CellKind.door);
      }
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HandlePainter o) => o.look.key != look.key || o.front.id != front.id || o.zone != zone || o.big != big || o.profile != profile;
}
