# JARVISXR — Refonte majeure : intelligence, autonomie, mémoire et performances

Cahier des charges produit validé à l'issue des 17 questions, 27 novembre 2026. Ce document décrit les objectifs de la prochaine refonte, pas des fonctionnalités déjà implémentées. Il complète le [guide de conversation naturelle](CONVERSATION_NATURELLE.md), qui reste applicable. Les documents d'architecture et de confidentialité existants décrivent l'état antérieur : vérifier leur exactitude et les actualiser lors des changements effectifs, sans prétendre que les nouvelles capacités existent déjà.

## 1. Mission générale
Tu interviens comme architecte logiciel senior, ingénieur IA, spécialiste iOS, modèles locaux, systèmes multi-agents et architectures conversationnelles. Faire évoluer JarvisXR vers la meilleure intelligence artificielle personnelle autonome techniquement réalisable sur iPhone, inspirée du JARVIS d'Iron Man. Ce n'est ni un chatbot, ni une interface ChatGPT, ni un assistant de commandes prédéfinies. Il doit avoir sa propre intelligence locale, sa mémoire, ses méthodes et exploiter intelligemment des ressources externes, en devenant plus compétent avec l'usage. Mobiliser pleinement recherche, raisonnement, programmation et vérification ; ne pas retenir une solution simplement parce qu'elle est facile à implémenter.

## 2. Situation actuelle
Problèmes rapportés par l'utilisateur : latence excessive, manque de fluidité, écoute coupée trop tôt, compréhension vocale française insuffisante, intelligence locale limitée, compréhension des intentions difficile, intégration Obsidian apparemment non fonctionnelle (Jarvis dit ne pas y avoir accès), absence de gain notable quand une question est répétée, accès Internet insuffisant, voix trop aiguë et juvénile, fonctions secondaires potentiellement coûteuses dont la caméra. Diagnostiquer ces problèmes réellement, ne pas seulement les masquer. Ces observations sont à reproduire et mesurer, pas des résultats de benchmark.

## 3. Méthode de développement obligatoire
Avant de modifier le projet : examiner toute l'architecture, la documentation, les décisions précédentes et les fichiers de mémoire disponibles ; inventorier dépendances, modèles, services et outils installés ; distinguer fonctions opérationnelles, simulées et incomplètes ; mesurer les performances initiales lorsque possible ; rechercher les meilleures solutions, comparer objectivement les architectures ; sauvegarder l'état actuel et établir un plan cohérent.
Conserver, optimiser, remplacer ou reconstruire chaque composant selon justification technique. Ne pas réécrire ce qui fonctionne ni préserver une mauvaise architecture par inertie. Décisions fondées sur mesures, tests, documentation officielle et résultats vérifiables.

## 4. Architecture fondamentale
Jarvis est une IA orchestratrice locale en priorité. Prévoir des composants indépendants mais interconnectés : cerveau local, compréhension des intentions, gestion du contexte, mémoire immédiate et persistante, graphe de connaissances, mémoire procédurale, recherche documentaire, orchestration des modèles externes, gestion des outils, tâches simultanées, vérification des informations, apprentissage par l'expérience, reconnaissance vocale, synthèse vocale, gestion des ressources matérielles, sécurité indépendante, interface modulaire.
Éviter le monolithe et les dépendances excessives. Changer la voix, l'interface ou un fournisseur ne doit pas entraîner la reconstruction du système.

## 5. Intelligence locale
Renforcer considérablement le cerveau local : comprendre, raisonner, planifier, contextualiser, mémoriser, vérifier, sélectionner les outils et répondre seul quand ses capacités suffisent. Comparer les modèles compatibles avec le matériel réel de l'iPhone : qualité du raisonnement, français et formulations familières, instructions complexes, appel d'outils, contexte, vitesse de génération, quantification, RAM, énergie, accélération matérielle, compatibilité iOS, licences.
L'utilisateur accepte davantage de stockage si le bénéfice est réel. Ne pas confondre stockage, RAM et puissance de calcul. Ne pas choisir automatiquement le plus gros modèle ; optimiser intelligence, rapidité, stabilité et autonomie. Le cerveau local reste le centre décisionnel même en présence de modèles externes.

