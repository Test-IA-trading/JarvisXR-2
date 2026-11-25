# Public Release Handoff

## Reprise rapide — état au 25/11/2026, midi

À lire en premier pour reprendre le travail sans raconter le projet.

- **PR à fusionner dans l'ordre** (chacune contient les précédentes, toutes vers `develop`) :
  - #5 Réglages en français ;
  - #6 voix française ;
  - #7 cube AR à la pince ;
  - #8 conversation et bilan ;
  - #9 aide des Réglages ;
  - #10 documentation (idées, tuto) ;
  - #11 cerveau local ;
  - #12 minuteurs, rappels et agenda ;
  - #13 guide en direct français ;
  - #14 Vision tout en français ;
  - #15 cube AR mains libres ;
  - #16 voix naturelle (fin des voix Eloquence, choix de la voix) ;
  - #17 calculs exacts, formules lues en mots, consignes du cerveau ;
  - #18 mémoire personnelle (prénom, notes données au cerveau) ;
  - #19 cerveau avancé en option (Qwen3 4B, contrôle de la mémoire) ;
  - #20 réveil par la voix « Jarvis » (option, reconnaissance sur l'iPhone) ;
  - #21 conversions et questions de dates.

  Les fusions restent la décision du propriétaire.
- **Dernière préversion publiée** : `v2.0.0-preversion.4`, commit `917a9bb` (PR #16), avec la voix naturelle.
  - IPA vérifiée : `llama.framework` embarqué et chargé par `@rpath`. Lien public testé sans compte, empreinte identique.
  - Copie dans `OneDrive\Desktop\Jarvis\IPA`, avec LISEZMOI et TUTO à jour ; page tuto republiée.
- **Validé sur iPhone 14 Pro (25/11)** :
  - micro, transcription française ;
  - cerveau local hors ligne : « Pourquoi le ciel est-il bleu ? » bien expliqué.
  - Deux retours ont été corrigés depuis : une intégrale refusée (corrigé par #17) et une voix « horrible » (corrigé par #16 : à qualité égale, l'app prenait souvent une voix Eloquence).
- **Prochaine action exacte** : publier `v2.0.0-preversion.5` depuis le haut de la pile (#21, ou #20 si #21 n'est pas encore verte), quand sa CI est verte. Mêmes étapes que pour la préversion 4 :
  1. télécharger l'artefact `JarvisXR-unsigned-ipa` dans un dossier vide ;
  2. vérifier `llama.framework` ;
  3. publier en préversion ;
  4. tester le lien sans compte ;
  5. copier l'IPA dans OneDrive, mettre à jour LISEZMOI et TUTO, republier la page tuto.
- **Essais demandés au propriétaire** :
  1. Voix : Réglages › Voix de Jarvis (plus d'Eddy ni de Jacques), puis télécharger « Thomas (Améliorée) » dans les Réglages d'iOS.
  2. Préversion 5 :
     - « Intégrale de 0 à 1 de x au carré » ;
     - « Je m'appelle… », puis « Bonjour Jarvis » ;
     - le cerveau Avancé (noter la mémoire libre affichée) ;
     - le réveil par la voix.
- **CI** : deux pannes du runner Intel ont eu lieu le 25/11, sans lien avec le code. `gh run rerun <id> --failed` les corrige :
  - un envoi d'artefact en `ENOTFOUND` ;
  - un simulateur qui ne démarre pas (étape « annulée »).
- **Méthode** :
  - ce PC Windows n'a pas de compilateur Swift. La logique pure est d'abord rejouée dans une réplique Python : `VisionLiveGuideEngine`, `JarvisMathSolver`, conversions et dates. Leurs tests sont passés au premier essai en CI ;
  - le runner `macos-26-intel` met environ 1 h 30 par CI ;
  - tout envoi sur une PR de code, même de documentation seule, relance sa CI : on regroupe donc les envois.

## Current Product

The shipping source is the Swift and UIKit app under `ios/JarvisXR`. Jarvis Vision provides Describe, Live Guide, Find, Read Text, Barcode, and Color modes through a model-agnostic, on-device pipeline with tracking, scene fusion, safe narration, priority speech, haptics, diagnostics, privacy controls, and thermal degradation.

The build fetches Apple's `YOLOv3TinyInt8LUT` detector, verifies its pinned size and SHA-256, and bundles the compiled model, manifest, and notice. GitHub Actions is configured to generate the project, validate the repository, build the unsigned arm64 app, run simulator unit and UI tests, execute real fixture inference, capture 28 visual states, audit safety, privacy, model, and IPA surfaces, and upload evidence artifacts. Run-specific pass evidence for the current rewrite remains pending in [Jarvis Vision Completion Ledger](JARVIS_VISION_COMPLETION_LEDGER.md).

## Installation Path

1. Download the prerelease IPA or build from source.
2. Sign and sideload it with an authorized Apple ID.
3. Complete the first-run checklist.
4. Enable Guided Access only after testing the exit path.

Simulator and CI evidence does not replace physical-device checks for live camera accuracy, speech input, audio routes, haptic feel, signing, sustained heat, battery use, VoiceOver focus, or Guided Access. No physical iPhone XR success is claimed until the checklist is completed and recorded.

## Voix française — suivi (lot 1, branche `fix/voix-francaise`)

Symptôme rapporté sur iPhone 14 Pro (iOS 27.2.1) : « Aucune parole détectée » après un tap sur l'orbe. Causes établies dans le code distribué (`7613083`) :

1. `SFSpeechRecognizer` était fixé sur `en-US`, sans rapport avec la parole française.
2. Au démarrage de l'écoute, l'accueil appelait `speech.stop()`, qui désactivait la session audio partagée juste après son activation par le micro ; le rappel asynchrone `didCancel` de la synthèse pouvait faire de même.
3. Seule l'autorisation Speech était demandée ; celle du micro restait implicite. Un micro refusé ou en attente livre des buffers nuls, qui finissaient en « Aucune parole détectée ».
4. Toute erreur de reconnaissance finissait en `.noSpeech` ; un rappel tardif d'une tâche précédente pouvait clore ou dupliquer un nouveau tour.
5. La synthèse choisissait des voix anglaises ; le routeur ne comprenait que des commandes anglaises.

| Élément | Prévu | Implémenté | Vérifié en CI | Validé sur iPhone |
|---|---|---|---|---|
| Reconnaissance `fr-FR`, moteur local préféré puis repli Apple en ligne | ✓ | ✓ | ✓ | ✓ transcription correcte (25/11) |
| Autorisations Speech puis micro, messages français et bouton Réglages | ✓ | ✓ | ✓ | ✓ acceptées (25/11) |
| Session `.playAndRecord`, jamais désactivée sous un micro ouvert | ✓ | ✓ | ✓ | ✓ (25/11) |
| Erreur ≠ silence ; détection d'un micro muet (buffers nuls) ; jeton de tour contre les rappels tardifs | ✓ | ✓ | tests unitaires | à faire |
| Indicateur « Micro · Son · Texte · Réponse » avec niveau | ✓ | ✓ | en attente | à faire |
| Pauses : 1,6 s de silence après parole, 7 s sans parole, 30 s max | ✓ | ✓ | tests unitaires | à faire |
| Voix française (premium > améliorée > standard), phrases de test en français | ✓ | ✓ | tests unitaires | à faire |
| Routeur français déterministe (heure, date, notes, caméra, réglages, aide) | ✓ | ✓ | tests unitaires | à faire |
| Réarmement automatique de l'écoute après la réponse, interruption vocale | ✓ | — | — | — |
| Étiquette d'état (`Ready`, `Listening`…) en français (dépend des tests UI) | ✓ | — | — | — |

Essai terrain le plus court : toucher l'orbe, dire « Bonjour Jarvis, est-ce que tu m'entends ? ». Attendu : « ● Micro · ● Son · ● Texte », la phrase affichée, puis « Oui, je vous entends bien. » prononcé en français. En cas d'échec, l'étape en ✕ et Diagnostics > « Dernière écoute » indiquent où la chaîne s'arrête (aucun audio ni texte n'est conservé).

Prochaine action : valider ce lot sur l'iPhone, puis lot 2 (pince sur un cube ancré ARKit, image de l'`ARFrame` analysée par Vision, sans seconde session caméra).

## Cube AR à la pince — suivi (lot 2, branche `feature/cube-ar-pince`)

Ouverture : menu « Vision » > « Cube AR à la pince », ou à la voix « Ouvre le cube ». Écran `JarvisARCubeViewController`.

Architecture :
- **Caméra** : l'`ARSession` (suivi du monde, détection des plans horizontaux) est le seul client de la caméra pendant l'écran. Aucune `AVCaptureSession` n'est ouverte en parallèle.
- **Main** : `VNDetectHumanHandPoseRequest` tourne sur `ARFrame.capturedImage` (orientation `.right`) dans une file série, jusqu'à 30 images/s (12 si l'iPhone chauffe). Une seule image est analysée à la fois et les images en retard sont abandonnées.
- **Coordonnées** : les points Vision sont convertis en coordonnées de `capturedImage`, puis par `ARFrame.displayTransform(for: .portrait, …)`, qui applique la rotation et le recadrage de l'image affichée. La caméra arrière n'est pas en miroir. Des pastilles sur le pouce, l'index et le point visé permettent de contrôler l'alignement sur l'iPhone.
- **Pince** (`JarvisPinchDetector`) :
  - rapport distance pouce–index / taille de la main (poignet → articulation du majeur) ;
  - deux seuils (0,30 fermeture, 0,50 ouverture) confirmés sur 2 images, avec confiance minimale ;
  - une main qui entre déjà fermée ne saisit rien ;
  - une coupure de moins de 0,35 s fige le cube, une coupure plus longue lâche le cube sur place ; il faut rouvrir les doigts avant de le reprendre.
- **Calibrage** guidé, main ouverte puis pince : la position reconnue s'affiche en direct et les seuils sont enregistrés.
- **Manipulation** (`JarvisCubeManipulator`) :
  - la saisie exige que la pince commence sur le cube tel qu'il apparaît à l'écran ;
  - le point de pince est projeté sur le plan de la table (intersection rayon/plan) ;
  - le décalage de saisie est conservé, donc pas de saut sous les doigts ;
  - une image sans rayon exploitable, ou un saut de plus de 35 cm, fige le cube ;
  - au lâcher, le cube est réancré dans le monde.
- **Retours distincts** : visé (jaune, vibration de sélection), saisi (vert, agrandi, impact), déposé (couleur d'origine, vibration de succès), plus le texte d'état et les annonces VoiceOver.
- **Repli tactile** : glisser le cube d'un doigt à l'écran.
- **Perte du suivi du monde ou interruption** : le cube est figé et la saisie annulée.
- **Voix** : le bouton « Parler » de l'écran AR envoie au routeur. « Qu'est-ce que je viens de déplacer ? » est répondu par `JarvisSpatialSceneMemory` (« Le cube. », avec distance et direction par rapport à la caméra). Ce fait vient du moteur de scène, pas d'une déduction depuis l'image.
- **Mesures** affichables à l'écran : cadence d'analyse, part des images avec main, rapport de pince et seuils, délai pince → mouvement, saisies, lâchers, pinces ratées, pertes, état du suivi.

| Élément | Prévu | Implémenté | Vérifié en CI | Validé sur iPhone |
|---|---|---|---|---|
| Cube posé sur le premier plan horizontal, ancré dans le monde | ✓ | ✓ | compilation | à faire |
| Pince dans l'air : saisir, déplacer, lâcher | ✓ | ✓ | tests unitaires | à faire |
| Pince dans le vide sans effet ; pas de saut à la saisie | ✓ | ✓ | tests unitaires | à faire |
| Main entrée fermée, tremblement, perte de la main | ✓ | ✓ | tests unitaires | à faire |
| Calibrage main ouverte / pince | ✓ | ✓ | tests unitaires | à faire |
| « Qu'est-ce que je viens de déplacer ? » → « Le cube. » | ✓ | ✓ | tests unitaires | à faire |
| Repli tactile | ✓ | ✓ | — | à faire |
| Écoute continue mains libres pendant la manipulation : Jarvis réécoute après chaque réponse, jusqu'à « C'est tout » ou un silence (branche `feature/ar-mains-libres`) | ✓ | ✓ | compilation | à faire |
| Profondeur, rotation, redimensionnement, fiche « bilan » | ✓ | — | — | — |
| Annonces spontanées d'objets réels (tasse) dans la même session | ✓ | — | — | — |

Essai terrain le plus court, en mode avion :
1. Ouvrez le cube, cadrez un livre posé sur une table et attendez le cube.
2. Pincez-le dans l'air à gauche du livre, portez-le à droite, ouvrez les doigts.
3. Filmez de côté : le cube doit rester à droite du livre.
4. Touchez « Parler » et dites « Qu'est-ce que je viens de déplacer ? ». Réponse attendue : « Le cube ».

À rapporter : les valeurs de « Mesures » (cadence, délai pince → mouvement, ratées) et l'alignement des pastilles sur vos doigts.

## Conversation, bilan et « Dis Jarvis » — suivi (lot 3, branche `feature/conversation-bilan`)

- **Conversation qui suit les corrections** (`JarvisConversationContext`) :
  - les heures sont lues en français : « neuf heures », « 9 h 30 », « 21:15 », « midi », « onze heures et demie », « dix heures moins le quart », « huit heures du soir », « dix-sept heures quinze » ;
  - les phrases du type « <le/la/l'> <objet> part/décolle à <heure> » sont retenues, y compris la seconde moitié d'une phrase comme « le train part à 9 h et le bus à 11 h » ;
  - les corrections sont prises en compte (« en fait… ») ;
  - réponses possibles : lequel part en premier ou en dernier, « Et maintenant ? », « Explique-moi pourquoi », « juste l'heure du train ».

  Moteur déterministe et local : il marche pour n'importe quels objets et horaires, pas seulement train/bus. Ce n'est pas un modèle de langage général.
- **Bilan des notes** (`JarvisNotesSummary`) : « Combien de notes ai-je prises ces sept derniers jours ? » compte sur 7 × 24 h glissants. « Montre-les-moi » affiche exactement les notes comptées, et « Pose ce bilan sur la table » montre le même total. Avec zéro note, Jarvis répond « aucune note ». Pour les téléchargements, il répond qu'il n'y a pas accès. « Prépare l'essai du bilan » crée les 3 notes du scénario (deux aujourd'hui, une il y a huit jours) ; « Efface les notes d'essai » les retire.
- **Fiche AR** : une carte debout, tournée vers la caméra, posée à droite du cube. Elle se saisit à la même pince (la pince choisit l'objet le plus proche sous les doigts) et se réoriente au lâcher. On la ferme avec « Fermer la fiche » ou « Ferme le bilan ». « Qu'est-ce que je viens de déplacer ? » répond « La fiche du bilan. » si c'est elle qui a bougé.
- **Conversation continue** (réglage par défaut : activée) :
  - après une réponse parlée à une demande parlée, l'écoute reprend seule 0,45 s après la fin de la voix ;
  - un silence met la conversation en pause ;
  - « C'est tout » la termine ;
  - un tap pendant la réponse coupe Jarvis et l'écoute reprend ;
  - « Désactive / active la conversation continue ».

  L'interruption par la voix pendant que Jarvis parle n'est pas faite : il faudrait faire passer la synthèse par le moteur audio avec annulation d'écho, ce qu'on ne peut vérifier que sur l'iPhone.
- **« Dis Jarvis »** : intention `StartJarvisListeningIntent` (« Parler à JARVIS »), raccourci d'app et lien `jarvis://listen`. iOS n'autorise pas une app à écouter en permanence un mot de réveil. Le chemin prévu est Réglages > Accessibilité > Raccourcis vocaux : phrase « Dis Jarvis » → raccourci « Parler à JARVIS ». L'app s'ouvre alors micro actif ; iPhone verrouillé, il faut d'abord le déverrouiller.
- **États de l'accueil en français** (« Prêt », « À l'écoute », « En veille »…), l'identifiant technique restant stable. Les attentes des tests d'interface sont mises à jour.

| Élément | Prévu | Implémenté | Vérifié en CI | Validé sur iPhone |
|---|---|---|---|---|
| Train/bus, corrections, « juste l'heure du train » | ✓ | ✓ | tests unitaires | à faire |
| Bilan 7 jours, « Montre-les-moi », zéro, téléchargements | ✓ | ✓ | tests unitaires | à faire |
| Fiche AR du bilan, déplaçable à la pince | ✓ | ✓ | compilation | à faire |
| Conversation continue (reprise sans toucher) | ✓ | ✓ | — | à faire |
| Interruption vocale pendant la réponse | ✓ | — | — | — |
| « Dis Jarvis » via raccourci vocal iOS | ✓ | ✓ | compilation | à faire |
| États de l'accueil en français | ✓ | ✓ | test de surface | à faire |

## Aide contextuelle des Réglages — suivi (lot 4, branche `feature/contexte-reglages`)

- `JarvisScreenContext` garde en mémoire l'option touchée en dernier dans les Réglages : un tap sur son panneau, ou un changement de valeur. Cette option est mise en évidence par un cadre.
- Le bouton « Demander » de la barre des Réglages ouvre le micro :
  - « À quoi sert cette option ? » répond avec le titre et l'explication de l'option sélectionnée, tirés du texte même des Réglages ;
  - « Et celle-ci ? » utilise la nouvelle sélection ;
  - sans sélection, Jarvis demande d'abord de toucher une option.
- « Suspends l'assistance » arrête de suivre les sélections, et les actions suivantes ne déclenchent plus de réaction. « Reprends l'assistance » la réactive.
- Rien n'est lu hors de JARVIS : le contexte d'une autre app dépend de ce qu'iOS permet de partager (partage, raccourcis).

| Élément | Prévu | Implémenté | Vérifié en CI | Validé sur iPhone |
|---|---|---|---|---|
| « À quoi sert cette option ? » puis « Et celle-ci ? » | ✓ | ✓ | tests unitaires | à faire |
| Suspension / reprise de l'assistance | ✓ | ✓ | tests unitaires | à faire |
| Contexte d'autres apps via les mécanismes iOS autorisés | ✓ | — | — | — |

## Cerveau local hors ligne — suivi (lot 5, branche `feature/cerveau-local`)

Retour du 25/11 sur l'iPhone : le micro et la transcription marchent, mais Jarvis « ne peut pas répondre » aux questions libres. Il ne connaissait que des commandes fixes et disait « Je n'ai pas encore de réponse locale ».

Choix techniques :
- **Moteur** : llama.cpp, version précompilée `b12262` (10/11/2026), épinglée par taille et SHA-256 dans `tools/fetch_llama_framework.py`. MLX a été écarté : il exige une puce Apple, alors que la CI teste sur un simulateur Intel.
- **Pas de variante simulateur** dans cette version de llama.cpp : le framework est lié aux builds iPhone seulement (`FRAMEWORK_SEARCH_PATHS`/`OTHER_LDFLAGS[sdk=iphoneos*]`) et copié dans l'app par un script de post-build. Le code est protégé par `#if canImport(llama)`. Les tests simulateur voient donc le cerveau « indisponible », et le build iPhone de la CI compile le vrai moteur.
- **Modèle** : Qwen2.5-1.5B-Instruct Q4_K_M, licence Apache 2.0, 1 117 320 736 octets, SHA-256 `6a1a2eb6…407e`. Il est téléchargé une seule fois depuis Hugging Face, depuis Réglages > Cerveau local, après confirmation.
  - Le fichier est vérifié, rangé dans Application Support et exclu des sauvegardes iCloud.
  - C'est la seule exception réseau de l'app, inscrite dans `tools/audit_vision_privacy.py` et verrouillée par un test.
- **Aiguillage** : le routeur français déterministe passe toujours en premier. Le cerveau ne reçoit que les questions françaises qu'aucune commande ne couvre (`openQuestion`) et ne déclenche jamais d'action.
- **Ce que le cerveau reçoit** : les 6 derniers échanges et les faits connus de l'app (horaires donnés, dernier objet déplacé, bilan de notes), plus une consigne de style « réponse courte, en français, lue à voix haute, sans inventer ».
- **Réponse** : le texte s'affiche pendant qu'il s'écrit, puis Jarvis le prononce, et la conversation continue reprend ensuite. Un tap sur l'orbe interrompt la réflexion.
- **Accès** : depuis l'accueil, depuis « Parler » dans l'écran AR et depuis « Demander » dans les Réglages.
- **Paramètres du moteur** : 2 048 jetons de contexte, 200 jetons de réponse au maximum, Metal (`n_gpu_layers = 99`), échantillonnage top-k 40, top-p 0,9, température 0,6, pénalité de répétition 1,1. Le modèle est déchargé si iOS manque de mémoire.

| Élément | Prévu | Implémenté | Vérifié en CI | Validé sur iPhone |
|---|---|---|---|---|
| Framework llama.cpp épinglé et embarqué (iPhone) | ✓ | ✓ | build iPhone | à faire |
| Téléchargement unique, vérifié, avec consentement | ✓ | ✓ | tests (SHA-256, état) | à faire |
| Réponses aux questions libres, affichées puis lues | ✓ | ✓ | tests (prompt, nettoyage, aiguillage) | à faire |
| Contexte de conversation (6 échanges + faits) | ✓ | ✓ | tests unitaires | à faire |
| Exception réseau unique dans l'audit de confidentialité | ✓ | ✓ | test Python | — |
| Lecture de la réponse au fil de l'écriture | ✓ | ✓ | tests (découpe en phrases) | à faire |

Essai sur l'iPhone :
1. Réglages > Cerveau local > « Télécharger le cerveau (1,1 Go) », en Wi-Fi, en gardant l'app ouverte.
2. Mode avion activé, touchez l'orbe et dites « Pourquoi le ciel est-il bleu ? ».
3. Attendu : « Je réfléchis… », la réponse qui s'écrit, puis une réponse française parlée en une à trois phrases.

À rapporter : le délai entre la fin de la question et le début de la voix, et la vitesse affichée dans Réglages > Cerveau local (« jetons/s »).

## Minuteurs, rappels, agenda et point du jour — suivi (lot 6, branche `feature/agenda-minuteurs`)

- **Minuteurs nommés**, persistants (`JarvisTimerStore`) :
  - « Mets un minuteur de 10 minutes pour les pâtes », « Minuteur pâtes 8 minutes », « Réveille-moi dans 20 minutes » ;
  - « Il reste combien pour les pâtes ? » ;
  - « Annule le minuteur (des pâtes) ».

  Notification locale à l'échéance, après autorisation. Si JARVIS est ouvert, l'échéance s'affiche et se dit à voix haute.
- **Durées en français** : « une heure et demie », « 1 h 30 », « un quart d'heure », « une demi-heure », « 2 heures 15 », « 10 minutes 30 secondes ». « à 9 h » reste une heure d'horloge.
- **Rappels** (EventKit, app Rappels) : « Rappelle-moi d'appeler maman demain à 18 h » ou « …dans 20 minutes ». Le titre reprend vos mots ; date et alarme sont réglées.
- **Agenda** (EventKit, lecture seule du jour demandé) : « Qu'est-ce que j'ai demain ? », « Mon agenda de vendredi », « Est-ce que je suis libre aujourd'hui ? ».
- **Jours compris** : aujourd'hui, ce soir, demain, après-demain, jours de la semaine, « lundi prochain ».
- **Point du jour** : « Fais-moi le point » donne la date, l'heure, l'agenda du jour, les minuteurs en cours et la batterie.
- **Accès** : depuis l'accueil, l'écran AR et les Réglages. Les textes d'autorisation iOS (calendrier, rappels) sont en français.

| Élément | Prévu | Implémenté | Vérifié en CI | Validé sur iPhone |
|---|---|---|---|---|
| Minuteurs nommés, reste, annulation, persistance | ✓ | ✓ | tests unitaires | à faire |
| Notification + annonce à l'échéance | ✓ | ✓ | compilation | à faire |
| Rappels datés dans l'app Rappels | ✓ | ✓ | tests (analyse) | à faire |
| Agenda du jour demandé, point du jour | ✓ | ✓ | tests (analyse, résumé) | à faire |

Essai sur l'iPhone : dites « Mets un minuteur de 2 minutes pour le thé », verrouillez l'écran et attendez. Attendu : une notification « thé » au bout de 2 minutes. Dites ensuite « Rappelle-moi d'appeler maman demain à 18 h ». Attendu : le rappel apparaît dans l'app Rappels, daté de demain 18 h.

## Guide en direct en français et vraie tasse — suivi (lot 7, branche `feature/vision-francais`)

Scénario 4 de la checklist. Téléphone immobile, une vraie tasse est posée devant la caméra.
- Jarvis annonce son apparition une seule fois.
- Il signale son déplacement vers la droite, puis se tait tant qu'elle ne bouge plus.
- Une fois la tasse retirée, il répond à « Elle est où maintenant ? ».
- Couper le mode arrête l'observation et les annonces.

Ce qui bloquait :
- Le guide en direct parlait anglais.
- En mode « changements importants » (réglage par défaut), toute annonce de priorité inférieure à `.target` était coupée. Les apparitions et déplacements n'étaient donc jamais dits.
- Les annonces brutes du suivi (`TemporalObjectTracker`) posaient d'autres problèmes :
  - elles se répétaient dès que le détecteur perdait la tasse un instant ;
  - elles rataient les déplacements lents, car seul le déplacement entre deux images était mesuré ;
  - elles confondaient un mouvement du téléphone avec un déplacement de la tasse.

Ce qui change :
- **`VisionLiveGuideEngine`** garde en mémoire les objets réels de la session, uniquement en mémoire vive. Il n'émet que trois sortes d'événements :
  - une apparition, une seule fois par objet ;
  - un déplacement, mesuré depuis la dernière place annoncée, et annoncé seulement quand l'objet est de nouveau immobile depuis 2 images ;
  - une disparition, après 2,5 s et 3 images analysées sans l'objet.

  Les points délicats sont traités ainsi :
  - Une piste perdue puis retrouvée par le suivi reste le même objet, y compris quand la main la cache en la portant.
  - Une image floue ne compte pas comme « non vue ».
  - Si l'objet clignote, le délai avant « disparu » s'allonge.
- **Le téléphone qui bouge n'est pas la tasse qui bouge** : `VisionCameraMotionMonitor` lit l'attitude CoreMotion (gyroscope et accéléromètre, sans autorisation à demander, rien n'est stocké). Dans trois cas, la nouvelle place est acceptée en silence au lieu d'être annoncée comme un déplacement :
  - une rotation de plus de 1,2° entre deux images ;
  - une rotation de plus de 4° depuis la dernière place connue ;
  - une secousse de plus de 0,1 g.
- **Français partout dans la narration Vision** :
  - noms des 80 classes du détecteur, avec genre et élision (`VisionFrenchVocabulary`) ;
  - positions « à gauche / au centre / à droite » ;
  - qualité d'image et réponses de Décrire et de Trouver.
- **Phrases du guide** :
  - « Je vois une tasse au centre. » (ou « Je crois voir… » si la confiance est moyenne) ;
  - « La tasse s'est déplacée du centre vers la droite. » ;
  - « Je ne vois plus la tasse. » ;
  - « Je revois la tasse à gauche. ».
- **Questions pendant le guide** (bouton Voix, sans quitter le mode) :
  - « Elle est où maintenant ? » / « Où est la tasse ? » / « Tu vois mon téléphone ? » ;
  - « Qu'est-ce que tu vois ? » ;
  - « Qu'est-ce qui a bougé ? ».

  Les pronoms suivent le genre (« elle » pour la tasse, « il » pour le livre). Exemple de réponse : « Je ne la vois plus. Je l'ai vue pour la dernière fois à droite, il y a 8 secondes. ».
- **Arrêt** :
  - « Stop », « Arrête d'observer », « Coupe la caméra » coupent caméra, capteurs et voix, et effacent la mémoire de la session.
  - Pendant que le micro écoute, les annonces sont suspendues pour que Jarvis ne s'entende pas lui-même.
- **Sécurité** : la politique de sécurité bloque aussi les affirmations françaises interdites :
  - « le chemin est libre », « vous pouvez traverser » ;
  - « il n'y a aucun obstacle » ;
  - distances chiffrées, certitudes.

| Élément | Prévu | Implémenté | Vérifié en CI | Validé sur iPhone |
|---|---|---|---|---|
| Apparition annoncée une fois, silence ensuite | ✓ | ✓ | tests unitaires | à faire |
| Déplacement vers la droite repéré à l'arrêt de la tasse | ✓ | ✓ | tests unitaires | à faire |
| Mouvement du téléphone non confondu (gyroscope) | ✓ | ✓ | tests unitaires | à faire |
| Disparition, « Elle est où maintenant ? » | ✓ | ✓ | tests unitaires | à faire |
| Arrêt du mode : plus d'observation ni d'annonce | ✓ | ✓ | tests unitaires | à faire |
| Narration Vision en français, règles de sécurité françaises | ✓ | ✓ | tests unitaires + audits | à faire |
| Boutons, états, modes et erreurs de l'écran Vision en français, tests UI alignés (branche `feature/vision-ecran-fr`) | ✓ | ✓ | en attente | à faire |
| Aide (accueil et Vision), autotest et accueil Vision en français ; Réglages Vision déjà en français (#5) | ✓ | ✓ | test de surface | à faire |
| « Trouve la tasse », « Cherche mon téléphone » lancent Trouver ; l'alerte Trouver comprend les noms français | ✓ | ✓ | tests unitaires | à faire |

Essai sur l'iPhone, en posant le téléphone :
1. Caméra > Guide en direct (« Live Guide »), puis démarrez.
2. Posez une tasse au centre. Attendu : une seule annonce, « Je vois une tasse au centre. » ou « Je crois voir une tasse au centre. ».
3. Faites-la glisser vers la droite et lâchez-la. Attendu : « La tasse s'est déplacée du centre vers la droite. » environ une seconde après l'arrêt, puis le silence.
4. Retirez-la. Touchez « Voix » et dites « Elle est où maintenant ? ». Attendu : « Je ne la vois plus. Je l'ai vue pour la dernière fois à droite… ».
5. Touchez Stop. Attendu : plus aucune annonce.

À rapporter : les annonces manquées ou répétées, et le délai de chacune.


## Preserved Boundaries

The app uses public APIs and does not provide jailbreak hooks, root access, hidden screen reading, injected taps, a lock-screen replacement, or unrestricted system control.

## Source of Truth

- Product source: `ios/JarvisXR`
- Project configuration: `ios/JarvisXR/project.yml`
- CI: `.github/workflows/ios-build.yml`
- Public docs: `docs/README.md`
- Vision evidence status: `docs/JARVIS_VISION_COMPLETION_LEDGER.md`
- Detector decision and acceptance boundary: `docs/JARVIS_VISION_MODEL_DECISION.md`
- Release artifact: GitHub Releases
