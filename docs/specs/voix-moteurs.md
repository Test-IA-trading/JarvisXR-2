# Voix de Jarvis : moteurs, licences, droits (novembre 2026)

## La voix de référence

Le fichier `jarvis_reference.wav` (14,6 min, stéréo 48 kHz) reste sur le PC du propriétaire. Il n'est jamais copié dans le dépôt, et il n'est pas non plus utilisé pour cloner une voix. Le timbre qu'on y entend est celui d'un acteur réel (Paul Bettany, voix de J.A.R.V.I.S. au cinéma), et les enregistrements appartiennent aux studios Marvel/Disney. Reproduire ce timbre demanderait l'accord de l'acteur et des ayants droit, quelle que soit la licence du moteur choisi.

Ce que fait Jarvis : `python -m jarvis_pc --analyse-voix chemin.wav` mesure localement le **style** de la voix sur ses passages les plus propres, puis ne conserve que des chiffres (`voix_reference.json`) :

| Mesure (passages propres) | Référence |
|---|---|
| Hauteur médiane | ≈ 163 Hz (de 121 à 250 Hz) |
| Débit | ≈ 6,4 syllabes/s |
| Pause médiane entre groupes | ≈ 0,31 s (90 % sous 0,58 s) |

Ces mesures sont approximatives (la bande-son contient de la musique et des bruitages). `python -m jarvis_pc --voix-essais` classe ensuite les voix françaises libres par proximité de style et écrit des essais WAV à écouter. Le réglage retenu est la voix Piper « pierre » (upmc, CC BY-SA 4.0), la voix masculine connue la plus proche. Les voix MLS plus proches en hauteur n'ont pas de sexe documenté. Réglages : hauteur relevée de 1,5 demi-ton (`voice_pitch_semitones`, 136 → 151 Hz, débit conservé), `voice_length_scale` 1,10 (6,43 syllabes/s mesurées, contre 6,42 pour la référence) et 0,3 s entre les phrases (pause médiane 0,31 s, comme la référence).

## Moteurs étudiés

| Moteur | Licence (code / modèles) | Français | Latence sur ce PC | Clonage | Verdict |
|---|---|---|---|---|---|
| **Piper** | MIT / selon la voix (upmc CC BY-SA 4.0, MLS CC BY 4.0, gilles CC0, tom AGPL) | oui, plusieurs voix | ≈ 0,06 s pour 5 s d'audio (CPU) | non | **retenu** : instantané, continu, servi à l'iPhone |
| XTTS-v2 (Coqui) | MPL / Coqui Public Model License (non commercial) | oui | GPU nécessaire, ~0,2–0,5 s par segment | oui, à partir de 6 s | possible plus tard avec une voix dont on a l'accord |
| F5-TTS | MIT / modèles CC BY-NC (données Emilia) ; versions françaises communautaires | via fine-tune | GPU, plus lent que Piper | oui | expressif, non commercial ; même condition d'accord |
| OpenVoice V2 | MIT (code et modèles) | oui (via MeloTTS français) | GPU conseillé | conversion de timbre | idem : seulement une voix autorisée |
| Chatterbox multilingue (Resemble AI) | MIT | oui | GPU 8 Go juste suffisant | oui, avec filigrane | prometteur pour l'expressivité |
| Kokoro | Apache 2.0 | une voix française féminine | très rapide | non | pas de voix masculine française |

La carte graphique (RTX 5060 Ti, 8 Go) sert déjà au cerveau (Qwen 30B en partie déchargé). Un moteur de clonage sur GPU entrerait en concurrence avec lui et ajouterait de la latence. Piper sur processeur évite ce conflit.

## Pour aller plus loin, légalement

1. Enregistrer une voix dont on a l'accord : la sienne, ou celle d'un comédien qui accepte par écrit. Quelques minutes de lecture propre suffisent.
2. L'utiliser comme référence de XTTS-v2, F5-TTS ou Chatterbox (usage personnel et non commercial selon les licences), dans `pc/.venv`, sans rien publier.
3. Ajouter ce moteur derrière l'interface existante (`Speaker.synthesize` / `/v1/tts`) : l'iPhone n'a rien à changer.