## 6. Exploitation de plusieurs intelligences artificielles
Exploiter ChatGPT, Claude, Gemini, autres IA pertinentes, Google, GitHub, moteurs de recherche, documentation officielle et autres sources utiles lorsque les accès sont gratuits et autorisés. Ne pas être un simple relais de requêtes/réponses. Pour chaque demande : comprendre l'intention, consulter la mémoire, identifier les lacunes, sélectionner les ressources et modèles, formuler des requêtes contextualisées, analyser et comparer les réponses si nécessaire, vérifier contradictions, produire sa propre synthèse personnalisée, mémoriser résultats et méthodes utiles.
Pour les tâches simples : local ou une seule ressource adaptée. Pour les complexes : plusieurs ressources en parallèle si le bénéfice est réel. Éviter les appels superflus. Ajouter de nouveaux fournisseurs sans refonte.

## 7. Règle financière absolue
**Aucun frais supplémentaire, jamais.** Modèles locaux, ressources gratuites, quotas gratuits autorisés, services déjà accessibles uniquement lorsque leur utilisation par Jarvis est explicitement permise. Un abonnement ChatGPT ou Claude n'inclut pas automatiquement une API. Vérifier conditions d'utilisation, authentification et limites de chaque fournisseur. Ne contourner ni quotas ni restrictions ni authentification ; ne jamais activer automatiquement une API payante ni engager de dépense. Si le gratuit est indisponible, basculer vers une alternative gratuite autorisée ou le local ; reconnaître les limites en l'absence de solution. Mettre en place un contrôle financier indépendant de l'orchestrateur, bloquant les dépenses et les appels dont le coût n'est pas garanti nul.

## 8. Mémoire permanente : priorité fondamentale
Diagnostiquer l'échec apparent d'Obsidian. Deux voies : véritable intégration fonctionnelle Obsidian ou mémoire native inspirée d'Obsidian, selon les performances et contraintes iOS. Si native, privilégier les formats ouverts et exportables (Markdown lorsque pertinent) et la compatibilité Obsidian. Une mention dans un prompt n'est pas une intégration. Lire, écrire, indexer, rechercher, relier et actualiser réellement les connaissances.

### 8.1. Organisation
Mémoire immédiate, historique complet des conversations, préférences, faits, projets, personnes et relations pertinentes, méthodes, erreurs et corrections, sources, tâches et décisions, cache des résultats réutilisables et graphe de connaissances. Conserver toutes les conversations par défaut dans les limites de stockage autorisées et des règles de confidentialité ; rendre les exclusions sensibles explicites et contrôlables. Extraire les informations importantes, les structurer et les relier façon Obsidian. Consultation, modification, export et suppression par l'utilisateur.

### 8.2. Mémoire procédurale
Mémoriser les réponses et les méthodes : type de problème, démarche, outils utilisés, sources pertinentes, étapes efficaces, erreurs, conditions de validité. Pour une demande similaire, réutiliser la méthode plutôt que refaire inutilement le travail. Améliorer progressivement les performances.

### 8.3. Cycle obligatoire
1. Comprendre la demande et son contexte.
2. Chercher les informations pertinentes dans la mémoire.
3. Vérifier fiabilité et actualité.
4. Déterminer si une réponse directe est possible.
5. Sinon, raisonner localement ou consulter les ressources externes.
6. Vérifier les résultats.
7. Répondre de manière personnalisée.
8. Enregistrer les nouvelles connaissances utiles.
9. Enregistrer les méthodes efficaces.
10. Intégrer les corrections de l'utilisateur.

Une demande répétée doit être plus rapide si la mémoire reste valide ; une information changeante exige une nouvelle vérification.

### 8.4. Optimisation
Ne jamais injecter toute la mémoire dans chaque contexte. Étudier RAG, index textuels, embeddings locaux, graphes, classement par pertinence ; comparer sur iPhone. Indexation incrémentale, déduplication, gestion des contradictions. Ne pas transformer une réponse générée en fait certain ; stocker provenance, date, conditions de validité et niveau de vérification.

