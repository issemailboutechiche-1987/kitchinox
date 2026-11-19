// Fenêtre de démarrage d'un univers (« Nouveau projet » / « Ouvrir un projet ») : les tests créent un projet vierge.
import 'package:flutter_test/flutter_test.dart';

/// Si la fenêtre de démarrage est ouverte : « Nouveau projet » puis « Créer le projet ».
Future<void> startNewProject(WidgetTester t) async {
  await t.pumpAndSettle();
  if (find.text('Nouveau projet').evaluate().isEmpty) return;
  await t.tap(find.text('Nouveau projet').first);
  await t.pumpAndSettle();
  final create = find.text('Créer le projet');
  if (create.evaluate().isNotEmpty) {
    await t.tap(create.first);
    await t.pumpAndSettle();
  }
}
