# Contrat : modèles 3D simplifiés des aménagements intérieurs

Objectif : chaque accessoire du catalogue (INOXA, Blum, Klaus…) posé dans un caisson apparaît **dans le meuble** en 3D (porte ouverte, mode Transparent, AR, image finale).

Les modèles ne sont **pas des fichiers 3D** : ce sont des **familles paramétriques** dessinées par le moteur (`web/fittings3d.js`, écrit par Claude). Chaque modèle s'adapte tout seul à la taille intérieure du caisson.

Un article du catalogue reçoit donc une simple description `model3d`.

## État (Claude, 25/11)

Le moteur est prêt.
- Fichiers : `web/fittings3d.js` (les 11 familles) et `buildFittingFor` dans `web/three_view.js`.
- L'aménagement est posé dans le volume utile du caisson. Il sort avec le tiroir, ou une fois la porte ouverte ; un carrousel tourne, une étagère descendante descend.
- Tant qu'un article n'a pas de `model3d`, sa famille est **déduite de sa catégorie et de son type** (`model3dOf` dans `lib/engine/kitchen_accessories.dart`). Le `model3d` écrit dans le catalogue l'emporte toujours.
- Tests : `test/fittings3d_test.dart`.

Pour voir le rendu dans l'app : poser un caisson, l'équiper (fiche → Équipement), ouvrir la porte (double toucher), passer en mode Transparent.

## Où écrire

Dans chaque article de `assets/data/kitchen_accessories_catalog.json` (INOXA, Blum…) et de `assets/data/klaus_ma_catalog.json` (Klaus), on ajoute un champ :

```json
"model3d": { "family": "basket_pullout", "tiers": 2, "mount": "side", "finish": "anthracite" }
```

- Les cotes sont en **mm**.
- Une cote absente est **déduite du caisson** : largeur, profondeur et hauteur intérieures, moins les jeux usuels.
- `finish` : `anthracite` (par défaut), `chrome`, `blanc`, `inox`, `bois`.
- Article sans volume visible (charnière, poignée, profil Gola, vérin…) : `"model3d": { "family": "none" }`.

## Les familles et leurs paramètres

| family | ce que c'est | paramètres (tous facultatifs sauf indiqué) |
|---|---|---|
| `drawer_box` | tiroir intérieur ou casserolier métal / verre | `height` (côtés, 80–250), `sides` (`metal`, `glass`, `rail`), `count` (tiroirs empilés), `cutout` (`u` : découpe siphon), `inner` (true : tiroir à l'anglaise derrière la porte) |
| `basket_pullout` | coulissant à paniers fil ou tôle | `tiers` (1–4), `mount` (`side` latéral, `bottom` sous le panier, `door` fixé à la façade), `wire` (`round`, `flat`, `solid`), `heights` (hauteur de chaque bord, ex. `[80, 120]`), `width` |
| `tall_pantry` | colonne garde-manger | `baskets` (3–7), `frame` (`door` sur la façade, `independent`), `rotating` (true : tourne sur elle-même), `double` (true : deux corps tandem) |
| `carousel` | plateaux tournants d'angle | `shape` (`3/4`, `4/4`, `half`, `kidney`), `levels` (1–3) |
| `corner_pullout` | angle coulissant | `type` (`magic` : 2 + 2 paniers, `lemans` : 2 plateaux haricot, `compact`), `levels` (1–2) |
| `lift` | relevant de meuble haut (mécanisme visible) | `type` (`bifold`, `stay`, `up`, `swing`) |
| `pulldown_shelf` | étagère descendante de meuble haut | `levels` (1–3) |
| `bins` | poubelles de tri coulissantes | `count` (1–4), `capacities` (litres, ex. `[15, 15, 30]`) |
| `organizer` | range-couverts, porte-assiettes, séparateurs | `type` (`cutlery`, `pots`, `plates`, `spices`), `rows` |
| `rack` | porte-bouteilles, porte-serviettes, épices étroit | `type` (`bottle`, `towel`, `spice`), `tiers` |
| `rod` | dressing | `type` (`rod` penderie, `trouser` porte-pantalons, `tie` cravates, `shoe` chaussures, `pullout_rod` penderie descendante) |
| `none` | rien à dessiner | — |

## Règles de dessin (le moteur les applique ; elles servent aussi à juger le rendu)

1. **Simplifié mais juste** : paniers en cadres fins (fil Ø4), tôles minces (1 mm), coulisses en barres. Pas de vis ni de logos.
2. **Toujours dans le caisson** : jamais à travers les côtés, le dessus ou la façade. Jeu de 10 mm aux côtés et 30 mm au fond.
3. **Suit l'ouverture** : un coulissant sort avec sa porte ou son tiroir. Un carrousel tourne de 30° quand on ouvre.
4. **Léger** : moins de 3 000 triangles par accessoire, pour l'iPad et l'AR.
5. **Hauteurs réelles** : un panier bas commence 60 mm au-dessus du fond du caisson. Les étages se répartissent sur la hauteur utile.

## Qui fait quoi

L'ordre est fixe. **On ne travaille jamais en même temps.**

1. **Claude** : le moteur des familles (`web/fittings3d.js`), son branchement dans la 3D, l'AR et l'image finale, et les tests.
2. **Gemini** (`docs/fittings/MISSION_GEMINI.md`) : lit les fiches et les schémas cotés de chaque article et en tire les paramètres → `docs/fittings/parametres_gemini.json`.
3. **Antigravity** (`docs/fittings/MISSION_ANTIGRAVITY_3D.md`) : écrit `model3d` dans les deux catalogues, contrôle chaque rendu, et dresse la liste des écarts.
4. **Claude** : corrige les familles d'après cette liste.
