# Feuille de route — refonte JarvisXR

Référence normative : [VISION_JARVIS.md](VISION_JARVIS.md), notamment §30. « Écrit » signifie présent dans le code et couvert par des tests automatisés ; rien n'est « validé » avant l'essai sur iPhone consigné dans [PROGRESS.md](PROGRESS.md).

| Priorité | Travaux | État |
|---|---|---|
| P0 | Audit, sauvegarde (branche dédiée), mesures disponibles dans l'app | Audit fait ; mesures iPhone à faire |
| P0 | Écoute : fin de tour, hésitations, reconnaissance recousue | Écrit (D1) |
| P0 | Latence du cerveau iPhone : cache KV, préchauffage | Écrit (D2) |
| P0 | Mémoire réelle : recherche, réponses réutilisées, questions sur la mémoire, journal | Écrit (D3) |
| P0 | Sécurités : arrêt d'urgence, zéro frais, confirmations, réinitialisation | Écrit (D4) |
| P0 | Caméra mise de côté | Écrit (D5) |
| P0 | Lot 1 de CONVERSATION_NATURELLE (parole réellement diffusée) | À faire |
| P1 | `SpeechAnalyzer` d'iOS 26 en option, comparé à `SFSpeechRecognizer` | À faire |
| P1 | Modèle local : banc d'essai sur l'appareil, candidats 2026 (D7) | À faire |
| P1 | Recherche Web gratuite sur l'iPhone (Wikidata, plusieurs Wikipédia), mémoire procédurale | À faire |
| P2 | Multitâche, conséquences, intégration iOS, apprentissage, auto-amélioration autorisée | À planifier |
| P3 | Énergie, stabilité, modularité voix, interface technique (mémoire, tâches, mesures) | À planifier |

Voix : plus grave par défaut et réglable à la voix (D6) ; voix définitive, esthétique et plafond de stockage restent à définir par l'utilisateur. Aucune dépense supplémentaire.
