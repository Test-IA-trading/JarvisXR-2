# Architecture vocale temps réel — JarvisXR 2.0

Statut : spécification de développement, 27 novembre 2026. Base examinée : PR #32, commit 8cfc75b. Ce document décrit une architecture locale proposée, inspirée des comportements publics de l'API Realtime d'OpenAI. Ce n'est ni le code source de ChatGPT Voice, ni une description certaine de ses modèles, seuils ou traitements propriétaires. Aucune API OpenAI payante n'est requise.

## 1. Constat sur le code existant

La PR #32 annonce des correctifs du texte anglais, de la veille, du mot d'appel, de l'interruption et du routage. Ne pas refaire ces changements aveuglément : vérifier les régressions sur appareil.
Sur PC, `pc/jarvis_pc/voice.py` utilise actuellement faster-whisper small CPU int8, une transcription par énoncé après silence (trames 30 ms, seuil RMS, 0,8 s de silence, maximum 15 s), un pré-roll de dix trames, et Piper avec concaténation des fragments, lecture bloquante et pause de 0,3 s. Le callback abandonne l'audio si Jarvis parle : le duplex réel PC nécessite donc un changement de conception. Ces constats proviennent de la branche #32, pas d'un test matériel.
Sur iOS, inspecter les interfaces existantes JarvisVoiceInputService, JarvisDuplexAudio, JarvisWakeWord, JarvisConversationFlow/JarvisEchoFilter et JarvisSpeechService ; respecter les états de veille et les contraintes iOS.

## 2. Ce que documente OpenAI et ce que nous reproduisons

- VAD acoustique : détection du début et de la fin de parole à partir du signal, avec pré-roll et durée de silence configurables.
- VAD sémantique : estimation de la probabilité que l'utilisateur ait terminé son tour, au-delà d'un seuil de silence. Adapter le temps d'attente à la phrase.
- Conversation temps réel : audio entrant et sortant transmis progressivement ; événements séparés pour le cycle du tour, la génération et la lecture.
- Interruption : annulation de la réponse en cours, purge de l'audio en attente et ajustement de l'historique au segment réellement entendu. Ces mécanismes sont publiquement documentés dans l'API, sans garantie que l'app ChatGPT utilise exactement la même implémentation.

Sources : https://developers.openai.com/api/docs/guides/realtime-vad ; https://developers.openai.com/api/docs/guides/realtime-conversations ; https://developers.openai.com/api/reference/resources/realtime/client-events . Consultées le 27/11/2026. Les choix ci-dessous sont des propositions d'ingénierie Jarvis et doivent être testés.

## 3. Pipeline duplex, horloges et responsabilités

Micro -> tampon circulaire RAM -> conversion de format -> AEC + réduction de bruit -> VAD / wake / claps -> transcription partielle -> décision de fin de tour -> routeur + mémoire -> réponse texte progressive -> segmentation TTS -> synthèse anticipée -> file PCM -> sortie audio.
Retour de référence PCM réellement envoyée au haut-parleur vers AEC. Les détecteurs tournent en parallèle sur un signal approprié : garder un chemin préservant les transitoires pour les claps. Ne pas laisser AGC ou suppression de bruit déformer systématiquement les impulsions.

- Sur PC, utiliser un stream duplex ou des streams entrée/sortie horodatés compatibles ; callbacks temps réel limités à copier vers une file bornée, pas de réseau, d'ASR, de TTS ou de blocage dans le callback. Resampling hors callback ; mesurer dérive d'horloge, délais et pertes. Étudier WebRTC Audio Processing/AEC3 et WASAPI loopback pour la référence du son système quand le consentement et la configuration le permettent. Ne pas confondre AEC de Jarvis et suppression de tout son externe.
- Sur iOS, tester AVAudioSession .playAndRecord / .voiceChat et voice processing AVAudioEngine ; vérifier Bluetooth, haut-parleur, route audio, interruptions d'appel et arrière-plan. Un mode clap distinct peut être nécessaire si le traitement supprime les impulsions. Pas d'écoute après fermeture forcée.
- Tampon RAM de départ 300–800 ms (ajuster par tests), plus tampon court borné pendant énoncé ; jamais de capture de conversation sur disque. Gérer débordement et backpressure en journalisant uniquement des métriques non sensibles. Une longue dictée doit continuer par segments au lieu d'être arbitrairement traitée comme une nouvelle commande.
- Horloge monotone et identifiants session_id, turn_id, response_id, segment_id, génération d'annulation. Les résultats asynchrones obsolètes doivent être ignorés. Chaque action externe est idempotente et ne part qu'après validation d'un tour final.

