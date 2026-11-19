# Privacy Policy

Effective date: July 8, 2026

This policy describes how the JARVIS XR open-source application handles information when built from this repository or installed from a project release.

## Summary

JARVIS XR does not include a developer-operated account system, advertising SDK, analytics SDK, or remote application backend. The project maintainer does not receive app usage data from the application.

## Information Handled by the App

### Commands, notes, and history

Typed commands, recognized command text, saved notes, preferences, and command history are stored locally in the app container. They are used to provide app functions such as command routing, note search, voice settings, and history management.

Message-composition commands are excluded from general command history. Jarvis uses the system contact picker to let the user authorize one recipient selection without copying or uploading the address book. The selected phone number and message body remain in an in-memory draft and are passed to Apple's standard message composer only after the user asks to open it. Sending or cancelling occurs in that system interface.

### Optional PC chat (modified edition, November 19, 2026)

Under **Chat avec mon PC**, the user enters the companion’s private IPv4 address and chooses written chat in Safari or a French voice conversation in the app. Both modes send the current text and recent conversation turns to the paired Windows PC, which runs Ollama locally. The native client posts to port 8765 and refuses redirects. The pairing code and text travel over unencrypted HTTP on the chosen private network.

In voice mode, Apple Speech transcribes microphone input as described below. Only the transcript and recent chat turns are sent to the PC. Camera frames, contacts, the app’s notes and command history are excluded. The app remembers the PC address. The dialogue stays in memory while the chat is open, and the companion keeps no chat log. The connection code changes when the companion restarts.

### Microphone and speech recognition

Microphone access is used only after the user starts in-app voice input. Audio is provided to Apple's Speech framework for recognition. Recognition may occur on-device or may be processed by Apple depending on the device, language, operating system, network state, and Apple's service availability. Apple's handling is governed by Apple's own privacy terms.

JARVIS XR does not provide a background wake word and does not intentionally record while voice input is inactive.

### Camera and visual inspection

Camera access is used for the inspection screen. Captured frames are analyzed in the app with Apple Vision for text, barcode, QR, classification, and compatible bundled model requests. The app does not upload camera images to a developer-operated server. The current inspection flow does not intentionally save captured images to the photo library.

### Device diagnostics

The diagnostics screen may display information available through public iOS APIs, including system version, battery state, app version, permissions, feature availability, and local record counts. This information is displayed locally.

## Network and Third-Party Services

The core app does not require a project-operated server. When a user opens an external URL, app, Shortcut, or Apple service, that third party may process information under its own terms and privacy policy. Examples include Apple Speech services, Safari, Spotify, YouTube, AltServer, and Sideloadly.

## Data Sharing and Sale

The project maintainer does not receive, sell, rent, or share personal information from the app because the app does not transmit app data to a maintainer-operated service.

## Retention and Deletion

Local notes, history, and preferences remain until the user clears them in the app, resets the relevant setting, or removes the app and its container. iOS backups and sideloading tools may retain copies according to the user's own device and tool configuration.

## Permissions

The app requests only permissions used by implemented features:

- Microphone for push-to-talk input
- Speech Recognition for command transcription
- Camera for visual inspection
- Local Network for the optional paired PC chat

Permission can be denied or revoked in iOS Settings. Some features will be unavailable when permission is denied.

## Children

JARVIS XR is a developer prototype and is not directed to children under 13. It does not knowingly collect children's personal information through a project-operated service.

## Security

No software can guarantee absolute security. Protect the device passcode, Apple ID, signing credentials, saved notes, and backups. Do not place passwords, payment details, private keys, medical records, or other highly sensitive information in notes or commands.

## Changes

Material policy changes will be recorded in the repository history with an updated effective date.

## Contact

For privacy questions, open a GitHub issue without including private data. For a security vulnerability, follow [SECURITY.md](SECURITY.md) and use private vulnerability reporting when available.
