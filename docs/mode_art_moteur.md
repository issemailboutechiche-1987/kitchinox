# Mode Art : moteur de création de meubles en panneaux

But : avec **une seule logique**, fabriquer n'importe quel meuble en panneaux (caisson bas, haut, colonne, tiroirs, étagère, table, banc, dressing, niche, meuble TV…) à partir d'une ou plusieurs feuilles, avec la découpe, l'assemblage en 3D, l'usinage (vis, tourillons, charnières, coulisses, pieds…), la quincaillerie, les contrôles et les plans.

Le caisson bas 600 × 750 × 600 à une porte, avec pieds et plinthe, sert d'exemple tout du long. Il est entièrement chiffré au § 13.1.

---

## 0. Principes (règles qu'on ne casse jamais)

1. **Un meuble = des pièces + des relations.** Rien d'autre n'est stocké. Positions, perçages, quincaillerie, découpe et plans sont **recalculés** à partir de ces deux listes.
2. **Une pièce garde son identité** de la feuille jusqu'au meuble monté : même identifiant, même étiquette, même nom.
3. **Les relations décrivent l'intention**, pas la géométrie : « le côté couvre le chant du dessous », et non « le côté est en x = 0 ».
4. **Les cotes ont trois états** : *imposée* (tapée), *paramétrée* (formule) ou *déduite* (le solveur la calcule à partir des relations : un dessus « entre les côtés » prend la largeur libre).
5. **L'usinage découle des relations** et des règles du métier, jamais d'un meuble particulier. Une règle modifiée vaut pour tous les meubles.
6. **Tout est vérifiable** : chaque étape produit des contrôles (bloquants ou à vérifier) avec les pièces concernées.
7. **Annuler couvre tout** : pièces, relations, réglages d'assemblage, découpe, calques.
8. **Les trois façons de créer convergent** vers le même modèle : recette paramétrique, découpe d'une feuille, dessin libre.

---

## 1. Repères et conventions

### 1.1 Repère du monde
- **X** = largeur (gauche → droite), **Y** = hauteur (sol → haut), **Z** = profondeur (**avant = Z min**, arrière = Z max).
- Millimètres, nombres décimaux, arrondis à 0,1 mm au calcul et à 0,5 mm à l'affichage de la découpe.
- La vue de découpe est la vue de dessus : X vers la droite, Z vers le bas de l'écran, origine (0, 0) en haut à gauche de la feuille.

