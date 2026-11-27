# Suivi de la refonte

Référence : [VISION_JARVIS.md](VISION_JARVIS.md). Chaque entrée distingue ce qui est écrit, ce qui est testé
(tests automatisés, simulateur) et ce qui est vérifié sur l'iPhone. Rien de ce fichier ne vaut validation sur
appareil tant que la ligne « iPhone » ne le dit pas.

## Point de reprise (à lire en premier)
- Branche de travail : `feature/vision-jarvis-autonome`, partie de `feature/jarvis-v10-iphone` (PR nº 35, pile
  nº 5 à nº 35 non fusionnée) avec `develop` fusionné (PR nº 36 : cahier des charges). Aucune branche de
  référence modifiée ; retour en arrière : revenir à `feature/jarvis-v10-iphone` (commit `24f66b4`).
- Pas de compilateur Swift sur le PC de développement : la logique pure est rejouée en Python (ports dans le
  répertoire de travail de Claude), le Swift est relu à la main, puis compilé et testé par la CI macOS
  (`.github/workflows/ios-build.yml`, environ 1 h 30 par exécution).
- Prochaine action : voir « Lots » ci-dessous, premier lot non coché.

## Lots de la refonte (P0 d'abord, §30)
| Lot | Contenu | État |
|---|---|---|
| A · Écoute | Fin de tour plus patiente, ponctuation du reconnaisseur prise avec prudence, voix encore entendue qui repousse la fin, reconnaissance Apple relancée et recousue après un `isFinal` | Écrit, port Python 22/22, XCTest ajoutés ; CI à passer ; iPhone à tester |
| B · Latence du cerveau | Cache KV réutilisé (préfixe commun), règles fixes en tête du prompt, préchauffage à l'ouverture du micro, mesures premier mot / jetons réutilisés | Écrit, XCTest ajoutés ; CI à passer ; gain à mesurer sur iPhone |
| C · Mémoire réelle | Diagnostic Obsidian, mémoire qui répond aux questions sur elle-même, recherche par lemmes et sens, réponses réutilisées, journal des conversations | En cours |
| D · Sécurités | Arrêt d'urgence indépendant, contrôle « zéro frais » des appels réseau, réinitialisation complète | À faire |
| E · Caméra | Désactivation temporaire réversible (§22) | À faire |
| F · Voix | Voix plus grave et mature (§23), sans effort disproportionné | À faire |

## Journal
### 27 novembre 2026 — audit et lots A, B
- Synchronisation : `develop` (f129643) fusionné dans la branche de travail sans conflit ; travaux locaux intacts.
- Audit (code lu, pas d'essai sur appareil) :
  - Écoute coupée trop tôt : seuils de 0,55 s après un « ? » que le reconnaisseur écrit lui-même avant la fin
    de l'idée ; le silence ne tenait compte que des mots écrits, pas de la voix encore entendue ; un `isFinal`
    d'Apple terminait la demande immédiatement.
  - Latence : `llama_memory_clear` à chaque question, donc environ 900 jetons de règles recalculés avant le
    premier mot ; règles variables (humour, longueur) placées avant les règles fixes ; un prompt trop long
    était tronqué par le début (perte des consignes).
  - « Obsidian inaccessible » : la consigne du modèle disait « tu n'as accès ni […] aux données de l'iPhone en
    dehors du contexte » ; la mémoire n'était cherchée que par mots identiques, et seulement pour le modèle
    embarqué ; aucune réponse réutilisée (pas de gain à la répétition) ; aucun journal des conversations.
  - Caméra : aucun traitement visuel actif au repos (lancement seulement à l'ouverture de l'écran Vision),
    mais un accueil Vision au premier lancement et des commandes qui l'ouvrent.
- Tests réellement exécutés : port Python de la fin de tour (22 cas, voix/clic, délais, raccord) : tout passe.
  XCTest écrits, non exécutés localement (CI).
- Problèmes et limites : seuils à calibrer sur l'iPhone ; le gain de latence du lot B n'est pas mesuré.
