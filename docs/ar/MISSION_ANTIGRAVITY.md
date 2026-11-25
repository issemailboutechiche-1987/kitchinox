# Mission Antigravity : mode AR « Voir dans ma pièce »

Dossier de travail : `D:\kitchinox\kitchen_planner - anti` (branche `main`).
Rédigé par Claude, qui a construit le moteur. Ta mission : l'interface, le contenu et le volume.

## Règles (à lire avant de commencer)

1. **On ne travaille jamais en même temps.** Tu commences quand l'utilisateur te le dit, et Claude ne touche à rien pendant ce temps.
2. **Fichiers du moteur : interdits en écriture.** Si tu as besoin d'un changement dedans, note-le dans la section « Demandes pour Claude » à la fin de ce fichier :
   - `web/ar_export.js` (exporteur USDZ)
   - `web/three_view.js` (vue 3D, fonctions `arPrepare`, `arOpen`, `cornerMarker`, `buildNets`)
   - `lib/engine/net_routes.dart` (tracé des réseaux)
   - `lib/ui/scene_export.dart` (`netsSceneData`)
   - `lib/ui/view3d_web.dart`, `view3d_stub.dart`, `view3d_native.dart` (fonctions AR)
   - dans `lib/ui/ar_mode.dart` : `ArOptions`, `ArStats` et `prepareAr` (le contrat). Tu peux remplacer `showArSheet` et `_ArSheet`.
3. **Pas de téléchargement ni d'installation** (npm, Blender, gltf-transform…) sans l'accord explicite de l'utilisateur.
4. Ne jamais copier de textes ni de photos d'IKEA ou de concurrents. Ne jamais afficher « Media Progetti ».
5. Formats visibles dans l'app : seulement .sct, .kin, Excel (et .usdz pour l'AR). Pas de JSON ni de CSV à l'écran.
6. L'app est **toujours en paysage**.
7. Tout texte affiché passe par `tr()` / `trp()`, avec sa traduction anglaise et arabe dans un nouveau `tool/i18n/translations_bNN.json` (le prochain libre : b49, b50…).
   **Ne jamais régénérer `lib/ui/i18n_dict.dart` en entier** (`gen_dict2.py` l'a fait le 25/11 et a effacé des centaines de traductions). On **ajoute** seulement les nouvelles clés au dictionnaire existant.
8. **Fin de mission** :
   - `flutter analyze` sans aucun avertissement ;
   - `flutter test` entièrement vert ;
   - build web : `powershell -ExecutionPolicy Bypass -File tool/build_web.ps1` ;
   - **un seul commit**, et **pas de push** : l'utilisateur décide.

## Le contrat (déjà en place, ne pas modifier)

```dart
// lib/ui/ar_mode.dart
const ArOptions({kitchen = true, walls = false, nets = false, marker = true, maxTexture = 1024, maxVertices = 1500000});
Future<ArStats?> prepareAr(AppState st, ArOptions o); // asynchrone : fabrique le paquet USDZ de la vue 3D ouverte
bool openArPackage();        // À APPELER DIRECTEMENT dans onPressed, jamais après un await (sinon Safari refuse)
bool get arQuickLookAvailable; // true sur iPad / iPhone (Safari) : ouverture en AR, sinon téléchargement du .usdz
// ArStats : meshes, vertices, materials, textures, dropped (modèles omis car trop lourds), size, sizeText, quickLook
```

- `prepareAr` renvoie `null` si la vue 3D n'est pas affichée. L'écran AR doit donc ouvrir la 3D avant (`state.setView(ViewMode.view3d)`), ou expliquer qu'il faut le faire.
- **Repère** : le L rouge est posé au sol sur l'origine du plan, c'est-à-dire le coin des murs A et C. L'utilisateur pose ce L sur le vrai coin de sa pièce.
- Les **réseaux** ne sont disponibles que si `project.networks` est vrai et que des points existent.
- Une version minimale existe déjà (menu Affichage → « Voir dans ma pièce (AR) ») : `_ArSheet` dans `ar_mode.dart`. C'est elle que tu remplaces.

## Tâche 1 : l'écran du mode AR (`lib/ui/ar_page.dart`)

Un parcours en 3 temps, simple, dans l'esprit « une seule place par action » :

1. **Quoi projeter** : 4 cartes illustrées à cocher.
   - Cuisine
   - Murs en transparence
   - Réseaux (électricité, eau, gaz)
   - Repère du coin

   Les réseaux sont grisés, avec une explication, s'il n'y en a pas.
2. **Préparer** : barre d'avancement, puis le résumé (taille, nombre de pièces, modèles omis s'il y en a).
   Si une option change, le paquet préparé est oublié (`stats = null`).
