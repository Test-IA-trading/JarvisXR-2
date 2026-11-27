"""The PC's brain: a large model run by Ollama on this computer (Qwen3 30B by default).

Only localhost is used: Ollama stays closed to the network, and the iPhone reaches the
brain through Jarvis's own server, which checks the pairing code. Answers stream
sentence by sentence; LaTeX and markdown are turned into plain text for the voice."""
from __future__ import annotations

import json
import re
import time
import urllib.error
import urllib.request
from datetime import datetime

from . import mathsolver

OLLAMA = "http://127.0.0.1:11434"

WEEKDAYS = ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"]
MONTHS = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"]


# (what the user may say, the command it means): pairs, so the brain learns the rewording
# rather than copying an example.
COMMAND_EXAMPLES_PC = [
    ("J'ai envie de voir des vidéos de chats", "mets des vidéos de chats sur YouTube"),
    ("Tu peux me lancer Word ?", "ouvre Word"),
    ("Il me faudrait la recette des crêpes", "cherche sur Internet la recette des crêpes"),
    ("Mets-moi de la musique", "ouvre Spotify"),
    ("Réveille-moi dans 20 minutes", "minuteur 20 minutes"),
    ("N'oublie pas que je dois acheter du pain", "prends une note je dois acheter du pain"),
    ("Dis à mon téléphone que le dîner est prêt", "envoie sur mon téléphone que le dîner est prêt"),
    ("Est-ce que je vais avoir besoin d'un parapluie à Lyon demain ?", "quel temps fait-il à Lyon demain"),
]
COMMAND_EXAMPLES_IPHONE = [
    ("Passe-moi Paul", "appelle Paul"),
    ("Préviens Marie que je serai en retard", "envoie un message à Marie pour lui dire que je serai en retard"),
    ("Les pâtes, c'est 10 minutes", "minuteur pâtes 10 minutes"),
    ("Fais-moi penser à appeler maman demain à 18 h", "rappelle-moi d'appeler maman demain à 18 h"),
    ("J'ai quoi de prévu demain ?", "qu'est-ce que j'ai demain"),
    ("J'ai beaucoup marché aujourd'hui ?", "combien de pas aujourd'hui"),
    ("Fais voir la photo que je viens de prendre", "montre-moi ma dernière photo"),
    ("Il me faut un parapluie demain ?", "quel temps fait-il demain"),
    ("N'oublie pas que je dois acheter du pain", "prends une note je dois acheter du pain"),
    ("Mets des vidéos de chats sur l'ordi", "sur le PC, mets des vidéos de chats sur YouTube"),
]


def _examples(pairs: list[tuple[str, str]]) -> str:
    return " ; ".join(f"« {said} » → COMMANDE: {command}" for said, command in pairs)


COMMAND_RULE = (
    "écris seulement « COMMANDE: » suivi de la demande reformulée simplement, sur une seule ligne, en gardant les mots de "
    "l'utilisateur pour ce qu'il cherche, veut voir ou veut dire. "
)
PC_COMMANDS = (
    "Si la demande est une action que Jarvis PC sait faire, ne réponds pas par une phrase : " + COMMAND_RULE +
    "Exemples : " + _examples(COMMAND_EXAMPLES_PC) + ". "
    "Jarvis PC sait ouvrir une application, un dossier ou un site, chercher sur Internet ou sur YouTube, lancer un minuteur, prendre et "
    "lire des notes, donner la météo et les titres de l'actualité, envoyer un message vers l'iPhone et calculer. "
    "Pour une question ou une conversation, réponds normalement, sans « COMMANDE: »."
)
IPHONE_COMMANDS = (
    "La demande vient de l'iPhone. Si c'est une action que Jarvis sait faire, ne réponds pas par une phrase : " + COMMAND_RULE +
    "Exemples : " + _examples(COMMAND_EXAMPLES_IPHONE) + ". "
    "L'iPhone sait appeler un contact, lui écrire un message ou donner son numéro, lancer des minuteurs, créer des rappels, lire l'agenda, "
    "donner les pas du jour, compter et montrer les photos, donner la météo, les actualités et l'endroit où l'on est, prendre des notes, "
    "et faire agir le PC (« sur le PC, … »). Pour une question ou une conversation, réponds normalement, sans « COMMANDE: »."
)


