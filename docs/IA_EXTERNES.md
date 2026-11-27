# ChatGPT, Claude, Gemini : intégrations officielles sans dépense

Étude faite pour JarvisXR (novembre 2026). Contrainte : aucune dépense, pas de contournement des conditions d'utilisation, et Jarvis reste local et autonome.

| Service | Voie officielle | Coût | Dans Jarvis |
|---|---|---|---|
| ChatGPT | Action « Demander à ChatGPT » de l'app ChatGPT dans Raccourcis | gratuit avec un compte ChatGPT gratuit (limites du compte) | « Demande à ChatGPT … » lance le raccourci « Demander à ChatGPT » avec la question |
| Claude | Actions de l'app Claude dans Raccourcis, si l'app les propose sur l'iPhone (à vérifier dans Raccourcis) | gratuit avec un compte Claude gratuit (limites du compte) | « Demande à Claude … » lance « Demander à Claude » |
| Gemini | App Gemini dans Raccourcis si elle propose l'action ; sinon l'API Gemini avec une clé créée par l'utilisateur dans Google AI Studio (offre gratuite limitée) | gratuit dans les limites ; avec l'offre gratuite de l'API, Google peut utiliser les échanges pour améliorer ses produits | « Demande à Gemini … » lance « Demander à Gemini » ; l'API n'est pas branchée sans l'accord du propriétaire |
| API OpenAI / Anthropic | API payantes à l'usage | payant | non utilisé |

Non retenu : l'automatisation des sites web de ces assistants (scraping), contraire à leurs conditions d'utilisation.

## Créer le raccourci une fois

1. App Raccourcis › « + » › nommer le raccourci exactement « Demander à ChatGPT ».
2. Ajouter l'action de l'app ChatGPT (« Demander à ChatGPT » ou « Poser une question »), avec comme entrée « Entrée du raccourci ».
3. Ajouter « Énoncer le texte » avec la réponse, pour l'entendre.
4. Dire « Jarvis, demande à ChatGPT pourquoi la mer est salée ».

La réponse est lue par le raccourci. Jarvis ne la reçoit pas : iOS ne renvoie pas le résultat d'un raccourci à l'app qui l'a lancé.
