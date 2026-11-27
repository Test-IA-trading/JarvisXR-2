"""French commands of the PC Jarvis. What is exact or local is answered here; the rest
goes to the brain (route returns None). Same wording as the iPhone where both apply."""
from __future__ import annotations

import os
import re
import unicodedata
import urllib.parse
import webbrowser
from dataclasses import dataclass, field
from datetime import datetime

from . import everyday, internet, mathsolver
from .memory import Memory

WEEKDAYS = ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"]
MONTHS = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"]

NOTE_PREFIXES = ["prends une note", "prend une note", "prends note", "nouvelle note", "enregistre une note", "note que",
                 "souviens toi que", "retiens que", "rappelle toi que"]
NAME_PREFIXES = ["je m'appelle", "appelle moi", "tu peux m'appeler", "vous pouvez m'appeler", "mon prenom est", "mon prenom c'est",
                 "mon nom est", "mon nom c'est"]
REFUSED_NAME_WORDS = {"un", "une", "le", "la", "les", "des", "du", "de", "mon", "ma", "mes", "ton", "ta", "quand", "si", "dans",
                      "demain", "ce", "cette", "vite", "plus", "encore", "moi", "comment", "quoi", "qui", "pas", "jarvis"}

# Applications and sites « Ouvre… » knows; a URI or a program name for Windows.
TARGETS = {
    "spotify": ("Spotify", "spotify:"),
    "chrome": ("Chrome", "chrome"),
    "google chrome": ("Chrome", "chrome"),
    "edge": ("Edge", "microsoft-edge:"),
    "firefox": ("Firefox", "firefox"),
    "explorateur": ("l'Explorateur de fichiers", "explorer"),
    "explorateur de fichiers": ("l'Explorateur de fichiers", "explorer"),
    "calculatrice": ("la Calculatrice", "calc"),
    "bloc notes": ("le Bloc-notes", "notepad"),
    "parametres": ("les Paramètres", "ms-settings:"),
    "reglages": ("les Paramètres", "ms-settings:"),
    "discord": ("Discord", "discord://"),
    "steam": ("Steam", "steam://open/main"),
    "youtube": ("YouTube", "https://www.youtube.com"),
    "google": ("Google", "https://www.google.com"),
    "gmail": ("Gmail", "https://mail.google.com"),
    "netflix": ("Netflix", "https://www.netflix.com"),
    "twitch": ("Twitch", "https://www.twitch.tv"),
    "wikipedia": ("Wikipédia", "https://fr.wikipedia.org"),
    "github": ("GitHub", "https://github.com"),
    "deepl": ("DeepL", "https://www.deepl.com/translator"),
    "amazon": ("Amazon", "https://www.amazon.fr"),
}


@dataclass
class Answer:
    spoken: str
    display: str = ""
    data: dict = field(default_factory=dict)

    def __post_init__(self):
        if not self.display:
            self.display = self.spoken


def normalize(text: str) -> str:
    folded = unicodedata.normalize("NFD", text.replace("’", "'"))
    folded = "".join(c for c in folded if unicodedata.category(c) != "Mn").lower()
    folded = re.sub(r"[,.?;:!\"«»()…]|(?<=[a-z])-(?=[a-z])", " ", folded)
    return " ".join(folded.split())


def strip_wake_word(text: str) -> str:
    for prefix in ("dis jarvis ", "hey jarvis ", "ok jarvis ", "eh jarvis ", "bonjour jarvis ", "jarvis "):
        if text.startswith(prefix):
            text = text[len(prefix):]
            break
    if text.endswith(" jarvis"):
        text = text[: -len(" jarvis")]
    return text


def original_after(original: str, words: int) -> str:
    """The user's own wording after the first `words` words (accents and capitals kept)."""
    tokens = re.findall(r"[^\s,.;:!?«»()\-]+", original)
    if words >= len(tokens):
        return ""
    start = original.find(tokens[words])
    return original[start:].strip(" ,.;:!?")


def clean_name(raw: str) -> str | None:
    words = raw.strip(" .,;:!?«»\"").split()
    if not 1 <= len(words) <= 3 or words[0].lower() in REFUSED_NAME_WORDS:
        return None
    parts = []
    for word in words:
        if len(word) > 24 or not all(ch.isalpha() or ch in "-'" for ch in word):
            return None
        parts.append("-".join(piece[:1].upper() + piece[1:] for piece in word.split("-")))
    return " ".join(parts)


