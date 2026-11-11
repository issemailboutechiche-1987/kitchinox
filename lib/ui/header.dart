// En-tête : étapes du projet, actions globales, résumé et bouton « Suivant »,
// puis la barre d'outils propre à chaque étape (grandes icônes avec libellé).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/engine.dart';
import 'app_state.dart';
import 'logo.dart';
import 'theme.dart';
import 'i18n.dart';
import 'app_settings.dart';

class StepHeader extends StatelessWidget {
  final AppState state;
  final VoidCallback onOpen, onSave, onIssues;
  final VoidCallback? onDownload; // fichier du projet (.json)
  final VoidCallback? onClient, onSettings; // fiche client, paramètres (langue, unités, numérotation)
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeMode;
  const StepHeader({
    super.key,
    required this.state,
    required this.onOpen,
    required this.onSave,
    this.onDownload,
    this.onClient,
    this.onSettings,
    required this.onIssues,
    required this.themeMode,
    required this.onThemeMode,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    final phone = MediaQuery.sizeOf(context).width < 700;
    final issues = state.issues;
    final errors = issues.where((i) => i.severity == Severity.error).length;
    final warnings = issues.where((i) => i.severity == Severity.warning).length;
    final bom = state.bom;
    final last = state.step == PlanStep.values.last;

    return Container(
      height: 60,
      color: scheme.surface,
      padding: EdgeInsets.symmetric(horizontal: phone ? Tokens.s2 : Tokens.s4),
      child: Row(children: [
        // retour à l'accueil (quand la cuisine a été ouverte depuis l'accueil)
        if (Navigator.of(context).canPop()) ...[
          IconButton(
            tooltip: tr('Accueil'),
            icon: const Icon(Icons.home_outlined),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: Tokens.s1),
        ],
        // marque (cliquable : accueil)
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: Navigator.of(context).canPop() ? () => Navigator.of(context).maybePop() : null,
          child: Tooltip(
            message: tr('kitchinox'),
            child: SizedBox(width: phone ? 46 : 72, height: 52, child: const LogoMark()),
          ),
        ),
        SizedBox(width: phone ? Tokens.s2 : Tokens.s5),
        // étapes
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final s in PlanStep.values) _StepTab(state: state, step: s, compact: !wide),
            ]),
          ),
        ),
        // actions globales
        if (!phone) ...[
          IconButton(tooltip: tr('Annuler (Ctrl+Z)'), onPressed: state.canUndo ? state.undo : null, icon: const Icon(Icons.undo)),
          IconButton(tooltip: tr('Rétablir (Ctrl+Y)'), onPressed: state.canRedo ? state.redo : null, icon: const Icon(Icons.redo)),
          IconButton(tooltip: tr('Enregistrer le projet'), onPressed: onSave, icon: const Icon(Icons.save_outlined)),
        ],
        PopupMenuButton<String>(
          tooltip: tr('Plus'),
          icon: const Icon(Icons.more_vert),
          onSelected: (v) {
            switch (v) {
              case 'undo':
                state.undo();
              case 'redo':
                state.redo();
              case 'save':
                onSave();
              case 'open':
                onOpen();
              case 'download':
                onDownload?.call();
              case 'client':
                onClient?.call();
              case 'settings':
                onSettings?.call();
              case 'new':
                state.newProject();
              case 'light':
                onThemeMode(ThemeMode.light);
              case 'dark':
                onThemeMode(ThemeMode.dark);
              case 'system':
                onThemeMode(ThemeMode.system);
            }
          },
          itemBuilder: (_) => [
            if (phone) ...[
              PopupMenuItem(value: 'undo', enabled: state.canUndo, child: ListTile(leading: Icon(Icons.undo), title: Text(tr('Annuler')))),
              PopupMenuItem(value: 'redo', enabled: state.canRedo, child: ListTile(leading: Icon(Icons.redo), title: Text(tr('Rétablir')))),
              PopupMenuItem(value: 'save', child: ListTile(leading: Icon(Icons.save_outlined), title: Text(tr('Enregistrer')))),
              const PopupMenuDivider(),
            ],
            PopupMenuItem(value: 'open', child: ListTile(leading: Icon(Icons.folder_open_outlined), title: Text(tr('Ouvrir un projet…')))),
            if (onDownload != null)
              PopupMenuItem(value: 'download', child: ListTile(leading: Icon(Icons.download_outlined), title: Text(tr('Télécharger le fichier du projet')))),
            if (onClient != null) PopupMenuItem(value: 'client', child: ListTile(leading: const Icon(Icons.badge_outlined), title: Text(tr('Fiche client')))),
            if (onSettings != null) PopupMenuItem(value: 'settings', child: ListTile(leading: const Icon(Icons.settings_outlined), title: Text(tr('Paramètres')))),
            PopupMenuItem(value: 'new', child: ListTile(leading: Icon(Icons.delete_sweep_outlined), title: Text(tr('Vider la cuisine')))),
            const PopupMenuDivider(),
            CheckedPopupMenuItem(value: 'light', checked: themeMode == ThemeMode.light, child: Text(tr('Thème clair'))),
            CheckedPopupMenuItem(value: 'dark', checked: themeMode == ThemeMode.dark, child: Text(tr('Thème sombre'))),
            CheckedPopupMenuItem(value: 'system', checked: themeMode == ThemeMode.system, child: Text(tr('Thème du système'))),
          ],
        ),
        const SizedBox(width: Tokens.s3),
        // résumé du projet
        if (wide)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onIssues,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Tokens.s2, vertical: Tokens.s1),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(tr(state.project.name), style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(trp('{0} caissons', [bom.cabinetCount]), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(width: Tokens.s2),
                  _IssueChip(errors: errors, warnings: warnings),
                ]),
              ]),
            ),
          )
        else
          IconButton(
            tooltip: tr('Contrôles'),
            onPressed: onIssues,
            icon: Badge(
              isLabelVisible: errors + warnings > 0,
              label: Text('${errors + warnings}'),
              backgroundColor: errors > 0 ? scheme.error : scheme.tertiary,
              child: const Icon(Icons.rule),
            ),
          ),
        SizedBox(width: phone ? Tokens.s1 : Tokens.s3),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 20)),
          onPressed: last
              ? onSave
              : () {
                  final m = state.next();
                  if (m != null) {
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating, width: 560));
                  }
                },
          child: Text(last ? tr('Enregistrer') : tr('Suivant')),
        ),
      ]),
    );
  }
}

