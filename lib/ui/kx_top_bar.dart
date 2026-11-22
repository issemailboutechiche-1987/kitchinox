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
