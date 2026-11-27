"""What « Ouvre … » can open on this PC: the known sites and apps, Windows folders, and
every application of the Start menu (Get-StartApps, read once in the background).

The spoken name is compared without spaces, dots, accents or capitals, then with a small
tolerance, so « You Tube », « youtube.com », « la page YouTube » and « Youtub » all open
YouTube."""
from __future__ import annotations

import difflib
import json
import os
import re
import subprocess
import threading
import unicodedata

# Spoken name → (what Jarvis says, a URI or a program for Windows).
KNOWN = {
    "spotify": ("Spotify", "spotify:"),
    "chrome": ("Chrome", "chrome"),
    "google chrome": ("Chrome", "chrome"),
    "edge": ("Edge", "microsoft-edge:"),
    "microsoft edge": ("Edge", "microsoft-edge:"),
    "firefox": ("Firefox", "firefox"),
    "navigateur": ("le navigateur", "https://duckduckgo.com"),
    "internet": ("le navigateur", "https://duckduckgo.com"),
    "explorateur": ("l'Explorateur de fichiers", "explorer"),
    "explorateur de fichiers": ("l'Explorateur de fichiers", "explorer"),
    "explorateur windows": ("l'Explorateur de fichiers", "explorer"),
    "calculatrice": ("la Calculatrice", "calc"),
    "bloc notes": ("le Bloc-notes", "notepad"),
    "parametres": ("les Paramètres", "ms-settings:"),
    "reglages": ("les Paramètres", "ms-settings:"),
    "gestionnaire des taches": ("le Gestionnaire des tâches", "taskmgr"),
    "discord": ("Discord", "discord://"),
    "steam": ("Steam", "steam://open/main"),
    "documents": ("vos Documents", "shell:Personal"),
    "mes documents": ("vos Documents", "shell:Personal"),
    "telechargements": ("vos Téléchargements", "shell:Downloads"),
    "bureau": ("le Bureau", "shell:Desktop"),
    "mes images": ("vos Images", "shell:My Pictures"),
    "mes photos": ("vos Images", "shell:My Pictures"),
    "ma musique": ("votre dossier Musique", "shell:My Music"),
    "mes videos": ("vos Vidéos", "shell:My Video"),
    "corbeille": ("la Corbeille", "shell:RecycleBinFolder"),
    "youtube": ("YouTube", "https://www.youtube.com"),
    "youtube music": ("YouTube Music", "https://music.youtube.com"),
    "google": ("Google", "https://www.google.com"),
    "gmail": ("Gmail", "https://mail.google.com"),
    "google maps": ("Google Maps", "https://www.google.com/maps"),
    "maps": ("Google Maps", "https://www.google.com/maps"),
    "outlook": ("Outlook", "https://outlook.live.com"),
    "netflix": ("Netflix", "https://www.netflix.com"),
    "twitch": ("Twitch", "https://www.twitch.tv"),
    "wikipedia": ("Wikipédia", "https://fr.wikipedia.org"),
    "github": ("GitHub", "https://github.com"),
    "deepl": ("DeepL", "https://www.deepl.com/translator"),
    "amazon": ("Amazon", "https://www.amazon.fr"),
    "facebook": ("Facebook", "https://www.facebook.com"),
    "instagram": ("Instagram", "https://www.instagram.com"),
    "twitter": ("X", "https://x.com"),
    "linkedin": ("LinkedIn", "https://www.linkedin.com"),
    "reddit": ("Reddit", "https://www.reddit.com"),
    "whatsapp": ("WhatsApp", "https://web.whatsapp.com"),
    "chatgpt": ("ChatGPT", "https://chatgpt.com"),
    "le bon coin": ("leboncoin", "https://www.leboncoin.fr"),
    "leboncoin": ("leboncoin", "https://www.leboncoin.fr"),
    "prime video": ("Prime Video", "https://www.primevideo.com"),
    "disney plus": ("Disney+", "https://www.disneyplus.com"),
    "deezer": ("Deezer", "https://www.deezer.com"),
}

