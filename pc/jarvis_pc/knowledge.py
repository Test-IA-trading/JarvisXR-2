"""Jarvis's own long-term memory, inspired by Obsidian: one Markdown note per thing worth
keeping (a preference, a habit, a fact about the user, a correction, a verified answer),
linked to the people, places and subjects it mentions ([[Lyon]]). It lives in the
« Mémoire Jarvis » folder of %APPDATA%\\JarvisPC, which Obsidian can open as a vault.

Before each answer, only the notes relevant to the question are given to the brain (a
BM25 search, widened along the links), never the whole memory. After an exchange, what
the user said about themselves is learned, without duplicates: a note that says the same
thing is updated instead. Verified answers are kept for a while, so a question already
asked is answered from what was checked; nothing that changes quickly (weather, time,
news) is cached. The iPhone gets a copy of the durable notes when it synchronizes.

Distinct from Claude Code's own memory: this one belongs to Jarvis and the user."""
from __future__ import annotations

import json
import math
import re
import threading
import unicodedata
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

from .config import data_dir

KINDS = ("preference", "habitude", "fait", "correction", "reponse")
LABELS = {"preference": "Préférence", "habitude": "Habitude", "fait": "Fait", "correction": "Correction", "reponse": "Réponse vérifiée"}
STOPWORDS = set("""
a au aux avec ce ces cet cette c ca d de des du elle elles en est et etre eu il ils j je l la le les leur lui m ma mais me
mes moi mon n ne ni nos notre nous on ou par pas pour qu que qui s sa se ses si son sont sur t ta te tes toi ton tu un une
vos votre vous y quoi quel quelle quels quelles comment est-ce dis jarvis tres plus moins bien fait faire peux peut veux
""".split())
# What changes too fast to be answered from memory.
VOLATILE = ("meteo", "temps qu'il fait", "heure", "aujourd'hui", "demain", "actualite", "actualites", "news", "prix", "cours",
            "score", "resultat du match", "en ce moment", "maintenant", "ce soir", "cette semaine", "trafic", "bourse")
