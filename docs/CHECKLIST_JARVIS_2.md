# JarvisXR 2.0 — mes usages sur iPhone

Les cases seront cochées après un essai réussi sur l’iPhone. Les dialogues ci-dessous sont des exemples pour juger le résultat.

## En premier, tenir une conversation en français

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

## Choisir le modèle selon la tâche et mon budget

La vidéo de référence montre un outil de code qui envoie ses requêtes à un proxy, puis à différents modèles. Pour Jarvis, je veux pouvoir garder la même conversation sur l’iPhone et choisir qui traite chaque tâche.

- [ ] Dans les réglages, je peux choisir un modèle précis ou activer le choix automatique. Mon choix est conservé après redémarrage.
- [ ] En mode automatique, une tâche simple utilise le modèle disponible le moins coûteux capable de la traiter. Je peux autoriser un modèle plus puissant pour une tâche difficile et fixer si Jarvis doit me demander avant tout appel payant.
- [ ] Je peux choisir Qwen via Ollama sur le PC pour une tâche locale. Quand le PC est éteint ou qu’un fournisseur atteint sa limite, Jarvis propose les autres options autorisées et conserve la demande à reprendre.
- [ ] Pour chaque réponse, je peux voir le fournisseur et le modèle réellement utilisés, les tokens si le fournisseur les communique et le coût s’il est connu. Un coût inconnu s’affiche comme tel.

**Essai sur iPhone.** En mode local, je demande à Jarvis de résumer trois phrases et je vérifie que Qwen a répondu. J’éteins le PC puis je demande une reformulation. Jarvis explique l’indisponibilité et respecte mon choix de secours. Si j’autorise un autre fournisseur, il reprend la même conversation et je peux vérifier quel modèle a produit la réponse.

## Plus tard, l’appeler en disant « Dis Jarvis »

- [ ] Une fois le déclenchement configuré, je peux dire « Dis Jarvis » pour commencer à lui parler. Essayer depuis l’écran d’accueil, puis séparément avec l’iPhone verrouillé et noter les cas qui fonctionnent sur l’appareil.

Apple permet d’associer une expression personnalisée à une action avec les raccourcis vocaux. C’est une piste à essayer sur le modèle d’iPhone et la version d’iOS utilisés. [Guide d’Apple](https://support.apple.com/fr-fr/guide/iphone/iph7f242ea2c/ios)

## Point de départ du prototype

Dans la version examinée, l’écoute des commandes utilise l’anglais américain et s’arrête au plus tard après huit secondes. Le menu du chat Qwen ouvre une conversation écrite dans le navigateur. Le premier chantier vocal consiste à relier l’écoute en français, les réponses de Qwen et la parole de Jarvis dans le même échange. [Écoute native](https://github.com/Test-IA-trading/JarvisXR-2/blob/cd930850c242a543614f289006ff705d34f74e7d/ios/JarvisXR/JarvisXR/JarvisVoiceInputService.swift) · [Ouverture du chat](https://github.com/Test-IA-trading/JarvisXR-2/blob/cd930850c242a543614f289006ff705d34f74e7d/ios/JarvisXR/JarvisXR/JarvisPCChat.swift) · [Interface du chat](https://github.com/Test-IA-trading/JarvisXR-2/blob/cd930850c242a543614f289006ff705d34f74e7d/companion/windows/web/index.html)
