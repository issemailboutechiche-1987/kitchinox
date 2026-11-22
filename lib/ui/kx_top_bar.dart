// Barre du haut commune à tous les modes (cuisine, dressing, salle de bain, atelier Art…) :
// accueil, logo, menus Fichier / Édition / Affichage…, puis annuler, rétablir, enregistrer.
import 'package:flutter/material.dart';

import 'i18n.dart';
import 'logo.dart';
import 'theme.dart';

/// Un menu : titre et lignes.
class KxMenu {
  final String label, key;
  final List<Widget> items;
  const KxMenu(this.label, this.key, this.items);
}

/// Ligne de menu ; cochée, elle montre une coche à la place de l'icône. [on] nul : grisée.
MenuItemButton kxItem(String label, VoidCallback? on, {IconData? icon, MenuSerializableShortcut? keys, String? key, bool checked = false}) => MenuItemButton(
      key: key == null ? null : ValueKey(key),
      onPressed: on,
      shortcut: keys,
      style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(220, 44))),
      leadingIcon: checked ? const Icon(Icons.check, size: 20) : (icon == null ? const SizedBox(width: 20) : Icon(icon, size: 20)),
      child: Text(tr(label)),
    );

class KxTopBar extends StatelessWidget {
  static const height = 48.0;
  final VoidCallback? onHome;
  final List<KxMenu> menus;
  final VoidCallback? onUndo, onRedo, onSave;
  final List<Widget> trailing;
  final bool history; // boutons annuler / rétablir
  const KxTopBar({super.key, this.onHome, required this.menus, this.onUndo, this.onRedo, this.onSave, this.trailing = const [], this.history = true});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: height,
      color: scheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: Tokens.s2),
      child: Row(children: [
        if (onHome != null) IconButton(tooltip: tr('Accueil'), icon: const Icon(Icons.home_outlined), onPressed: onHome),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onHome,
          child: Tooltip(message: tr('kitchinox'), child: const SizedBox(width: 60, height: 44, child: LogoMark())),
        ),
        const SizedBox(width: Tokens.s2),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: MenuBar(
              style: const MenuStyle(
                elevation: WidgetStatePropertyAll(0),
                backgroundColor: WidgetStatePropertyAll(Colors.transparent),
                padding: WidgetStatePropertyAll(EdgeInsets.zero),
              ),
              children: [
                for (final m in menus)
                  SubmenuButton(
                    key: ValueKey(m.key),
                    style: ButtonStyle(
                      minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
                      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: Tokens.s3)),
                      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    ),
                    menuStyle: MenuStyle(
                      backgroundColor: WidgetStatePropertyAll(scheme.surface),
                      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
                      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: scheme.outlineVariant))),
                      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: Tokens.s2)),
                    ),
                    menuChildren: m.items,
                    child: Text(tr(m.label), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ),
        ),
        if (history) IconButton(tooltip: tr('Annuler (Ctrl+Z)'), onPressed: onUndo, icon: const Icon(Icons.undo)),
        if (history) IconButton(tooltip: tr('Rétablir (Ctrl+Y)'), onPressed: onRedo, icon: const Icon(Icons.redo)),
        if (onSave != null) IconButton(tooltip: tr('Enregistrer le projet'), onPressed: onSave, icon: const Icon(Icons.save_outlined)),
        ...trailing,
      ]),
    );
  }
}

/// Étape numérotée d'un parcours (cuisine, dressing, atelier…).
class KxStepTab extends StatelessWidget {
  final int number;
  final String label;
  final bool active, done, compact;
  final double height;
  final VoidCallback onTap;
  const KxStepTab({super.key, required this.number, required this.label, required this.active, required this.done, required this.onTap, this.compact = false, this.height = 52});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Semantics(
      selected: active,
      button: true,
      label: trp('Étape {0} : {1}', [number, label]),
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: Tokens.s3),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: active ? scheme.primary : Colors.transparent, width: 3))),
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
                  : Text('$number', style: t.labelMedium?.copyWith(color: active ? scheme.onPrimary : scheme.onSurfaceVariant, fontWeight: FontWeight.w700)),
            ),
            if (!compact || active) ...[
              const SizedBox(width: Tokens.s2),
              Text(label, style: t.titleSmall?.copyWith(fontWeight: active ? FontWeight.w800 : FontWeight.w600, color: active ? scheme.primary : scheme.onSurface)),
            ],
          ]),
        ),
      ),
    );
  }
}