Contrats indicatifs, à adapter sans multiplier les fichiers :
```text
AudioFrame(ts_monotonic, pcm, sample_rate, route_id)
SpeechEvent(turn_id, start|partial|pause|final, text, confidence, revision)
OutputSegment(response_id, segment_id, text, pcm, duration, played_samples)
TurnState = STOPPED | WATCHING | LISTENING | END_PENDING | THINKING | SPEAKING | INTERRUPTING
```
Les activités d'écoute et de lecture sont indépendantes (duplex) ; ces états décrivent le cycle logique et ne doivent pas couper mécaniquement le micro en SPEAKING. Le contrôleur possède l'autorité sur les transitions, l'arrêt veille et les annulations.

## 4. Dictée progressive, personnalisation et fin de phrase

1. Détection acoustique de parole : comparer Silero VAD, traitement natif iOS et baseline RMS. Hystérésis, seuils différents entrée/sortie, confirmation sur quelques trames, plancher bruit adaptatif, contrôle de confiance. Pas de faux texte Whisper sur silence ; rejeter les segments pauvres en parole.
2. ASR : garder moteur chargé. Étudier faster-whisper avec décodage incrémental par fenêtres chevauchantes et whisper.cpp ou recognizer natif sur iOS. Faster-whisper n'est pas en lui-même un service streaming : implémenter la stabilisation des hypothèses. Ne pas retranscrire tout le tour à chaque trame. Dédupliquer la zone chevauchante ; confirmer un préfixe après plusieurs hypothèses cohérentes, conserver une queue révisable, produire un final lors de validation. Ne pas exécuter une action à partir d'un partiel.
3. Langue française et biais lexical limité : prénoms, noms d'apps, vocabulaire approuvé ; les corrections utilisateur enrichissent un lexique borné. Éviter le prompt de réveil omniprésent qui pourrait halluciner « Jarvis » ; comparer tests avec/sans biais. Les mots non reconnus ne doivent pas basculer vers un ancien routeur anglais.
4. Endpointer sémantique léger : combiner VAD, silence, stabilité ASR, confiance, grammaire, prosodie si fiable, historique de pauses et intention. Utiliser d'abord règles rapides ; petit classificateur local facultatif si amélioration mesurée, pas un appel 30B pour chaque pause. Score de complétude + temporisation : phrase complète et commande claire -> délai court ; connecteurs, hésitations, verbes incomplets, énumération -> délai plus long. Reprendre l'écoute si parole revient avant commit. Une question sans point d'interrogation reste une question ; une intonation montante seule ne suffit pas.
5. Exemple de seuils INITIAUX à calibrer (pas les seuils de ChatGPT) : confirmation parole 60–150 ms ; candidat fin 250–450 ms pour commande claire, 600–1000 ms ordinaire, 1200–2000 ms si phrase incomplète ; extension bornée et réglable, mode dictée longue séparé. Les valeurs doivent s'adapter au bruit, à la route et aux pauses de l'utilisateur ; aucun seuil global ne garantit la compréhension. Le score de complétude doit avoir un maximum d'attente et un mécanisme « je n'ai pas fini ».
6. Personnalisation sans entraînement systématique : quantiles robustes des pauses intra-phrase, vitesse, erreurs corrigées, vocabulaire et préférences ; mise à jour prudente seulement sur tours validés, option reset et désactivation. Pas de profil biométrique vocal par défaut.

