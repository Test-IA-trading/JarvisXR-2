# Spécifications de Jarvis (intelligence, voix, personnalité)

Ce dossier reçoit les spécifications complémentaires (rédigées par exemple avec ChatGPT). Un fichier par sujet :

| Fichier | Sujet | Où le code l'applique |
|---|---|---|
| `intelligence.md` | compréhension, raisonnement, sources | PC : `pc/jarvis_pc/brain.py` (`difficulty`, `system_prompt`), `core.py` (`research`) · iPhone : `JarvisLocalBrain.swift`, `JarvisFrenchCommands.swift` |
| `voix.md` | écoute, mot « Jarvis », fin de phrase, interruption | iPhone : `JarvisVoiceInputService.swift`, `JarvisDuplexAudio.swift`, `JarvisWakeWord.swift`, `JarvisConversationFlow.swift` (`JarvisEchoFilter`) · PC : `wake.py` |
| `personnalite.md` | ton, vouvoiement, longueur, manière de parler | PC : `brain.py` (`system_prompt`) · iPhone : `JarvisChatPrompt` (`JarvisLocalBrain.swift`), `JarvisSpeechService.swift` |

## Règles pour une spécification

- Écrire des comportements vérifiables : « Après « non non », Jarvis se tait en moins de 0,5 s », plutôt que « Jarvis est réactif ».
- Donner des exemples de phrases réelles en français, avec la réponse attendue.
- Les règles qui doivent valoir sur l'iPhone et sur le PC sont écrites une fois : les deux codes s'y conforment, et des tests les vérifient (`ios/JarvisXR/JarvisXRTests`, `pc/tests`).
- Rien qui exige un service payant, un compte tiers ou l'envoi de données sans l'accord de l'utilisateur.

## Modules et points d'extension

- **Comprendre** une demande : règles françaises (`JarvisFrenchCommands.swift`, `phrasing.py`), puis le cerveau. Une nouvelle commande s'ajoute comme règle avec un test, sans toucher au reste.
- **Raisonner** : cerveau du PC d'abord (Qwen via Ollama), cerveau local de l'iPhone sinon. Le niveau d'effort vient de `difficulty()`.
- **Vérifier** : `core.research` réunit plusieurs sources gratuites. Une nouvelle source est une fonction de `internet.py` qui renvoie des lignes « Extrait de … : … ».
- **Parler, écouter** : la voix passe par le son de conversation (annulation d'écho). L'interruption suit `JarvisEchoFilter`.
- **Agir sur l'iPhone** : commandes natives (appels, messages, rappels, agenda, photos) et raccourcis de l'utilisateur (`shortcuts://run-shortcut`).
