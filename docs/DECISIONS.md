# Journal des décisions

## Exigences produit validées
Voir [VISION_JARVIS.md](VISION_JARVIS.md). Intelligence locale orchestratrice, mémoire façon Obsidian, zéro frais supplémentaires, contrôle utilisateur, confidentialité, fluidité et écoute en priorité ; caméra temporairement désactivée lors de la refonte. Voix et esthétique définitives, plafond de stockage et modèle local final restent à déterminer.

## Décisions techniques
Format : date, statut, problème, alternatives, sources, mesures, choix et justification, risques, compatibilité iOS et licences, coûts, tests, conditions de réexamen et rollback. Aucune décision ci-dessous n'est validée sur iPhone tant que [PROGRESS.md](PROGRESS.md) ne le dit pas.

### D1 · Fin de tour de parole (27 novembre 2026, appliquée, à calibrer)
- **Problème** : écoute coupée trop tôt (§2, §10). Code : 0,55 s de silence après un « ? » ou un « . » que le reconnaisseur d'Apple écrit lui-même avant la fin de l'idée ; silence mesuré seulement entre deux textes reçus, pas sur la voix ; un `isFinal` d'Apple terminait la demande.
- **Alternatives** : (a) seuils + activité vocale du micro + reconnaissance recousue ; (b) `SpeechAnalyzer`/`SpeechTranscriber` d'iOS 26 (reconnaissance longue sur l'appareil) ; (c) VAD neuronal (Silero via Core ML) ; (d) classifieur sémantique de fin de tour.
- **Choix** : (a) d'abord : aucune dépendance, aucun téléchargement, réversible, testable sans appareil. (b) est le meilleur candidat suivant pour la compréhension française (lot P1, derrière un réglage, repli sur `SFSpeechRecognizer`) : des retours de la bêta signalent un premier résultat lent, à mesurer sur l'iPhone 14 Pro avant d'en faire le défaut. (c) et (d) seulement si les mesures montrent des coupures restantes.
- **Valeurs** : 0,8 / 1,2 / 1,5 / 2,2 s, 2,6 s après « euh », « attends », « enfin » ; voix encore entendue : jusqu'à +2,5 s ; demande jusqu'à 60 s (12 reconnaissances recousues au plus).
- **Tests** : port Python 22 cas, XCTest `JarvisConversationFlowTests`. **Rollback** : annuler le commit `bbfce0b`. **Réexamen** : dialogues de recette 02, 06, 14 de CONVERSATION_NATURELLE sur l'iPhone (coupures, débuts perdus, délai ressenti).

### D2 · Cerveau iPhone : contexte réutilisé (27 novembre 2026, appliquée, gain à mesurer)
- **Problème** : `llama_memory_clear` à chaque question, environ 900 jetons de règles recalculés avant le premier mot ; un prompt trop long perdait son début (les consignes).
- **Alternatives** : réutilisation du préfixe commun du cache KV (llama.cpp `llama_memory_seq_rm`) ; MLX Swift ; un modèle plus petit ; Apple Foundation Models (exclu : l'iPhone 14 Pro n'a pas Apple Intelligence).
- **Choix** : préfixe réutilisé, règles fixes en tête (`JarvisChatPrompt.staticRules`), préchauffage à l'ouverture du micro (`JarvisLocalBrain.prepare`). Même moteur, aucun coût, repli sûr (effacement complet si la suppression partielle échoue, cas des modèles récurrents).
- **Mesures prévues** : jetons du prompt, jetons réutilisés, délai du premier mot (`JarvisLocalBrain.Measurement`). **Rollback** : annuler `44c870f`.

### D3 · Mémoire : native, au format Obsidian (27 novembre 2026, appliquée)
- **Diagnostic** « Jarvis dit ne pas avoir accès à Obsidian » : la consigne du modèle disait n'avoir accès à aucune donnée de l'iPhone ; « Qu'est-ce que tu sais sur moi » ignorait les notes apprises ; recherche par mots identiques seulement ; aucune réponse réutilisée.
- **Alternatives** : piloter l'app Obsidian (impossible : bac à sable iOS, aucune API pour une autre app) ; base SQLite FTS5 ; modèle d'embeddings téléchargé (Core ML, ~100 Mo) ; outils NaturalLanguage d'iOS (lemmes, embedding de phrases français, gratuits, hors ligne).
- **Choix** : garder le dossier Markdown « Mémoire Jarvis » (format ouvert, exportable, synchronisé avec le PC) ; recherche lemmes + rareté des mots, sens proche (NLEmbedding) seulement sans mot commun et au-dessus d'un seuil prudent (0,85, à calibrer) ; réponses mémorisées (`kind: reponse`, provenance, date, expiration, vérification), jamais pour ce qui dépend de la personne, du moment ou de la conversation ; journal des conversations par jour, activé par défaut (§8.1), désactivable et effaçable.
- **Risques** : seuil de sens non calibré ; heuristique de réutilisation volontairement prudente (moins de gains, pas d'erreur de contexte). **Réexamen** : mesurer « première question / question semblable » sur l'iPhone ; SQLite FTS5 si la mémoire dépasse quelques milliers de notes. **Rollback** : annuler `4275a7a` (les fichiers Markdown restent lisibles par l'ancienne version, `reponse` est ignoré).

### D4 · Contrôle de l'utilisateur (27 novembre 2026, appliquée)
- Arrêt d'urgence `JarvisEmergencyStop` (phrase reconnue avant tout routage, ou secousse de l'iPhone), garde financière `JarvisCostGuard` (liste d'hôtes gratuits, HTTPS seulement, refus avant envoi), confirmations `JarvisConfirmations` (une minute, phrase de la personne seulement), réinitialisation `JarvisReset`. Indépendants du cerveau : aucune sortie de modèle n'y accède.
- **Limites** : les téléchargements épinglés (modèle, voix) et le PC appairé ne passent pas par la garde (adresses fixes ou réseau local, sans coût) ; une action déjà faite hors de l'iPhone n'est pas annulable.

### D5 · Caméra mise de côté (27 novembre 2026, appliquée, réversible)
- `JarvisFeatures.cameraEnabled = false` : commandes visuelles, cube AR et accueil Vision ne démarrent plus ; le code, le modèle et les preuves visuelles de la CI restent. Audit : aucun traitement visuel n'était actif au repos ; le gain attendu est l'absence de démarrage accidentel, pas une baisse de consommation au repos. Retour : remettre `true`.

### D6 · Voix plus grave (27 novembre 2026, appliquée, réglable)
- Voix « pierre » jouée à −2 demi-tons au lieu de +1,5 (même débit), réglable à la voix d'un demi-ton entre −5 et +3 (« voix plus grave », « plus aiguë », « voix normale »). Défaut du PC aligné (`voice_pitch_semitones = -2.0`) ; un `settings.json` du PC existant garde sa valeur.

### D7 · Modèle local de l'iPhone (en attente de mesures)
- Catalogue actuel conservé (Qwen2.5 1.5B, Qwen3 4B Instruct 2507 IQ4_XS). Candidats 2026 à mesurer sur l'iPhone 14 Pro (6 Go) : Qwen3.5 4B (meilleure qualité dans les essais publics, 2,7 Go en 4 bits, demande une version plus récente de llama.cpp), Gemma 4 E2B (équilibre), LFM2 1.2B (vitesse). Aucun changement sans mesure de vitesse, mémoire et français sur l'appareil.