Exemples : « Est-ce que tu pourrais… [pause] ouvrir Spotify ? » -> un seul tour ; « Euh… attends… » -> attendre, pas de réponse ; « Quelle heure est-il ? » -> réponse directe ; « Je pensais à… [pause] non, finalement… » -> révision ; « Il a parlé à Jarvis hier » -> pas de réveil en veille. En cas d'ambiguïté d'action importante, une clarification courte vaut mieux qu'une exécution incorrecte.

## 5. Mot d'appel et clappements

Veille : détecteur local dédié (évaluer openWakeWord sur PC et alternative iOS compatible ; modèles/licences à vérifier) + filtre contexte adressé + présence de parole + confiance calibrée. Comparer au comportement PR #32. Ne pas utiliser une distance orthographique seule. Rejet silence/bruit, cooldown, fenêtre de réarmement ; éviter les auto-réveils pendant lecture. Le mode conversation active n'exige pas de redire Jarvis à chaque tour.

Claps : remplacer le seul niveau RMS par une combinaison attaque/décroissance, durée, spectre, flux spectral, rapport transitoire/bruit, similarité temporelle de la paire et espacement. Évaluer un petit classificateur local seulement si les caractéristiques simples ne suffisent pas. Utiliser référence audio disponible (propre TTS et son système PC) pour rejeter des correspondances acoustiques. Ne pas collecter d'audio d'autrui ; pas de transmission microphone à un tiers. Une paire de claps jouée par une enceinte externe peut être impossible à distinguer d'une paire réelle ; ne pas promettre zéro faux positif. Réglage sensibilité, calibration volontaire, désactivation indépendante. Tester en silence, avec vidéo, jeu PC, clavier, porte, notifications, musique, parole et claps réellement produits par l'utilisateur. Mesurer faux réveils/heure et rappel, séparément sur iPhone et PC.

## 6. Interruption naturelle (barge-in)

Pendant SPEAKING le micro reste disponible si autorisé. AEC + VAD évaluent la parole humaine ; dès candidat fiable, réduire rapidement la sortie (ducking progressif) puis confirmer par ASR partiel ou signal robuste. Si faux candidat, restaurer le volume sans couper. « non non », « attends », « laisse-moi finir », « stop », « c'est pas ça » : priorité ; « oui », « mhm » : acquiescement possible, ne pas annuler systématiquement. Si Jarvis dit lui-même « non », le signal de référence et le contexte empêchent l'auto-interruption.
Sur interruption confirmée : incrémenter génération d'annulation, stopper lecture, purger file PCM, annuler TTS/LLM/recherche si possible, ignorer résultats périmés. Mesurer la position du rendu réellement entendu (compteur samples + délai périphérique, pas seulement texte généré). Enregistrer l'assistant comme interrompu, avec le préfixe entendu et incertitude si alignement imparfait. Ne pas inventer que tout texte envoyé a été entendu. Les actions déjà exécutées ne sont pas annulées implicitement ; rapporter leur état.
Nouvelle demande = nouveau turn_id, contexte précédent pertinent et correction ; aucun ancien segment ne doit reprendre. Gérer double interruption, changement de route et arrêt veille en cours de réponse. Cible initiale : ducking < 200 ms et arrêt confirmé < 500 ms sur matériel réel, à mesurer.

## 7. TTS vraiment continu

