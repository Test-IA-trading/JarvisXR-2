# Préparer Claude Code pour JarvisXR

Édition de développement du 19 novembre 2026, à partir de *JARVIS XR by Amrik Majumdar*. L’agent utilise le `qwen3:8b` installé sur le PC. Le lanceur d’Ollama 0.40.16 associe les rôles de modèle de Claude Code au modèle choisi. [Source du lanceur](https://github.com/ollama/ollama/blob/v0.40.16/cmd/launch/claude.go)

## Premier essai sous Windows

Double-clique sur **Agent-Jarvis.cmd** à la racine du dossier extrait. Il vérifie que les programmes et le modèle sont présents. Il crée un dossier neuf dans `%USERPROFILE%\JarvisAI-Test`, écrit une ligne aléatoire dans `entree.txt`, puis démarre Claude Code en mode manuel. Qwen reçoit les chemins absolus. Il doit lire la ligne avec `Read` et la recopier dans `sortie.txt` avec `Write`.

Lorsque Claude demande la permission d’écrire, autorise-la **une fois**. Après sa réponse, tape **`/exit`**. Le lanceur relit les deux fichiers et affiche **FICHIER VERIFIE** uniquement si la sortie contient la même ligne. Ce résultat prouve l’écriture sur disque. La demande de permission se vérifie à l’écran. Les deux fichiers restent dans le dossier de l’essai.

Pour coder ensuite dans ce dépôt, `Agent-Jarvis.cmd coder` lance une session avec les outils habituels. `Agent-Jarvis.cmd leger` propose le même modèle avec six outils de code. Les deux modes conservent la validation manuelle. Compare la même petite tâche dans deux sessions neuves. Relève si le résultat est juste et le temps écoulé. Dans Claude Code, `/context` montre les postes qui occupent le contexte. Pendant que Qwen répond, `ollama ps` dans un autre terminal indique le contexte alloué et la répartition CPU/GPU. On peut relever la VRAM utilisée dans le Gestionnaire des tâches au même moment. [Commandes Claude Code](https://code.claude.com/docs/en/commands) · [Contexte Ollama](https://docs.ollama.com/context-length)

## Outils examinés

| Outil | Version et usage retenus |
| --- | --- |
| [Token Optimizer](https://github.com/alexgreensh/token-optimizer/tree/f450eb6f3cf496e8cefc08500d88510394c4c4e8) | Le dépôt `alexgreensh/token-optimizer` correspond à la description de l’ancienne discussion. Son diagnostic `report` peut être appelé à la demande. Le plugin complet ajoute des hooks à plusieurs étapes, dont les appels d’outils. Le diagnostic a été exécuté sans réseau sur une copie des instructions. |
| [Claude-Mem](https://github.com/thedotmack/claude-mem/tree/cc0fb95154581052f3611698b6ab6ec48a08f3f0) | La version 16.0.0 enregistre des observations et appelle un modèle pour les traiter. Son fournisseur par défaut est Claude et un secours vers Claude est prévu. Le profil de configuration joint sélectionne Ollama sur le PC, `qwen3:8b`, un contexte limité au projet courant et la recherche SQLite. Il règle le fournisseur de secours sur `off`. [Paramètres de cette version](https://github.com/thedotmack/claude-mem/blob/cc0fb95154581052f3611698b6ab6ec48a08f3f0/src/shared/SettingsDefaultsManager.ts) |
| [Claude Code Router](https://github.com/musistudio/claude-code-router/tree/da96d5dfb4d3d7f91818043a1500c4a447f3cdcf) | La version 3.1.5 ajoute un service qui choisit un modèle selon des règles et peut enregistrer les requêtes. L’évaluation du routage prendra son sens lorsqu’un deuxième modèle aura réussi un essai réel avec les outils sur ce PC. |

Les liens précis des trois projets étudiés ici identifient les versions revues. L’examen de Claude-Mem et du routeur porte sur leur code de configuration, leurs points de déclenchement et leur documentation. Leur fonctionnement avec ce PC reste à vérifier.

## Mesurer les instructions

Avec la même version de Token Optimizer et un profil vide, le fichier d’instructions de la première branche de chat a été estimé à **312 tokens**. La version courte du fichier, qui renvoie les détails dans ce guide, en demande **120**. La différence est de **192 tokens estimés pour ce fichier**. L’outil applique un coût fixe au système et suppose par défaut une fenêtre de 1 million de tokens. Ces deux valeurs sont exclues du résultat Jarvis. La consommation totale de Claude Code, la vitesse, la qualité de Qwen et la VRAM se mesurent sur le PC.

Pour reproduire la mesure, lance `python dev/claude/budget.py` depuis le dépôt avec Python 3.11 ou plus récent. Le premier appel utilise Git pour récupérer la version épinglée. Le cache conserve environ 7,4 Mo de scripts. Leur empreinte est vérifiée avant chaque exécution. Le diagnostic travaille sur une copie temporaire des fichiers `CLAUDE.md` du projet, avec un profil vide. Il peut aussi utiliser une copie existante de ces scripts via `--scripts CHEMIN`. L’essai Windows par double-clic fonctionne indépendamment de Python et de Git.

## Essai de mémoire à préparer après la mesure

[claude-mem.local.json](claude-mem.local.json) est un profil d’essai pour Claude-Mem 16.0.0. Le lanceur Windows initial n’installe pas le plugin. Pour un essai ultérieur, utiliser ce profil comme `settings.json` dans un **nouveau dossier de données dédié à Jarvis**, désigné par `CLAUDE_MEM_DATA_DIR`, et attribuer au worker un port distinct des autres instances. Une fois le plugin installé dans le périmètre du projet, vérifier que l’observateur utilise bien l’URL locale et le modèle attendu avant d’y enregistrer des sessions. Comparer le temps du premier échange, puis la capacité à reprendre une information dans une deuxième session. [Fournisseur Ollama et traitement des observations](https://github.com/thedotmack/claude-mem/blob/cc0fb95154581052f3611698b6ab6ec48a08f3f0/docs/public/usage/openai-compatible-provider.mdx)
