# Public Release Handoff

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
| Reconnaissance `fr-FR`, moteur local préféré puis repli Apple en ligne | ✓ | ✓ | en attente | à faire |
| Autorisations Speech puis micro, messages français et bouton Réglages | ✓ | ✓ | en attente | à faire |
| Session `.playAndRecord`, jamais désactivée sous un micro ouvert | ✓ | ✓ | en attente | à faire |
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
| Écoute continue mains libres pendant la manipulation | ✓ | — | — | — |
| Profondeur, rotation, redimensionnement, fiche « bilan » | ✓ | — | — | — |
| Annonces spontanées d'objets réels (tasse) dans la même session | ✓ | — | — | — |

Essai terrain le plus court, en mode avion :
1. Ouvrez le cube, cadrez un livre posé sur une table et attendez le cube.
2. Pincez-le dans l'air à gauche du livre, portez-le à droite, ouvrez les doigts.
3. Filmez de côté : le cube doit rester à droite du livre.
4. Touchez « Parler » et dites « Qu'est-ce que je viens de déplacer ? ». Réponse attendue : « Le cube ».

À rapporter : les valeurs de « Mesures » (cadence, délai pince → mouvement, ratées) et l'alignement des pastilles sur vos doigts.

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
