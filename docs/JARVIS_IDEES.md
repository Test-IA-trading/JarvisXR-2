# Idées pour un vrai Jarvis — au-delà de la fiche

Ces idées complètent la fiche d'usages et la mission (voix française, cube à la pince, conversation, tasse, bilan, aide contextuelle, tâches, recherche sourcée, liaison PC, « Dis Jarvis »). Aucune n'est encore implémentée : leur statut est **proposée**. Quand une idée est réalisée, déplacez-la dans `docs/FINAL_HANDOFF.md` avec ses colonnes « Implémenté / Vérifié en CI / Validé sur iPhone ».

Appareil cible : **iPhone 14 Pro**. Il a la Dynamic Island et un LiDAR, mais ni Apple Intelligence ni bouton Action. L'app est installée avec un identifiant Apple gratuit et doit être re-signée tous les 7 jours. Sauf mention contraire, chaque idée fonctionne sur l'iPhone, gratuitement et sans le PC.

## Contraintes communes

- **Extensions** (Dynamic Island, widgets, bouton du Centre de contrôle) : chacune est une cible signée à part. Avec un compte gratuit, elle consomme un identifiant d'app (10 au maximum par période de 7 jours) et l'outil d'installation doit la signer aussi (Sideloadly sait le faire).
- **Météo d'Apple** (WeatherKit) : réservée au programme développeur payant. Une source gratuite en ligne (Open-Meteo, sans clé) la remplace, en option et signalée comme nécessitant Internet.
- **Maison (HomeKit) en direct** : l'autorisation spéciale peut être indisponible avec un compte gratuit, à vérifier. Passer par les Raccourcis iOS de l'utilisateur évite ce besoin.
- **Réseau** : `tools/audit_vision_privacy.py` interdit aujourd'hui `URLSession`, `URLRequest` et `NWConnection` dans tout le code de l'app. La météo en ligne et l'allumage du PC demanderont un module réseau isolé, désactivé par défaut, avec une exception documentée dans l'audit, comme le transport vers le PC de la PR #1.
- **Vie privée** : même règle que le reste de l'app. Rien n'est envoyé à un service tiers en mode local, et aucune image ni aucun audio n'est conservé sans demande explicite.

## 1. Appeler Jarvis sans ouvrir l'app

| Idée | Ce que ça fait | Comment (iOS) | Limites |
|---|---|---|---|
| Toucher le dos | Deux tapes au dos de l'iPhone → Jarvis écoute | Réglages > Accessibilité > Toucher > Toucher le dos > Toucher deux fois > raccourci « Parler à JARVIS » (intention `StartJarvisListeningIntent`, lot 3) | Réglage à faire par l'utilisateur ; iPhone déverrouillé |
| Jarvis dans la Dynamic Island | Voir en permanence : écoute, réponse, tâche en cours, minuteur | ActivityKit (Live Activity) + extension WidgetKit, `NSSupportsLiveActivities` | Extension signée à part (voir contraintes) |
| Bouton du Centre de contrôle | Appeler Jarvis en un geste, même depuis une autre app | `ControlWidget` (iOS 18) qui lance l'intention « Parler à JARVIS » | Extension signée à part |
| Oui / non avec la tête | Hocher ou secouer la tête avec des AirPods pour confirmer, sans les mains ni l'écran | `CMHeadphoneMotionManager` (Core Motion), `NSMotionUsageDescription` | AirPods compatibles avec le suivi de la tête |

## 2. Agir dans la vie de l'utilisateur

| Idée | Ce que ça fait | Comment (iOS) | Limites |
|---|---|---|---|
| Agenda et rappels | « Qu'est-ce que j'ai demain ? », « Rappelle-moi d'appeler maman à 18 h » | EventKit (`requestFullAccessToEvents`, `requestFullAccessToReminders`), clés `NSCalendarsFullAccessUsageDescription` et `NSRemindersFullAccessUsageDescription` | Autorisations à accepter |
| Minuteurs nommés | « Minuteur pâtes 10 minutes », « Il reste combien pour le four ? » | AlarmKit (iOS 26, minuteurs visibles par le système) ou notifications locales `UNUserNotificationCenter` | Notifications autorisées |
| Lancer les Raccourcis | « Lance mon raccourci Bonsoir » ; pilote aussi les scènes Maison | `shortcuts://run-shortcut?name=…` (+ `x-callback-url` pour revenir dans Jarvis) | Ouvre brièvement l'app Raccourcis |
| Briefing du matin | Agenda, rappels, notes, batterie, météo en option | EventKit + `JarvisMemoryStore` + `UIDevice` ; météo Open-Meteo optionnelle | Météo = Internet |
| Allumer le PC | « Jarvis, allume mon PC », puis tâches lourdes confiées à Qwen | Paquet Wake-on-LAN (UDP, framework Network), `NSLocalNetworkUsageDescription` ; compagnon Windows de la PR #1 | Wake-on-LAN activé dans le BIOS et la carte réseau du PC ; même réseau domestique |