def command_in(answer: str) -> str | None:
    """The request reworded by the brain when it chose an action (« COMMANDE: ouvre YouTube »), else None."""
    text = answer.strip()
    if not text.upper().startswith("COMMANDE"):
        return None
    rest = text[len("COMMANDE"):].lstrip(" :").strip()
    rest = (rest.splitlines() or [""])[0].strip().strip("«»\"' ").strip()
    return rest or None


def may_be_command(partial: str) -> bool:
    """True while the text written so far could still become « COMMANDE: … » (never spoken)."""
    head = partial.lstrip()[:9].upper()
    return "COMMANDE:".startswith(head) or head.startswith("COMMANDE")


def system_prompt(context: list[str], now: datetime | None = None, extra: str | None = None) -> str:
    now = now or datetime.now()
    date = f"{WEEKDAYS[now.weekday()]} {now.day} {MONTHS[now.month - 1]} {now.year}, {now:%H:%M}"
    lines = [
        "Tu es JARVIS, l'assistant personnel de l'utilisateur, sur son PC et son iPhone : cultivé, précis et calme, avec une pointe d'humour discret.",
        "Vouvoie toujours l'utilisateur, avec la courtoisie d'un majordome.",
        "Réponds toujours en français, comme dans une vraie conversation à voix haute : des phrases complètes, fluides et bien reliées "
        "entre elles, comme le dirait une personne cultivée, jamais un style télégraphique. Va droit à l'essentiel, en deux ou trois "
        "phrases et une soixantaine de mots au plus en général, sauf si l'utilisateur demande plus de détails ou si un calcul demande "
        "quelques étapes.",
        "Ta réponse est lue à voix haute : pas de listes, pas de titres, pas de markdown, pas d'émoji. Écris les formules en texte simple, sans LaTeX, par exemple x³/3 + C.",
        "Tu sais faire des mathématiques, de la physique, de la chimie, de l'histoire, du droit, du code et de la culture générale : réponds même aux questions difficiles, en donnant d'abord le résultat puis une courte explication.",
        "Quand des extraits de Wikipédia ou d'autres sites sont fournis, réponds d'après eux, fidèlement, avec tes "
        "mots, en gardant ce sur quoi ils s'accordent et sans rien ajouter dont tu n'es pas certain. Sinon, pour un fait récent ou qui change souvent, dis que tu ne peux pas le vérifier.",
        f"Nous sommes le {date}.",
    ]
    if extra:
        lines.append(extra)
    lines.extend(line for line in context if line)
    return "\n".join(lines)


def clean(text: str) -> str:
    """Plain text for screen and voice: no thinking, LaTeX or markdown."""
    text = re.sub(r"(?s)<think>.*?</think>", "", text)
    if "<think>" in text:
        text = text[: text.index("<think>")]
    text = mathsolver.plain_math(text)
    for symbol in ("**", "__", "`", "#"):
        text = text.replace(symbol, "")
    lines = []
    for line in text.splitlines():
        line = line.strip()
        for bullet in ("- ", "* ", "• ", "– "):
            if line.startswith(bullet):
                line = line[len(bullet):]
        if line:
            lines.append(line)
    return " ".join(" ".join(lines).split())


