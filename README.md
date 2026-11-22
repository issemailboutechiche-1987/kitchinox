# Kitchinox (Kitchen Planner)

Application professionnelle complète de conception, d'implantation 2D/3D, d'atelier de menuiserie sur mesure (Mode Art), de calepinage/débit de panneaux et de chiffrage/devis pour cuisines et agencements intérieurs.

## 📖 Documentation Complète pour Développeurs & IA

Pour une description exhaustive de l'architecture, de tous les modules, des algorithmes de coupe et des règles métier :
- 📘 **[Architecture Globale & Guide de Référence (KITCHINOX_MASTER_ARCHITECTURE.md)](KITCHINOX_MASTER_ARCHITECTURE.md)** *(Fichier conçu pour être transmis directement à des assistants IA comme Google Gemini ou Claude).*
- 📐 **[Moteur du Mode Art & Usinage (docs/mode_art_moteur.md)](docs/mode_art_moteur.md)** *(Spécification mathématique et règles d'assemblage des meubles en panneaux).*

---

## 🚀 Fonctionnalités Clés

1. **Conception d'Implantation 2D / 3D** :
   - Vue de dessus (plan coté), vue de face (élévation) et **rendu 3D temps réel réaliste (Three.js WebGL)**.
   - Catalogues complets pour Cuisines, Salles de bain, Dressings, Buanderies et Meubles TV.
   - Habillage automatique des joues et côtés visibles de colonnes (`endPanelFinish`).

2. **Mode Art (CAO & Usinage Paramétrique)** :
   - Outils de dessin 2D complets (Ligne à 90°, Rectangle, Arc, Cercle, Polygone, Main levée).
   - Outils de manipulation (Déplacer, Pivoter, Échelle, Symétrie/Miroir).
   - Outil **Pousser / Tirer** (Extrusion 3D) avec épaisseurs de panneaux standards (18, 16, 19, 12, 6 mm...).
   - Usinage automatique complet : vis, tourillons 8×30 mm, charnières invisibles 35 mm, coulisses, pieds réglables, plinthes, bandes de chant et rainures.

3. **Optimisation de Découpe (Nesting & Guillotine)** :
   - Algorithmes de calepinage avec gestion du trait de scie, rognage de rives et sens du fil.
   - Gestion distincte des 3 formats de panneaux : **Caissons** (ex. Latté 2100×2020), **Façades** (ex. MDF 2800×1220), **Fonds** (ex. HDF 6mm).
   - **Export sélectif SketchCut (`.sct`)** multi-fichiers avec dialogue de sélection.

4. **Exports Industriels & Production** :
   - Dossiers techniques PDF vectoriels (plans cotés, schémas de calepinage, étiquettes QR code).
   - Devis client et bons de commande fournisseurs en PDF et Excel.
   - Sauvegarde et partage de projets au format compressé `.kin`.

---

## 🛠️ Commandes Utiles

```bash
# Vérifier la qualité du code (0 erreur, 0 avertissement)
dart analyze lib/

# Exécuter les tests unitaires
flutter test test/features_test.dart test/materials_test.dart test/engine_test.dart

# Lancer l'application sur Chrome
flutter run -d chrome

# Compiler pour Windows Desktop
flutter build windows

# Compiler l'application iOS (exécuté automatiquement par GitHub Actions)
# Voir .github/workflows/ios.yml
```