## 3. Voir et comprendre

| Idée | Ce que ça fait | Comment (iOS) | Limites |
|---|---|---|---|
| Montrer du doigt | « C'est quoi, ça ? » en pointant un objet | Direction articulation → bout de l'index (`VNDetectHumanHandPoseRequest`) croisée avec les boîtes du détecteur Core ML, ou rayon ARKit | Objets connus du détecteur (80 classes) |
| Mémoire des objets | « Où est la télécommande ? » → « Je l'ai vue il y a 20 min sur la table » | Dernière position et heure par classe (mémoire de session étendue), position dans le monde en AR ; objets personnels appris une fois via `VNGenerateImageFeaturePrintRequest` (« montre-moi tes clés ») | Les clés ne font pas partie des 80 classes : apprentissage nécessaire |
| Traduire un texte filmé | Viser un texte anglais → Jarvis le lit en français, hors ligne | `VNRecognizeTextRequest` + framework Translation (iOS 18, langues téléchargées une fois) | Première utilisation : téléchargement de la langue |
| Mode surveillance | Téléphone posé : alerte quand quelque chose change devant la caméra | Pipeline Vision existant + seuil de changement + notification locale | Batterie et chaleur ; ce n'est pas un système de sécurité |

## 4. Réalité augmentée façon Iron Man

| Idée | Ce que ça fait | Comment (iOS) | Limites |
|---|---|---|---|
| Objets qui restent dans la pièce | Un pense-bête accroché au frigo, retrouvé à la prochaine ouverture | `ARWorldMap` (`getCurrentWorldMap`, `initialWorldMap`) enregistrée sur l'iPhone, relocalisation au retour | Relocalisation sensible à la lumière et aux changements de la pièce |
| Occlusion et physique LiDAR | Le cube passe derrière le vrai livre, tombe, rebondit, peut être lancé | `sceneReconstruction = .mesh` + `sceneUnderstanding.options = [.occlusion, .physics, .collision]`, `PhysicsBodyComponent`, vitesse du geste de la main | Appareils avec LiDAR (le 14 Pro en a un) ; repli sans occlusion ailleurs |
| Panneau flottant au-dessus du bureau | Heure, agenda, tâches en cours, déplaçable à la pince | Entité RealityKit avec texte, comme la fiche du bilan (lot 3) | — |
| Son spatial | La voix semble venir de l'objet dont Jarvis parle | `AVAudioEnvironmentNode` (ou PHASE) positionné sur l'entité ; AirPods avec suivi de la tête | Synthèse à faire passer par le moteur audio de l'app (aussi utile pour l'interruption vocale) |

## 5. Personnalité et confiance

| Idée | Ce que ça fait | Comment (iOS) | Limites |
|---|---|---|---|
| Personnalité constante | Ton et vocabulaire stables, réponses courtes, pauses naturelles | Guide de style des réponses ; `AVSpeechUtterance(ssmlRepresentation:)` (iOS 16) pour pauses et accentuation | — |
| Petits sons d'interface | Sons courts pour « j'écoute », « saisi », « déposé », « terminé » | Sons originaux intégrés à l'app (jamais d'extraits de films) | — |
| « Ce que Jarvis sait de moi » | Tableau des données gardées (notes, historique, calibrage, conversation en mémoire), effacement en un tap, verrou Face ID | LocalAuthentication (`LAContext`), `NSFaceIDUsageDescription` | — |
| Journal de la journée | « Qu'ai-je fait aujourd'hui ? » | Agrégation des notes, tâches, manipulations AR et historique | — |

## Ordre conseillé

1. **Toucher le dos + Dynamic Island** : appeler Jarvis et le voir à tout moment.
2. **Agenda, rappels, minuteurs** : utile chaque jour, entièrement local.
3. **Occlusion LiDAR + objets qui restent dans la pièce** : l'effet « vrai Jarvis », dans la continuité du cube.

Ensuite : montrer du doigt et la mémoire des objets (qui prolongent le scénario de la tasse), puis le son spatial avec l'interruption vocale (même travail audio).