class OllamaBrain:
    def __init__(self, model: str, fallback: str | None = None, host: str = OLLAMA, max_tokens: int = 400):
        self.model = model
        self.fallback = fallback
        self.host = host
        self.max_tokens = max_tokens
        self.last_tokens_per_second = 0.0

    def installed_models(self) -> list[str]:
        try:
            with urllib.request.urlopen(self.host + "/api/tags", timeout=3) as response:
                return [m["name"] for m in json.loads(response.read().decode("utf-8")).get("models", [])]
        except (OSError, ValueError, urllib.error.URLError):
            return []

    def active_model(self) -> str | None:
        models = self.installed_models()
        for name in (self.model, self.fallback):
            if name and name in models:
                return name
        return None

    def ask(self, question: str, history: list[dict] | None = None, context: list[str] | None = None, on_text=None, timeout: float = 300,
            commands: str | None = None) -> str:
        """The answer to `question`; `on_text` receives the cleaned text written so far. With `commands`
        (PC_COMMANDS, IPHONE_COMMANDS), an action comes back as « COMMANDE: … » (see command_in)."""
        model = self.active_model()
        if model is None:
            raise RuntimeError("Le cerveau du PC n'est pas prêt : Ollama ne répond pas, ou le modèle n'est pas installé.")
        # The sources' text goes with the question itself: the brain then keeps to it.
        excerpts = [line for line in context or [] if line.startswith("Extrait de ")]
        others = [line for line in context or [] if line not in excerpts]
        messages = [{"role": "system", "content": system_prompt(others, extra=commands)}]
        for turn in (history or [])[-6:]:
            if turn.get("user") and turn.get("assistant"):
                messages.append({"role": "user", "content": turn["user"]})
                messages.append({"role": "assistant", "content": turn["assistant"]})
        content = question
        if len(excerpts) == 1:
            content += "\n\n(" + excerpts[0] + ")"
        elif excerpts:
            content += ("\n\n(Sources trouvées sur Internet :\n" + "\n".join(excerpts) +
                        "\nRéponds d'après ce sur quoi ces sources s'accordent, et dis brièvement d'où cela vient, par exemple "
                        "« selon Wikipédia et legifrance.gouv.fr ». Si elles se contredisent, dis-le. N'utilise pas une source "
                        "qui parle d'autre chose.)")
        if commands:
            # After a few exchanges, a model imitates its earlier answers: the rule is repeated here.
            content += "\n\n(Rappel : si c'est une action que Jarvis sait faire, écris seulement « COMMANDE: … ». Sinon, réponds en vouvoyant.)"
        messages.append({"role": "user", "content": content})
        # Facts from the sources are told as they are, without embroidery.
        grounded = bool(excerpts)
        body = json.dumps({
            "model": model,
            "messages": messages,
            "stream": True,
            "think": False,
            "keep_alive": "30m",
            "options": {"temperature": 0.3 if grounded else 0.6, "num_ctx": 4096, "num_predict": self.max_tokens},
        }).encode("utf-8")
        request = urllib.request.Request(self.host + "/api/chat", data=body, headers={"Content-Type": "application/json"})
        raw = ""
        started = time.time()
        tokens = 0
        with urllib.request.urlopen(request, timeout=timeout) as response:
            for line in response:
                if not line.strip():
                    continue
                chunk = json.loads(line.decode("utf-8"))
                piece = (chunk.get("message") or {}).get("content", "")
                if piece:
                    raw += piece
                    if on_text:
                        on_text(clean(raw))
                if chunk.get("done"):
                    tokens = chunk.get("eval_count", 0)
                    duration = chunk.get("eval_duration", 0) / 1e9
                    self.last_tokens_per_second = tokens / duration if duration else tokens / max(time.time() - started, 0.001)
                    break
        answer = clean(raw)
        if not answer:
            raise RuntimeError("Le cerveau du PC n'a rien répondu.")
        return answer


class SentenceStreamer:
    """Hands out complete sentences of a growing text, as on the iPhone."""

    def __init__(self):
        self.emitted = 0

    def new_sentences(self, text: str, final: bool) -> list[str]:
        sentences, start = [], self.emitted
        for index in range(self.emitted, len(text)):
            if text[index] in ".!?…" and index + 1 < len(text) and text[index + 1] in " \n":
                sentence = text[start:index + 1].strip()
                if sentence:
                    sentences.append(sentence)
                start = index + 1
        if final:
            rest = text[start:].strip()
            if rest:
                sentences.append(rest)
            start = len(text)
        self.emitted = start
        return sentences
