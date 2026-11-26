# Mission Gemini : lire les fiches et les schémas des accessoires

Tu travailles **après Claude** et **avant Antigravity**, jamais en même temps qu'eux.

Lis d'abord `docs/fittings/CONTRAT_3D.md`.

## Ce qu'on attend de toi

Pour **chaque article** des deux catalogues :
- `assets/data/kitchen_accessories_catalog.json` (56 articles INOXA, Blum…) ;
- `assets/data/klaus_ma_catalog.json` (environ 140 articles Klaus) ;

regarde ses images : `assets/illustrations/...`, les chemins sont dans le champ `illustrations` de chaque article (produit, ambiance, schéma coté). Lis aussi ses textes et ses cotes. Déduis-en sa **famille** et ses **paramètres** selon le tableau du contrat.

C'est un travail de **lecture d'images** : compter les étages d'un panier, voir si la coulisse est latérale ou sous le panier, repérer une découpe de siphon, lire les cotes du schéma.

## Le fichier à produire : `docs/fittings/parametres_gemini.json`

```json
{
  "8107Y": {
    "family": "basket_pullout",
    "tiers": 2,
    "mount": "side",
    "wire": "solid",
    "heights": [110, 90],
    "finish": "anthracite",
    "confidence": 0.9,
    "source": "schéma : 2 paniers, coulisses latérales, bord bas 110 mm",
    "doubts": ""
  }
}
```

- La clé est l'`id` de l'article.
- `confidence` va de 0 à 1. En dessous de 0,6, explique dans `doubts` ce qui manque.
- Un article sans volume (charnière, poignée, profil…) : `"family": "none"`.
- N'invente pas de cote : laisse-la absente, le moteur la déduira du caisson.

## Règles

- Tu n'écris **que** `docs/fittings/parametres_gemini.json` (et une courte note `docs/fittings/notes_gemini.md` si besoin). Tu ne modifies aucun autre fichier.
- Aucun texte ni aucune photo de fabricant n'est recopié dans l'app : uniquement des nombres et des familles.
- À la fin, donne à l'utilisateur :
  - le nombre d'articles traités ;
  - le nombre d'articles avec une confiance inférieure à 0,6 ;
  - les 5 cas les plus douteux.