class Router:
    def __init__(self, memory: Memory, settings, opener=None, browser=None):
        self.memory = memory
        self.settings = settings
        self.opener = opener or (lambda target: os.startfile(target))  # noqa: S606 (the user's own command)
        self.browser = browser or (lambda url: webbrowser.open(url))

    def route(self, original: str, now: datetime | None = None) -> Answer | None:
        now = now or datetime.now()
        text = normalize(original)
        request = strip_wake_word(text)
        if not request or request == "jarvis":
            return Answer("Oui ?", data={"listen": True})
        wake_words = len(text.split()) - len(request.split())

        def has(*phrases: str) -> bool:
            padded = f" {request} "
            return any(f" {phrase} " in padded for phrase in phrases)

        if has("tu m'entends", "vous m'entendez", "est ce que ca marche"):
            return Answer("Oui, je vous entends bien.")
        if request.split()[0] in ("bonjour", "salut", "bonsoir", "coucou", "hello") and len(request.split()) <= 3:
            return Answer(f"Bonjour {self.memory.name} ! Je vous écoute." if self.memory.name else "Bonjour ! Je vous écoute.")
        if has("c'est tout", "ce sera tout", "ca sera tout", "fin de la conversation"):
            return Answer("Très bien. Appelez-moi quand vous voulez.", data={"end": True})

        # What Jarvis knows about the person (shared with the iPhone).
        if has("comment je m'appelle", "je m'appelle comment", "quel est mon nom", "quel est mon prenom", "tu connais mon nom"):
            if self.memory.name:
                return Answer(f"Vous vous appelez {self.memory.name}.")
            return Answer("Je ne connais pas encore votre prénom. Dites par exemple : « Je m'appelle Tony ».")
        if has("oublie mon nom", "oublie mon prenom", "efface mon nom", "efface mon prenom"):
            self.memory.set_name(None)
            return Answer("C'est oublié : je ne vous appellerai plus par votre prénom.")
        if has("qu'est ce que tu sais sur moi", "que sais tu de moi", "que sais tu sur moi", "ce que tu sais sur moi"):
            return self._known_facts()
        for prefix in NAME_PREFIXES:
            if request.startswith(prefix + " "):
                name = clean_name(original_after(original, wake_words + len(prefix.split())))
                if name:
                    self.memory.set_name(name)
                    return Answer(f"Enchanté, {name}. Je m'en souviendrai.")
                break
        for prefix in NOTE_PREFIXES:
            if request == prefix or request.startswith(prefix + " "):
                body = original_after(original, wake_words + len(prefix.split()))
                if not body:
                    return Answer("Que dois-je noter ?")
                self.memory.add_note(body)
                return Answer("C'est noté.", f"Note enregistrée : {body}")
        if has("mes notes", "lis mes notes", "montre mes notes"):
            notes = self.memory.latest_notes(10)
            if not notes:
                return Answer("Vous n'avez aucune note.")
            return Answer(f"Vous avez {len(notes)} note{'s' if len(notes) > 1 else ''}.", "\n".join(f"{i + 1}. {n}" for i, n in enumerate(notes)))

        # The iPhone: a message waits there until Jarvis is opened on the phone.
        match = re.match(r"(?:envoie|dis|ecris)(?: le| ca| ceci)? (?:sur|a) mon (?:telephone|iphone|portable)(?: que)? (.+)", request)
        if match:
            message = original_after(original, wake_words + len(request.split()) - len(match.group(1).split()))
            return Answer("C'est envoyé sur votre téléphone : il le dira à sa prochaine ouverture.", f"Pour l'iPhone : {message}", {"to_phone": message})

        # Exact answers, as on the iPhone.
        exact = mathsolver.answer(original) or everyday.convert_answer(original) or everyday.date_answer(original, now.date())
        if exact:
            return Answer(exact[0], exact[1])
        if has("quelle heure", "l'heure", "il est quelle heure"):
            return Answer(f"Il est {now.hour} h {now.minute:02d}.")
        if has("quel jour", "quelle date", "on est le combien", "la date"):
            return Answer(f"Nous sommes le {WEEKDAYS[now.weekday()]} {now.day if now.day > 1 else '1er'} {MONTHS[now.month - 1]} {now.year}.")

        timer = re.search(r"(?:minuteur|timer|chrono)\D*?(\d+)\s*(seconde|secondes|minute|minutes|heure|heures)\b", request)
        if timer:
            value = int(timer.group(1))
            unit = timer.group(2)
            seconds = value * (1 if unit.startswith("seconde") else 60 if unit.startswith("minute") else 3600)
            return Answer(f"Minuteur de {value} {unit} lancé.", data={"timer_seconds": seconds, "timer_label": f"{value} {unit}"})

        # The PC itself.
        match = re.match(r"(?:ouvre|lance|demarre|ouvrir)(?: moi)? (?:l'|le |la |les )?(.+)", request)
        if match:
            target = match.group(1).strip()
            target = re.sub(r"\s+(?:sur le pc|s'il te plait|stp|svp)$", "", target)
            if target in TARGETS:
                label, uri = TARGETS[target]
                (self.browser if uri.startswith("http") else self.opener)(uri)
                return Answer(f"J'ouvre {label}.")
        match = re.match(r"(?:cherche|recherche|google)(?: moi)? (.+?)(?: sur (?:internet|google|le web|le net))?$", request)
        if match and has("sur internet", "sur google", "sur le web", "sur le net") or (match and request.startswith(("cherche sur internet", "recherche sur internet"))):
            # The user's own words, accents kept: « la recette des crêpes ».
            skip = wake_words + 1 + (1 if request.split()[1:2] == ["moi"] else 0)
            query = original_after(original, skip)
            query = re.sub(r"^sur\s+internet\s+", "", query, flags=re.IGNORECASE)
            query = re.sub(r"\s+sur\s+(?:internet|google|le web|le net)\s*[?!.]*$", "", query, flags=re.IGNORECASE).strip(" ?!.")
            self.browser("https://duckduckgo.com/?q=" + urllib.parse.quote(query))
            return Answer(f"Je cherche « {query} » sur Internet.")

        if self.settings.internet:
            answer = self._internet(original, request, has)
            if answer:
                return answer
        return None

    def _internet(self, original: str, request: str, has) -> Answer | None:
        match = re.match(r"ma ville (?:est|c'est) (.+)", request)
        if match:
            city = original_after(original, len(original.split()) - len(match.group(1).split()))
            self.settings.city = city
            self.settings.save()
            return Answer(f"C'est noté : je donnerai la météo de {city}.")
        if has("meteo", "quel temps", "il fait beau", "va t il pleuvoir", "il va pleuvoir"):
            match = re.search(r"\b(?:a|au|pour) ([a-z' -]+?)(?: demain| aujourd'hui)?$", request)
            city = match.group(1).strip() if match and match.group(1).strip() not in ("demain", "aujourd'hui") else self.settings.city
            if not city:
                return Answer("Dans quelle ville ? Dites par exemple : « Ma ville est Lyon ».")
            try:
                return Answer(internet.weather(city, tomorrow=has("demain")), data={"internet": "open-meteo"})
            except OSError:
                return Answer("Je n'arrive pas à joindre le service météo pour le moment.")
        if has("actualites", "les infos", "les nouvelles", "les titres", "quoi de neuf dans le monde"):
            try:
                titles = internet.news()
            except (OSError, ValueError):
                return Answer("Je n'arrive pas à joindre franceinfo pour le moment.")
            if not titles:
                return Answer("Je ne trouve pas de titres pour le moment.")
            return Answer("Voici les titres de franceinfo : " + " ; ".join(titles[:3]) + ".", "\n".join(titles), {"internet": "franceinfo"})
        match = re.match(r"(?:qui est|qui etait|c'est qui|parle moi de)\s+(.+)", request)
        if match:
            subject = original_after(original, len(original.split()) - len(match.group(1).split()))
            try:
                found = internet.wikipedia(subject)
            except (OSError, ValueError):
                found = None
            if found:
                return Answer(f"D'après Wikipédia : {found[1]}", f"{found[0]} — {found[1]}", {"internet": "wikipedia"})
        return None

    def _known_facts(self) -> Answer:
        notes = self.memory.latest_notes(10)
        parts = []
        if self.memory.name:
            parts.append(f"Vous vous appelez {self.memory.name}.")
        if not notes:
            parts.append("Je ne sais encore rien d'autre de vous : dites « Souviens-toi que… »." if self.memory.name else
                         "Je ne sais encore rien de vous. Dites « Je m'appelle… » ou « Souviens-toi que… ».")
        else:
            count = "une chose" if len(notes) == 1 else f"{len(notes)} choses"
            parts.append(f"Vous m'avez demandé de retenir {count} : " + " ; ".join(notes[:3]) + ".")
        return Answer(" ".join(parts))
