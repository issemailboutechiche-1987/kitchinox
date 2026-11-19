// Session : le travail en cours est sauvegardé automatiquement dans le navigateur (copie de travail) pour
// reprendre exactement où l'on était après avoir quitté l'onglet ; « Enregistrer » fixe la version enregistrée.
// En quittant une création, l'app demande d'enregistrer ou de quitter sans enregistrer.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'web_io.dart';
import 'i18n.dart';

/// Messagerie de l'application (alertes hors de tout écran, comme l'échec de la sauvegarde automatique).
final appMessenger = GlobalKey<ScaffoldMessengerState>();

class Session {
  static const _prefix = 'kitchinox.';

  /// Espaces dont la sauvegarde automatique échoue (l'alerte n'est montrée qu'une fois par échec).
  static final Set<String> failing = {};

  /// Alerte en cas d'échec (remplaçable dans les tests).
  static void Function(String message) onFailure = (m) => appMessenger.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 10), behavior: SnackBarBehavior.floating, width: 560));

  /// Copie de travail (sauvegarde automatique) d'un espace : cuisine, dressing, bain, tv, interieur, art, debit.
  static String? work(String id) => storeGet('${_prefix}work.$id');
  static String? saved(String id) => storeGet('${_prefix}saved.$id');

  static final Map<String, Timer> _timers = {};

  /// Sauvegarde différée (regroupe les changements rapprochés).
  static void autosave(String id, String Function() json) {
    _timers[id]?.cancel();
    _timers[id] = Timer(const Duration(milliseconds: 700), () => saveNow(id, json()));
  }

  static void saveNow(String id, String json) {
    _timers.remove(id)?.cancel();
    // trop gros pour le stockage du navigateur (photos de textures) : on garde la dernière copie valide et on prévient
    final ok = json.length <= 4000000 && storeSet('${_prefix}work.$id', json);
    if (ok) {
      failing.remove(id);
    } else if (failing.add(id)) {
      onFailure(json.length > 4000000
          ? 'Sauvegarde automatique impossible : le projet est trop lourd (photos de textures). Téléchargez le projet pour ne rien perdre.'
          : 'Sauvegarde automatique impossible : le stockage du navigateur est plein ou désactivé. Téléchargez le projet pour ne rien perdre.');
    }
  }

  /// Le travail diffère-t-il de la version enregistrée ?
  static bool dirty(String id, String currentJson) {
    if (currentJson == _empty[id]) return false; // projet neuf, encore intact : rien à enregistrer
    final s = saved(id);
    if (s == null) return currentJson != (_empty[id] ?? '');
    return s != currentJson;
  }

  /// Contenu d'un espace vide (pour savoir s'il y a quelque chose à enregistrer).
  static final Map<String, String> _empty = {};
  static void setEmpty(String id, String json) => _empty[id] ??= json;

  /// Nouveau projet créé : il devient la référence « vide » de l'espace.
  static void resetEmpty(String id, String json) => _empty[id] = json;

  static void commit(String id, String json) {
    if (!storeSet('${_prefix}saved.$id', json)) {
      onFailure('Enregistrement impossible dans le navigateur (stockage plein). Téléchargez le projet pour le garder.');
    }
    saveNow(id, json);
  }

  /// Écran ouvert (pour y revenir directement au retour dans l'app).
  static String get route => storeGet('${_prefix}route') ?? 'home';
  static set route(String r) => storeSet('${_prefix}route', r);
}

/// Demande en quittant une création : enregistrer, quitter sans enregistrer, ou rester.
/// [current] : contenu actuel ; [revert] remet la version enregistrée. Renvoie vrai si l'on peut quitter.
Future<bool> confirmLeave(BuildContext context, String id, String current, {required void Function(String? saved) revert}) async {
  if (!Session.dirty(id, current)) return true;
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.save_outlined),
      title: Text(tr('Enregistrer votre travail ?')),
      content: Text(tr('Vous avez des modifications non enregistrées. Voulez-vous les enregistrer avant de quitter ?')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, 'stay'), child: Text(tr('Annuler'))),
        TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: Text(tr('Quitter sans enregistrer'))),
        FilledButton.icon(onPressed: () => Navigator.pop(ctx, 'save'), icon: const Icon(Icons.save), label: Text(tr('Enregistrer'))),
      ],
    ),
  );
  switch (choice) {
    case 'save':
      Session.commit(id, current);
      return true;
    case 'discard':
      final s = Session.saved(id);
      revert(s);
      Session.saveNow(id, s ?? '');
      return true;
    default:
      return false;
  }
}

/// Garde de sortie pour un écran de création : intercepte le retour (bouton, geste, navigateur).
class LeaveGuard extends StatelessWidget {
  final String id;
  final String Function() current;
  final void Function(String? saved) revert;
  final Widget child;
  const LeaveGuard({super.key, required this.id, required this.current, required this.revert, required this.child});

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final nav = Navigator.of(context);
          if (await confirmLeave(context, id, current(), revert: revert)) {
            Session.route = 'home';
            nav.pop();
          }
        },
        child: child,
      );
}

/// Contenu JSON d'un projet sans les sections gérées à part (art, débit manuel, autres univers).
String projectWorkJson(Map<String, dynamic> j) {
  final m = Map<String, dynamic>.of(j)
    ..remove('art')
    ..remove('manual_cut')
    ..remove('furniture');
  return jsonEncode(m);
}