3. **Ouvrir dans ma pièce** : gros bouton. Juste au-dessus, une **aide illustrée** dessinée par toi (CustomPainter, pas de photo) : la pièce vue de dessus, le L rouge, la flèche « posez-le sur le vrai coin », et les murs A et C nommés.
   Sur un appareil sans AR (`quickLook == false`), le bouton devient « Télécharger le fichier USDZ », avec un message : « à ouvrir sur iPad ou iPhone ».

Pour y accéder :

- remplace le corps de `showArSheet(context, state)` pour ouvrir ta page (le menu Affichage l'appelle déjà) ;
- ajoute un bouton « AR » bien visible dans la barre de la vue 3D (`lib/ui/toolbar.dart`, près de l'icône `view_display`).

Clés de test à garder : `ar_sheet` (racine de l'écran), `ar_prepare`, `ar_open`, `view_ar`.

## Tâche 2 : mesurer et alléger les modèles 3D pour l'AR

Le paquet AR a un budget de 1,5 million de sommets. Au-delà, l'exporteur omet les modèles les plus lourds. Les plus gros fichiers sont dans `web/objects/polyhaven/` : potted_plant_01 (5,3 Mo), potted_plant_02, modern_wooden_cabinet, bar_chair_round_01…

1. **Mesure** : produis `docs/ar/modeles_poids.md`, un tableau de chaque modèle de `web/objects` avec son nombre de sommets, de triangles, ses textures et leur taille, trié du plus lourd au plus léger.
2. **Allègement** : *seulement si l'utilisateur approuve l'outil*. Crée à côté de chaque modèle lourd une version `…_ar.glb` : au plus 20 000 triangles et des textures de 512 px. Liste-les dans `web/objects/ar_lods.json` :

   ```json
   { "polyhaven/potted_plant_01/potted_plant_01.gltf": "polyhaven/potted_plant_01/potted_plant_01_ar.glb" }
   ```

   Claude branchera ensuite l'exporteur sur ce fichier : il ne charge pas ces versions lui-même.

## Tâche 3 : tests de l'écran (`test/ar_page_test.dart`)

- L'écran s'ouvre depuis le menu Affichage (`view_ar`).
- « Préparer » est désactivé si rien n'est coché.
- Les réseaux sont désactivés sans points de réseau.
- Hors navigateur, `prepareAr` renvoie null : l'écran affiche le message « Ouvrez la vue 3D… », sans planter.
- Golden de l'écran en paysage 1180×820 (`test/goldens/tablet/`).

## Tâche 4 : guide court dans l'app

Une page d'aide (bouton « ? » de l'écran AR), en français, anglais et arabe :

- AR Quick Look fonctionne sur iPad et iPhone, dans Safari ;
- comment poser le L sur le coin ;
- garder l'échelle 1:1 (le pincement est bloqué) ;
- la lumière (pièce éclairée) ;
- les limites : ±2 cm, pas d'édition dans la vue AR.

## Ce que Claude fera après toi

- Branchement des versions allégées (`ar_lods.json`) dans l'exporteur.
- Cotes et étiquettes flottantes des points de réseau en AR (« prise h 1100 »).
- Contrôle du rendu des matériaux sur l'iPad.
- Si l'utilisateur valide le prototype : l'étude de l'AR native (ARKit + LiDAR, murs détectés, recalage automatique).

## Demandes pour Claude

1. **`tool/nest_worker.dart` & `dart compile js`** : Lors de l'exécution de `tool/build_web.ps1`, la commande `dart compile js -O2 tool/nest_worker.dart -o web/nest_worker.js` échoue car `nest_worker.dart` importe `lib/engine/cutting.dart` qui importe en cascade `catalog.dart` -> `front_layout.dart` -> `project.dart` -> `art.dart` -> `art_cad.dart` -> `lib/ui/art_camera.dart`, lequel importe `package:flutter/material.dart` (qui dépend de `dart:ui`). Le compilateur JS Dart pur refuse `dart:ui`. Il conviendrait de découpler `art_cad.dart` / `art.dart` de `lib/ui/art_camera.dart` ou de séparer les modèles de données des contrôleurs Flutter pour que le worker de nesting reste 100% pur Dart.
2. **Allègement des modèles 3D (LODs AR)** : L'inventaire complet des 137 modèles a été mesuré dans `docs/ar/modeles_poids.md`. 16 modèles dépassent le budget (> 20 000 triangles ou > 1,5 Mo), notamment `potted_plant_01` (176 960 triangles, 6 Mo) et `modern_wooden_cabinet` (51 308 triangles, 3,4 Mo). Dès que l'utilisateur aura approuvé l'outil de décimation (gltf-transform ou Blender headless), nous pourrons générer les `_ar.glb` et le fichier `ar_lods.json`.
