# Mission Antigravity : brancher les 200 accessoires sur leurs modèles 3D

Tu travailles **après Gemini**, jamais en même temps que Claude ou Gemini.

Lis d'abord `docs/fittings/CONTRAT_3D.md`.

## Les fichiers

**À ne pas toucher** (moteur de Claude) :
- `web/fittings3d.js`
- `web/three_view.js`
- `lib/ui/scene_export.dart`

**À modifier** :
- `assets/data/kitchen_accessories_catalog.json`
- `assets/data/klaus_ma_catalog.json`
- `docs/fittings/`

## Tâche 1 : écrire `model3d` dans les deux catalogues

Pour chaque article, pars de `docs/fittings/parametres_gemini.json`. Vérifie-le contre les photos et le schéma de l'article, puis écris le champ `model3d` (format du contrat). Les champs `confidence`, `source` et `doubts` ne vont pas dans le catalogue.

Ne change rien d'autre dans les catalogues : prix, noms, cotes existantes restent tels quels.

## Tâche 2 : contrôle visuel de chaque article

Dans l'app (Safari, http://192.168.11.106:8692) :
1. Pose un caisson de la bonne taille.
2. Équipe-le de l'article.
3. Ouvre la porte (double toucher) et passe en mode **Transparent**.
4. Compare avec la photo du produit.

Note chaque écart dans `docs/fittings/ecarts_rendu.md`, sous la forme d'un tableau :

| article | famille | ce qui ne va pas | gravité (1 à 3) |

Exemples de lignes : « traverse au travers du côté », « 3 étages au lieu de 2 », « ne sort pas avec la porte ».

Claude corrigera le moteur à partir de ce fichier.

## Tâche 3 : la vignette 3D dans la fenêtre des accessoires

Dans la fiche d'un article (`lib/ui/kitchen_accessories_ui.dart`, ton fichier), ajoute un bouton **« Voir en 3D »**. Il ferme la fenêtre, sélectionne le caisson équipé, ouvre sa porte et passe la vue en 3D.

Pour ouvrir la porte, utilise `state.togglePart(uid, -1, 0)`.

## Fin de mission

- `flutter analyze` sans avertissement ;
- `flutter test` entièrement vert ;
- build web : `powershell -ExecutionPolicy Bypass -File tool/build_web.ps1` ;
- **un seul commit**, sans push.

Ne régénère **jamais** `lib/ui/i18n_dict.dart` en entier. Ajoute les traductions dans un nouveau `tool/i18n/translations_bNN.json`.
