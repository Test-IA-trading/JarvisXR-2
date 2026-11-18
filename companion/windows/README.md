# Discuter avec Qwen depuis l’iPhone

Sur le PC Windows où Ollama et `qwen3:8b` sont déjà installés, extrais l’archive de cette branche et double-clique sur **Demarrer-Jarvis.cmd** à la racine. Windows prépare le compagnon avec .NET Framework, puis Jarvis demande une vraie réponse à Qwen. La première réponse peut prendre plus de temps si le modèle doit être chargé en mémoire.

1. Garde la fenêtre ouverte. Elle affiche la réponse du modèle, une adresse et un code temporaire.
2. Sur l’iPhone connecté au même réseau domestique, ouvre **l’adresse affichée** dans Safari, puis saisis le code. Le PC peut être connecté en Ethernet. Dans l’app iOS construite à partir de cette branche, le menu **Chat avec mon PC** ouvre la même page.
3. Envoie « Retiens le prénom Léa pour cette discussion », puis « Quel prénom t’ai-je donné ? ». **Nouvelle discussion** efface les messages de la page. Fermer l’onglet termine aussi cette conversation.

Si Windows affiche une demande de pare-feu, autorise le compagnon sur le **réseau privé** de la maison. Si le lanceur affiche `127.0.0.1`, le chat est accessible sur le PC seul. Vérifie que Windows classe ton réseau domestique comme **Privé**, puis relance. Le Wi-Fi invité peut isoler les appareils.

## Portée de cette version

La page utilise HTTP sur le réseau local. Le code contrôle l’accès au chat et change à chaque démarrage. Le code et les messages circulent en clair sur ce réseau. Utilise ton réseau de confiance. Ollama est appelé sur `127.0.0.1:11434`. Seul le compagnon écoute sur l’adresse privée du PC, au port 8765. Il accepte les connexions du même sous-réseau et relaie uniquement les conversations. **Ctrl+C** ou la fermeture de la fenêtre arrête le compagnon.

La page affiche la conversation de l’onglet. À chaque question, elle propose jusqu’à quatre échanges précédents. Le compagnon garde des paires question-réponse entières jusqu’à 4 200 caractères avec la question du moment. Qwen utilise un contexte de 4 096 tokens et un maximum de 512 tokens de sortie pour ce chat. Ces réglages s’appliquent uniquement aux requêtes du compagnon. Il n’y a aucune écriture des conversations par le compagnon.

## Vérifier le PC ou travailler sur le dépôt

Dans PowerShell, à la racine du projet :

```powershell
.\Demarrer-Jarvis.cmd --check
```

Cette commande affiche la réponse de Qwen puis se termine. Pour discuter uniquement sur le PC, utilise `.\Demarrer-Jarvis.cmd --pc`.

Pour travailler avec l’agent local depuis une copie Git de la branche :

```powershell
ollama launch claude --model qwen3:8b -- --permission-mode default
```

Le projet sélectionne aussi le mode manuel dans `.claude/settings.json`. Les demandes de modification suivent les permissions de la session Claude Code. L’API de chat ne donne aucun accès à cet agent de développement.

Cette édition modifiée du 18 novembre 2026 est basée sur [JARVIS XR by Amrik Majumdar](https://github.com/Amrik-Majumdar/JarvisXR).
