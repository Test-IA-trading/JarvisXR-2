# Installing on iPhone

JARVIS XR is distributed as an unsigned IPA for personal sideload testing. The IPA must be signed during installation.

## Before You Begin

- Use a phone and Apple ID you are authorized to use.
- Back up important device data.
- Never share Apple ID passwords, verification codes, signing certificates, or provisioning profiles.
- Download sideloading tools only from their official sources.
- Read [Privacy](../PRIVACY.md), [Terms](../TERMS.md), and [Disclaimer](../DISCLAIMER.md).

## Télécharger l'IPA (tuto rapide en français)

1. Ouvrez la page des versions : <https://github.com/Test-IA-trading/JarvisXR-2/releases>. Aucun compte GitHub n'est nécessaire.
2. Prenez la version **tout en haut**. La pastille **Pre-release** signifie « préversion ».
3. Descendez jusqu'à **Assets** (cliquez sur le mot si la liste est repliée).
4. Cliquez sur le fichier qui finit par **`.ipa`**, par exemple `JarvisXR-voix-francaise-cfad6b7-NON-SIGNEE.ipa`. Jamais sur **Source code (zip)** ni **Source code (tar.gz)** : c'est le code du projet, pas l'app.
5. Vérifiez que la page appartient bien à `Test-IA-trading/JarvisXR-2`, et comparez si besoin l'empreinte SHA-256 donnée dans les notes de la version.

**Version de test pas encore publiée** (compte GitHub nécessaire) : ouvrez la PR, onglet **Checks**, puis **Build JarvisXR iOS IPA**, puis **Summary**. Tout en bas, sous **Artifacts**, cliquez sur `JarvisXR-unsigned-ipa`. Vous recevez un `.zip` : extrayez-le, le `.ipa` est dedans.

## Download

1. Open the repository [Releases](https://github.com/Test-IA-trading/JarvisXR-2/releases).
2. Select the newest prerelease.
3. Download the asset ending in `.ipa` (for example `JarvisXR-voix-francaise-cfad6b7-NON-SIGNEE.ipa`); never the "Source code" archives.
4. Confirm the release and asset belong to `Test-IA-trading/JarvisXR-2`.

## Windows With AltServer or Sideloadly

1. Install the chosen sideloading tool and its required Apple device drivers.
2. Connect and unlock the iPhone by USB.
3. Tap **Trust This Computer** if prompted.
4. Select the downloaded `.ipa` file.
5. Complete signing with an Apple ID intended for sideload testing.
6. Start the installation.
7. On iPhone, approve the developer profile if iOS requests it.
8. Enable Developer Mode if iOS requires it, then restart as directed.
9. Launch JARVIS and complete the first-run checks.

Free Apple ID signing commonly expires after seven days and requires refresh. Apple and sideloading tool policies can change.

## macOS With Xcode

1. Generate the Xcode project as described in [Building](BUILDING.md).
2. Open `JarvisXR.xcodeproj`.
3. Select your development team and connected device.
4. Allow Xcode to manage signing.
5. Build and run the `JarvisXR` scheme.

## Guided Access

Only enable Guided Access after confirming camera, microphone, speech, typed commands, Settings, and the exit process work correctly. Guided Access restricts app switching; it does not grant JARVIS additional system privileges.
