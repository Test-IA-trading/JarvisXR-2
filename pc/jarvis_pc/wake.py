"""The request addressed to Jarvis in what the microphone heard (same rules as
JarvisWakeWord.swift): the words after the last « Jarvis », or before it when nothing
follows; "" when Jarvis is only called; None when « Jarvis » is never said."""
from __future__ import annotations

import re
import unicodedata

SPELLINGS = {"jarvis", "jarvisse", "jarviss", "jarvice", "djarvis", "jarvys", "jarvi"}
CALL_WORDS = {"hey", "he", "eh", "ok", "okay", "dis", "dites", "bonjour", "salut", "allo", "alors"}
# « Dis Jarvis » is sometimes written as one word (« Dijardvis »).
CALL_PREFIXES = ("dis", "di", "hey", "he", "eh", "ok")
# One letter away from « jarvis », yet a French word.
NOT_JARVIS = {"parvis"}


def _fold(word: str) -> str:
    folded = unicodedata.normalize("NFD", word)
    return "".join(c for c in folded if unicodedata.category(c) != "Mn").lower()


def distance(a: str, b: str) -> int:
    """Edit distance (letters added, removed or changed)."""
    if not a:
        return len(b)
    if not b:
        return len(a)
    previous = list(range(len(b) + 1))
    for i, letter in enumerate(a, start=1):
        current = [i] + [0] * len(b)
        for j, other in enumerate(b, start=1):
            current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (letter != other))
        previous = current
    return previous[-1]


def _looks_like_jarvis(word: str) -> bool:
    return 5 <= len(word) <= 8 and word not in NOT_JARVIS and distance(word, "jarvis") <= 1


def is_jarvis(folded: str) -> bool:
    """« jarvis », a letter off (« jardvis »), or run together with « dis » (« dijarvis »)."""
    if folded in SPELLINGS or _looks_like_jarvis(folded):
        return True
    for prefix in CALL_PREFIXES:
        if folded.startswith(prefix):
            rest = folded[len(prefix):]
            if rest in SPELLINGS or _looks_like_jarvis(rest):
                return True
    return False


def command(transcript: str) -> str | None:
    last = None
    for match in re.finditer(r"[\w'’-]+", transcript):
        if is_jarvis(_fold(match.group(0))):
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