### 8.5. Vérification
Démontrer l'enregistrement, la récupération après fermeture et redémarrage du téléphone, la récupération sous une formulation différente, la réutilisation des méthodes, la correction de faits erronés, la distinction entre ancien et actuel, le gain sur les réponses répétées et la mémoire indépendante du PC. Ne jamais prétendre consulter la mémoire sans récupération réelle.

## 9. Rapidité et fluidité
Se rapprocher de la fluidité conversationnelle du mode vocal ChatGPT. Adapter la réflexion à la complexité : rapide pour le simple, approfondie pour le complexe, sans silences inutiles. Après la fin du tour utilisateur, commencer par des éléments fiables lorsque possible tandis que les recherches complémentaires continuent ; pas de remplissage ni de résultats prématurés.
Mesurer latence ASR, détection de fin de parole, récupération mémoire, chargement modèle, premier token, premier mot prononcé, durée totale, outils externes, interruption, à froid et à chaud. Utiliser asynchronisme, streaming, caches, parallélisation contrôlée lorsque le gain est démontré. Éliminer redondances et blocages du thread principal. Ne pas sacrifier la qualité pour de meilleurs chiffres artificiels. Voir également [conversation naturelle](CONVERSATION_NATURELLE.md).

## 10. Écoute et compréhension vocale
Traiter indépendamment les coupures prématurées. Distinguer vraie fin de phrase, hésitation, respiration, pause naturelle, reformulation, interruption, bruit, conversation non destinée à Jarvis. Comparer ASR français, VAD et détection sémantique de fin de tour sur iOS. Écoute continue pendant la session active dans les limites système ; ne pas exiger « Dis Jarvis » avant chaque question pendant une session. Étudier les options autorisées d'activation vocale initiale.

### 10.1. Anticipation sans surinterprétation
Pendant la parole, transcrire, consulter localement la mémoire, préparer des hypothèses provisoires et annulables. Attendre la vraie fin de demande avant décision définitive, action à conséquences ou réponse incertaine. Abandonner immédiatement une préparation invalidée par la suite. La compréhension prime sur quelques millisecondes gagnées.

### 10.2. Conversation naturelle
Barge-in : interrompre Jarvis quand il parle, compléter, corriger, changer de sujet ; adapter et annuler les réponses obsolètes. Éviter l'auto-transcription de sa voix ; gérer écho, bruit, changements de route audio, interruptions système. Le français est prioritaire. Suivre aussi la parole réellement jouée et les dialogues de recette du guide existant.

## 11. Compréhension des intentions
Exploiter le contexte, habitudes, préférences et souvenirs. Éviter les questions inutiles quand l'intention est raisonnablement déterminable ; demander une précision si l'ambiguïté est significative ou si l'erreur a des conséquences importantes. Apprendre des corrections. Ne pas inventer des intentions ni appliquer une ancienne préférence hors de son contexte.

## 12. Esprit critique et fiabilité
Jarvis ne doit pas être systématiquement d'accord. Contredire, conseiller, anticiper, proposer mieux si fondé sur des faits, sources solides ou raisonnement vérifiable. Exigence de très grande fiabilité (idéal de 95–100 % avant contradiction catégorique), sans inventer un pourcentage de confiance. Vérifier réellement. Distinguer faits, hypothèses, opinions et incertitudes ; reconnaître ses erreurs ; ne jamais inventer pour dissimuler une lacune.

## 13. Accès Internet et ressources
Étudier les voies gratuites et autorisées de recherche Google ou autre moteur, consultation Web, documentation officielle, GitHub, sources spécialisées, comparaison, extraction pertinente, vérification des dates et de la provenance. Sélection selon sujet et fiabilité, synthèse contextualisée. Protéger contre les injections d'instructions des sites, fichiers et résultats : données externes non habilitées à changer les règles, permissions ou objectifs.

