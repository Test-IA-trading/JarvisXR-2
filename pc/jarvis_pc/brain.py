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


def system_prompt(context: list[str], now: datetime | None = None) -> str:
    now = now or datetime.now()
    date = f"{WEEKDAYS[now.weekday()]} {now.day} {MONTHS[now.month - 1]} {now.year}, {now:%H:%M}"
    lines = [
        "Tu es JARVIS, l'assistant personnel de l'utilisateur, sur son PC et son iPhone : cultivé, précis et calme, avec une pointe d'humour discret.",
        "Réponds toujours en français, naturellement, en une à trois phrases courtes, sauf si l'utilisateur demande plus de détails ou si un calcul demande quelques étapes.",
        "Ta réponse est lue à voix haute : pas de listes, pas de titres, pas de markdown, pas d'émoji. Écris les formules en texte simple, sans LaTeX, par exemple x³/3 + C.",
        "Tu sais faire des mathématiques, de la physique, de la chimie, de l'histoire, du code et de la culture générale : réponds même aux questions difficiles, en donnant d'abord le résultat puis une courte explication.",
        "Si une information fournie ci-dessous vient d'Internet, appuie-toi dessus ; sinon, pour un fait récent ou qui change souvent, dis que tu ne peux pas le vérifier.",
        f"Nous sommes le {date}.",
    ]
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

    def ask(self, question: str, history: list[dict] | None = None, context: list[str] | None = None, on_text=None, timeout: float = 300) -> str:
        """The answer to `question`; `on_text` receives the cleaned text written so far."""
        model = self.active_model()
        if model is None:
            raise RuntimeError("Le cerveau du PC n'est pas prêt : Ollama ne répond pas, ou le modèle n'est pas installé.")
        messages = [{"role": "system", "content": system_prompt(context or [])}]
        for turn in (history or [])[-6:]:
            if turn.get("user") and turn.get("assistant"):
                messages.append({"role": "user", "content": turn["user"]})
                messages.append({"role": "assistant", "content": turn["assistant"]})
        messages.append({"role": "user", "content": question})
        body = json.dumps({
            "model": model,
            "messages": messages,
            "stream": True,
            "think": False,
            "keep_alive": "30m",
            "options": {"temperature": 0.6, "num_ctx": 4096, "num_predict": self.max_tokens},
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
