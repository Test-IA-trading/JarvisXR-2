"""« Qu'est-ce que l'arrêt Blanco ? », « Qui était Marie Curie ? »: the subject to look up on
Wikipédia before the brain answers, so it explains from the article instead of from memory.
Same rule as the iPhone (JarvisWikipediaAnswer.subject)."""
from __future__ import annotations

import re

from .phrasing import rewrite
from .router import normalize, original_after, strip_wake_word

PREFIXES = [
    "cherche sur wikipedia", "wikipedia", "qui est", "qui etait", "qui sont", "qui etaient", "qu'est ce que c'est que",
    "qu'est ce qu'un", "qu'est ce qu'une", "qu'est ce que", "c'est quoi", "parle moi de", "parle moi du", "parle moi des",
    "parle moi", "explique moi", "definition de", "definis", "que veut dire", "que signifie",
]
PERSONAL_WORDS = {
    "je", "tu", "il", "elle", "on", "nous", "vous", "ils", "elles", "ce", "ca", "cela", "ceci", "moi", "toi", "lui",
    "mon", "ma", "mes", "ton", "ta", "tes", "son", "sa", "ses", "notre", "nos", "votre", "vos", "leur", "leurs",
    "jarvis", "que", "quoi", "qui", "y", "l'on", "comment", "pourquoi", "combien",
}
PERSONAL_ELISIONS = ("j'", "t'", "m'", "s'", "c'", "qu'", "n'")
LONELY = {"la", "le", "les", "ici", "present", "dehors", "ca", "tout"}


def knowledge_subject(question: str) -> str | None:
    """The subject in the user's own words, or None when Wikipédia is not the place to look."""
    original = rewrite(question)
    text = normalize(original)
    request = strip_wake_word(text)
    wake_words = len(text.split()) - len(request.split())
    for prefix in PREFIXES:
        if request != prefix and not request.startswith(prefix + " "):
            continue
        subject = original_after(original, wake_words + len(prefix.split())).strip(" ?!.,;:«»\"")
        if prefix == "parle moi":
            subject = re.sub(r"^(?:de |d'|d’)", "", subject, flags=re.IGNORECASE)
        words = normalize(subject).split()
        if not words or len(words) > 8 or any(ch.isdigit() for ch in subject):
            return None
        if words[0] in PERSONAL_WORDS or words[0].startswith(PERSONAL_ELISIONS) or " ".join(words) in LONELY:
            return None
        return subject
    return None


def passage(text: str, subject: str, limit: int = 450) -> str:
    """The sentences of a web page that speak of the subject, in the page's order, up to `limit`
    characters: what the brain compares with the other sources."""
    keys = {word.split("'")[-1] for word in normalize(subject).split()}
    keys = {word for word in keys if len(word) > 3} or keys
    sentences = re.split(r"(?<=[.!?])\s+", " ".join(text.split()))
    scored = [(sum(key in normalize(sentence) for key in keys), index) for index, sentence in enumerate(sentences)
              if 30 < len(sentence) < 400]
    chosen, used = [], 0
    for score, index in sorted(scored, key=lambda item: (-item[0], item[1])):
        if score == 0 or used + len(sentences[index]) > limit:
            continue
        chosen.append(index)
        used += len(sentences[index]) + 1
    return " ".join(sentences[index] for index in sorted(chosen))
