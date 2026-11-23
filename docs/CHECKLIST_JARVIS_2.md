# JarvisXR 2.0 — mes usages sur iPhone

Les cases seront cochées après un essai réussi sur l’iPhone. Les dialogues ci-dessous sont des exemples pour juger le résultat.

## Priorité sur iPhone — manipuler des objets virtuels avec les doigts

Je veux voir des objets virtuels dans le décor filmé par l’iPhone et les manipuler avec ma main libre. Le premier geste à essayer en réalité augmentée est de saisir un objet entre le pouce et l’index, de le déplacer et de le déposer.

- [ ] Je cadre une table. Un cube virtuel apparaît posé dessus. Je distingue le cube que je vise et je vois quand je l’ai saisi.
- [ ] Je rapproche le pouce et l’index dans l’air devant la caméra pour saisir le cube, sans toucher l’écran. Tant que je garde les doigts pincés, le cube suit ma main sur la table. Quand je les écarte, il reste à l’endroit où je l’ai déposé, même si je change de point de vue.
- [ ] Si la caméra perd ma main de vue pendant le geste, le cube s’immobilise. Je peux le reprendre avec une nouvelle pince.
- [ ] Jarvis tient compte de mon geste. Si je lui demande « Qu’est-ce que je viens de déplacer ? », il me répond « Le cube » en français. La caméra, le suivi des doigts et la manipulation fonctionnent sur l’iPhone, PC éteint et hors ligne.

**Premier essai à faire sur l’iPhone.** En mode avion avec le Wi-Fi coupé, je cadre un livre posé sur la table. Je déplace le cube virtuel de la gauche du livre vers sa droite, puis je le lâche. Je filme la table de côté. L’essai réussit si le cube reste à droite du livre et si je peux le saisir de nouveau depuis ce point de vue. Un pincement à côté du cube doit le laisser en place.