class _IssueChip extends StatelessWidget {
  final int errors, warnings;
  const _IssueChip({required this.errors, required this.warnings});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, label) = errors > 0
        ? (Icons.error_outline, scheme.error, '$errors erreur${errors > 1 ? 's' : ''}')
        : warnings > 0
            ? (Icons.warning_amber_rounded, scheme.tertiary, '$warnings à vérifier')
            : (Icons.check_circle_outline, scheme.primary, 'OK');
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 4),
      Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w700)),
    ]);
  }
}

class _StepTab extends StatelessWidget {
  final AppState state;
  final PlanStep step;
  final bool compact;
  const _StepTab({required this.state, required this.step, required this.compact});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final active = state.step == step;
    final done = step.index < state.step.index;
    return Semantics(
      selected: active,
      button: true,
      label: trp('Étape {0} : {1}', [step.index + 1, tr(step.label)]),
      child: InkWell(
        onTap: () => state.goTo(step),
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: Tokens.s3),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: active ? scheme.primary : Colors.transparent, width: 3)),
          ),
          child: Row(children: [
            AnimatedContainer(
              duration: Tokens.fast,
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active || done ? scheme.primary : Colors.transparent,
                border: Border.all(color: active || done ? scheme.primary : scheme.outline),
              ),
              child: done
                  ? Icon(Icons.check, size: 14, color: scheme.onPrimary)
                  : Text('${step.index + 1}',
                      style: t.labelMedium?.copyWith(color: active ? scheme.onPrimary : scheme.onSurfaceVariant, fontWeight: FontWeight.w700)),
            ),
            if (!compact || active) ...[
              const SizedBox(width: Tokens.s2),
              Text(tr(step.label),
                  style: t.titleSmall?.copyWith(
                      fontWeight: active ? FontWeight.w800 : FontWeight.w600, color: active ? scheme.primary : scheme.onSurface)),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Grande icône avec libellé, comme une barre d'outils de logiciel de conception.
class ToolTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  const ToolTile({super.key, required this.icon, required this.label, this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(Tokens.radius),
        onTap: onTap,
        child: Container(
          width: 96,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedContainer(
              duration: Tokens.fast,
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: active ? scheme.primary : scheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: active ? scheme.primary : scheme.outlineVariant),
              ),
              child: Icon(icon, color: active ? scheme.onPrimary : scheme.onSurface),
            ),
            const SizedBox(height: 4),
            Text(label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(height: 1.15, color: active ? scheme.primary : null)),
          ]),
        ),
      ),
    );
  }
}

/// Champ numérique compact « libellé [valeur] mm » validé à Entrée ou à la perte du focus.
class MmField extends StatefulWidget {
  final String label;
  final double value;
  final double min, max;
  final ValueChanged<double> onSubmit;
  const MmField({super.key, required this.label, required this.value, required this.onSubmit, this.min = 1000, this.max = 20000});
  @override
  State<MmField> createState() => _MmFieldState();
}

class _MmFieldState extends State<MmField> {
  late final c = TextEditingController(text: lenValue(widget.value));
  final focus = FocusNode();
  String? error;

  @override
  void initState() {
    super.initState();
    focus.addListener(() {
      if (!focus.hasFocus) _submit();
    });
  }

  @override
  void didUpdateWidget(covariant MmField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !focus.hasFocus) c.text = lenValue(widget.value);
  }

  @override
  void dispose() {
    focus.dispose();
    c.dispose();
    super.dispose();
  }

  void _submit() {
    final v = parseLen(c.text)?.roundToDouble();
    if (v == null || v < widget.min || v > widget.max) {
      setState(() => error = lenRange(widget.min, widget.max));
      return;
    }
    setState(() => error = null);
    if ((v - widget.value).abs() >= 0.5) widget.onSubmit(v);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 150,
        child: TextField(
          controller: c,
          focusNode: focus,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.allow(lenInputPattern)],
          decoration: InputDecoration(
            labelText: widget.label,
            suffixText: lenSuffix,
            isDense: true,
            border: const OutlineInputBorder(),
            errorText: error,
          ),
          onSubmitted: (_) => _submit(),
        ),
      );
}