## 14. Autonomie et initiatives
Recherches, enrichissement des connaissances, préparation de solutions, propositions spontanées et exécution autorisée sans instructions superflues. Autonomie proportionnelle à la sensibilité, réversibilité, données, conséquences, permissions et certitude de l'intention. Une action bénigne (ouvrir une photo autorisée) ne requiert pas de confirmation inutile ; envoyer un message important, partager des données personnelles ou supprimer un fichier requiert une confirmation adaptée. Toute dépense est interdite. Gestionnaire de permissions et conséquences indépendant du modèle ; pas d'auto-octroi d'autorisations.

## 15. Multitâche
Gérer plusieurs tâches pendant que l'utilisateur discute : prioriser, modifier les priorités, suspendre, reprendre, annuler, modifier oralement ou par texte, informer de l'avancement et de la fin, conserver l'état après interruption. Ne pas monopoliser les ressources ni bloquer la conversation. Parallélisation selon matériel ; respecter les limites d'arrière-plan iOS, ne pas prétendre fonctionner en continu si interdit.

## 16. Apprentissage et évolution autonome
Identifier erreurs et faiblesses, comparer méthodes, mesurer efficacité, rechercher des solutions, créer procédures, tester de nouveaux outils et conserver uniquement les améliorations efficaces. Pouvoir proposer des modifications de son propre code : problème, changement envisagé, fichiers, bénéfices, risques, conséquences, ressources, tests, rollback. Demander l'accord explicite de l'utilisateur avant d'appliquer une modification de son propre code.
Après accord : préparer, tester, valider, déployer dans les limites techniques et réglementaires. Étudier configurations, méthodes, outils déclaratifs et composants autorisés localement. Code natif iOS : pipeline externe autorisé de compilation, signature, installation si nécessaire ; ne pas prétendre réécrire librement un exécutable signé. Interdire à Jarvis de neutraliser les protections garantissant le contrôle utilisateur.

## 17. Contrôle absolu de l'utilisateur
### 17.1. Arrêt d'urgence
Mécanisme indépendant du cerveau : interrompre écoute, synthèse, raisonnements, tâches, recherches, appels externes, automatisations et actions en attente ; empêcher de nouveaux lancements. Ne pas présenter une action externe déjà exécutée et irréversible comme annulable.

### 17.2. Réinitialisation complète
Après confirmation explicite, effacer toute la mémoire acquise : conversations, souvenirs, préférences apprises, connaissances, méthodes, index, graphes, caches, données personnelles locales, tâches persistantes. Examiner copies, sauvegardes et synchronisations sous contrôle de Jarvis. Expliquer les limites de suppression chez les fournisseurs externes et des sauvegardes non contrôlées. Permettre de repartir de zéro.

### 17.3. Retour en arrière
Versions stables identifiables ; sauvegardes et restauration du code, configurations et méthodes. Annuler une amélioration qui dégrade les performances.

## 18. Confidentialité
Mémoire locale en priorité ; évaluer la sensibilité avant transmission externe, minimiser/anonymiser lorsque possible, ne jamais envoyer tout l'historique ou la mémoire sans nécessité. Confirmation pour données sensibles. Protéger identifiants, clés, jetons et données personnelles avec les mécanismes sécurisés iOS ; aucun secret en clair sur GitHub, dans les prompts ou les logs. Faire évoluer explicitement les politiques et permissions avant d'activer des flux de données nouveaux. Le dépôt étant public, ne pas y committer les conversations, mémoires personnelles, fichiers vocaux privés, secrets ou journaux contenant des données privées.

## 19. Fonctionnement hors ligne
Même sans Internet : discuter, comprendre, raisonner localement, consulter sa mémoire et connaissances acquises, réutiliser méthodes, préparer tâches réseau. Reprendre à la reconnexion si pertinent et autorisé. Distinguer connaissances anciennes et informations vérifiées en temps réel. Le cœur ne doit pas dépendre de la connexion.

