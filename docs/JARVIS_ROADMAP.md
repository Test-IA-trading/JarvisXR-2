# JarvisXR — feuille de route et consignes de reprise

Ce document est la référence du projet JarvisXR. Toute personne ou IA qui reprend le dépôt doit le lire avant de modifier le code.

## 1. État validé

- L’application iPhone est installable avec un IPA signé depuis Windows.
- La conversation vocale iPhone ↔ PC fonctionne.
- Le micro iPhone fonctionne après correction de la configuration `AVAudioSession`.
- Le flux actuel est iPhone → réseau local → compagnon Windows → Qwen local → réponse → iPhone.
- Le test doit inclure plusieurs phrases successives sans relancer l’application.
- L’application et l’écran d’accueil Jarvis Vision contiennent encore de l’anglais.
- La voix actuelle est jugée mauvaise et doit être remplacée.

## 2. Objectif général

Faire évoluer JarvisXR vers un assistant vocal personnel utilisable depuis l’iPhone sans dépendre d’un PC allumé, avec une interface française, une voix naturelle, une mémoire persistante et une synchronisation entre appareils.

Architecture cible :

```text
iPhone → service Jarvis en ligne → modèle IA et services vocaux → iPhone
```

Le PC local peut rester disponible comme mode de développement ou mode hors ligne, mais il ne doit plus être une dépendance obligatoire dans la version finale.

## 3. Priorité 1 — interface française

- [ ] Traduire l’interface principale en français.
- [ ] Traduire Jarvis Vision et son écran d’accueil.
- [ ] Traduire les boutons, menus, permissions et erreurs.
- [ ] Traduire les textes d’aide et les états de connexion.
- [ ] Ajouter le français comme langue par défaut.
- [ ] Prévoir la sélection de langue dans les réglages.
- [ ] Vérifier l’affichage des textes sur les petits écrans.

## 4. Priorité 2 — voix et prononciation

- [ ] Remplacer la voix actuelle par une voix française naturelle.
- [ ] Comparer plusieurs voix et retenir celle qui est la plus agréable.
- [ ] Détecter les passages français et anglais dans une même réponse.
- [ ] Prononcer les mots anglais avec une prononciation anglaise correcte.
- [ ] Gérer les noms propres, acronymes, termes techniques et mots étrangers.
- [ ] Utiliser des indications de langue pour le moteur TTS lorsque c’est possible.
- [ ] Éviter de prononcer toute la phrase avec un seul accent.
- [ ] Ajouter un réglage de voix, de vitesse et de volume.

## 5. Priorité 3 — conversation vocale naturelle

Version initiale ciblée lorsque l’application est ouverte :

- [ ] Maintenir le microphone actif dans le mode vocal.
- [ ] Ajouter un mot d’activation, par exemple « Jarvis ».
- [ ] Détecter la voix sur l’iPhone avant d’envoyer l’audio.
- [ ] Attendre la fin réelle de la phrase après une courte pause.
- [ ] Utiliser un délai de fin de parole configurable, environ 0,8 à 1,2 seconde.
- [ ] Prévoir une durée maximale d’écoute par demande.
- [ ] Ne pas répondre au premier silence court au milieu d’une phrase.
- [ ] Permettre l’interruption de Jarvis pendant sa réponse.
- [ ] Reprendre l’écoute après la réponse.
- [ ] Ajouter un bouton d’arrêt total de l’écoute.
- [ ] Afficher les états « écoute », « traitement » et « réponse ».
- [ ] Gérer clairement les permissions micro et reconnaissance vocale.

Une écoute permanente en arrière-plan doit être étudiée séparément selon les contraintes iOS. Le mode ouvert au premier plan est la première cible.

## 6. Priorité 4 — indépendance du PC

- [ ] Définir le backend Jarvis accessible en ligne.
- [ ] Déplacer le traitement Qwen vers un serveur ou un fournisseur adapté.
- [ ] Déplacer la transcription et la synthèse vocale vers le service cible.
- [ ] Faire communiquer l’iPhone directement avec le backend.
- [ ] Permettre l’utilisation lorsque le PC est éteint.
- [ ] Conserver le compagnon Windows comme mode local de développement.
- [ ] Ajouter une authentification personnelle.
- [ ] Synchroniser les conversations entre appareils.
- [ ] Synchroniser les réglages et la mémoire.
- [ ] Ajouter une reconnexion automatique.
- [ ] Afficher l’état du service et les erreurs réseau.
- [ ] Chiffrer les communications.
- [ ] Documenter les données envoyées au serveur et leur durée de conservation.
- [ ] Prévoir un mode local dégradé pour certaines fonctions si le réseau est absent.

## 7. Mémoire et synchronisation

- [ ] Définir les informations que Jarvis peut mémoriser.
- [ ] Permettre à l’utilisateur de consulter, corriger et supprimer sa mémoire.
- [ ] Stocker la mémoire dans le backend, avec une séparation par compte.
- [ ] Synchroniser les conversations entre iPhone, PC et futurs appareils.
- [ ] Éviter de mélanger les données de plusieurs utilisateurs du même service.
- [ ] Prévoir l’export et la suppression complète des données.

## 8. Tests obligatoires

- [ ] Première phrase vocale.
- [ ] Deuxième phrase sans redémarrer l’application.
- [ ] Phrase avec un mot anglais.
- [ ] Phrase avec un nom propre anglais.
- [ ] Phrase longue avec pauses naturelles.
- [ ] Interruption pendant une réponse.
- [ ] Silence avant la fin de la phrase.
- [ ] Coupure puis retour du Wi-Fi.
- [ ] Redémarrage de l’application.
- [ ] PC éteint après mise en place du backend.
- [ ] Test sur haut-parleur et écouteurs.
- [ ] Test des permissions après réinstallation.
- [ ] Test de tous les écrans traduits.

Chaque correction doit préciser le fichier modifié, le comportement attendu et le test effectué.

## 9. Règles pour toute IA qui reprend le dépôt

1. Lire ce document et `CLAUDE.md` avant toute modification.
2. Ne pas supprimer une fonctionnalité validée sans expliquer la raison.
3. Ne pas modifier le fonctionnement vocal sans prévoir un test sur iPhone.
4. Ne pas ajouter de secret, clé API, mot de passe ou identifiant dans le dépôt.
5. Ne pas considérer les tests simulateur comme suffisants pour le micro réel.
6. Conserver le mode local tant que le backend en ligne n’est pas validé.
7. Mettre à jour ce document après chaque décision importante.
8. Indiquer clairement les éléments terminés, en cours, bloqués et à tester.

## 10. Format de suivi

À chaque session, ajouter une courte entrée dans le journal ci-dessous.

```text
### AAAA-MM-JJ — outil ou IA
- Fichiers lus :
- Modifications :
- Tests réalisés :
- Résultat :
- Prochaine étape :
```

## Journal

### 2026-11-19 — première version de la feuille de route
- État validé : conversation vocale iPhone ↔ PC et micro fonctionnels.
- Décisions : interface française, nouvelle voix, prononciation multilingue, écoute conversationnelle, backend indépendant du PC et mémoire synchronisée.
- Prochaine étape : traduire l’application et améliorer la voix avant de concevoir le backend en ligne.
