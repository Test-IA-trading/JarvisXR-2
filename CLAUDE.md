# Instructions permanentes pour Claude Code — JarvisXR

## Point d'entrée
- Lire [docs/VISION_JARVIS.md](docs/VISION_JARVIS.md) : cahier des charges produit en 32 sections, issu des décisions validées par l'utilisateur. Il constitue la référence pour la prochaine refonte.
- Lire [docs/CONVERSATION_NATURELLE.md](docs/CONVERSATION_NATURELLE.md) pour les exigences vocales détaillées et les dialogues de recette.
- Consulter [docs/README.md](docs/README.md), les documents d'architecture, de test, de sécurité et de confidentialité, puis vérifier leur correspondance avec le code réel.
- Vérifier branche active, modifications locales et PR en cours avant tout changement. Ne pas écraser des travaux existants. Préserver main et develop ; utiliser une branche de travail dédiée.

## Règles non négociables
- Zéro frais supplémentaires. Modèles locaux, services gratuits et usages explicitement autorisés uniquement. Aucun contournement de quotas ou authentification.
- Intelligence et mémoire locales d'abord ; orchestration externe uniquement si utile et autorisée.
- Priorité à l'écoute française sans coupure prématurée, à la fluidité, à la mémoire réelle et aux performances.
- Contrôle utilisateur indépendant : arrêt d'urgence, confirmations proportionnées, réinitialisation, autorisation avant auto-modification du code.
- Confidentialité : dépôt public, aucun secret, donnée personnelle, conversation ou référence vocale privée dans Git.
- Ne pas contourner les protections iOS. Distinguer capacités réelles et objectifs.
- Caméra à désactiver temporairement lors de la refonte, en conservant le code réutilisable. Esthétique et voix définitives reportées.
- Audit, sauvegarde, mesures, implémentation, tests et non-régression ; ne pas présenter une simulation ou un test non effectué comme une réussite.

## Reprise et économie de contexte
Utiliser RTK si installé et adapté, sans diminuer la qualité. Lire les sections pertinentes de la vision en fonction de la tâche, sans oublier les contraintes transversales. Maintenir les fichiers de suivi ci-dessous à mesure des travaux. Reprendre depuis le dernier état vérifié après interruption. Ne pas dépenser au-delà des accès existants.
- docs/ROADMAP.md
- docs/PROGRESS.md
- docs/DECISIONS.md
- docs/BENCHMARKS.md
