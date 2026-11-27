# Jarvis PC

Le même Jarvis que sur l'iPhone, sur Windows. Il fonctionne seul, et il parle avec l'iPhone.

- **Cerveau puissant** : Qwen3 30B (« Instruct 2507 ») tourne sur la carte graphique grâce à [Ollama](https://ollama.com).
  Sur une RTX 5060 Ti, il produit environ 45 jetons par seconde.
- **Voix complète** :
  - le micro est écouté sur le PC (faster-whisper) ;
  - la voix française « pierre » de Piper parle ;
  - il se réveille quand on dit « Jarvis, … » ou quand on tape deux fois dans ses mains.
- **Mêmes commandes que l'iPhone** :
  - calculs exacts (intégrales, dérivées), conversions, dates, minuteurs ;
  - prénom et notes.
- **Commandes du PC** : « Ouvre Spotify », « Ouvre YouTube », « Cherche … sur Internet ».
- **Internet, gratuit et sans compte** : météo (Open-Meteo), « Qui est… ? » (Wikipédia), titres de l'actualité (franceinfo).
- **Lien avec l'iPhone** :
  - l'iPhone peut poser ses questions au cerveau du PC et lui donner des commandes ;
  - les deux partagent le prénom et les notes ;
  - « Envoie sur mon téléphone que… » laisse un message que l'iPhone lit à son ouverture.

## Lancer

1. Installez [Ollama](https://ollama.com), puis le cerveau, une seule fois (environ 17 Go) :
   ```powershell
   ollama pull qwen3:30b-a3b-instruct-2507-q4_K_M
   ```
   Si le 30B manque, Jarvis se rabat sur `qwen3:8b`.
2. Double-cliquez sur **`Jarvis.bat`**.
   - La première fois, il prépare son environnement Python dans `pc\.venv`, et télécharge la voix (environ 75 Mo) et le modèle de reconnaissance de la parole (environ 480 Mo).
3. Windows demande d'autoriser Python sur les **réseaux privés** : acceptez, c'est ce qui permet à l'iPhone de joindre le PC.
4. Jarvis affiche son **code d'appairage** et l'adresse du PC. Ce sont les deux informations à saisir une fois dans l'iPhone.

Autres commandes :

```powershell
.\Jarvis.bat --texte
```

Sans micro ni voix : on écrit à Jarvis.

```powershell
.\Jarvis.bat --appareils
```

Liste les micros et haut-parleurs (choisissez celui de Windows par défaut).

```powershell
.\Jarvis.bat --autotest
```

Vérifie chaque partie pour de vrai : le cerveau, la voix vers les oreilles puis le réveil, et le serveur.

## Hors de la maison : Tailscale

À la maison, l'iPhone joint le PC par le Wi-Fi. Ailleurs, [Tailscale](https://tailscale.com) relie les deux appareils par un réseau privé chiffré :
- c'est gratuit pour un usage personnel, avec un compte à créer soi-même ;
- installez-le sur le PC et sur l'iPhone, connectez-vous avec le même compte ;
- dans l'iPhone, l'adresse du PC est alors celle que Tailscale lui donne : `100.x.y.z`, ou son nom `…ts.net`.

## Vie privée

- **Sur le PC**, rien ne sort pour la reconnaissance de la parole, la voix ou le cerveau. Ollama reste fermé au réseau : l'iPhone ne passe que par le serveur de Jarvis (port 8765), qui exige le code d'appairage.
- **Aucun son n'est enregistré.** Seul le niveau sonore de chaque 10 ms sert aux clappements.
- **Avec Internet** (désactivable dans `settings.json`), seuls partent :
  - le nom de la ville, vers Open-Meteo ;
  - le sujet de « Qui est… ? », vers Wikipédia ;
  - la demande des titres, vers franceinfo.
- **Réglages et mémoire** (prénom, notes) : `%APPDATA%\JarvisPC`. Modèles téléchargés : `%LOCALAPPDATA%\JarvisPC\cache`.

## Licences

- Code : GPL-3.0-or-later, comme le reste du projet.
- Voix Piper « upmc » (fr_FR, locuteur « pierre ») : jeu de données [upmc-pierre-data](https://github.com/marytts/upmc-pierre-data), licence CC BY-SA 4.0. Elle est téléchargée par le PC, pas incluse dans le dépôt.
- Bibliothèques :
  - faster-whisper : MIT, modèle Whisper « small » d'OpenAI sous licence MIT ;
  - Piper : GPL-3.0 ;
  - sounddevice : MIT ;
  - zeroconf : LGPL-2.1.
- Modèle Qwen3-30B-A3B-Instruct-2507 : Apache 2.0, téléchargé par Ollama.