**Piste de réalisation.** Vision fournit les positions du bout du pouce et de l’index dans l’image. Pour ce premier essai, projeter le milieu de la pince sur la surface de la table repérée avec ARKit. Une fois le geste fiable sur une surface, essayer le déplacement en profondeur, la rotation ou le redimensionnement. [Détection de la main avec Vision](https://developer.apple.com/videos/play/wwdc2020/10653/) · [Placement d’objets avec ARKit sur iOS](https://developer.apple.com/documentation/arkit/placing-objects-and-handling-3d-interaction)

## Réagir aussi aux changements dans la scène réelle

- [ ] J’active la caméra une fois. Pendant la session, Jarvis observe la scène sur l’iPhone, repère les changements utiles et prend la parole de lui-même en français. Je peux continuer ce que je fais sans toucher l’écran ni lui demander « Qu’est-ce que tu vois ? » à chaque geste.
- [ ] Jarvis suit une action dans le temps. Si je déplace un objet déjà repéré, il peut me dire ce qui a changé. Quand la scène reste stable, il reste silencieux. S’il perd un objet de vue, il distingue ce qu’il a vu de ce qu’il ignore.
- [ ] Je peux l’interrompre ou lui demander « Et maintenant ? ». Sa réponse tient compte de ce qu’on vient de faire et de l’image actuelle. Quand je coupe le mode caméra, l’observation et les annonces s’arrêtent.
- [ ] Ce parcours fonctionne avec le PC éteint et l’iPhone hors ligne. L’analyse des images et les réactions vocales se font sur l’iPhone.

**Essai avec un objet réel.** PC éteint, iPhone en mode avion et Wi-Fi coupé, je cadre une table vide avec le téléphone immobile. J’active le mode et je pose une tasse au centre sans rien dire. Jarvis signale spontanément son apparition, une seule fois. Je la déplace vers la droite et il signale le changement de position. Je la laisse immobile, puis je la sors du cadre et je demande « Elle est où maintenant ? ». La réponse attendue est « Je ne la vois plus », sans inventer où je l’ai mise. Je coupe le mode, puis je remets la tasse dans le champ pour vérifier l’arrêt des annonces. Pendant l’essai, noter le délai entre chaque geste et la première réaction, les changements manqués et les répétitions.

Le prototype dispose déjà du mode *Live Guide*, du suivi d’objets entre images et d’annonces vocales. Ces fonctions servent de point de départ. Le scénario ci-dessus reste à valider sur un iPhone physique. [Fonctions et limites de la vision](https://github.com/Test-IA-trading/JarvisXR-2/blob/develop/docs/FEATURES_AND_LIMITS.md)

## Tenir une conversation en français

- [ ] Je peux enchaîner plusieurs échanges à voix haute. Jarvis comprend à quoi je fais référence et tient compte d’une correction.
- [ ] Sa voix a un débit naturel. Je peux marquer une courte pause pour chercher mes mots et terminer ma phrase. Après sa réponse, la conversation reprend sans que je touche l’écran à chaque tour.
- [ ] Si je l’interromps pour préciser ma demande, il me laisse la parole et répond à la précision.
- [ ] Quand je lui pose une question, même délicate, il me donne directement la réponse qu’il peut établir. Quand il lui manque un fait ou un accès, il me dit précisément lequel.

**Premier dialogue à essayer**

1. « Le train part à neuf heures et le bus à onze heures. Lequel part en premier ? » Jarvis répond que c’est le train.
2. « En fait, le train part à midi. Et maintenant ? Explique-moi pourquoi. » Il comprend que je compare toujours les deux départs et répond que c’est le bus.
3. Pendant sa réponse, je dis « Attends, juste l’heure du train. » Il s’arrête et répond « Midi ».

Pendant l’essai, relever le délai entre la fin de ma phrase et le début de sa réponse. Noter aussi si Jarvis me coupe, reste silencieux trop longtemps ou continue à parler par-dessus moi.

## Ensuite, lui confier du travail en parallèle

- [ ] Je peux lui confier un projet, continuer à lui parler et lui donner une deuxième tâche pendant que la première avance.
- [ ] À « Tu en es où ? », il indique la dernière étape réellement terminée, ce qu’il fait maintenant ou ce qu’il attend. Je peux vérifier son annonce dans l’app.
- [ ] Je peux utiliser Jarvis entièrement en audio ou ouvrir l’application pour écrire, relire la même discussion et retrouver les tâches et leurs résultats.

**Essai proposé.** Je lui donne deux projets GitHub à comparer. Pendant la comparaison, je lui demande où il en est, puis de créer une courte note dans Jarvis. Je vérifie que la note est disponible pendant que la comparaison est encore en cours, puis que celle-ci se termine une seule fois.

## Autres usages demandés

- [ ] Rechercher sur X, Reddit, GitHub et le Web et retrouver les sources.
- [ ] Utiliser plusieurs modèles, dont Qwen sur le PC Windows.
- [ ] Lancer depuis l’iPhone une tâche sur le PC et récupérer son résultat.
- [ ] Utiliser les fonctions iOS que j’autorise.
- [ ] Retrouver mes décisions et reprendre une tâche lors d’une nouvelle conversation.

## Un assistant local qui réagit à ce que je fais

- [ ] Je peux utiliser Jarvis sur l’iPhone avec Internet coupé et le PC éteint. L’app traite ma demande sur l’appareil. Les appels entre l’interface, le modèle et les actions restent locaux.
- [ ] Quand j’active l’assistance dans Jarvis, l’app tient compte de ma voix, de l’écran de Jarvis où je me trouve et des actions que j’y fais. Elle adapte sa réponse si je change d’écran ou de sélection. Je peux suspendre cette assistance.
- [ ] Pour une autre app, le contexte disponible dépend de ce qu’iOS permet de transmettre et de ce que je choisis de partager.
- [ ] Qwen sur le PC reste une extension facultative sur mon réseau local. Si une tâche dépasse les capacités de l’iPhone, Jarvis me l’indique. Aucun transfert automatique vers un fournisseur cloud.

**Essai complémentaire dans les réglages.** PC éteint et iPhone en mode avion, j’ouvre les réglages de Jarvis et je demande « À quoi sert cette option ? ». Je sélectionne une autre option et je dis « Et celle-ci ? ». Jarvis explique la nouvelle sélection sans me demander de répéter son nom. Je suspends l’assistance et je vérifie que mes actions suivantes ne déclenchent plus de réaction.

## Plus tard, l’appeler en disant « Dis Jarvis »

- [ ] Une fois le déclenchement configuré, je peux dire « Dis Jarvis » pour commencer à lui parler. Essayer depuis l’écran d’accueil, puis séparément avec l’iPhone verrouillé et noter les cas qui fonctionnent sur l’appareil.

Apple permet d’associer une expression personnalisée à une action avec les raccourcis vocaux. C’est une piste à essayer sur le modèle d’iPhone et la version d’iOS utilisés. [Guide d’Apple](https://support.apple.com/fr-fr/guide/iphone/iph7f242ea2c/ios)

## Point de départ du prototype

Dans la version examinée, l’écoute des commandes utilise l’anglais américain et s’arrête au plus tard après huit secondes. Le menu du chat Qwen ouvre une conversation écrite dans le navigateur. Pour l’essai facultatif avec le PC, il reste à relier l’écoute en français, les réponses de Qwen et la parole de Jarvis dans le même échange. [Écoute native](https://github.com/Test-IA-trading/JarvisXR-2/blob/cd930850c242a543614f289006ff705d34f74e7d/ios/JarvisXR/JarvisXR/JarvisVoiceInputService.swift) · [Ouverture du chat](https://github.com/Test-IA-trading/JarvisXR-2/blob/cd930850c242a543614f289006ff705d34f74e7d/ios/JarvisXR/JarvisXR/JarvisPCChat.swift) · [Interface du chat](https://github.com/Test-IA-trading/JarvisXR-2/blob/cd930850c242a543614f289006ff705d34f74e7d/companion/windows/web/index.html)
