# Une conversation naturelle avec Jarvis sur iPhone

**Cahier des charges produit et guide d’implémentation pour Claude Code · 26 novembre 2026**

Je veux pouvoir réfléchir à voix haute avec Jarvis comme je le fais avec ChatGPT. Je dois pouvoir chercher un mot, changer d’avis, l’interrompre ou lui demander « pourquoi ? » sans apprendre une formule de commande. Je veux pouvoir écouter un texte, faire une parenthèse sur une phrase et reprendre ma lecture. Jarvis parle français, me vouvoie et reste utilisable sur l’iPhone quand le PC est éteint.

Le code de référence est celui de la [PR nº 31][pr31] au [commit `a663933`][code]. Elle était ouverte au moment de la rédaction et reprend les travaux sur la conversation de la PR nº 28. Ce guide se trouve sur `develop` pour être accessible depuis les prochaines branches. Avant de coder, retrouver les mêmes responsabilités sur la branche de travail. Les comportements décrits comme objectifs et les temps proposés ci-dessous restent à vérifier sur appareil.

**Pour commencer dans Claude Code**, lire [le diagnostic du code](#diagnostic-du-code), [la gestion du son réellement joué](#suivre-la-parole-réellement-diffusée) et [l’ordre de réalisation](#ordre-de-réalisation). Le premier correctif porte sur une réponse que Jarvis a écrite en entier et que l’utilisateur interrompt pendant sa lecture. Les [dialogues de recette](#dialogues-de-recette) servent à vérifier la progression, y compris dans une conversation ordinaire sans document.

## Ce que je veux ressentir

### Une discussion spontanée

| Ce que dit l’utilisateur | Ce que fait Jarvis | Ce que le développeur doit observer |
| --- | --- | --- |
| « J’hésite entre deux sorties. Le musée dure quarante minutes, la balade une heure. J’ai quarante-cinq minutes. » | « Le musée tient dans vos quarante-cinq minutes. Il vous restera cinq minutes. » | Une question peut être implicite. Les noms, les durées et la contrainte restent associés. |
| « Et si… euh… finalement j’ai une heure dix ? » | Il attend la suite après l’hésitation. « Les deux sont possibles. Vous auriez dix minutes de marge pour la balade. » | La correction porte sur le temps disponible. Les deux durées restent valides. |
| Pendant la réponse, « Attends, juste celle qui prend le moins de temps. » | Il cède la parole. « Le musée, quarante minutes. » | L’interruption change le niveau de détail et le critère. Une ancienne réponse déjà prête ne reprend pas la parole. |
| Au clavier, « Et l’autre ? » | « La balade dure une heure. » | Le canal change. Le sujet et la dernière comparaison restent accessibles. |

Ces répliques illustrent des intentions. Pour valider la compréhension, varier les activités, les chiffres, l’ordre et les formulations. Une réponse équivalente dans un français naturel convient.

### Quand je veux simplement discuter

Une partie de l’aisance vient des échanges où je n’ai encore ni question bien formée ni action à demander. Laisser l’idée se préciser. Une reformulation courte peut vérifier le sens. Une suggestion concrète peut suffire. La réponse suivante doit tenir compte de mon retour, même si je change complètement d’avis.

| Ce que je dis | Exemple de réponse naturelle |
| --- | --- |
| « J’ai une idée pour un jeu, mais je sais pas trop comment l’expliquer… » | Après m’avoir laissé finir, « Qu’est-ce que vous aimeriez que le joueur ressente ? » |
| « Que ce soit le même lieu… mais qu’à chaque fois qu’on y retourne, quelque chose ait changé. » | « On reconnaîtrait l’endroit tout de suite et on se demanderait ce qui s’y est passé depuis la dernière visite. » |
| « Ouais, c’est ça. Donne-moi un seul exemple. » | « La première fois, une gare est déserte. Quand vous y revenez, une tasse de café encore chaude attend sur le quai. » |
| « Trop mystérieux. Garde la gare, fais quelque chose de drôle. » | « Vous retrouvez la même gare. Cette fois, sur le panneau des départs, tous les trains sont annoncés à l’heure sauf celui pour “Tout de suite”. » |

La dernière demande change le ton et conserve le lieu. « Trop mystérieux » est un retour sur la proposition, « garde la gare » une contrainte et « drôle » la nouvelle orientation. Le modèle peut composer une autre bonne réponse. Pour la recette, vérifier qu’il conserve les contraintes vivantes, respecte « un seul exemple » et évite de relancer avec une question à chaque réplique. Pour une personne qui réfléchit à voix haute, le droit de finir sa pensée fait partie du résultat.

### Lire, expliquer, reprendre

Utiliser d’abord ce texte fictif, assez court pour entendre précisément les coupures.

> Le tribunal retient le courrier du 12 avril. Ce courrier confirme la date de livraison. La facture permet ensuite de vérifier le montant.

1. « Lis-moi ce passage. » Jarvis commence avec les mots du texte source.
2. Au moment où on entend « Ce courrier confirme… », dire « Attends… quel courrier ? ». Jarvis s’arrête, laisse finir la question et répond « Celui du 12 avril. »
3. « Et qu’est-ce qu’il prouve ici ? » Jarvis répond « Dans ce passage, il confirme la date de livraison. » Il peut consulter la phrase source entière pour répondre, même si la lecture publique s’est arrêtée en son milieu.
4. « OK, reprends. » Il reprend dans la deuxième phrase, au repère disponible. Si le moteur garantit seulement la phrase, il en relit le début. La phrase sur la facture suit une seule fois.

Le modèle doit donc recevoir deux informations différentes. Le **document source** lui indique ce qu’il peut expliquer. La **position de lecture** lui indique ce qui a déjà été diffusé et à quoi « ce que tu viens de dire » renvoie. L’explication intermédiaire a sa propre réponse vocale. Elle laisse le marque-page du document intact.

## Ce que les architectures vocales publiques nous apprennent

Un assistant vocal peut transcrire la parole, confier le texte à un modèle de langage et faire lire sa réponse par une voix de synthèse. Un modèle audio natif peut aussi traiter le son directement et utiliser des indices qui disparaissent dans la transcription. OpenAI décrit une troisième propriété dans le mode Live de ChatGPT, le **full duplex**. Le modèle continue à traiter la voix entrante pendant qu’il parle. Il peut choisir d’attendre, de céder la parole ou de continuer. Une recherche plus longue peut être déléguée pendant que le dialogue reste disponible. [Présentation de GPT-Live][live] · [Architectures d’agents vocaux][agents]

Pour Jarvis, reprendre ces propriétés observables avec les moteurs déjà présents. Maintenir le micro ouvert résout une partie du transport audio. Le rythme dépend ensuite de décisions distinctes. Une hésitation mérite parfois du temps. Un « mmh » peut simplement encourager Jarvis à continuer. Un « attends » doit lui faire céder la parole. La pertinence d’une explication dépend du modèle et du contexte qu’on lui fournit. On peut améliorer la prise de parole indépendamment de la taille du modèle. Pour comparer ensuite la qualité des explications, utiliser les mêmes passages et les mêmes questions sur l’iPhone et sur le PC. [Détection de fin de parole][vad] · [Comportement conversationnel des modèles vocaux][prompting]

## Diagnostic du code

Les fichiers Swift ci-dessous se trouvent dans `ios/JarvisXR/JarvisXR/` sur le commit de référence. Le dossier `native/ios/JarvisShell` correspond à un autre chemin du dépôt. La cible de ce travail est l’app UIKit `JarvisXR` construite par XcodeGen.

| Point d’entrée | Comportement vérifié dans le code de référence | Conséquence pour l’implémentation |
| --- | --- | --- |
| [JarvisVoiceInputService.swift][input] | Utilise Speech en `fr-FR`, publie des transcriptions partielles et finales, associe des callbacks à une génération. En mode commande, les temporisations comprennent 7 s sans texte et un plafond de 30 s. Le réveil et la commande ont des politiques de reconnaissance distinctes. | Réutiliser le flux existant. Traiter une dictée de plus de 30 s comme un cas de continuité à tester. Vérifier la disponibilité effective de la reconnaissance française sur appareil. |
| [JarvisDuplexAudio.swift][duplex] | Un `AVAudioEngine` relie le micro et la sortie vocale. Le traitement de voix Apple sert à annuler l’écho. Un tampon glissant d’environ 1,2 s récupère le début d’une intervention. Le code rétablit le moteur après certains changements de configuration. | Conserver une capture unique. Placer les observations de lecture sur la sortie qui joue les buffers. Vérifier le comportement après une reprise de route ou un arrêt du lecteur. |
| [JarvisConversationFlow.swift][flow] | `JarvisTurnEndDetector` choisit entre 0,8, 1,2, 1,6 et 2,4 s selon le texte et sa ponctuation. `JarvisBargeInDetector` détecte une voix possible. `JarvisEchoFilter` compare les mots captés à ceux de la réponse. | Partir de ces règles et mesurer les cas où elles se trompent. Le point d’interrogation produit par la transcription peut arriver avant la vraie fin de l’idée. |
| [JarvisRootViewController.swift][controller] | Coordonne le micro, la baisse de volume, la confirmation de l’interruption et le flux de phrases. `brainTurn` protège plusieurs mises à jour d’interface. `execute` recalcule `conversationActive` selon que la demande vient de la voix ou du clavier. | Conserver un seul échange logique pour les deux entrées. Distinguer le choix de garder le micro ouvert du choix de conserver le sujet. Protéger aussi les effets différés sur le contexte. |
| [JarvisSpeechService.swift][speech] | Utilise `AVSpeechSynthesizer`. Selon le parcours, le synthétiseur parle directement ou écrit des buffers pour le moteur duplex. `currentReplyText` peut contenir des phrases déjà mises en file. Le rappel `willSpeakRangeOfSpeechString` sert notamment à alimenter la file. | Distinguer texte à prononcer, texte mis en file et portion déjà diffusée. Couvrir les deux parcours de sortie audio. |
| [JarvisLocalBrain.swift][brain] | Contient `JarvisSentenceStreamer`, la préparation du contexte et les appels au modèle. Pour une question ouverte, certains chemins enregistrent la réponse dès qu’elle est produite, par le PC, par le modèle embarqué ou depuis un extrait Wikipédia. | Rattacher la réponse au tour qui l’a demandée. Faire progresser séparément l’historique oral avec la lecture. Conserver le fonctionnement des réponses affichées. |
| [JarvisConversationContext.swift][context] | Conserve jusqu’à six échanges récents, ainsi que certains faits structurés sur les horaires, les notes et la scène. Le contexte du modèle embarqué est aussi limité en taille. | Garder les entités de la question, les corrections et les références utiles au-delà d’une simple suite de six messages. Réutiliser les informations déjà structurées. |
| [JarvisPhrasing.swift][phrasing] et [JarvisFrenchCommands.swift][french] | Reformulent de nombreuses tournures et reconnaissent des commandes et relances françaises. Le routage existant sait déjà traiter des cas exacts, dont les horaires. | Faire porter les règles sur les actions déterminées. Donner au modèle la formulation originale pour les demandes ouvertes. Tester les nouvelles capacités sur des exemples qui échappent aux règles existantes. |
| [JarvisPCLink.swift][pc-link] et [pc/jarvis_pc/server.py][server] | `/v1/ask` transporte la question, l’historique et des lignes de contexte. Le serveur diffuse du NDJSON avec des réponses partielles cumulatives puis une réponse finale. `/v1/command` peut déclencher une action. | Préserver le protocole des installations existantes. Distinguer les opérations de dialogue de celles qui produisent un effet sur le PC ou l’iPhone. |
| [JarvisScreenContext.swift][screen] et [JarvisMemoryStore.swift][memory] | Le premier conserve des options sélectionnées dans Jarvis. Le second gère entre autres notes et historique local. | Ancrer « cette option », « ma dernière note » et « ce passage » dans leur vraie source. Donner au texte lu une référence propre, en respectant les choix de conservation existants. |

**Premier défaut à reproduire.** Faire produire trois phrases, retarder la sortie audio avec un lecteur de test, puis couper au milieu de la deuxième. `recordTurn` peut déjà avoir reçu les trois phrases. Une question sur « la dernière chose que vous m’avez dite » risque alors de prendre pour point de départ le texte généré jusqu’au bout. Commencer par cet essai avant de modifier la voix ou de changer de modèle. [Chemin local][record-local] · [Chemin PC][record-pc] · [Gestion de l’interruption][interrupt]

## Organisation d’une session

~~~mermaid
flowchart TD
    A["Micro et clavier"] --> B["Conversation sur l’iPhone"]
    B --> C{"Intention du tour"}
    C -->|Lire| D["Texte source et marque-page"]
    C -->|Discuter ou expliquer| E["Modèle local ou PC appairé"]
    C -->|Agir| F["Action prise en charge"]
    D --> G["Affichage et lecture vocale"]
    E --> G
    F --> G
    G -->|Progression de lecture| B
~~~

L’iPhone tient la conversation pendant toute la session. Le modèle choisi est un exécutant auquel on fournit le contexte nécessaire. Un changement de moteur garde le même sujet, le même passage et les corrections de l’utilisateur. Un résultat d’action arrive avec son état réel, par exemple « brouillon ouvert », « recherche terminée » ou « appareil indisponible ».

Suivre trois états indépendants. **L’entrée** peut être en veille, écouter une phrase ou attendre sa conclusion. **La sortie** peut être silencieuse, en préparation, en lecture ou baissée le temps d’identifier une interruption. **Le travail en cours** peut attendre un résultat, être corrigé ou être terminé. Jarvis peut parler tout en écoutant et faire ces deux choses pendant qu’une recherche avance. L’écran affiche la situation qui aide l’utilisateur à agir.

| Événement | Décision attendue |
| --- | --- |
| L’utilisateur ouvre une session ou réveille Jarvis | Armer le micro approprié, préserver le début de la demande, continuer à écouter après la réponse si le mode continu est actif. |
| Un résultat partiel Speech remplace le précédent | Mettre à jour le texte provisoire. Conserver une seule demande et attendre sa stabilisation avant un effet externe. |
| Le tour est suffisamment complet | Valider la demande une seule fois, rattacher les références au sujet et lancer sa réponse ou son action. |
| Une première phrase utilisable est prête | Afficher selon le canal et programmer sa lecture. Associer sa sortie à la réponse active. |
| Un bruit ressemble à une reprise de parole | Baisser temporairement la sortie et observer la suite. Si l’hypothèse tombe, rétablir le volume et poursuivre au même endroit. |
| Une véritable intervention est confirmée | Figer la progression audio, rendre périmés les anciens événements de lecture, arrêter la sortie et traiter la nouvelle intervention avec son contexte. |
| Une réponse réseau ou audio arrive après une correction | Comparer l’identité et la version de l’opération à celles encore attendues avant toute parole, écriture mémoire ou action. |
| L’utilisateur termine la conversation | Fermer proprement la session. La veille éventuelle relève de son réglage propre. Un retour dans l’app retrouve l’état que l’utilisateur a choisi de conserver. |

## Savoir quand laisser la parole

### Du premier son à la fin d’une idée

1. **Récupérer les premiers mots.** En mode mains libres, garder le court tampon audio du moteur duplex en mémoire vive. Au déclenchement, alimenter la requête une seule fois avec ce tampon puis avec les nouveaux buffers. Tester « Ouvre les notes » dit immédiatement après « Jarvis » et « Non, mardi » prononcé sur la fin de sa voix. La première syllabe peut porter tout le sens.
2. **Suivre une hypothèse qui évolue.** Speech peut transcrire successivement « je veux mardi », puis « je veux mardi ou mercredi ». Remplacer l’hypothèse provisoire du même tour. Garder les accents et le texte original pour le modèle. La version normalisée sert à reconnaître les commandes. Une transcription finale, un délai expiré et une fermeture manuelle peuvent se croiser. Un seul événement doit valider le tour.
3. **Combiner plusieurs indices.** Utiliser l’activité vocale effective, l’âge du dernier résultat utile et la forme de la phrase. « Je voudrais que… », « entre le musée et… » et une énumération en cours invitent à attendre. « C’est tout » ou « donne-moi juste l’heure » sont plus conclusifs. Un bruit, une majuscule ou un changement de ponctuation isolé apporte peu d’information. Vérifier aussi qu’un retard de reconnaissance pendant que l’utilisateur parle ne déclenche pas une réponse.
4. **Gérer une hésitation longue.** Conserver la demande tant que la personne cherche ses mots. Si la pause s’allonge au point où il faut céder le tour, garder l’énoncé et permettre une reprise immédiate. Pour une dictée, accepter des segments de reconnaissance successifs dans une seule note et préserver l’ordre, les frontières et les mots communs lors du raccord. Tester le franchissement du plafond de 30 s avec une phrase à cheval sur la coupure.
5. **Régler sur des conversations françaises.** Comparer les seuils actuels sur un locuteur rapide, un locuteur qui hésite et une pièce bruyante. Essayer un classifieur de fin de tour sémantique si les erreurs persistent après ces mesures. Le faire prédire « la personne a-t-elle terminé ? » sur des exemples français. Mesurer sur l’iPhone son coût, sa latence et sa capacité à réduire les coupures. Une API ou un nouveau modèle reste un choix d’implémentation. [Principe de la détection sémantique][vad]

### Distinguer l’interruption, l’acquiescement et l’écho

| Son entendu pendant que Jarvis parle | Réaction souhaitée |
| --- | --- |
| « Attends », « stop », « pardon, je te coupe » | Céder rapidement la parole. « Attends… » suivi d’un silence donne du temps. L’utilisateur peut ensuite poser sa vraie question dans le même mouvement. |
| « Non, je voulais dire jeudi. » | Arrêter la phrase en cours. Conserver « jeudi », identifier la donnée corrigée et recalculer la suite. |
| « Oui, oui » ou « mmh » pendant une explication | Quand cela signifie « je suis », poursuivre à un rythme naturel. Après une vraie question fermée de Jarvis, le même « oui » devient une réponse. |
| Une toux, de la vaisselle ou une syllabe du haut-parleur | Utiliser l’annulation d’écho et les indices temporels. Une baisse passagère du volume se résorbe si aucune intervention ne se confirme. |
| L’utilisateur répète un mot que Jarvis prononce, puis pose une question | Tenir compte des mots qui suivent et du moment où les deux voix se chevauchent. « La livraison… quelle livraison ? » est une intervention légitime. |

Le filtre existant compte les mots communs avec `currentReplyText`. En flux continu, ce texte peut déjà contenir le paragraphe suivant. Comparer d’abord à une courte fenêtre autour de ce qui **sort réellement du haut-parleur**. Une personne peut aussi citer un mot que Jarvis vient de lire. Combiner proximité temporelle, niveau après annulation d’écho, forme de la demande et suite de la transcription. À la confirmation, conserver le début capté pendant la baisse de volume. [Filtre d’écho et reprise de parole][flow] · [Contrôleur de conversation][interrupt]

En cas d’échec d’ouverture du duplex, proposer le parcours qui fonctionne sur cette route, par exemple interrompre au toucher puis parler. Après un appel ou un changement casque/haut-parleur, conserver le sujet et le repère de lecture, reconstruire l’audio avec le format effectivement disponible et respecter le réglage de reprise. Tester la distinction entre session ouverte, app passée en arrière-plan et app relancée. [Changements de route audio sous iOS][route] · [Reprise du moteur dans Jarvis][duplex]

## Suivre la parole réellement diffusée

### Ce qu’il faut garder pour chaque réponse

| Donnée | Quand elle devient vraie | À quoi elle sert |
| --- | --- | --- |
| Texte produit | Le modèle l’a fourni, éventuellement par morceaux | Affichage, révision du brouillon et découpage en unités prononçables. |
| Texte mis en file | Un segment est confié au lecteur | Alimenter régulièrement la voix et jeter les segments en attente lors d’une interruption. |
| Portion diffusée | Le lecteur a progressé dans l’audio de ce segment | Construire le contexte oral et situer « ce que tu viens de dire ». |
| Portion affichée | L’interface a présenté le texte | Permettre une question sur un passage sélectionné à l’écran, y compris en mode silencieux. |
| Position dans la source | Une portion prononcée correspond à une plage du document | Lire la suite, revenir à la phrase précédente et expliquer le bon extrait. |

« Diffusé » signifie que la sortie audio a atteint la position observée. Le téléphone peut établir ce repère technique. Ce que la personne a effectivement perçu reste une approximation, en particulier en Bluetooth. Si le lecteur sait seulement qu’une phrase est terminée, mémoriser cette précision et reprendre à une frontière de phrase.

**Exemple d’état au moment de la coupure**

| Champ | Valeur illustrative |
| --- | --- |
| Source active | Note locale de démonstration, révision 3 |
| Dernière phrase entièrement diffusée | « Le tribunal retient le courrier du 12 avril. » |
| Phrase en cours | « Ce courrier confirme la date de livraison. » |
| Dernier mot repéré, si le moteur le permet | « confirme » |
| Suite déjà préparée par le moteur | « La facture permet ensuite de vérifier le montant. » |
| Question reçue | « Attends… quel courrier ? » |
| Contexte donné au modèle | La question, le passage source et le repère de lecture. La suite préparée reste identifiable comme texte source. |

### Où brancher la progression

**Sortie via le moteur duplex.** `JarvisSpeechService` appelle `renderer.write` puis `JarvisDuplexAudio.play`. Les buffers rendus peuvent arriver bien avant leur restitution. Associer chaque segment à sa génération de lecture et au texte source. Le code utilise déjà `.dataPlayedBack`. Son propre contrat tient aussi compte de buffers évacués à l’arrêt. Figer le dernier repère valable et invalider la génération **avant** de vider la file. Un rappel livré après `stop()` ne doit plus avancer le repère. Tenir compte d’un éventuel changement de format d’échantillonnage pendant la lecture. [Rendu des buffers][render] · [Mise en lecture dans Jarvis][played] · [Rappel Apple de lecture][played-apple]

**Précision au mot si elle est disponible.** Sur les voix et les versions compatibles, les marqueurs de synthèse peuvent associer des plages du texte à des positions dans l’audio produit. Les corréler avec la progression du lecteur, en tenant compte du format et d’un éventuel rééchantillonnage. Leur réception pendant la synthèse décrit le son préparé. Le premier lot peut confirmer les phrases terminées et identifier la phrase en cours. Il est déjà capable de restituer un dialogue cohérent à cette précision. [Marqueurs de synthèse Apple][markers]

**Sortie classique.** `willSpeakRangeOfSpeechString` signale la portion **sur le point** d’être prononcée. Utiliser ses rappels successifs et la fin normale de l’énoncé pour distinguer position en cours et portion terminée. À l’annulation, conserver le dernier repère défendable. Si la voix ou la route ne rapporte aucun repère fin, reprendre au début de la phrase interrompue. Utiliser le même contrat pour le lecteur duplex et le lecteur classique. [Rappel de progression du synthétiseur][will-speak]

**Affichage seul et saisie au clavier.** Une réponse affichée intégralement garde sa valeur même si la voix est coupée. « Explique la partie que j’ai sélectionnée » utilise la sélection. « Répète ce que tu viens de dire » utilise la progression vocale. L’historique transmis au modèle indique l’origine de l’information quand cette différence change la réponse.

### Petit contrat d’implémentation

Noms indicatifs pour expliquer les responsabilités. Réutiliser les types, identifiants et compteurs déjà adaptés dans le projet.

~~~text
Au début d’une réponse
  Associer le tour, la génération de lecture et, si pertinent, une révision du texte source.
  Conserver séparément le texte généré, les segments en attente et le dernier repère diffusé.

Quand un segment progresse
  Accepter uniquement une progression appartenant à la génération active.
  Avancer le repère de façon monotone à l’intérieur de la même lecture.
  Convertir la position du texte prononcé en position de la source si nécessaire.

Quand l’utilisateur interrompt
  Capturer la dernière position fiable et la phrase en cours.
  Invalider les anciens rappels, puis arrêter la sortie et vider la file.
  Enregistrer une seule fois le préfixe oral diffusé et l’état interrompu.
  Conserver la demande qui vient d’arriver. Décider séparément du sort de la tâche de fond.

Quand le modèle termine d’écrire
  Finaliser le texte généré du bon tour.
  Laisser la sortie audio faire progresser le repère oral à son rythme.
~~~

Prévoir une réponse interrompue **avant le premier son**, deux interruptions successives, un rappel rejoué et un retour réseau après la fermeture de la session. Un message dont aucun son n’est sorti ne fournit aucun préfixe oral. Adapter `recordTurn` ou son appelant pour conserver malgré tout la demande utilisateur utile au contexte. Maintenir la compatibilité des appels existants pour les échanges textuels et les anciens historiques.

## Comprendre une intention et garder le fil

### Donner les bons éléments au modèle

Pour répondre à « et la deuxième ? », le modèle a besoin de la liste telle qu’elle a été présentée, de son ordre et de la dernière question. Pour répondre à « pourquoi il dit ça ? », il a besoin de la phrase visée et, souvent, de la phrase précédente. Construire le contexte dans cet ordre de priorité lorsque la place est limitée.

1. Demande actuelle dans sa formulation originale, sélection explicite éventuelle et dernière correction formulée par l’utilisateur.
2. Objet ou passage actif avec sa source, sa révision, sa position et l’objectif du moment, par exemple lire, comparer ou expliquer.
3. Échanges récents utiles et portées des réponses précédentes, dont la dernière partie prononcée si elle a été interrompue.
4. Résultats confirmés et données structurées de la session, par exemple une liste ordonnée d’options, une note retrouvée ou le dernier geste réellement observé en réalité augmentée.
5. Résumé des tours plus anciens et préférences pertinentes choisies par l’utilisateur. Mettre à jour un fait corrigé sans réintroduire l’ancienne valeur comme encore valide.

Le code embarqué utilise un budget par défaut de 4 500 caractères pour préparer le prompt et une fenêtre de 2 048 tokens dans le moteur local de référence. Le client iPhone transmet au PC au plus six tours, et la route `/v1/ask` borne aussi les lignes de contexte. Prioriser explicitement les extraits utiles avant ces limites. Un long document peut rester sur l’iPhone, accompagné de ses positions. Au modèle, transmettre le passage visé et son voisinage, puis élargir si la question demande une synthèse. Pour une synthèse intégrale, traiter toutes les parties nécessaires et indiquer la portion couverte si la source est incomplète. [Préparation du contexte local][brain] · [Transport vers le PC][pc-link] · [Serveur du PC][server]

Autre limite concrète, le constructeur local applique actuellement `prefix(1_500)` à la question. Une correction située tout à la fin d’une longue dictée peut ainsi disparaître du prompt. Conserver le texte complet dans sa source, extraire la demande finale et lui réserver une place avant de choisir les extraits du contexte. Tester avec deux horaires opposés, dont le bon arrive après cette limite. Pour les petites demandes, ce traitement doit garder la question intacte. [Construction du prompt][prompt-local]

### Résoudre les relances en français

| Parole de l’utilisateur | Information à utiliser | Réponse ou décision attendue |
| --- | --- | --- |
| « Et l’autre ? » après deux propositions | Les deux éléments et celui qui vient d’être discuté | Identifier l’autre et répondre sur le même critère. |
| « Non, je parlais de l’heure du musée. » | L’objet corrigé et l’attribut demandé | Corriger uniquement le référent. Répondre directement si l’information existe. |
| « Pour demain… enfin vendredi. » | La dernière correction dans le même tour, le jour local si nécessaire | Utiliser vendredi. Pour une action dont la date reste ambiguë, obtenir la précision qui change l’exécution. |
| « Fais plus simple », « développe juste le deuxième point » | La réponse précédente et son niveau de détail | Réexpliquer le point demandé avec un exemple ou une formulation plus courte. |
| « Dis-le en anglais », puis « reprends en français » | La langue de cette demande et la préférence habituelle | Changer de langue sur le passage demandé, puis reprendre le français. Garder les noms propres. |
| « Pourquoi elle refuse ? » après deux personnes ou décisions possibles | Les référents compatibles dans le contexte | Si le choix change la réponse et reste incertain, demander « Vous parlez de la première décision ou de la seconde ? ». |
| « Qu’est-ce que je viens de déplacer ? » | Le dernier événement de manipulation fourni par la scène | Nommer l’objet attesté. Si l’événement manque, expliquer quelle observation manque. |
| « Et pour demain ? » après un changement de sujet explicite | Le nouveau sujet et les éventuelles références temporelles | Recalculer dans le nouveau contexte. Garder l’ancien sujet disponible si l’utilisateur y revient explicitement. |

Pour une discussion libre, laisser au modèle la possibilité de répondre directement. Pour une action reconnue, utiliser le routeur et les validations déjà prévues. Pour une phrase telle que « Que veut dire “appelle Paul” ? », l’intention est d’expliquer une expression. Protéger les citations, les hypothèses et les négations lors de la détection d’actions. Conserver la frontière entre texte destiné à être lu, dialogue de l’utilisateur et commande réellement demandée. La sortie interne `COMMANDE:` reste réservée au routage. [Reformulation française][phrasing] · [Routage du modèle][brain]

### Une seule discussion en voix et au clavier

Donner une même identité de session aux deux canaux. Taper une précision peut volontairement suspendre l’écoute, par exemple dans le mode silencieux. Le sujet, les références et la position de lecture restent disponibles. Une reprise vocale utilise le même contexte. Vérifier les deux sens, y compris une question tapée pendant qu’une réponse est en train d’être prononcée. Dès que le texte est **envoyé**, prendre en compte la correction, mettre à jour le tour actif et empêcher une ancienne réponse de revenir. L’ouverture du clavier ou la simple saisie d’une lettre peut rester discrète.

Distinguer ce que l’utilisateur veut garder pendant cette conversation et ce qu’il demande d’enregistrer pour la prochaine fois. Une remarque hypothétique (« imagine que je parte demain ») reste dans le scénario. Une instruction explicite (« retiens que je préfère les réponses courtes ») relève de la mémoire prévue par le produit. Réutiliser les notes, préférences et mécanismes d’effacement existants. Un ancien élément sans position de lecture peut encore s’afficher. À sa première relecture, initialiser son repère au début.

## Lire, expliquer et parler avec naturel

### Accès au passage

Démarrer avec une source déjà accessible dans l’app, par exemple une note choisie par l’utilisateur ou un extrait de texte collé. Un identifiant local, une révision de contenu et des plages de caractères suffisent au premier parcours. Le même mécanisme peut ensuite recevoir le texte extrait d’un PDF ou obtenu par OCR, avec la page et l’ordre de lecture lorsque ces informations existent. Réutiliser le texte issu de Vision lorsque ce parcours l’a déjà identifié. Une question sur un document absent appelle une demande ciblée pour l’ouvrir, le sélectionner ou le coller.

| Demande | Traitement | Ce que l’utilisateur entend |
| --- | --- | --- |
| « Lis ce paragraphe mot pour mot. » | Envoyer le texte source au lecteur. Conserver sa ponctuation, sa structure et son contenu. | Le passage original, y compris une répétition présente dans le document. |
| « Explique cette phrase. » | Envoyer la phrase source et le contexte immédiat au modèle. Sauvegarder le marque-page. | Une explication naturelle. Elle peut commencer par « Ici, le courrier sert à établir la date. » |
| « Résume les trois paragraphes. » | Identifier les trois paragraphes et couvrir chacun dans l’analyse. | Une synthèse proportionnée à la demande, fondée sur ces trois passages. |
| « Relis juste le début », « répète », « continue la lecture. » | Retrouver respectivement la source, la dernière unité orale ou le marque-page suspendu. | La bonne portion est relue. Une explication intercalée déplace son propre curseur. |
| « Il dit ça où exactement ? » | Retrouver dans la source le passage qui appuie la réponse et la page, si elle existe. | Une citation exacte et son emplacement disponible. Si le texte ne répond pas, Jarvis le dit en une phrase. |

Quand le document change pendant l’échange, retrouver la même phrase par identifiant stable ou par son texte et son voisinage. En cas d’ambiguïté, proposer le paragraphe identifiable le plus proche. Une seule révision de document doit servir à interpréter une plage. Pour les plages `NSRange`, tenir compte des unités UTF‑16 utilisées par les API Apple et convertir au point d’usage. Tester accents composés, apostrophes, emoji et caractères avant le passage. Une normalisation destinée à la prononciation peut changer la longueur de la chaîne. Conserver la correspondance avec l’original.

### Diction et personnalité

- **Parler pour être écouté.** Répondre à la question dès la première phrase. Proposer une idée à la fois, avec des phrases reliées. Pour « juste l’heure », « Midi. » suffit. Pour « explique-moi en détail », développer puis marquer une pause à une frontière qui a du sens. Terminer quand la demande est satisfaite.
- **Conserver le vouvoiement de Jarvis.** Le ton de référence est calme, précis et personnel. Éviter de répéter le nom de la personne, une formule d’accueil ou un compliment à chaque tour. Une correction simple reçoit une réponse simple, par exemple « Jeudi, compris. »
- **Adapter la voix à l’intention.** Une question courte, une lecture de cours et l’épellation d’un nom demandent des débits différents. Respecter d’abord la voix française et la vitesse choisies dans les réglages. « Plus lentement » pendant une lecture agit sur la suite du même passage. Un nom de logiciel ou un passage anglais conserve une prononciation intelligible dans le contexte français.
- **Préparer le texte oral.** Garder deux représentations si nécessaire, une pour l’écran et une pour l’audio. « 3,14 », « 18 h 05 », « art. 2 » et « M. Dupont » demandent une segmentation qui respecte leur sens. Lire les titres ou les listes quand ils structurent la compréhension. Pour un lien long, en lecture conversationnelle, donner son intitulé et le laisser disponible à l’écran. « Épelle-moi l’adresse » déclenche une diction littérale.
- **Démarrer tôt avec une unité stable.** Le moteur actuel peut produire la première phrase avant la fin de génération. Préserver ce gain. Affiner `JarvisSentenceStreamer` pour les abréviations, nombres décimaux, guillemets et entrées très longues. Envisager une coupure à une proposition complète si une phrase interminable retarde inutilement la voix. Recoller les fragments d’un même mot ou d’un caractère UTF‑8 avant leur émission.
- **Laisser de la place au silence.** Le code propose des formules d’attente après environ 0,9 s. Réserver une indication parlée à une attente perceptible où elle apporte une information, par exemple « Je cherche le passage. » si cette recherche est lancée. Annuler une indication devenue inutile. Un « voyons voir » dont le début a été diffusé n’entre pas dans le contenu de fond ni dans la mesure du temps de réponse utile.

**Exemple de consigne au modèle de conversation**, à adapter dans les prompts locaux et PC existants. Le modèle reçoit en complément les passages, les résultats d’outils et la question du tour.

> Vous êtes Jarvis. Parlez en français et vouvoyez la personne. Donnez d’abord la réponse à sa question, puis le détail qu’elle demande. Une relance très courte peut reprendre l’objet du tour précédent. Une correction remplace le fait concerné et conserve les autres. Pour expliquer un texte, appuyez-vous sur le passage fourni. Si deux interprétations plausibles changent la réponse, posez une question courte qui les départage. Si une action est demandée, rendez compte de son état réel.

Une consigne aide à produire de bonnes phrases. Les décisions de couper le haut-parleur, conserver le marque-page, vérifier une action et ignorer un ancien résultat appartiennent au code. Une voix naturelle demande aussi de tester le rendu en français avec la voix réellement installée sur l’appareil. [Moteur de parole de Jarvis][speech] · [Consignes de style pour la voix][prompting]

## Garder la conversation disponible pendant le travail

### Choix du moteur et fonctionnement local

| Situation | Chemin prévu |
| --- | --- |
| iPhone hors ligne, ressources françaises et modèle embarqué disponibles | Entrée locale, accès aux sources déjà sur le téléphone, explication par le modèle installé, lecture locale. Le parcours de lecture d’un texte disponible peut fonctionner même quand le modèle génératif est absent. |
| iPhone seul avec petit modèle | Pour une question sur un document, centrer le contexte sur l’extrait pertinent. Si l’information est absente, le dire. Préférer une explication courte et fidèle à une longue réponse spéculative. |
| PC appairé et choisi pour les questions ouvertes | L’iPhone garde le micro, la sortie et la position de lecture. Transmettre au PC le contenu permis et les références nécessaires. Afficher et prononcer ses résultats avec le même gestionnaire de session. |
| PC indisponible avant le début de réponse | Appliquer le repli local déjà prévu, si les ressources existent. Répondre une seule fois. Pour une demande exigeant réellement le PC, indiquer son indisponibilité. |
| PC perdu après un début de réponse | Conserver ce qui a été diffusé et signaler la coupure une fois. La reprise retrouve ce point. Une reformulation locale reste identifiable et évite de réciter le début en double. |
| Reconnaissance française locale indisponible, micro refusé ou modèle absent | Expliquer l’étape concernée. Le clavier donne accès à la même session. Rendre visibles la configuration nécessaire ou les ressources disponibles. Respecter le choix hors ligne lors du routage. |

Le catalogue iPhone du commit de référence propose Qwen2.5 1.5B et Qwen3 4B en option. Le compagnon PC déclare un modèle Qwen3 30B-A3B et un repli 8B. Il faut lire la configuration effective au lancement. Claude Code est l’outil de développement. Le choix du moteur de Jarvis appartient à l’app et au compagnon PC. Ce parcours peut être conçu avec les composants du projet, sans imposer un abonnement, une API vocale hébergée ni un PC allumé. Un modèle embarqué peut avoir besoin d’un téléchargement initial. Tester les ressources déjà installées en mode avion. [Catalogue iPhone][brain] · [Configuration PC][pc-config] · [Disponibilité locale d’Apple Speech][onsite]

Dans la branche étudiée, les commandes peuvent utiliser Apple Speech en ligne selon les capacités et les réglages. Le réveil à la voix fait l’objet d’une politique locale distincte. Pour un mode explicitement hors ligne, vérifier la disponibilité locale de `fr-FR` et demander cette reconnaissance à Speech. En cas d’indisponibilité, conserver le clavier ou un moteur local déjà disponible. Vérifier aussi les préférences des deux appareils pour la recherche Internet lorsqu’un PC est associé. Limiter les données envoyées à l’extrait utile au tour. La politique du projet exclut déjà certaines demandes, notamment de composition de messages, de l’historique général. [Reconnaissance de Jarvis][input] · [Option de reconnaissance sur l’appareil][require-local] · [Vie privée du projet][privacy]

### Correction, annulation et actions

**Exemple.** Jarvis cherche deux références pendant que l’utilisateur parle. « Attends, dis-moi d’abord ce que veut dire ce mot » ouvre une parenthèse. « En fait, cherche seulement la seconde référence » modifie la recherche. « Annule la recherche » demande son arrêt. Ces phrases peuvent toutes interrompre la voix. Le sort du travail en cours dépend de la demande.

Donner à une tâche longue une identité et une révision indépendantes de la génération de lecture. Conserver son objectif, les résultats obtenus et son état. En cas de correction, relancer seulement la partie concernée si l’outil le permet. Un ancien résultat peut terminer après le nouveau. Vérifier la révision avant de l’utiliser. Si la personne parle à ce moment-là, attendre une place appropriée pour annoncer le résultat. À « tu en es où ? », répondre avec la dernière étape réellement constatée.

Le PC utilise un flux NDJSON. Les événements `partial` y contiennent du **texte cumulé**. Remplacer le brouillon reçu et n’envoyer que le nouveau segment stable à la voix. À la fin, le `final` complète l’échange sans provoquer une seconde lecture. En cas d’annulation, annuler la tâche réseau qui appartient à cet échange si elle est accessible, libérer le flux, et vérifier l’identité du tour dans les callbacks avant lecture ou écriture. Un serveur qui finit tard doit rester sans effet sur le nouveau tour. Pour faire évoluer le protocole, commencer par des champs optionnels et conserver un essai iPhone récent / ancien serveur. [Client iPhone][pc-link] · [Serveur NDJSON][server] · [Génération en flux avec Ollama][ollama]

Une action modifiant le monde garde son propre état. L’ouverture d’un brouillon de message peut être confirmée par l’interface. L’envoi relève du parcours réel d’iOS et de ses confirmations existantes. Si la liaison se coupe après une demande d’action, conserver « résultat inconnu » jusqu’à vérification. Avant tout nouvel essai, retrouver le résultat de l’opération identifiable ou demander une précision si elle est indispensable. Une double notification de fin, une correction et une reconnexion ne doivent pas produire deux notes, deux brouillons ou deux lancements.

## Ordre de réalisation

| Lot | Modification verticale | Preuve attendue avant de décrire le lot comme opérationnel |
| --- | --- | --- |
| 1 · Mémoire de la parole | Relier `JarvisSpeechService`, `JarvisDuplexAudio`, le contrôleur et `JarvisConversationContext`. Séparer fin de génération et progression de lecture pour les questions ouvertes locales et PC. Introduire d’abord un repère fiable à la phrase. | Avec trois phrases préparées et une interruption pendant la deuxième, la troisième reste hors du préfixe oral. Un ancien callback après arrêt ne l’ajoute pas. Le mode clavier conserve la réponse affichée. |
| 2 · Lecture et référence | Brancher une note existante ou un extrait collé sur le même lecteur. Conserver source, révision, position et parenthèse explicative. Relier les demandes « lis », « explique », « répète », « reprends ». | Le scénario du courrier du 12 avril passe de bout en bout avec une explication intercalée, sur haut-parleur. Une seconde note et une seconde formulation donnent le même comportement. |
| 3 · Tours de parole français | Améliorer la fin de tour, l’acquiescement, les corrections et la comparaison d’écho à partir de la fenêtre de son réellement jouée. Préserver le pré-enregistrement et la relance après changement de configuration. | Comparer, sur les mêmes phrases, les coupures prématurées, les débuts perdus et les arrêts dus à l’écho. Vérifier aussi une interruption très tôt dans la première phrase. |
| 4 · Conversation générale et alternance clavier/voix | Conserver l’identité de session, transmettre les références actives et les corrections aux deux moteurs. Apprendre à sélectionner le bon contexte lorsque les anciens tours sortent de la fenêtre. | Réussir la comparaison des sorties avec de nouvelles valeurs, changer de sujet puis y revenir, et passer du clavier à la voix dans le même échange. |
| 5 · Travail de fond et rendu naturel | Versionner les travaux, annuler ou réviser proprement les requêtes PC et améliorer la diction sur les cas observés. Ajuster les indications d’attente et les frontières de phrases en français. | Une correction l’emporte sur un résultat tardif. La même action se produit une fois. Une abréviation, un horaire et un terme anglais se comprennent à l’oreille. |

**Approche de code.** Commencer par la plus petite modification observable dans le parcours normal de l’app. Étendre les composants existants et extraire un type de suivi de lecture si plusieurs parcours partagent réellement son état. Les profils vocaux, la veille, les claps, les notes et la connexion PC ont déjà leurs propres comportements. Les exercer dans leurs points d’entrée habituels à chaque lot qui les touche. Si la branche de travail a déjà résolu un défaut, conserver l’amélioration et passer à la première preuve encore manquante.

## Dialogues de recette

Les essais ci-dessous utilisent des données fictives. Faire varier au moins une formulation et une donnée de chaque scénario concerné. Observer le son produit, le texte affiché, le contexte du tour suivant et, pour une action, l’état réel de l’app. Les tests du routeur seuls laissent passer des erreurs audibles ou des doubles exécutions.

| Nº | Situation à rejouer | Résultat observable |
| --- | --- | --- |
| 01 | « Jarvis, ouvre les notes » d’une traite, puis « et ma dernière ? » | Le premier mot utile est capté. La relance désigne la dernière note accessible. |
| 02 | « Je voudrais que… [pause d’environ une seconde] tu m’expliques ce mot. » | Jarvis attend, récupère la fin et effectue une seule demande. |
| 03 | « Note qu’on se voit jeudi… enfin vendredi. » | Une note correspond au sens final. Contrôler son contenu et le nombre de créations. |
| 04 | Décrire le musée et la balade, changer le temps disponible, puis dire « juste la plus courte » | Les durées restent attachées aux activités. La dernière contrainte gouverne la réponse. |
| 05 | Donner trois options dans un ordre inhabituel. « Compare la troisième à la première », puis « inverse-les ». | Les mêmes objets sont repris dans le nouvel ordre. La comparaison garde le critère choisi. |
| 06 | Interrompre une explication avec « attends » dès son début, puis laisser une courte pause avant la correction | La voix cède la place, la correction est entendue entièrement et l’ancienne réponse reste arrêtée. |
| 07 | Faire deux fois une courte marque d’écoute pendant un récit, puis dire « oui » après une question fermée | Le récit peut continuer dans le premier cas. « Oui » répond à la question dans le second. |
| 08 | Laisser Jarvis parler au haut-parleur, faire un bruit bref, puis poser une question en répétant un de ses mots | Son propre écho et le bruit ne valident aucun tour. La vraie question est traitée. |
| 09 | Rejouer le passage du courrier du 12 avril et interrompre dans la deuxième phrase | Jarvis identifie le courrier, explique sa fonction et reprend la bonne phrase. |
| 10 | Mettre en file trois phrases, interrompre avant le premier son, puis pendant la deuxième dans un nouvel essai | Le premier préfixe oral est vide. Le second se termine à la position fiable de la deuxième phrase. |
| 11 | « Où est écrit le montant exact ? » dans le passage fictif | Jarvis constate que le nombre manque. Il peut citer la phrase sur la facture. |
| 12 | Sélectionner à l’écran un paragraphe encore muet, puis demander « Explique ce passage ». Ensuite « qu’est-ce que tu venais de lire ? » | La sélection sert à la première demande. La seconde utilise l’historique oral correspondant au contexte et distingue lecture du document et explication. |
| 13 | « Lis “M. Dupont arrive à 18 h 05. Le total est de 3,14 €.” », puis « redis juste l’heure plus lentement ». | Les abréviations et nombres sont intelligibles, la valeur reste exacte et le débit change comme demandé. |
| 14 | Dicter une note de plus de 30 s avec une correction à la fin | Un seul texte complet conserve la correction finale. Vérifier la jonction réelle des segments. |
| 15 | Poser une question à voix haute, envoyer une précision au clavier pendant la réponse, puis reprendre au micro | Un seul fil contient les trois demandes. La réponse dépassée ne reprend pas. Le choix de silence ou de réarmement reste respecté. |
| 16 | Après plusieurs autres échanges, demander « reviens à la première sortie dont on parlait » | L’objet est retrouvé grâce au rappel utile. En cas de référence perdue, une question précise permet de repartir sans inventer le nom. |
| 17 | Demander « Que veut dire la phrase “envoie ce message” ? », puis demander réellement de préparer un brouillon de test | L’explication reste verbale. La deuxième demande ouvre un seul brouillon avec les confirmations ordinaires de l’app. |
| 18 | Lancer une recherche lente, dire « seulement la seconde référence », et livrer artificiellement l’ancien résultat en dernier | Le résultat périmé ne parle pas et ne remplace pas la nouvelle conclusion. Une demande d’état rend compte du vrai travail en cours. |
| 19 | PC appairé mais éteint avant la demande, puis, dans un autre essai, coupure après la première phrase du PC | Le premier essai utilise le repli disponible. Le second garde la progression et signale la coupure sans reprise en double. |
| 20 | Passer du haut-parleur aux écouteurs au milieu d’une lecture, puis provoquer une interruption système | Le micro et le lecteur retrouvent un état utilisable. « Reprends » retrouve la source. Écouter la première phrase après le changement de route. |
| 21 | Répéter le parcours clé PC éteint et iPhone en mode avion, puis désactiver la voix et refaire au clavier | Les capacités installées fonctionnent localement. Une capacité manquante est nommée avec précision. La réponse écrite reste consultable. |
| 22 | Demander « À quoi sert cette option ? » après sélection dans Jarvis, puis « Et ce que je viens de déplacer ? » après un geste dans la scène | L’option et l’objet sont ancrés dans deux événements distincts. Les réponses décrivent les événements réellement disponibles. |
| 23 | Faire relire une note après modification, puis solliciter une phrase identique présente deux fois | Le repère se rattache à la bonne révision et à la bonne occurrence, ou Jarvis demande le paragraphe voulu. |
| 24 | Énoncer un texte qui contient une adresse, le nom anglais d’un logiciel et une citation. Demander ensuite uniquement l’orthographe du nom. | Le changement de langue n’altère pas le reste de la phrase. Jarvis épelle la bonne entité et garde la référence pour la relance. |

### Comment automatiser les régressions précises

- Étendre `JarvisConversationFlowTests` avec les faux positifs d’écho, les acquiescements et les transcriptions partielles qui évoluent. Simuler un temps monotone pour rejouer les mêmes pauses.
- Étendre `JarvisLocalBrainTests` et les tests du contexte avec un lecteur pilotable. Faire arriver génération, lecture, interruption et callbacks de fin dans plusieurs ordres. Vérifier le texte connu du tour suivant, pas seulement l’apparence de l’écran.
- Étendre `JarvisPCLinkTests` et `pc/tests/test_jarvis_pc.py` pour les `partial` cumulés, la fin tardive, les requêtes concurrentes et le repli avant/après la première phrase. Tester les révisions avec deux réponses que l’on peut faire terminer dans l’ordre inverse.
- Vérifier le parcours depuis la saisie vocale, le clavier et l’ouverture d’une note à l’écran. Un même test de haut niveau peut utiliser un moteur de génération déterministe et une sortie audio simulée pour détecter les régressions de logique. Le verdict sur l’écho, la latence perçue et la prosodie appartient au test physique.
- Depuis la racine, les entrées Python utiles sont `python tests/run_all_tests.py` et `python -m pytest pc/tests`. Pour les XCTest, utiliser le schéma `JarvisXR` et la cible `JarvisXRTests` du projet XcodeGen, sur un simulateur installé, puis faire les essais acoustiques sur l’iPhone. Les instructions de compilation et le workflow correspondent à la branche de travail. [Tests Swift][tests-flow] · [Tests du modèle][tests-brain] · [Tests PC][tests-pc] · [Construction iOS][build]

## Mesurer l’aisance en conditions réelles

Lancer une première série avec la version installée et conserver son identifiant de build. Répéter la même série après chaque modification qui touche l’audio ou le contexte. Pour comparer les délais, noter modèle d’iPhone, version iOS, route audio, voix française choisie, réglages de parole, modèle local ou PC, réseau et démarrage à froid ou à chaud. Une mesure en pièce calme et une en présence de bruit ordinaire sont plus instructives qu’une seule moyenne globale.

| Mesure | Début et fin | Ce qu’elle permet de décider |
| --- | --- | --- |
| Temps avant la première réponse utile | Fin réelle de la demande → premier son porteur de la réponse | Inclut l’attente de fin de tour. Exclure les formules de remplissage du point d’arrivée. |
| Coût de la fin de tour | Fin réelle de la parole → validation par le contrôleur | Montrer si une grande part de l’attente provient de la décision d’écouter plus longtemps. Compter également les départs trop précoces. |
| Temps de calcul et de mise en voix | Validation → première unité textuelle stable → premier son utile | Distinguer le délai du modèle de celui du découpage et de l’audio. Un premier token peut arriver bien avant une première phrase prononçable. |
| Réactivité à l’interruption | Début de l’intervention → baisse audible, puis → arrêt audible | Juger les deux délais séparément. Une coupure rapide avec la première syllabe de la correction perdue reste un échec. |
| Continuité du son | Intervalles entre segments d’une réponse et ruptures audibles involontaires | Distinguer pause linguistique, file vide et changement de route. Écouter aussi les liaisons et les noms. |
| Qualité des échanges | Nombre de références correctes, demandes à répéter, interruptions ratées et faux arrêts sur un ensemble documenté | Comparer les mêmes formulations et conserver celles qui mettent les règles en défaut. |
| Exactitude du marque-page | Position attendue au moment de l’arrêt et position retenue | Indiquer le niveau vérifié, phrase ou mot. Noter chaque répétition complète et chaque saut de contenu. |

**Repères de mise au point proposés.** Sur une commande locale courte et à chaud, viser d’abord une médiane de fin réelle de phrase au premier son utile d’environ 1,5 s ou moins. Pendant une réponse déjà établie, viser une baisse audible dans les 0,5 s qui suivent le début d’une vraie interruption. Ce sont des ambitions produit à ajuster d’après les mesures sur l’iPhone. Mesurer séparément le délai jusqu’à l’arrêt confirmé, les réponses du grand modèle, les démarrages à froid et le Bluetooth. Sur une série répétée, publier effectif, médiane et 95e percentile avec leurs conditions. Pour une petite série, donner aussi les valeurs brutes ou l’étendue. Une amélioration de vitesse accompagnée de davantage de phrases coupées appelle un nouvel ajustement.

Utiliser une horloge monotone et des événements locaux horodatés pour la décision de fin de tour, la première unité du modèle, l’entrée en lecture et l’arrêt. Les rappels logiciels donnent des approximations de la sortie physique. Pour la fin réelle de parole ou le premier son réellement audible, utiliser une observation indépendante, par exemple un essai volontaire avec des phrases fictives enregistrées localement puis chronométrées. Un mode de diagnostic peut ne conserver que des durées, codes de route, états et identifiants éphémères. Le texte des conversations, les sons ambiants et les notes personnelles restent en dehors des journaux de performance ordinaires.

### Comparer directement avec ChatGPT

Sur le même iPhone, faire une séance de cinq minutes avec chaque assistant. Dans chaque séance, réunir une hésitation, un « attends », une correction, une question implicite, un changement de sujet et une reprise de lecture. Utiliser le même passage et les mêmes informations initiales. Alterner l’ordre des assistants au prochain essai. Noter séparément la compréhension, la prise de parole et la qualité de la voix.

Donner un point à chaque réussite observée sur le scénario du courrier (arrêt, identification du courrier, explication liée au texte, reprise au bon endroit). Compter aussi le nombre de fois où l’utilisateur a dû répéter l’énoncé ou redonner le contexte. Enfin, lui faire décrire **le premier endroit précis où il a senti qu’il devait adapter sa façon de parler à Jarvis**. Ce retour localise souvent mieux la prochaine modification qu’une note générale sur dix. Chaque bilan distingue les tests de logique réussis, les essais entendus sur l’iPhone et les cas encore à exercer. [Évaluation des conversations vocales continues][evaluation]

## Message de démarrage pour Claude Code

> Lis ce guide et les versions effectives des composants sur ma branche JarvisXR. Mon objectif est une conversation française facile à interrompre, qui garde le sujet et la bonne position de lecture, y compris PC éteint. Commence par reproduire le défaut du premier lot avec une réponse de trois phrases. Suis son trajet jusqu’au haut-parleur et au contexte du prochain tour. Implémente la première amélioration encore manquante dans le parcours normal de l’app. Vérifie le cas normal, l’interruption, un ancien callback et la saisie au clavier. Poursuis dans l’ordre des lots. Pour chaque résultat, indique le commit, les essais réalisés et ce qu’il reste à écouter sur iPhone.

Pour lire ce document depuis une branche qui ne contient pas encore le commit documentaire, ces commandes récupèrent la référence et affichent le fichier sans changer la branche de travail.

~~~sh
git fetch origin develop
git show FETCH_HEAD:docs/CONVERSATION_NATURELLE.md
~~~

[pr31]: https://github.com/Test-IA-trading/JarvisXR-2/pull/31
[code]: https://github.com/Test-IA-trading/JarvisXR-2/tree/a66393334a2d788b1645db0a70e632ca2d1bb5c7
[input]: https://github.com/Test-IA-trading/JarvisXR-2/blob/a66393334a2d788b1645db0a70e632ca2d1bb5c7/ios/JarvisXR/JarvisXR/JarvisVoiceInputService.swift
[duplex]: https://github.com/Test-IA-trading/JarvisXR-2/blob/a66393334a2d788b1645db0a70e632ca2d1bb5c7/ios/JarvisXR/JarvisXR/JarvisDuplexAudio.swift
[flow]: https://github.com/Test-IA-trading/JarvisXR-2/blob/a66393334a2d788b1645db0a70e632ca2d1bb5c7/ios/JarvisXR/JarvisXR/JarvisConversationFlow.swift
[controller]: https://github.com/Test-IA-trading/JarvisXR-2/blob/a66393334a2d788b1645db0a70e632ca2d1bb5c7/ios/JarvisXR/JarvisXR/JarvisRootViewController.swift
[speech]: https://github.com/Test-IA-trading/JarvisXR-2/blob/a66393334a2d788b1645db0a70e632ca2d1bb5c7/ios/JarvisXR/JarvisXR/JarvisSpeechService.swift
[brain]: https://github.com/Test-IA-trading/JarvisXR-2/blob/a66393334a2d788b1645db0a70e632ca2d1bb5c7/ios/JarvisXR/JarvisXR/JarvisLocalBrain.swift
[context]: https://github.com/Test-IA-trading/JarvisXR-2/blob/a66393334a2d788b1645db0a70e632ca2d1bb5c7/ios/JarvisXR/JarvisXR/JarvisConversationContext.swift
[phrasing]: https://github.com/Test-IA-trading/JarvisXR-2/blob/a66393334a2d788b1645db0a70e632ca2d1bb5c7/ios/JarvisXR/JarvisXR/JarvisPhrasing.swift
[french]: https://github.com/Test-IA-trading/JarvisXR-2/blob/a66393334a2d788b1645db0a70e632ca2d1bb5c7/ios/JarvisXR/JarvisXR/JarvisFrenchCommands.swift
[pc-link]: https://github.com/Test-IA-trading/JarvisXR-2/blob/a66393334a2d788b1645db0a70e632ca2d1bb5c7/ios/JarvisXR/JarvisXR/JarvisPCLink.swift
[server]: https://github.com/Test-IA-trading/JarvisXR-2/blob/a66393334a2d788b1645db0a70e632ca2d1bb5c7/pc/jarvis_pc/server.py
[screen]: https://github.com/Test-IA-trading/JarvisXR-2/blob/a66393334a2d788b1645db0a70e632ca2d1bb5c7/ios/JarvisXR/JarvisXR/JarvisScreenContext.swift
[memory]: https://github.com/Test-IA-trading/JarvisXR-2/blob/a66393334a2d788b1645db0a70e632ca2d1bb5c7/ios/JarvisXR/JarvisXR/JarvisMemoryStore.swift
[prompt-local]: https://github.com/Test-IA-trading/JarvisXR-2/blob/a66393334a2d788b1645db0a70e632ca2d1bb5c7/ios/JarvisXR/JarvisXR/JarvisLocalBrain.swift#L133
[record-local]: https://github.com/Test-IA-trading/JarvisXR-2/blob/a66393334a2d788b1645db0a70e632ca2d1bb5c7/ios/JarvisXR/JarvisXR/JarvisLocalBrain.swift#L635
[record-pc]: https://github.com/Test-IA-trading/JarvisXR-2/blob/a66393334a2d788b1645db0a70e632ca2d1bb5c7/ios/JarvisXR/JarvisXR/JarvisLocalBrain.swift#L593
[interrupt]: https://github.com/Test-IA-trading/JarvisXR-2/blob/a66393334a2d788b1645db0a70e632ca2d1bb5c7/ios/JarvisXR/JarvisXR/JarvisRootViewController.swift#L764
[render]: https://github.com/Test-IA-trading/JarvisXR-2/blob/a66393334a2d788b1645db0a70e632ca2d1bb5c7/ios/JarvisXR/JarvisXR/JarvisSpeechService.swift#L367
[played]: https://github.com/Test-IA-trading/JarvisXR-2/blob/a66393334a2d788b1645db0a70e632ca2d1bb5c7/ios/JarvisXR/JarvisXR/JarvisDuplexAudio.swift#L169
[pc-config]: https://github.com/Test-IA-trading/JarvisXR-2/blob/a66393334a2d788b1645db0a70e632ca2d1bb5c7/pc/jarvis_pc/config.py
[privacy]: https://github.com/Test-IA-trading/JarvisXR-2/blob/a66393334a2d788b1645db0a70e632ca2d1bb5c7/PRIVACY.md
[tests-flow]: https://github.com/Test-IA-trading/JarvisXR-2/blob/a66393334a2d788b1645db0a70e632ca2d1bb5c7/ios/JarvisXR/JarvisXRTests/JarvisConversationFlowTests.swift
[tests-brain]: https://github.com/Test-IA-trading/JarvisXR-2/blob/a66393334a2d788b1645db0a70e632ca2d1bb5c7/ios/JarvisXR/JarvisXRTests/JarvisLocalBrainTests.swift
[tests-pc]: https://github.com/Test-IA-trading/JarvisXR-2/blob/a66393334a2d788b1645db0a70e632ca2d1bb5c7/pc/tests/test_jarvis_pc.py
[build]: https://github.com/Test-IA-trading/JarvisXR-2/blob/a66393334a2d788b1645db0a70e632ca2d1bb5c7/docs/BUILDING.md
[live]: https://openai.com/fr-FR/index/introducing-gpt-live/
[agents]: https://developers.openai.com/api/docs/guides/voice-agents
[prompting]: https://developers.openai.com/api/docs/guides/live-prompting
[vad]: https://developers.openai.com/api/docs/guides/realtime-vad
[evaluation]: https://developers.openai.com/cookbook/examples/audio/voice_agent_evaluation
[ollama]: https://docs.ollama.com/capabilities/streaming
[route]: https://developer.apple.com/documentation/avfaudio/responding-to-audio-route-changes
[played-apple]: https://developer.apple.com/documentation/avfaudio/avaudioplayernodecompletioncallbacktype/dataplayedback
[markers]: https://developer.apple.com/documentation/avfaudio/avspeechsynthesismarker
[will-speak]: https://developer.apple.com/documentation/avfaudio/avspeechsynthesizerdelegate/speechsynthesizer%28_%3Awillspeakrangeofspeechstring%3Autterance%3A%29
[onsite]: https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition
[require-local]: https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition
