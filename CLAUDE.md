# Développer JarvisXR 2.0

Les travaux de la version 2.0 partent de `develop` sur une branche dédiée. `main` conserve la version originale. Pour reprendre une tâche avec un contexte court, commence par la pull request correspondante, son diff contre `develop` et les seuls fichiers concernés.

Pour le chat local, le point d’entrée Windows est `Demarrer-Jarvis.cmd`. Le code du compagnon et sa page sont dans `companion/windows/`. Le menu de l’app appelle `presentPCChat()` dans `ios/JarvisXR/JarvisXR/JarvisPCChat.swift`. La discussion passe par le navigateur et l’API locale d’Ollama.

Sur Windows, `Demarrer-Jarvis.cmd --check` envoie une vraie question à Qwen. `python tests/windows_chat_smoke.py` exerce le compagnon avec un modèle simulé sur une machine de test. Dans les comptes rendus, indique quelle vérification a été exécutée et sur quel appareil. Les règles générales de contribution se trouvent dans [CONTRIBUTING.md](CONTRIBUTING.md).