ANSWER_LIFETIME = timedelta(days=30)
STALE_AFTER = timedelta(days=180)


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def parse_time(stamp: str) -> datetime:
    try:
        moment = datetime.fromisoformat(str(stamp).replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return datetime(1970, 1, 1, tzinfo=timezone.utc)
    return moment if moment.tzinfo else moment.replace(tzinfo=timezone.utc)


def fold(text: str) -> str:
    folded = unicodedata.normalize("NFD", text.lower().replace("’", "'").replace("œ", "oe").replace("æ", "ae"))
    return "".join(c for c in folded if unicodedata.category(c) != "Mn")


def tokens(text: str) -> list[str]:
    words = re.findall(r"[a-z0-9]+", fold(text).replace("'", " "))
    return [w[:-1] if len(w) > 4 and w.endswith("s") else w for w in words if w not in STOPWORDS and len(w) > 1]


def entities(text: str) -> list[str]:
    """Names in a note: [[links]] and capitalized words that do not start a sentence."""
    found = re.findall(r"\[\[([^\]]+)\]\]", text)
    for match in re.finditer(r"(?<![.!?]\s)(?<!^)\b([A-ZÀ-Ý][a-zà-ÿ]+(?:[ -][A-ZÀ-Ý][a-zà-ÿ]+)*)", text):
        if match.group(1) not in found and match.group(1) not in ("Jarvis", "Monsieur", "JARVIS"):
            found.append(match.group(1))
    return found[:8]


def is_volatile(question: str) -> bool:
    folded = fold(question)
    return any(word in folded for word in VOLATILE)


def similarity(a: str, b: str) -> float:
    left, right = set(tokens(a)), set(tokens(b))
    if not left or not right:
        return 0.0
    return len(left & right) / len(left | right)


# What the user says about themselves: (pattern on folded text, kind, how to write it down).
LEARNING_RULES = [
    (r"\bje (?:prefere|prefererais) (.+)", "preference", "L'utilisateur préfère {0}."),
    (r"\bj'(?:aime|adore) (?:bien )?(.+)", "preference", "L'utilisateur aime {0}."),
    (r"\bje (?:n'aime|deteste) (?:pas )?(.+)", "preference", "L'utilisateur n'aime pas {0}."),
    (r"\bappelle[ -]moi (.+)", "preference", "L'utilisateur veut être appelé {0}."),
    (r"\bj'habite (?:a |au |en |aux )?(.+)", "fait", "L'utilisateur habite {0}."),
    (r"\bje (?:vis|demeure) (?:a |au |en |aux )(.+)", "fait", "L'utilisateur habite {0}."),
    (r"\bje travaille (.+)", "fait", "L'utilisateur travaille {0}."),
    (r"\bje suis (?:ne|nee) (.+)", "fait", "L'utilisateur est né {0}."),
    (r"\bmon anniversaire (?:est|c'est) (.+)", "fait", "L'anniversaire de l'utilisateur est {0}."),
    (r"\b(?:mon|ma|mes) ([^\W\d_][\w' ]{2,30}?) (?:s'appelle|s'appellent|est|sont) (.+)", "fait", "{0} de l'utilisateur : {1}."),
    # Habits keep the user's own sentence: « je cours » is not turned into a wrong conjugation.
    (r"\b((?:tous les|chaque) (?:matins?|soirs?|jours?|lundis?|mardis?|mercredis?|jeudis?|vendredis?|samedis?|dimanches?),? je .+)", "habitude", "Habitude de l'utilisateur : « {0} »."),
    (r"\b((?:d'habitude|en general|souvent),? je .+)", "habitude", "Habitude de l'utilisateur : « {0} »."),
    (r"\b(?:reponds|parle)[ -]moi (.+)", "preference", "L'utilisateur veut des réponses {0}."),
]
CORRECTION = re.compile(r"^(?:non|mais non|pas du tout|c'est faux|faux|tu te trompes|ce n'est pas ca|c'est pas ca)\b[ ,.!]*(.*)")


def original_span(original: str, folded_match: str) -> str:
    """The user's own words (accents, capitals) for a piece found in the folded text."""
    # Each original character may fold to several (« œ » → « oe »): positions are mapped one by one.
    folded, origin = "", []
    for index, char in enumerate(original):
        piece = fold(char)
        folded += piece
        origin.extend([index] * len(piece))
    start = folded.find(folded_match)
    if start < 0 or not folded_match:
        return folded_match
    end = origin[start + len(folded_match) - 1] + 1
    return original[origin[start]:end]


class Knowledge:
    def __init__(self, folder: Path | None = None):
        self.folder = folder or data_dir() / "Mémoire Jarvis"
        self.folder.mkdir(parents=True, exist_ok=True)
        self.lock = threading.RLock()
        self.notes: dict[str, dict] = {}
        self._load()

    # Storage: Markdown with a small header, readable and editable in Obsidian.

    def _path(self, note: dict) -> Path:
        return self.folder / f"{note['kind']}-{note['id'][:8]}.md"

    def _load(self) -> None:
        for path in self.folder.glob("*.md"):
            try:
                note = self._parse(path.read_text(encoding="utf-8"))
            except (OSError, ValueError):
                continue
            if note:
                self.notes[note["id"]] = note

    @staticmethod
    def _parse(text: str) -> dict | None:
        match = re.match(r"(?s)^---\n(.*?)\n---\n(.*)$", text)
        if not match:
            return None
        header = dict(line.split(": ", 1) for line in match.group(1).splitlines() if ": " in line)
        body = match.group(2).strip()
        body = re.sub(r"(?s)\n*Liens : .*$", "", body).strip()
        if header.get("kind") not in KINDS or not header.get("id") or not body:
            return None
        note = {"id": header["id"], "kind": header["kind"], "text": body, "created": header.get("created", now_iso()),
                "updated": header.get("updated", now_iso()), "uses": int(header.get("uses", "0") or 0), "source": header.get("source", "pc")}
        if header.get("question"):
            note["question"] = json.loads(header["question"])
        if header.get("expires"):
            note["expires"] = header["expires"]
        return note

    def _save(self, note: dict) -> None:
        header = [f"id: {note['id']}", f"kind: {note['kind']}", f"created: {note['created']}", f"updated: {note['updated']}",
                  f"uses: {note.get('uses', 0)}", f"source: {note.get('source', 'pc')}"]
        if note.get("question"):
            header.append("question: " + json.dumps(note["question"], ensure_ascii=False))
        if note.get("expires"):
            header.append(f"expires: {note['expires']}")
        links = " ".join(f"[[{name}]]" for name in entities(note["text"] + " " + note.get("question", "")))
        text = "---\n" + "\n".join(header) + "\n---\n" + note["text"] + ("\n\nLiens : " + links if links else "") + "\n"
        self._path(note).write_text(text, encoding="utf-8")

    def _delete(self, note: dict) -> None:
        self.notes.pop(note["id"], None)
        try:
            self._path(note).unlink()
        except OSError:
            pass

    # Writing

    def remember(self, text: str, kind: str, source: str = "pc", question: str | None = None, lifetime: timedelta | None = None) -> dict:
        """Adds a note, or updates the one that already says the same (no duplicates). A new
        value for the same thing (« J'habite à Lyon » after « à Paris ») replaces the old one."""
        text = " ".join(text.split())
        with self.lock:
            same = self._same(text, kind, question)
            stamp = now_iso()
            if same:
                if same["text"] != text and kind != "reponse":
                    same["previous"] = same["text"]
                same.update(text=text, updated=stamp, source=source)
                if question:
                    same["question"] = question
                note = same
            else:
                note = {"id": str(uuid.uuid4()), "kind": kind, "text": text, "created": stamp, "updated": stamp, "uses": 0, "source": source}
                if question:
                    note["question"] = question
                self.notes[note["id"]] = note
            if lifetime:
                note["expires"] = (datetime.now(timezone.utc) + lifetime).isoformat(timespec="seconds")
            self._save(note)
            return note

    def _same(self, text: str, kind: str, question: str | None) -> dict | None:
        best, best_score = None, 0.0
        for note in self.notes.values():
            if note["kind"] != kind and not {note["kind"], kind} <= {"fait", "correction"}:
                continue
            score = similarity(question or text, note.get("question") or note["text"]) if kind == "reponse" else similarity(text, note["text"])
            # The same subject with another value (« habite Lyon » / « habite Paris »): same key words but one.
            if kind != "reponse":
                key = 2 if kind in ("fait", "correction") else 4
                left, right = tokens(text), tokens(note["text"])
                if len(left) > key and len(right) > key and left[:key] == right[:key]:
                    score = max(score, 0.7)
            if score > best_score:
                best, best_score = note, score
        return best if best_score >= 0.6 else None

    def forget(self, request: str) -> dict | None:
        """Removes the note that best matches « oublie que… »."""
        with self.lock:
            found = self.search(request, limit=1, kinds=KINDS, minimum=0.5)
            if not found:
                return None
            self._delete(found[0])
            return found[0]

    def learn(self, said: str, answer: str = "", previous_question: str | None = None) -> list[dict]:
        """What the user just said about themselves, or a correction of Jarvis's last answer."""
        learned = []
        folded = fold(said).strip(" ?!.")
        correction = CORRECTION.match(folded)
        if correction and previous_question and len(correction.group(1)) > 3:
            right = original_span(said, correction.group(1)).strip(" .!")
            learned.append(self.remember(f"À la question « {previous_question} », la bonne réponse selon l'utilisateur : {right}.", "correction",
                                         question=previous_question))
            # A cached answer that was just contradicted is not trusted any more.
            for note in list(self.notes.values()):
                if note["kind"] == "reponse" and similarity(note.get("question", ""), previous_question) >= 0.6:
                    self._delete(note)
        if "?" in said:
            return learned
        for pattern, kind, template in LEARNING_RULES:
            match = re.search(pattern, folded)
            if not match:
                continue
            parts = [original_span(said, group).strip(" .!,") for group in match.groups()]
            if any(len(part) < 2 or len(part) > 120 for part in parts):
                continue
            sentence = template.format(*parts)
            learned.append(self.remember(sentence[:1].upper() + sentence[1:], kind))
            break
        return learned

    def cache_answer(self, question: str, answer: str, sources: list[str]) -> dict | None:
        """A verified answer (from sources) to a question that does not change quickly."""
        if not sources or is_volatile(question) or len(answer) < 20:
            return None
        names = sorted({line[len("Extrait de "):].split(" : ")[0].split(" sur « ")[0] for line in sources if line.startswith("Extrait de ")})
        text = answer + (" (Sources : " + ", ".join(names) + ".)" if names else "")
        return self.remember(text, "reponse", question=question, lifetime=ANSWER_LIFETIME)

    def merge(self, items: list[dict], source: str = "iphone") -> None:
        """Notes from the iPhone: the most recently updated version of each wins."""
        with self.lock:
            for item in items or []:
                if not isinstance(item, dict):
                    continue
                known = self.notes.get(str(item.get("id")))
                if item.get("deleted"):
                    if known:
                        self._delete(known)
                    continue
                if item.get("kind") not in KINDS or not item.get("text"):
                    continue
                if known and parse_time(known["updated"]) >= parse_time(item.get("updated", "")):
                    continue
                if known:
                    known.update(text=item["text"], updated=item.get("updated") or now_iso(), source=source)
                    self._save(known)
                elif self._same(item["text"], item["kind"], item.get("question")) is None:
                    # Kept under the iPhone's id, so that a later deletion there finds it here.
                    stamp = item.get("updated") or now_iso()
                    note = {"id": str(item.get("id") or uuid.uuid4()), "kind": item["kind"], "text": " ".join(str(item["text"]).split()), "created": stamp,
                            "updated": stamp, "uses": 0, "source": source}
                    self.notes[note["id"]] = note
                    self._save(note)

    # Reading

    def _expired(self, note: dict) -> bool:
        return bool(note.get("expires")) and parse_time(note["expires"]) < datetime.now(timezone.utc)

    def search(self, query: str, limit: int = 5, kinds=KINDS, minimum: float = 0.6) -> list[dict]:
        """BM25 over the notes, then the notes linked to the best ones (shared [[names]])."""
        terms = tokens(query)
        with self.lock:
            notes = [n for n in self.notes.values() if n["kind"] in kinds and not self._expired(n)]
        if not terms or not notes:
            return []
        documents = [tokens(n["text"] + " " + n.get("question", "")) for n in notes]
        average = sum(len(d) for d in documents) / len(documents)
        frequency = {t: sum(1 for d in documents if t in d) for t in set(terms)}
        scores = []
        for note, words in zip(notes, documents):
            score = 0.0
            for term in terms:
                count = words.count(term)
                if count:
                    idf = math.log(1 + (len(notes) - frequency[term] + 0.5) / (frequency[term] + 0.5))
                    score += idf * count * 2.2 / (count + 1.2 * (0.25 + 0.75 * len(words) / max(average, 1)))
            scores.append(score)
        ranked = sorted(zip(scores, range(len(notes))), reverse=True)
        best = [(s, notes[i]) for s, i in ranked if s >= minimum][:limit]
        # The graph: a note sharing a name with a found one comes along (« Lyon » → « Ma sœur vit à Lyon »).
        names = {e for _, n in best for e in entities(n["text"])}
        if names and len(best) < limit:
            chosen = {n["id"] for _, n in best}
            for note in notes:
                if note["id"] not in chosen and names & set(entities(note["text"])):
                    best.append((0.0, note))
                    if len(best) >= limit:
                        break
        return [n for _, n in best]

    def context_lines(self, question: str, limit: int = 5) -> list[str]:
        """The few memories relevant to `question`, for the brain (empty when nothing fits)."""
        found = self.search(question, limit=limit)
        lines = []
        stale_before = datetime.now(timezone.utc) - STALE_AFTER
        with self.lock:
            for note in found:
                note["uses"] = note.get("uses", 0) + 1
                date = parse_time(note["updated"]).strftime("%d/%m/%Y")
                old = " (ancien, à confirmer si c'est important)" if note["kind"] == "fait" and parse_time(note["updated"]) < stale_before else ""
                if note["kind"] == "reponse":
                    lines.append(f"Réponse déjà vérifiée le {date} à « {note.get('question', '')} » : {note['text']}")
                else:
                    lines.append(f"Souvenir ({LABELS[note['kind']].lower()}, {date}){old} : {note['text']}")
        if lines:
            lines.insert(0, "Mémoire de Jarvis, à utiliser seulement si c'est pertinent :")
        return lines

    def export(self, limit: int = 80) -> list[dict]:
        """The durable notes for the iPhone (not the cached answers), most used first."""
        with self.lock:
            notes = [n for n in self.notes.values() if n["kind"] != "reponse"]
        notes.sort(key=lambda n: (n.get("uses", 0), n["updated"]), reverse=True)
        return [{k: n[k] for k in ("id", "kind", "text", "updated") if k in n} for n in notes[:limit]]

    def summary(self) -> str:
        """« Qu'est-ce que tu sais sur moi ? »"""
        with self.lock:
            durable = [n for n in self.notes.values() if n["kind"] in ("preference", "habitude", "fait")]
        if not durable:
            return "Je n'ai encore rien retenu de durable à votre sujet, Monsieur."
        durable.sort(key=lambda n: n["updated"], reverse=True)
        return "Voici ce que j'ai retenu : " + " ".join(n["text"] for n in durable[:8])
