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