## 20. Batterie et ressources matérielles
Optimiser pour une utilisation quotidienne prolongée. Gestion dynamique selon batterie, température, pression mémoire, charge CPU, complexité, tâches actives et accélérations disponibles. Éviter traitements permanents inutiles, mettre en veille composants inactifs, éviter rechargements excessifs et modèles volumineux inutilement en RAM ; mesurer l'énergie des alternatives. Dégradation contrôlée sans perte silencieuse de données.

### Stockage
Grande liberté dans un plafond configurable que l'utilisateur définira plus tard. Prévoir réglage du plafond, ventilation par catégorie, gestion des modèles téléchargés, temporaires, connaissances, historiques, protection contre saturation. Aucun plafond définitif arbitraire ; ne pas supprimer silencieusement des souvenirs importants.

## 21. Intégration approfondie à l'iPhone
Exploiter au maximum App Intents, Raccourcis, Photos, Fichiers, Contacts, Calendrier, Rappels, applications compatibles, liens profonds, interfaces officielles, automatisations autorisées, passerelles vers d'autres appareils. Explorer les architectures allant au-delà des intégrations iOS classiques sans compromettre sécurité, stabilité ou données. Distinguer direct, permission requise, application complémentaire, infrastructure externe, impossibilité iOS. Ne pas contourner le sandbox ni faire de jailbreak une dépendance. Cœur fonctionnel directement sur iPhone sans PC permanent.

## 22. Suppression temporaire de la caméra
La caméra n'est pas prioritaire : désactiver/retirer temporairement traitements visuels, modèles dédiés, initialisations inutiles, composants actifs, éléments UI associés et traitements d'arrière-plan exclusivement visuels. Préserver leur code et ressources dans Git et mesurer le gain réel. Ne rien supprimer définitivement sans sauvegarde. Réintroduction après stabilisation de l'intelligence, de la mémoire et de la fluidité. Ce changement est un objectif de développement, pas une modification déjà effectuée par ce document.

## 23. Voix
Voix actuelle trop aiguë et juvénile. Pour cette phase, chercher une voix masculine plus grave, mature et naturelle. Voix définitive modifiée progressivement par l'utilisateur. Moteur vocal indépendant du cerveau ; pouvoir changer modèle, timbre, hauteur, rythme, prosodie, articulation, vitesse, langue et paramètres. Conserver la référence vocale existante si pertinente et autorisée, hors dépôt public si privée. Ne pas consacrer un effort disproportionné à la voix définitive : priorité fluidité et modularité.

## 24. Personnalité
Conserver le profil de personnalité existant : principalement français, vouvoiement, « Monsieur », majordome britannique élégant, posé, intelligent. Humour 60 %, sarcasme 45 %, formalité 90 %, initiative 80 %, longueur 45 %, adaptation 100 %. Ce sont des préférences de comportement, non des probabilités mécaniques. Adapter le ton à la situation ; humour et sarcasme ne doivent pas nuire au sérieux, à la précision et à la compréhension.

## 25. Interface
Esthétique définitive décidée ultérieurement. Interface fonctionnelle, légère, modulaire : écran principal simple, conversation vocale et textuelle, gestion mémoire et graphe, tâches, ressources externes, confidentialité, réglages vocaux, indicateurs de performances, stockage, arrêt d'urgence, réinitialisation. Montrer les consultations mémoire, recherches et appels IA réellement effectués ; aucun faux indicateur. Animations et décor ne doivent pas dégrader les performances. Ne pas prioriser l'esthétique maintenant.

## 26. Tests et critères d'acceptation
Tests reproductibles avant/après :
- Intelligence : demandes simples, complexes, ambiguës, contextualisées, multi-sources ; sélection des ressources et synthèse.
- Mémoire : persistance, recherche sémantique, corrections, liens, réutilisation des méthodes ; comparaison de latence première demande/demande similaire.
- Voix : hésitations, pauses, respirations, interruptions, formulations familières et phrases françaises complexes ; aucune coupure prématurée dans les cas de recette.
- Multitâche : tâches simultanées, priorités, annulation, conversation maintenue.
- Sécurité : arrêt, confirmations, zéro frais, confidentialité, réinitialisation ; impossibilité de désactivation par modèle/instructions externes.
- Performances : latence, RAM, stockage, énergie, stabilité ; batterie faible, surchauffe, réseau instable, hors ligne.
- Non-régression : fonctionnalités conservées opérationnelles.

