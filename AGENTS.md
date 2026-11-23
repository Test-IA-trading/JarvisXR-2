# Reprendre JarvisXR

Travaille sur une branche issue de `develop`. Garde `main` pour l’original. Lis le diff et les fichiers utiles, puis suis `CONTRIBUTING.md`.

## Décisions en cours

- Claude Code utilise Qwen3 8B via Ollama. La priorité est de suivre correctement les consignes et de produire un résultat vérifiable. La RAM disponible peut être utilisée.
- La préparation de l’agent se poursuit dans la [PR 2](https://github.com/Test-IA-trading/JarvisXR-2/pull/2). Sur le fixe, Qwen a demandé l’autorisation de créer puis de corriger le fichier. Le premier essai avait une ligne vide en trop. Après correction, le lanceur a affiché `FICHIER VERIFIE`.
- Le relais de cette fiche a été vérifié entre deux copies Git. Le filtre de projet de Claude-Mem a passé quatre lectures SQLite sur données fictives. Le prochain essai sur le fixe porte sur le rappel d’une décision par Qwen en session neuve. Le profil Claude-Mem reste à essayer avec le plugin.
- Le premier essai à réaliser sur iPhone est de saisir un objet virtuel en pinçant le pouce et l’index devant la caméra, puis de le déplacer et de le déposer dans la scène. Cette interaction en réalité augmentée doit fonctionner hors ligne, PC éteint. Les réactions aux objets réels, la conversation en français et le suivi des tâches simultanées figurent aussi dans la [checklist des usages](docs/CHECKLIST_JARVIS_2.md). « Dis Jarvis » viendra plus tard. [Prototype iPhone](https://github.com/Test-IA-trading/JarvisXR-2/pull/1)

Après une décision ou un essai, actualise la ligne concernée sur la branche de travail. Indique le résultat observé et ce qui reste à vérifier. Garde ici seulement les éléments de développement partageables.