# « la page YouTube », « l'application Spotify », « le site de Netflix ».
LEADING = re.compile(
    r"^(?:(?:l'|le |la |les |un |une |mon |ma |mes |ton |ta |tes )?"
    r"(?:application |appli |app |logiciel |programme |jeu |page |page web |site |site web |site internet |chaine |dossier )"
    r"(?:de |d'|du |des )?|l'|le |la |les |un |une )"
)
TRAILING = re.compile(
    r"\s+(?:sur (?:le|mon) (?:pc|ordinateur|ordi)|sur l'ordinateur|sur l'ordi|pour moi|maintenant|tout de suite|s'il te plait|"
    r"stp|svp|merci|s'il vous plait|en grand|en plein ecran)$"
)
DOMAIN = re.compile(r"^([a-z0-9-]+)\s*(?:\.|point)\s*(com|fr|net|org|io|tv|eu|be|ch|ca)$")


def folded(text: str) -> str:
    """Lower case, no accents, apostrophes kept: « Téléchargements » → « telechargements »."""
    text = unicodedata.normalize("NFD", text.replace("’", "'"))
    return "".join(c for c in text if unicodedata.category(c) != "Mn").lower().strip()


def compact(text: str) -> str:
    """The name without spaces, dots or dashes: « You Tube » → « youtube »."""
    return re.sub(r"[^a-z0-9]", "", folded(text))


def clean_target(target: str) -> str:
    """« la page YouTube s'il te plait » → « youtube » (in the router's normalized form)."""
    value = folded(target).strip(" .,;:!?")
    previous = None
    while previous != value:
        previous = value
        value = TRAILING.sub("", value).strip()
        value = LEADING.sub("", value, count=1).strip()
    return value


def _load_start_apps() -> list[tuple[str, str]]:
    """(name, AppID) of each Start menu application, desktop and Store alike."""
    if os.name != "nt":
        return []
    script = "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; Get-StartApps | ConvertTo-Json -Compress"
    result = subprocess.run(["powershell", "-NoProfile", "-NonInteractive", "-Command", script], capture_output=True,
                            timeout=30, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    data = json.loads(result.stdout.decode("utf-8", errors="replace") or "[]")
    if isinstance(data, dict):
        data = [data]
    return [(str(item.get("Name", "")), str(item.get("AppID", ""))) for item in data if item.get("Name") and item.get("AppID")]


class Catalog:
    """Finds what to open for a spoken name. The Start menu is read once, off the main path."""

    def __init__(self, loader=_load_start_apps, known: dict | None = None):
        self.loader = loader
        self.known = {compact(name): value for name, value in (known or KNOWN).items()}
        self._apps: dict[str, tuple[str, str]] | None = None
        self._lock = threading.Lock()

    def preload(self) -> None:
        threading.Thread(target=self.apps, name="jarvis-start-apps", daemon=True).start()

    def apps(self) -> dict[str, tuple[str, str]]:
        with self._lock:
            if self._apps is None:
                try:
                    listed = self.loader()
                except Exception:  # noqa: BLE001 — without the list, the known names still work
                    listed = []
                self._apps = {}
                for name, app_id in listed:
                    key = compact(name)
                    if key and key not in self._apps:
                        self._apps[key] = (name, "shell:AppsFolder\\" + app_id)
            return self._apps

    def find(self, spoken: str) -> tuple[str, str] | None:
        """(what Jarvis says, what to open), or None."""
        target = clean_target(spoken)
        if not target:
            return None
        domain = DOMAIN.match(target)
        key = compact(target)
        if domain:
            name = domain.group(1)
            found = self._exact(compact(name))
            return found or (f"{name}.{domain.group(2)}", f"https://{name}.{domain.group(2)}")
        found = self._exact(key)
        if found:
            return found
        for suffix in ("com", "fr", "net", "org"):
            if key.endswith(suffix) and len(key) > len(suffix) + 2:
                found = self._exact(key[: -len(suffix)])
                if found:
                    return found
        return self._close(key)

    def _exact(self, key: str) -> tuple[str, str] | None:
        # An installed application wins (WhatsApp's app rather than its site), said as Jarvis
        # names it when it knows it (« la Calculatrice »).
        app = self.apps().get(key)
        known = self.known.get(key)
        if app and known:
            return known[0], app[1]
        return app or known

    def _close(self, key: str) -> tuple[str, str] | None:
        if len(key) < 4:
            return None
        names = list(self.known) + list(self.apps())
        close = difflib.get_close_matches(key, names, n=1, cutoff=0.82)
        if close:
            return self._exact(close[0])
        # « Word » for « Microsoft Word », « Photoshop » for « Adobe Photoshop 2025 ».
        starts = [name for name in self.apps() if len(key) >= 4 and (name.endswith(key) or name.startswith(key))]
        if len(starts) == 1:
            return self._exact(starts[0])
        return None
