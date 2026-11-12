# Traductions de l'interface

Sources des traductions (cle = texte francais, valeurs = [anglais, arabe]) : translations*.json.

- todo.py <dossier> : releve les cles du code (tr, trf, trp, L) et les noms des catalogues, liste celles sans traduction.
- gen_dict2.py <dossier> : fusionne les fichiers et genere lib/ui/i18n_dict.dart.
- templ.py, fix_const.py : outils ayant servi a transformer les textes du code en appels de traduction.

Les chemins dans ces scripts pointent vers D:/kitchinox/kitchen_planner.
