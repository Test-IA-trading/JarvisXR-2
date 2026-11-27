# Privacy Policy

Effective date: July 8, 2026

This policy describes how the JARVIS XR open-source application handles information when built from this repository or installed from a project release.

## Summary

JARVIS XR does not include a developer-operated account system, advertising SDK, analytics SDK, or remote application backend. The project maintainer does not receive app usage data from the application.

## Information Handled by the App

### Commands, notes, and history

Typed commands, recognized command text, saved notes, preferences, and command history are stored locally in the app container. They are used to provide app functions such as command routing, note search, voice settings, and history management.

Message-composition commands are excluded from general command history. Jarvis uses the system contact picker to let the user authorize one recipient selection without copying or uploading the address book. The selected phone number and message body remain in an in-memory draft and are passed to Apple's standard message composer only after the user asks to open it. Sending or cancelling occurs in that system interface.

### Microphone and speech recognition

Microphone access is used only after the user starts in-app voice input. Audio is provided to Apple's Speech framework for recognition. Recognition may occur on-device or may be processed by Apple depending on the device, language, operating system, network state, and Apple's service availability. Apple's handling is governed by Apple's own privacy terms.

JARVIS XR does not provide a background wake word and does not intentionally record while voice input is inactive.

### Camera and visual inspection

Camera access is used for the inspection screen. Captured frames are analyzed in the app with Apple Vision for text, barcode, QR, classification, and compatible bundled model requests. The app does not upload camera images to a developer-operated server. The current inspection flow does not intentionally save captured images to the photo library.

During Live Guide, the app also reads the phone's motion sensors (Core Motion attitude and acceleration, which need no permission) so that turning the phone is not announced as an object moving. These readings and the list of objects seen in the session stay in memory, are never written to storage or sent anywhere, and are erased when Live Guide stops.

### Device diagnostics

The diagnostics screen may display information available through public iOS APIs, including system version, battery state, app version, permissions, feature availability, and local record counts. This information is displayed locally.

## Network and Third-Party Services

The core app does not require a project-operated server. When a user opens an external URL, app, Shortcut, or Apple service, that third party may process information under its own terms and privacy policy. Examples include Apple Speech services, Safari, Spotify, YouTube, AltServer, and Sideloadly.

## Local Brain Download (optional)

The local brain is optional. When the user taps **Télécharger le cerveau** in Settings and confirms, the app downloads one pinned model file, `qwen2.5-1.5b-instruct-q4_k_m.gguf` (Qwen2.5 1.5B Instruct, Apache 2.0, about 1.1 GB), from Hugging Face over HTTPS. The request sends no user data: no questions, notes, audio, or images. Hugging Face may log the request itself (IP address, time) under its own privacy terms. If the user picks the optional **Avancé** brain in Settings and downloads it, the app fetches a second pinned file the same way: `Qwen3-4B-Instruct-2507-IQ4_XS.gguf` (Qwen3 4B Instruct, Apache 2.0, about 2.3 GB, quantised and published by Unsloth on Hugging Face). Before loading a brain, the app checks the memory iOS leaves it and declines to load rather than be closed by the system. The file is verified by size and SHA-256, stored in the app's Application Support folder, and excluded from iCloud backups. Questions sent to the local brain and its answers are processed on the iPhone and kept only in memory for the current session; the user can delete the model at any time in Settings.

The optional wake word (Settings › Réveil par la voix, off by default) keeps the microphone open while the JARVIS home screen is on screen and idle, so that « Jarvis, … » works without a tap. It uses on-device speech recognition only: the app refuses to start it when the iPhone cannot recognise French locally, and it never falls back to Apple's servers. No audio is stored or sent; words not addressed to Jarvis are dropped at once and never shown. iOS shows its microphone indicator the whole time, other audio is not lowered, and listening stops whenever JARVIS speaks, another screen opens or the app leaves the foreground. The same option can also answer two hand claps (on by default, can be turned off): the app only measures the sound level of each 10 ms of audio, on the iPhone, and keeps nothing.

**Background watch (Settings › Veille en arrière-plan, off by default).** When the user turns it on, the microphone stays open after leaving the app (not once the app is closed from the app switcher), so that two hand claps still call Jarvis. Off screen, only the sound level of each 10 ms is measured for the claps: there is no speech recognition until the claps are heard, and nothing is kept. Jarvis then listens to one request, answers aloud, and shows its state and answer in a Live Activity (Dynamic Island and lock screen), drawn on the iPhone. A call, a message or the photos wait until the user taps the Dynamic Island. iOS shows its microphone indicator the whole time.