### 1.2 Repère d'une pièce
Une pièce est un parallélépipède rectangle :
- **longueur `lo`** ≥ **largeur `la`** > **épaisseur `ep`** (convention ; en cas d'égalité, la longueur suit le fil) ;
- 2 **faces** : `intérieure` / `extérieure` (ou `dessus` / `dessous` pour une pièce à plat) ;
- 4 **chants** : `L1`, `L2` (les deux chants de longueur) et `C1`, `C2` (les deux chants de largeur).

### 1.3 Orientation
L'orientation d'une pièce est la correspondance entre ses 3 axes locaux (lo, la, ep) et les axes du monde, avec leur sens : **24 orientations possibles** (6 permutations × 4 combinaisons de signes valides). On la stocke sous la forme `(axeLo, axeLa, axeEp)` avec des signes, par exemple `(+Y, +Z, +X)` pour un côté gauche debout.

### 1.4 Chants nommés selon la position finale
Une fois la pièce orientée, chaque chant a une normale dans le monde, d'où son **nom de position** :

| Normale du chant | Nom |
|---|---|
| −Y / +Y | `bas` / `haut` |
| −Z / +Z | `avant` / `arriere` |
| −X / +X | `gauche` / `droite` |

On écrit donc `coteG.bas` ou `dessous.avant` dans les relations. Le solveur traduit en L1, L2, C1 ou C2 selon l'orientation : ça marche quel que soit le sens où la pièce était posée sur la feuille.

Les faces sont nommées de la même façon par leur normale : `coteG.face+X` est sa face intérieure.

### 1.5 Fil (sens des fibres)
- `fil: lo | la | aucun`. Le MDF et le mélaminé uni n'ont pas de fil ; les décors bois, le latté et le contreplaqué en ont un.
- Une pièce avec fil **ne pivote pas** au débit, et le fil d'une façade suit sa hauteur, sauf avis contraire.

---

## 2. Modèle de données

### 2.1 Matériau
```
Materiau { id, nom, famille (MDF, mélaminé, latté, contreplaqué, HDF, verre),
           ep (mm), feuille { L, l }, fil, prix_feuille, recoupe (mm, défaut 4) }
```

### 2.2 Pièce
```
Piece {
  id                 // stable, « p12 »
  nom                // « Côté gauche »
  role               // montant | tablette | traverse | fond | porte | tiroir | abattant |
                     // plateau | plinthe | joue | fileur | tablette_mobile | caisson_tiroir | decor
  materiau           // id du matériau → épaisseur
  lo, la             // cotes FINIES (après bande de chant), formules possibles
  etat_cotes         // imposee | parametree | deduite, pour lo et la
  chants             // { L1, L2, C1, C2 : null | { ep: 0.4 | 1 | 2, matiere } }
  fil                // lo | la | aucun
  // résultats du solveur (jamais saisis à la main en mode recette)
  orientation, position (coin min x, y, z)
  // résultats de la découpe
  feuille, x_feuille, z_feuille, tournee
}
```

### 2.3 Relation
```
Relation {
  id, type                     // voir § 5
  a: "piece.chant|face", b: "piece.chant|face"
  options {                    // selon le type
    alignement: debut | centre | fin | decale(v) | etire
    cote: dedans | dehors      // de quel côté de la face de b
    jeu: mm, recouvrement: mm, retrait: mm
    assemblage: auto | confirmat | minifix | vis_bois | tourillons_colles | lamelles | pocket | aucun
    quincaillerie: { charniere, coulisse, pied, ... }   // selon le type
  }
  ordre_montage (calculé)
}
```

### 2.4 Support
`Support { type: pieds | socle | roulettes | suspension | pose_sol, hauteur, retrait_plinthe, ... }`. C'est une relation entre le meuble et le **sol** (ou le **mur**), traité comme une pièce fixe virtuelle.

### 2.5 Projet
```
ProjetArt {
  version: 2
  parametres { L: 600, H: 750, ... }      // si recette
  pieces [], relations [], supports []
  reglages { assemblage_defaut, charniere_defaut, pied_defaut, chant_defaut, jeux… }
  decoupe { feuilles [], chutes [], mode: manuel | auto }
  calques, cotes, esquisses               // déjà existants
}
```

---

## 3. Cotes : finie, débit, brute

C'est souvent là que naissent les erreurs. On distingue trois cotes :

| Cote | Définition | Utilisée pour |
|---|---|---|
| **Finie** | la pièce terminée, bande de chant comprise | assemblage, solveur, plans |
| **Débit** | ce que la scie coupe | découpe, étiquettes |
| **Brute** | débit + surcote, si le chant est posé avant la mise à cote | plaqueuse avec affleureuse |

**Formule du débit**, pour chaque direction :
`débit = finie − ep_chant(côté 1) − ep_chant(côté 2)`, sauf si la plaqueuse affleure (`mode_chant = surcote`, + 2 mm puis recoupe).

Exemple : une porte finie de 597 × 747 avec 4 chants de 1 mm se débite à **595 × 745**.

**Jeux standard** (réglages modifiables) :

| Jeu | Défaut |
|---|---|
| porte / porte | 3 mm |
| porte / bord du caisson, en applique | 1,5 mm par côté |
| haut de porte | 3 mm |
| façade de tiroir / façade | 3 mm |
| caisson de tiroir / côté | selon la coulisse : 12,5 mm (billes), 21 mm (sous-montée) |
| tablette mobile / côtés | 1 mm par côté |

---

## 4. Langage de formules (recettes)

- **Variables** : les paramètres de la recette (`L`, `H`, `P`, `n_etageres`…), `T` (épaisseur de la matière principale), `Tf` (épaisseur du fond), `jeu`, et les cotes déjà calculées (`dessous.la`).
- **Opérations** : `+ − × /`, parenthèses, `min`, `max`, `arrondi(x, pas)`, `si(cond, a, b)`.
- **Répétitions** : `pour i de 1 à n_etageres` crée `etagere_1 … etagere_n` et leurs relations, avec `i` utilisable dans les formules (`hauteur = i × H / (n + 1)`).
- **Évaluation** : on trie les cotes par dépendances (ordre topologique). Une dépendance circulaire est une erreur qui nomme la boucle.
- **Validation** : chaque paramètre a `min`, `max` et un pas. Une valeur hors limites est refusée avec le message de la recette, par exemple : « Largeur de 150 à 1200 ».

---

## 5. Catalogue des relations

Notations, pour une relation de A vers B (B est déjà placée) :
- `tB` : axe d'épaisseur de B ;
- `nB`, `sB` : normale du chant visé de B et son sens (±1) ;
- `lB` : axe le long de ce chant (le troisième axe) ;
- `face(B, s)` : coordonnée de la face de B côté `s` sur `tB` ; `chant(B)` : coordonnée du chant visé sur `nB` ;
- `hA` : dimension de A perpendiculaire au chant `ca` (la distance de ce chant au chant opposé), `lenA` : la longueur du chant `ca`, `tA` : son épaisseur.

### R1 · Bout sur face, à l'intérieur (`bout`)
*Exemples : dessus ou dessous entre deux côtés, tablette fixe, séparation, traverse.*

**Géométrie.** A devient perpendiculaire à B, son chant `ca` contre une face de B :
- orientation de A : normale de `ca` = `−s · tB` (tournée vers B), épaisseur de A sur `nB`, longueur de `ca` sur `lB` ;
- sur `tB` : `[face(B,s), face(B,s) + s·hA]` ;
- sur `nB`, à fleur du chant de B, vers l'intérieur : `[chant(B) − tA, chant(B)]` si `sB = +1`, sinon `[chant(B), chant(B) + tA]` ;
  option `retrait r` : décalé de `r` vers l'intérieur (fond en retrait, tablette en retrait de 20) ;
- sur `lB` : alignement `debut | centre | fin | decale(v)` ; **`etire`** : la longueur de A devient déduite et s'étend jusqu'à la pièce opposée (§ 6.4).

**Validité.** `lenA ≤` longueur du chant de B (sauf débord voulu) ; les épaisseurs sont compatibles avec l'assemblage (Confirmat : T ≥ 16).

**Usinage.** Jonction chant contre face (§ 8.2) : la **face de B est percée**, le **chant de A est percé**.

### R2 · Applique structurelle (`applique`)
*Exemples : côté qui couvre le chant du dessous, joue de finition, dessus posé sur les côtés.*

**Géométrie.** A recouvre le chant de B :
- sur `nB` : `[chant(B), chant(B) + tA]` si `sB = +1` (A devant le chant), sinon `[chant(B) − tA, chant(B)]` ;
- sur `tB` : A part de la face opposée de B et couvre son chant : `[face(B,−s), face(B,−s) + s·hA]` ;
  option `recouvrement` : n'en couvre qu'une partie (semi-applique, chant partagé) ;
- sur `lB` : alignement comme R1.

**Différence avec R1** : c'est A qui montre son chant, et c'est sa face qui reçoit les perçages. **Le rôle ne change pas** : A reste un montant, il ne devient pas une porte.

**Usinage.** Jonction chant contre face : la **face de A est percée**, le **chant de B est percé**.

### R3 · Articulé (`articule`) : porte, abattant
*Exemples : porte en applique, semi-applique ou encloisonnée ; abattant relevable ou basculant.*

**Géométrie.**
- `applique` : comme R2, avec un **jeu** sur les 4 côtés ; la porte couvre l'ouverture moins les jeux.
- `encloisonnee` : la porte se loge dans l'ouverture (entre les côtés, sous le dessus), jeu de 2 mm tout autour, en retrait de 0 (à fleur) ou de r.
- `semi-applique` : la porte couvre la moitié du chant partagé moins 1,5 mm (deux portes sur un même côté).
- La façade se calcule sur **l'ouverture**, soit le rectangle libre entre les pièces de structure qui l'entourent :
  `largeur = ouverture + 2 × recouvrement − 2 × jeu`.
- Côté charnières : `gauche | droite | haut | bas`, choisi par l'utilisateur ou déduit (porte large > 600 → 2 portes proposées).

**Usinage.**
- Charnières : nombre selon la hauteur (§ 8.4), boîtier Ø35 dans la porte, embase sur le côté ou le dessus.
- Abattant : compas ou vérins à la place des charnières, selon le poids (surface × épaisseur × densité).
- **Aucune vis ni aucun tourillon** entre la façade et le caisson.

**Montage** : en dernier, puis réglage des charnières.

### R4 · Coulissant (`coulissant`) : tiroir
*Un tiroir = 1 façade + 1 caisson de tiroir (2 côtés, avant, arrière, fond), générés.*

**Géométrie.**
- Ouverture : largeur intérieure `Li`, profondeur intérieure `Pi`, hauteur de la case `Hc`.
- Coulisse : longueur `Lc = slideLength(Pi − 10)`, valeurs du commerce de 250 à 550 par pas de 50.
- Caisson de tiroir (coulisse à billes, 12,5 mm par côté) :
  - largeur extérieure `Li − 25` ;
  - profondeur `Lc` ;
  - hauteur `Hc − 40` (caisson bas) ou choisie (100, 150, 200) ;
  - côtés en 16 mm ; avant et arrière entre les côtés ; fond en 8 mm dans une rainure à 10 mm du bas.
- Façade : comme une porte en applique ; ses jeux avec les autres façades de la même colonne valent 3 mm.

**Usinage.**
- Coulisses vissées sur les montants, à `y` = bas de la case + 3 et à 37 mm de l'avant.
- Fixation de la façade au caisson de tiroir : 4 vis par l'intérieur, ou un réglage de façade.
- Poignée centrée (§ 8.8).

### R5 · Face contre face (`jonction`)
*Exemples : deux caissons côte à côte, une joue doublée.*

**Géométrie.** A plaquée contre B, face contre face, sur `tB`.

**Usinage.** Vis de jonction (manchon Ø5) près des 4 coins, à 50 mm des bords, si la surface commune fait au moins 100 × 100.

### R6 · En rainure (`rainure`)
*Exemples : fond mince (3 à 8 mm), fond de tiroir, panneau de porte à cadre.*

**Géométrie.** A est logée dans une rainure de chaque pièce qui l'entoure :
- rainure à `d = 10 mm` du bord (8 à 20, réglable), profondeur `p = 8` (au plus `T/2`), largeur = épaisseur de A + 0,5 ;
- dimensions de A = ouverture intérieure + `2 × (p − 1)` sur chaque axe.

**Usinage.** Rainure sur les pièces hôtes (segment), arrêtée ou débouchante selon la machine : débouchante à la scie, arrêtée à la CNC.

**Contrôle.** Une rainure ne doit pas croiser un perçage de jonction : on décale la station de 32 mm.

### R7 · Feuillure (`feuillure`)
Comme R6, mais ouverte sur l'arrière : fond posé par derrière, cloué ou vissé tous les 150 mm. La feuillure fait épaisseur du fond + 1 de large et 10 de profondeur.

### R8 · Onglet (`onglet`)
*Exemples : angle de plateau, cadre, caisson sans chant visible.*

**Géométrie.** Les deux pièces se rejoignent sur l'arête commune, chacune coupée à 45°. Chacune garde sa cote extérieure, et le débit tient compte de la coupe biaise (la longueur courte = longue − 2T sur la face intérieure).

**Usinage.** Lamelles n° 20 tous les 150 mm le long de l'onglet, ou collé + serré. La découpe marque « coupe 45° » sur le chant concerné.

### R9 · Tablette mobile (`taquets`)
**Géométrie.** Posée entre deux montants, avec 1 mm de jeu de chaque côté, en retrait de 20 mm de l'avant. Sa hauteur suit une formule ou un pas de 32 mm.

**Usinage.**
- Rangées de trous Ø5, profondeur 12 (système 32), à 37 mm de l'avant et de l'arrière de chaque montant.
- Les trous vont de la tablette − 96 à la tablette + 96, au pas de 32, sans descendre sous 64 mm du bas.
- 4 taquets par tablette.

### R10 · Support au sol (`support`)
- **Pieds vérins** (100 à 150) : sous le dessous, à 50 mm des coins, un pied de plus tous les 900 mm sur la largeur. Le meuble monte de la hauteur choisie.
- **Socle** : un cadre en panneaux (avant, arrière, 2 côtés) de la hauteur du socle, en retrait de 50 à l'avant, assemblé en R1.
- **Roulettes** : 4 à 50 mm des coins, vissées dans le dessous (T ≥ 18, sinon une cale).
- **Plinthe** (avec pieds) :
  - hauteur = hauteur des pieds − 3 ;
  - longueur = largeur du meuble, ou de la rangée de meubles ;
  - en retrait de 50 de la face des portes ;
  - posée sur des clips aux pieds de devant (2 par meuble, 1 par pied avant) ;
  - chant du haut (et du bas si le sol est humide).

### R11 · Suspension murale (`suspension`)
Boîtiers réglables dans les coins hauts, derrière les côtés, avec un rail au mur (largeur du meuble − 20) ; ou plaques à visser ; ou tasseau biseauté.

**Contrôle.** Le fond doit pouvoir porter : boîtier avec fond en 18, ou traverse arrière d'accroche si le fond est mince.

### R12 · Plateau posé (`plateau`)
*Exemples : plan de travail, dessus de table, dessus de commode.*

**Géométrie.** A posé sur les chants hauts de B, avec un débord avant, arrière ou latéral réglable (plan de travail : 20 à l'avant, 0 à l'arrière).

**Usinage.**
- Équerres ou taquets d'assemblage par-dessous (vissés dans le plateau sans le traverser : vis ≤ T − 3).
- Ou tourillons dans les chants hauts des côtés.

### R13 · Joue et fileur (`joue`, `fileur`)
- **Joue** : panneau de finition plaqué en R5 sur un côté visible, dépassant devant de l'épaisseur de la porte.
- **Fileur** : bande entre le meuble et le mur, en R2 sur le côté.

Ces deux pièces n'ont pas de perçage de structure, seulement des vis de jonction par l'intérieur.

---

## 6. Le solveur (construction du meuble)

### 6.1 Graphe
- **Nœuds** : les pièces, plus le **Sol** et le **Mur** (pièces virtuelles fixes).
- **Arêtes** : les relations. Chaque relation sait placer A depuis B **et** B depuis A (formules inverses), donc l'ordre de saisie n'a pas d'importance.

### 6.2 Algorithme
```
placer(projet):
  ancre = piece choisie, sinon la plus grande pièce de rôle tablette (dessous), sinon la plus grande pièce
  fixer(ancre, orientation à plat, position actuelle)
  file = relations touchant l'ancre
  tant que file non vide:
    r = la relation la plus « rigide » de la file   // priorité : bout/applique > rainure > articulé > coulissant > support
    p = la pièce de r pas encore placée
    si p déjà placée:                              // boucle : vérifier au lieu de placer
       e = ecart(r)                                // distance à la position voulue
       si e > 0,5 mm: conflit(r, e)                // ex. « le dessus fait 564, l'écart entre côtés vaut 580 »
       continuer
    placer_depuis(r, p)                            // formules du § 5
    file += relations de p
  orphelines = pièces non placées                   // contrôle « pièce reliée à rien »
  redresser()                                       // § 6.3
  appliquer_supports()                              // monte sur les pieds, accroche au mur…
  calculer_cotes_deduites()                         // § 6.4, puis replacer si une cote a changé (2 passes au plus)
```

### 6.3 Redresser
Le meuble doit finir debout, face avant vers −Z :
- `bas` = la face de l'ancre déclarée « au sol » (par défaut la face −Y du dessous) ;
- `avant` = le chant de l'ancre relié par une relation `articule` ou `coulissant` (là où sont les portes), sinon le chant choisi ;
- on applique au meuble entier la rotation (parmi les 24) qui envoie `bas → −Y` et `avant → −Z`, puis une translation pour que le point le plus bas soit à `y = 0` (ou à la hauteur des pieds) et le coin avant gauche à `x = 0, z = 0`.

### 6.4 Cotes déduites
Une cote marquée `deduite` est calculée par le solveur à partir de deux relations opposées :
- un dessus `etire` entre `coteG.face+X` et `coteD.face−X` a pour longueur l'écart entre les deux faces ;
- un fond en rainure prend l'ouverture + 2 × (profondeur − 1) ;
- une façade prend l'ouverture ± les recouvrements et les jeux.

Les cotes déduites sont calculées **avant** la découpe : le débit utilise toujours les vraies valeurs.

### 6.5 Messages du solveur
| Cas | Message |
|---|---|
| boucle incohérente | « Relation 4 : le dessus (564) ne touche pas le côté droit (écart 16 mm). Longueur déduite ? » + bouton « rendre déduite » |
| pièce orpheline | « Fond : relié à rien, il restera à sa place sur la feuille. » |
| sur-contrainte | « Le côté droit est placé par 2 relations qui ne concordent pas (12 mm). » |
| orientation impossible | « Le chant bas de la porte ne peut pas toucher la face du dessous en applique : choisissez son chant arrière. » |

---

## 7. Relations retrouvées depuis la géométrie (mode dessin libre)

Quand on dessine librement ou qu'on importe une scène, les relations sont **proposées** d'après les contacts :

```
pour chaque paire (A, B) de pièces de structure:
  ov = recouvrement sur les 3 axes
  si contact sur un axe k (écart ≤ 0,5) et recouvrement ≥ 12 mm sur les deux autres:
     si A présente sa face et B son chant → R1 (B bout sur A) ou R2, selon qui dépasse
     si les deux présentent leur face → R5
     si les deux présentent leur chant → rien, ou onglet si les chants sont biseautés
  si A est mince (≤ 10) et se trouve dans B jusqu'à 12 mm → R6
  façades (porte, tiroir) devant un chant → R3 ou R4
```

Ces relations proposées s'affichent en pointillés, et l'utilisateur les valide ou les change. C'est ce que fait l'usinage actuel, mais en silence.

---

## 8. Usinage : règles du métier

Toutes les cotes sont réglables. Les valeurs par défaut sont celles du moteur actuel.

### 8.1 Règles générales
- Distance minimale entre un trou et un chant : **8 mm**. Entre deux trous : **10 mm** de matière.
- Profondeur d'un trou borgne dans une face : au plus **T − 6** (on ne traverse jamais une face visible).
- En cas de collision entre deux éléments (station de jonction / embase de charnière / taquet / rainure) : on décale l'élément le moins prioritaire de ±32 mm, sinon on le supprime et on le signale.
  Ordre de priorité : charnière > coulisse > jonction > taquet.

### 8.2 Jonction chant contre face (R1, R2)
**Stations** le long de la jonction `[l0, l1]` (`len = l1 − l0`) :
- `len < 60` : 1 vis au milieu ;
- `len < 200` : 2 tourillons à 32 des bouts + 1 vis au milieu ;
- sinon : tourillons à 32 des bouts, vis à 96 des bouts puis tous les **400 mm** au plus ; si `len > 600`, un tourillon entre deux vis.

**Perçages selon l'assemblage** :

| Assemblage | Face de l'hôte | Chant de l'invité |
|---|---|---|
| Confirmat Ø7×50 | Ø8 traversant + fraisage de tête (ou cache) | Ø5 × 45, à mi-épaisseur |
| Tourillon Ø8×35 | Ø8 × 12 (T = 18) | Ø8 × 25 |
| Minifix Ø15 | Ø15 × 13 à 34 du chant (face intérieure de l'invité) + Ø8 × 34 dans le chant | tige Ø5 × 11 dans la face de l'hôte |
| Vis bois Ø4×40 | avant-trou Ø4,5 traversant + fraisage | avant-trou Ø2,5 × 30 |
| Vis de poche Ø4×30 | — | trou de poche à 15°, dans la face cachée de l'invité |
| Lamelle n° 20 | rainure de 4 × 10 | rainure de 4 × 10 |
| Tourillons collés seuls | tous les postes deviennent des tourillons | |

### 8.3 Fond
- Fond épais (≥ 16) : traité comme une jonction (R1).
- Fond mince en rainure (R6) : la rainure, sans vis.
- Fond mince cloué (R7) : clous ou agrafes tous les 150 mm sur le pourtour.

### 8.4 Charnières (R3)
- **Nombre** selon la hauteur de la porte : ≤ 900 → 2, ≤ 1600 → 3, ≤ 2000 → 4, au-delà → 5.
- **Positions** : à 100 mm du haut et du bas, puis réparties régulièrement ; on décale de 32 en cas de collision avec une tablette, une traverse ou une coulisse.
- **Porte** : boîtier Ø35, profondeur 13, axe à 22,5 mm du chant côté charnière (distance de perçage 5 mm), 2 trous de fixation Ø2,5 si nécessaire.
- **Caisson** : embase de 2 trous Ø5 × 12 sur le côté, à 37 mm de l'avant, entraxe 32.
- **Variantes** : mini Ø26 si T ≤ 16 ; charnière pour verre sans perçage de la porte ; push-open avec un poussoir au milieu du chant opposé ; charnière piano sur toute la hauteur.

### 8.5 Coulisses (R4)
- Longueur : celle du commerce, juste inférieure à la profondeur utile − 10.
- Montants : 2 vis par élément de coulisse, à 37 mm de l'avant puis selon le gabarit de la coulisse.
- Caisson de tiroir : côtés percés pour la coulisse, avant et arrière assemblés en R1 (2 vis par jonction), fond en rainure.

### 8.6 Système 32 (R9)
Rangées à 37 mm de l'avant et de l'arrière de chaque montant, trous Ø5 × 12, pas de 32, de la tablette − 96 à + 96, jamais sous 64 mm du bas ni à moins de 64 mm du haut.

### 8.7 Pieds, roulettes, suspension (R10, R11)
- Pieds : platine vissée (4 vis Ø4 × 16) ou trou de Ø10 pour un pied à clipser.
- Clips de plinthe : 1 par pied avant.
- Suspension : boîtier dans le coin haut (encoche du fond ou fond découpé), 2 vis sur le côté.

### 8.8 Poignées
- **Entraxe** selon la largeur : < 250 → 96, < 450 → 128, < 900 → 160, au-delà → 320.
- **Porte de meuble bas** : verticale, à 75 mm du chant opposé aux charnières, axe à 130 mm du haut.
- **Porte de meuble haut** : à 130 mm du bas.
- **Colonne** : axe à 1050 mm du sol.
- **Tiroir** : horizontale, centrée, à 55 mm du haut.
- **Perçage** : Ø5 traversant, ou aucun pour un profil Gola (la gorge est sur le caisson) ou une poignée intégrée (fraisage du chant de la façade).

### 8.9 Bande de chant
Elle est déduite du rôle et de la visibilité, puis modifiable chant par chant :

| Rôle | Chants à plaquer par défaut |
|---|---|
| porte, façade de tiroir, abattant | les 4 |
| montant | avant (+ haut s'il est visible) |
| tablette fixe ou mobile | avant |
| traverse avant | avant |
| dessus visible, plateau | les 4 (ou les 3 visibles) |
| plinthe | haut (+ bas en milieu humide) |
| fond, caisson de tiroir caché | aucun (côtés de tiroir : haut) |

Épaisseurs : 0,4 (chants cachés), 1 (standard), 2 (chants exposés aux chocs). Les épaisseurs choisies modifient les cotes de débit (§ 3).

---

## 9. Découpe

### 9.1 De la pièce au morceau à couper
Pour chaque pièce : cote de débit (§ 3), matériau, fil, chants à poser, étiquette. On regroupe par matériau et épaisseur : une série de feuilles par groupe.

### 9.2 Découpe manuelle (déjà en place)
Tu coupes la feuille à la guillotine (grande coupe, petite coupe, parallèles, cercle CNC). Chaque morceau issu d'une coupe garde un identifiant ; quand tu le lies ou le nommes, il devient une pièce du meuble.

### 9.3 Découpe automatique
**Guillotine par bandes**, compatible avec une scie à panneaux :
```
trier les pièces par largeur décroissante (en profondeur de bande), puis par longueur
pour chaque pièce:
  essayer chaque bande ouverte où largeur ≤ profondeur de la bande et reste en X ≥ longueur (+ trait de scie)
  sinon, si sans fil : essayer tournée de 90°
  sinon ouvrir une nouvelle bande dans la feuille courante (profondeur = largeur de la pièce)
  sinon nouvelle feuille
dans chaque bande : pièces moins profondes que la bande → coupe de recoupe en Z
```
- Trait de scie (4) déduit à chaque coupe, recoupe des bords (4) au départ.
- **Ordre des coupes** : d'abord les coupes en Z de pleine longueur (bandes), puis les coupes en X dans chaque bande, puis les recoupes : c'est l'ordre réel à la scie.
- **Chutes** : tout rectangle restant d'au moins 200 × 100 va dans le **stock de chutes**, avec sa matière et ses dimensions, et sera utilisé en priorité au prochain débit.
- **CNC** : placement libre (nesting) possible, avec les découpes circulaires et les formes ; le moteur de débit de la cuisine (`nest_worker`) peut servir.

### 9.4 Étiquettes
Chaque pièce porte : identifiant, nom, meuble, cotes de débit, chants à poser (marqués sur le dessin de la pièce), sens du fil, face des perçages, et un QR code vers la fiche de la pièce.

---

## 10. Contrôles

| Contrôle | Gravité | Seuil ou règle |
|---|---|---|
| deux pièces se chevauchent | bloquant | > 0,5 mm sur les 3 axes (sauf fond en rainure ≤ 12, onglet) |
| pièce orpheline | à vérifier | aucune relation |
| relation incohérente (boucle) | bloquant | écart > 0,5 mm |
| pièce plus grande que la feuille | bloquant | débit > feuille − 2 × recoupe |
| pièce trop petite pour la scie | à vérifier | < 50 mm de large ou < 100 de long |
| épaisseur différente de la matière choisie | à vérifier | |
| assemblage incompatible avec l'épaisseur | bloquant | Confirmat si T < 16, Minifix si T < 15 |
| perçage trop près d'un chant | bloquant | < 8 mm |
| perçage qui traverse une face visible | bloquant | profondeur > T − 6 |
| charnière en collision | à vérifier | décalée automatiquement, sinon signalée |
| porte sans jeu | bloquant | jeu < 1 mm avec une façade ou un mur voisin |
| coulisse trop longue | bloquant | > profondeur utile − 10 |
| meuble en l'air | bloquant | aucun support et rien dessous |
| meuble haut sans suspension | bloquant | |
| porte trop lourde pour ses charnières | à vérifier | > 12 kg pour 2 charnières (densité MDF ≈ 750 kg/m³) |
| tablette qui fléchit | à vérifier | portée > 800 en 18 mm (> 900 en 22) sans appui |
| plinthe plus haute que les pieds | bloquant | |

---

## 11. Ordre de montage et notice

L'ordre découle du graphe, en remontant depuis l'ancre :
1. **Préparation** : poser les chants, faire les perçages (liste par pièce), monter les embases et les taquets.
2. **Structure** : l'ancre, puis les relations R1 et R2, dans l'ordre du solveur (les pièces qui en portent d'autres d'abord).
3. **Fonds** : en rainure pendant la structure, cloués ou vissés après.
4. **Supports** : pieds, socle ou suspension, avec le meuble à l'envers sur une couverture.
5. **Façades** : portes (clipser sur les embases), tiroirs (coulisses puis façades), poignées.
6. **Réglages** : charnières en 3 axes, aplomb des façades, plinthe.

Chaque étape liste ses pièces (avec leur étiquette) et sa quincaillerie. On peut générer la notice en PDF, avec une vue 3D par étape (pièces déjà montées en gris, pièces de l'étape en couleur).

---

## 12. Quincaillerie et coût

- Liste agrégée par article : vis, tourillons, charnières + embases, coulisses, pieds, clips, poignées, mètres de chant par épaisseur, colle.
- Prix : feuilles d'après le tarif choisi (prix publics), quincaillerie d'après la marque choisie, main-d'œuvre optionnelle (minutes par coupe, par perçage, par mètre de chant).
- Le coût s'affiche en direct, et un écart s'affiche dès qu'une modification change le nombre de feuilles.

---

## 13. Exemples de recettes

### 13.1 Caisson bas 1 porte (ton exemple), chiffré
Paramètres : `L = 600, H = 750, P = 600, T = 18, pieds = 100, jeu = 3`. Profondeur caisson `Pc = P − T − 2 = 580`.

| Pièce | Rôle | Finie | Chants (1 mm) | Débit |
|---|---|---|---|---|
| coteG, coteD | montant | 750 × 580 | avant | 750 × 579 |
| dessous | tablette | (L − 2T) × Pc = 564 × 580 | avant | 564 × 579 |
| traverseAv, traverseAr | traverse | 564 × 100 | traverseAv : avant | 564 × 99 / 564 × 100 |
| fond | fond | 564 × (H − 2T) = 564 × 714 | — | 564 × 714 |
| porte | porte | (L − 3) × (H − 3) = 597 × 747 | 4 | 595 × 745 |
| plinthe | plinthe | L × (pieds − 3) = 600 × 97 | haut | 600 × 96 |

Relations :
```
R2 applique  coteG.bas      → dessous.gauche
R2 applique  coteD.bas      → dessous.droite
R1 bout      traverseAv.gauche → coteG.face+X   (alignement : avant, à fleur du haut, longueur etire jusqu'à coteD)
R1 bout      traverseAr.gauche → coteG.face+X   (alignement : arrière)
R1 bout      fond.bas       → dessous.face+Y    (à fleur de l'arrière, etire entre les côtés, jusqu'à traverseAr)
R3 articule  porte          → ouverture(coteG, coteD, dessous, traverseAv)  applique, jeu 3, charnières à gauche
R10 support  pieds vérins 100, plinthe retrait 50
```

Usinage obtenu (règles du § 8) : environ **18 Confirmat et 24 tourillons**, **2 charnières**, **4 pieds**, **2 clips**.
Découpe (feuille 2800 × 2070) :
- bande de 580 : 2 côtés + dessous ;
- bande de 747 : porte + fond ;
- bande de 100 : 2 traverses + plinthe ;
- chute réutilisable de 2792 × 623.

Hauteur sous le plan de travail : 850.

### 13.2 Caisson haut 2 portes
- Paramètres : `L = 800, H = 720, P = 350`.
- Côtés pleine hauteur ; dessus et dessous en R1 entre les côtés ; fond de 8 mm en rainure (R6) ; 1 tablette mobile (R9) à H/2.
- 2 portes en R3 de `(L − 3 − 3)/2 × (H − 3)`, charnières à gauche et à droite.
- R11 suspension : 2 boîtiers + rail de L − 20.
- Contrôle : porte ≤ 600 de large, sinon proposer 2 portes.

### 13.3 Colonne 2 portes + tablettes
- `L = 600, H = 2100, P = 580`, pieds 100.
- Côtés pleine hauteur, dessus et dessous en R1, tablette fixe à 1300 (raidisseur), `n` tablettes mobiles.
- Portes : 2 portes superposées (H1 = 1300 − jeu, H2 = reste), charnières selon la hauteur (3 et 2).
- Contrôle : sans tablette fixe, une hauteur > 1600 demande un raidisseur.

### 13.4 Caisson à tiroirs
- `n_tiroirs = 3`, hauteurs des façades en proportion (1 : 1 : 2) ou imposées.
- Pour chaque tiroir : R4 avec son caisson de tiroir généré (§ 5, R4) et ses coulisses de `slideLength(Pc − 10)`.
- Traverse avant remplacée par une traverse arrière + 2 traverses avant si la façade du haut est une fausse façade (sous un évier).

### 13.5 Étagère murale ouverte
- `L, H, P, n_etageres`, sans façade.
- Côtés + `pour i de 1 à n` tablettes fixes en R1 à `i × H / (n + 1)`.
- Dessus et dessous en applique (R2) sur les côtés, pour masquer les chants.
- R11 suspension par tasseau biseauté.
- Chants : tous les chants avant + les chants des côtés en haut et en bas.

### 13.6 Table
- Plateau (R12, débord 30 tout autour) sur une ceinture : 4 bandeaux de 100 de haut en R1 entre eux, avec des onglets aux angles si souhaité.
- 4 pieds en panneaux doublés (R5), ou pieds achetés (R10, platine vissée).
- Contrôle : portée du plateau > 900 en 18 mm → un raidisseur sous le plateau.

### 13.7 Banc
- Assise (R12) sur 2 joues pleines (R1 sous l'assise), avec une traverse basse en R1 entre les joues (contreventement).
- Contrôle de flexion : assise de 1200 en 22 mm, traverse obligatoire.

---

## 14. Bibliothèque paramétrique

Enregistrer une création en fait une **recette** :
1. On enregistre pièces + relations + réglages.
2. On repère les **dimensions maîtresses** : largeur, hauteur et profondeur hors tout ; l'utilisateur peut en ajouter (hauteur d'une tablette…).
3. Pour chaque cote de pièce, on choisit sa loi de variation (proposée automatiquement, puis modifiable) :
   - **fixe** : épaisseurs, traverses de 100, retraits ;
   - **suit** une dimension maîtresse : un côté suit H et P ;
   - **déduite** par le solveur : un dessus entre les côtés.
4. Reposer la recette avec d'autres cotes → nouvelles cotes, nouveau débit, nouvel usinage, et les contrôles revérifiés (« porte de 900 : 2 portes conseillées »).

Les assistants « en dur » (le caisson 1 porte actuel) deviennent des recettes livrées avec l'application, dans un fichier JSON.

---

## 15. Interface

### 15.1 Parcours
| Étape | Écran | Outils |
|---|---|---|
| 1. Créer | accueil : Nouveau (feuille, recette, vide), Ouvrir, Bibliothèque | |
| 2. Pièces | vue 2D de dessus de la feuille, ou fiche de recette avec ses paramètres | Couper (X, Y, petite, parallèles, cercle), Importer un débit, Découpe auto |
| 3. Relations | écran partagé : 2D à gauche, 3D assemblée à droite, mise à jour en direct | Lier (type, chants, options), liste des relations (modifier, supprimer, réordonner) |
| 4. Usiner | 3D avec les perçages ; liste par pièce | changer l'assemblage d'une relation, déplacer une station, ajouter un perçage |
| 5. Vérifier | panneau des contrôles, un clic sélectionne les pièces | |
| 6. Sortir | PDF découpe, étiquettes, plans pièce par pièce, notice, quincaillerie, export CNC (DXF ou CSV) | |

### 15.2 Lier les chants (interaction)
1. Au survol, le chant s'allume (vert, épais) et affiche son nom (`bas`, `avant`…) quand la pièce est déjà orientée.
2. 1er clic : chant de A ; 2e clic : chant ou face de B.
3. Le **type est proposé** d'après les rôles et la géométrie : façade → articulé, pièce mince → rainure, sinon bout ou applique. On peut le changer avec un sélecteur de type à côté du curseur.
4. La relation apparaît, numérotée, avec des hachures sur les deux chants ; la 3D se met à jour.
5. Un clic sur le numéro ouvre ses options : alignement, jeu, assemblage, inverser A et B.

### 15.3 Retours visuels
Couleur par type de relation, pièces orphelines en rouge pâle, cotes déduites en italique, conflits avec un trait rouge entre les deux pièces concernées.

---

## 16. Format de fichier et compatibilité

- `ProjetArt` version 2 = version 1 (panneaux libres, liaisons, coupes d'angle, assemblages par jonction) + `relations`, `parametres`, `supports`, `decoupe`.
- **Migration** :
  - chaque `edgeLink` (Lier actuel) devient une relation R1 (`over = false/true`) ou R2 (`outside = true`) ;
  - les panneaux d'un ancien dessin sans relation reçoivent les relations proposées par le § 7 (à valider).
- **Recette** : fichier JSON séparé (`recettes/*.json`), versionné, avec ses tests d'exemple (cotes attendues).

---

## 17. Tests de validation

1. **Banc de meubles** : chaque recette du § 13 est construite à 3 tailles (petite, standard, grande), et on vérifie :
   - zéro contrôle bloquant ;
   - hors-tout = paramètres ;
   - pièces finies et débit attendus ;
   - nombres de vis, tourillons, charnières, pieds ;
   - toutes les pièces sur le nombre de feuilles attendu.
2. **Invariance d'ordre** : saisir les relations dans un ordre aléatoire donne le même meuble.
3. **Invariance d'orientation** : couper les pièces dans n'importe quel sens sur la feuille (tournées, retournées) donne le même meuble.
4. **Aller-retour** : enregistrer → recharger → même meuble, mêmes perçages ; recette → autres cotes → contrôles cohérents.
5. **De bout en bout dans l'interface** : feuille → coupes → liens → Usiner → PDF, pour le caisson bas, une étagère et une table.
6. **Collisions d'usinage** : charnière face à une tablette, rainure face à une jonction → décalage de 32 ou message.

---

## 18. Plan d'implémentation

| Étape | Contenu | Fichiers |
|---|---|---|
| 1 | Orientation (24 cas), chants et faces nommés, relations typées R1, R2, R3, R6 et R10, solveur avec boucles, cotes déduites et « redresser » ; migration de `edgeLinks` | `engine/art_relations.dart` (nouveau), `engine/art.dart` |
| 2 | Usinage piloté par les relations (R1/R2 jonctions, R3 charnières, R6 rainures, R10 pieds + plinthe) ; ordre de priorité et collisions | `engine/art_machining.dart` |
| 3 | Recettes JSON + langage de formules + recettes livrées (caisson bas, haut, colonne, étagère) ; l'assistant 1 porte devient une recette | `engine/art_recipes.dart`, `assets/data/art_recipes.json` |
| 4 | Interface : Lier avec choix du type et chants nommés, liste des relations, panneau des contrôles, fiche de recette | `ui/art_page.dart`, `ui/art_relations_ui.dart` |
| 5 | R4 tiroirs (caisson de tiroir généré), R9 taquets, R11 suspension, R12 plateau, R8 onglets | moteur + recettes |
| 6 | Découpe automatique en bandes + stock de chutes ; étiquettes ; notice de montage ; export CNC | `engine/art_cut_auto.dart`, `ui/art_blueprint_pdf.dart` |
| 7 | Bibliothèque paramétrique (enregistrer une création comme recette) | `ui/art_library.dart` |

Chaque étape se termine par les tests du § 17 sur au moins 3 meubles différents.

### Avancement

- **Fait** :
  - liaisons typées `bout`, `applique` et `articule`, avec le chant de b nommé (`bas`, `haut`, `avant`…) et un retrait le long du chant ;
  - solveur à ordre libre, qui signale les conflits et les liaisons non résolues ;
  - support pieds + plinthe ; le meuble monté se pose à côté des chutes ;
  - langage de formules et 5 recettes (caisson bas 1 porte, caisson haut 2 portes, colonne 2 portes, étagère, caisson 1 porte simple) ;
  - découpe à la guillotine sur une ou plusieurs feuilles ;
  - interface : Nouveau → Meuble, « Meuble depuis cette feuille », type de liaison dans Lier ;
  - tests sur 12 tailles de meubles (`test/art_recipes_test.dart`).
- **Reste** :
  - redresser (meuble construit couché) ;
  - relations rainure, feuillure, onglet, coulissant (tiroirs) et taquets comme vraies relations ;
  - usinage lu dans les relations plutôt que déduit des contacts ;
  - déduction des chants dans les cotes de débit ;
  - liste des relations modifiable et panneau des contrôles ;
  - bibliothèque paramétrique ;
  - notice de montage ;
  - export CNC.
