# Mesures et benchmarks

Voir [VISION_JARVIS.md](VISION_JARVIS.md), notamment §9, §20 et §26, et [CONVERSATION_NATURELLE.md](CONVERSATION_NATURELLE.md).

**Aucune mesure sur iPhone n'a encore été faite pour la refonte.** Les lignes « Après » attendent les essais de l'utilisateur sur la version de la branche `feature/vision-jarvis-autonome`.

| Indicateur | Avant (version 10, `24f66b4`) | Après (refonte) |
|---|---|---|
| Latence ASR / fin de tour | Non mesuré ; seuils du code : 0,55 s après « ? », 0,9 s ordinaire | Seuils du code : 0,8 / 1,2 / 1,5 / 2,2 / 2,6 s ; mesure iPhone à faire |
| Récupération mémoire | Non mesuré ; recherche par mots identiques | Non mesuré ; lemmes + sens, compteur « souvenirs consultés » |
| Chargement modèle | Non mesuré (`loadSeconds` existait) | Non mesuré ; chargé à l'ouverture du micro |
| Premier token / premier mot prononcé | Non mesuré ; prompt entier recalculé | Non mesuré ; `lastFirstTokenSeconds`, `lastReusedTokens` disponibles |
| Durée totale / appels externes | Non mesuré | Non mesuré |
| Réaction à l'interruption | Non mesuré | Non mesuré |
| Première question / question similaire | Non mesuré ; aucune réutilisation | Non mesuré ; réponse mémorisée immédiate attendue |
| RAM / stockage / énergie / température | Non mesuré | Non mesuré |
| Stabilité, hors ligne, multitâche | Non mesuré | Non mesuré |

## Essais de logique réellement exécutés (PC de développement, sans iPhone)
- 27 novembre 2026, port Python de `JarvisTurnEndDetector` / `JarvisVoiceActivity` : 22 phrases françaises classées comme attendu, clic ignoré, hésitation de 0,5 s détectée, délai repoussé puis plafonné. Ce n'est pas une mesure de latence.
- `python tests/run_all_tests.py` (validation du dépôt, audit de confidentialité, PC 29/29) : réussi.

Pour chaque mesure : commit, appareil, version iOS, modèle et quantification, scénario reproductible, réseau, batterie, température, nombre d'essais, conditions à froid/à chaud, distribution et limites. Séparer tests automatisés, simulateur et appareil physique. Ne jamais inventer de résultats.