PC : remplacer la boucle synthèse intégrale + sd.play/sd.wait + délai 0,3 s par producteur texte et consommateur PCM continu, ou autre solution démontrée. iOS : évaluer synthèse native avec buffers et planification AVAudioPlayerNode sans trous entre utterances ; tenir compte des restrictions de l'API choisie.
- Segmentation linguistique, pas un token par synthèse. Frontières ponctuation/clauses, protéger décimales, abréviations, noms, URLs et unités ; seuil longueur/temps raisonnable pour éviter attente infinie. Démarrer un premier segment utile, anticiper le suivant pendant lecture.
- Normaliser français oral (dates, chiffres, sigles, mathématiques), conserver texte affiché intact. Préserver la prosodie, limiter les variations de volume et les silences artificiels ; éviter concaténations qui coupent un phonème. Formats PCM stables et resampling hors callback.
- File bornée avec watermark adaptatif, prébuffer initial (p. ex. 100–300 ms à tester) et suivi sous-alimentations. Précharger moteurs, éviter compétition GPU entre ASR/TTS/LLM. Sur surcharge préférer voix locale de secours plutôt que silence prolongé.
- Interface TTS interchangeable : synthèse par segments, flux PCM, cancel(response_id), profil voix, choix appareil. Comparer Piper, moteur natif Apple et alternatives TTS locales françaises (qualité, licence, latence, RAM/VRAM, compatibilité iOS). Ne pas promettre une voix identique à un acteur ; référence audio future à traiter seulement si droits et consentement appropriés, ne pas publier d'échantillon privé. Le profil de voix reste en attente de la référence.
- Ne jamais parler un contenu d'action non confirmé ni des citations/URLs interminables ; afficher les sources et résumer oralement.

## 8. Veille, erreurs et état UI

Le bouton Arrêter la veille (app + widget) doit annuler tous les timers, générations, écoutes, claps, wake, ASR et Live Activity, persister off et libérer audio ; une réouverture ne réactive pas sans demande. Vérifier la notification Darwin de #32, cas app suspendue et restrictions iOS. Micro orange doit disparaître dès que le système libère la capture. Afficher honnêtement « Prêt », « J'écoute », « Je réfléchis », « Je parle », « Veille arrêtée » ; pas d'ancien texte anglais, doublons ni faux voyant réponse. Si ASR ou cerveau échoue, présenter une erreur courte et un retour sûr au repos. Pas de boucle de relance incontrôlée.

## 9. Mesures, tests et ordre de livraison

Instrumentation locale sans transcript ni audio brut par défaut : timestamps speech_start, speech_end_estimate, final_asr, route_ready, first_token, first_tts_pcm, playback_start, interruption_detected, playback_stopped ; p50/p95, taux d'échec, underruns, RTF ASR/TTS, CPU/GPU/RAM, batterie iOS et état réseau. Mesurer à froid/chaud, local/distant, bruit/silence, Bluetooth/haut-parleur. Cible indicative : premier retour sonore utile < 1 s pour commandes simples, pas une promesse ; qualifier latence bout en bout et ne pas masquer l'attente par remplissage verbal.
- Tests unitaires avec audio synthétique ou corpus autorisé : VAD, wake, claps, fin de phrase, révisions ASR, normalisation TTS, transitions, cancellation, audio obsolète.
- Tests intégrés : silence 10 min, conversations longues, claps/sons PC, phrases interrompues, corrections, désaccord de source, perte réseau, passage arrière-plan, stop veille en cours de génération, aucune réactivation.
- Essais matériels : vraies voix françaises et vrais claps, interruption de la propre voix, appels et Bluetooth ; rapporter séparément simulateur et iPhone réel. Aucun audio de test personnel dans le dépôt.
- Ordre : reproduire et mesurer les problèmes existants ; endpointer/ASR et duplex PC ; streaming TTS et annulation ; claps/wake ; iOS et régressions ; personnalisation et benchmark final. Chaque PR petite, tests ciblés puis suite complète, aucune fusion sans accord.

Références techniques à évaluer : https://github.com/snakers4/silero-vad ; https://github.com/SYSTRAN/faster-whisper ; https://github.com/ggml-org/whisper.cpp ; https://github.com/dscripka/openWakeWord ; https://webrtc.googlesource.com/src/+/refs/heads/main/modules/audio_processing/ ; https://developer.apple.com/documentation/avfaudio/avaudioengine . Vérifier licences, versions et compatibilité avant dépendance.
