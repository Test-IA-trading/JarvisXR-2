"""The request addressed to Jarvis in what the microphone heard (same rules as
JarvisWakeWord.swift): the words after the last « Jarvis », or before it when nothing
follows; "" when Jarvis is only called; None when « Jarvis » is never said."""
from __future__ import annotations

import re
import unicodedata

SPELLINGS = {"jarvis", "jarvisse", "jarviss", "jarvice", "djarvis", "jarvys", "jarvi"}
CALL_WORDS = {"hey", "he", "eh", "ok", "okay", "dis", "dites", "bonjour", "salut", "allo", "alors"}


def _fold(word: str) -> str:
    folded = unicodedata.normalize("NFD", word)
    return "".join(c for c in folded if unicodedata.category(c) != "Mn").lower()


def command(transcript: str) -> str | None:
    last = None
    for match in re.finditer(r"[\w'’-]+", transcript):
        if _fold(match.group(0)) in SPELLINGS:
            last = match
    if last is None:
        return None
    trim = " \t\n,.;:!?«»\"()-–—…"
    after = transcript[last.end():].strip(trim)
    if after:
        return after
    before = transcript[: last.start()].strip(trim)
    words = [w for w in re.split(r"[^\w]+", _fold(before)) if w]
    if not words or all(w in CALL_WORDS for w in words):
        return ""
    return before