**Speaking over Jarvis (Settings › Interrompre Jarvis en parlant, on by default).** During a hands-free conversation the microphone stays open between turns, with Apple's echo cancellation (voice processing), and Jarvis's voice is played through the same audio engine, so the user can interrupt Jarvis by speaking. The last 1.2 seconds of sound are kept in memory only, so that the first words of a turn are not lost; they are overwritten continuously and never stored or sent. While Jarvis speaks, only the sound level is measured; when the user may be speaking, the words go to the speech recognizer like any request, and Jarvis's own words are recognised and ignored. iOS shows its microphone indicator, and the microphone closes when the conversation ends, another screen opens or the app leaves the foreground.

**Jarvis PC (optional).** The app can be paired with Jarvis PC, the same assistant running on the user's own Windows PC (`pc/` in this repository), by typing the PC's address and the pairing code the PC shows; the code is kept in the iOS keychain (or, when the keychain refuses it, in the app's own preferences). Once paired, and only then, the app sends to that PC, over the home Wi-Fi or the user's own Tailscale network: open questions with the recent conversation, the first name and the latest notes (so the PC's local model, run by Ollama, can answer); « Sur le PC, … » commands and « Dis sur le PC… » sentences; and the first name and notes to keep both copies in step. When the app opens it fetches the messages the PC left for the phone. The PC's brain may also reword a free request into a command the iPhone knows (« Préviens Marie que… » becomes « Envoie un message à Marie… »), which the iPhone then runs itself, with the same confirmations. In connected mode, the Wikipédia text found for a question goes to the PC's brain with the question, so it explains the article in its own words. Nothing is sent to any other service, and when the PC does not answer within two seconds the iPhone's own brain answers instead. Finding the PC on the Wi-Fi uses Bonjour (`_jarvis._tcp`), which iOS lets the user allow or refuse (local network permission).

**Connected mode (optional, off by default).** Only when the user turns it on in Settings › Internet, and only for the request being answered, the app contacts three free services that need no account: Open-Meteo (`api.open-meteo.com`, `geocoding-api.open-meteo.com`) for the weather, sent the city the user named or the iPhone's position rounded to two decimals (about a kilometre); Wikipédia (`fr.wikipedia.org`) for « Qui est… ? » and « C'est quoi… ? », sent the subject searched; and franceinfo (`www.francetvinfo.fr`) for the news, sent nothing but the request for its public feed. For the weather of where the user is and for « Où suis-je ? », iOS asks once for the location permission, and Apple's geocoder, part of iOS, turns the position into a town or an address; the position is not stored. Requests carry a generic name (`JarvisXR/2.0`), no identifier and no cookie. Recordings, camera frames, notes, transcripts and the conversation are never sent. With the connected mode off, none of these services is contacted.

**The iPhone's own data (on request).** « Appelle Paul », « Écris à Paul que j'arrive » and « Quel est le numéro de Paul ? » read the contacts on the iPhone to find that person (iOS asks once, and allows sharing only some contacts); the call then goes through iOS's call confirmation, and the message opens in iOS's message window, filled in, where the user taps Send. « Combien de pas aujourd'hui ? » reads the step count, distance and floors the iPhone's motion coprocessor keeps for the last seven days (iOS asks once for Motion & Fitness). « Combien de photos hier ? » and « Montre-moi ma dernière photo » read the photo library (iOS asks once); photos are shown in the app and never changed. None of this is stored by Jarvis or sent anywhere, including in connected mode and to Jarvis PC.

To personalise its answers, the local brain also reads, on the iPhone only, the first name the user gave (« Je m'appelle… », stored in the app's preferences until « Oublie mon prénom ») and the latest notes the user dictated (« Souviens-toi que… », at most eight, shortened). Nothing of this is sent anywhere. « Qu'est-ce que tu sais sur moi ? » lists what Jarvis keeps, and Settings › Effacer les notes removes the notes.

## Data Sharing and Sale

The project maintainer does not receive, sell, rent, or share personal information from the app because the app does not transmit app data to a maintainer-operated service.

## Retention and Deletion

Local notes, history, and preferences remain until the user clears them in the app, resets the relevant setting, or removes the app and its container. iOS backups and sideloading tools may retain copies according to the user's own device and tool configuration.

## Permissions

The app requests only permissions used by implemented features:

- Microphone for push-to-talk input
- Speech Recognition for command transcription
- Camera for visual inspection

Permission can be denied or revoked in iOS Settings. Some features will be unavailable when permission is denied.

## Children

JARVIS XR is a developer prototype and is not directed to children under 13. It does not knowingly collect children's personal information through a project-operated service.

## Security

No software can guarantee absolute security. Protect the device passcode, Apple ID, signing credentials, saved notes, and backups. Do not place passwords, payment details, private keys, medical records, or other highly sensitive information in notes or commands.

## Changes

Material policy changes will be recorded in the repository history with an updated effective date.

## Contact

For privacy questions, open a GitHub issue without including private data. For a security vulnerability, follow [SECURITY.md](SECURITY.md) and use private vulnerability reporting when available.