Distinguer tests automatisés, simulateur et iPhone physique. Ne jamais déclarer validé sur appareil ce qui ne l'a pas été. Définir des seuils réalistes à partir du matériel et des mesures de départ ; aucun chiffre inventé. Consigner les résultats.

## 27. Recherche technique
Documentations officielles, dépôts GitHub sérieux, publications techniques et tests reproductibles en priorité. Vérifier compatibilité, maintenance, licences, dépendances, sécurité, coûts, performances, restrictions. Ne pas installer un projet sur la seule promesse de bénéfice. Ne pas inventer fonctionnalités, modèles, API ni résultats ; signaler toute solution non vérifiable.

## 28. Optimisation du travail de Claude
Utiliser les outils déjà installés, notamment RTK si disponible et compatible. Lire les fichiers de mémoire/documentation avant de relire inutilement de gros volumes de code. Maintenir une documentation persistante : architecture, décisions et justifications, modifications, tests, résultats, problèmes restants, prochaines étapes. Enregistrer l'avancement régulièrement afin de reprendre après interruption ou limite Claude Pro. Éviter analyses redondantes, sorties volumineuses et relectures inutiles sans sacrifier la qualité. Utiliser le niveau Max pour audit et décisions architecturales si disponible ; respecter le forfait et ne pas engager de frais supplémentaires.

## 29. Gestion GitHub
Dépôt de référence : https://github.com/Test-IA-trading/JarvisXR-2. Vérifier branche active et état réel du dépôt avant toute modification. Préserver version actuelle, branches et commits cohérents, documenter changements, ne pas détruire l'historique ni fusionner d'instabilité dans une branche de référence. Vérifier workflows de compilation et validation. Compilation réussie ≠ fonctionnement démontré.

## 30. Ordre des priorités
- **P0 — Fondations critiques** : audit, sauvegarde, mesures, retrait temporaire caméra, latence, écoute, compréhension vocale, mémoire réellement fonctionnelle, sécurités fondamentales.
- **P1 — Intelligence** : cerveau local renforcé, orchestration des ressources externes gratuites, Internet, mémoire procédurale, intentions, vérification, synthèse contextualisée.
- **P2 — Autonomie** : multitâche, gestion conséquences, intégration iOS, apprentissage par l'expérience, propositions d'auto-amélioration, hors ligne et reprise des tâches.
- **P3 — Consolidation** : optimisation énergétique, tests approfondis, stabilité, modularité voix, interface technique, documentation, préparation des futures évolutions.

Réorganiser si une dépendance technique l'exige, en justifiant les changements. Ne pas reporter sécurité, mémoire ou performances pour des fonctionnalités secondaires.

## 31. Livrables attendus
Pas seulement un rapport : modifications concrètes, architecture améliorée, code fonctionnel, tests, documentation, mesures comparatives, commits, version compilable si environnement compatible, procédure claire d'installation et test iPhone, liste honnête des capacités validées et limites restantes, tests à réaliser par l'utilisateur sur appareil. Aucun simulacre présenté comme opérationnel.

## 32. Directive finale
Construire progressivement une véritable IA personnelle : réfléchir localement, exploiter les ressources disponibles, mémoriser expériences et méthodes, s'adapter, devenir plus intelligente et efficace avec l'usage, rester sous contrôle de l'utilisateur, ne jamais occasionner de frais, fonctionner quotidiennement sur iPhone.
Ne pas confondre accumulation de fonctions et intelligence, rapidité apparente et fluidité, historique et mémoire intelligente, accès multi-IA et orchestration, apprentissage par mémoire et réentraînement automatique, autonomie et absence de contrôle.
Ne pas prétendre que tout est possible. Rechercher la meilleure solution techniquement réalisable, vérifier, implémenter et démontrer. Commencer par auditer l'existant, puis engager les modifications concrètes en respectant toutes les exigences.
