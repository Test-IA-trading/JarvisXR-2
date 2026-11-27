"""What Jarvis knows about the person, shared by the PC and the iPhone: the first name and
the notes (« Souviens-toi que… »). Stored as JSON in %APPDATA%\\JarvisPC; merged with the
iPhone's copy when they talk, so a note taken on one is known by the other."""
from __future__ import annotations

import json
import threading
import uuid
from datetime import datetime, timezone
from pathlib import Path

from .config import data_dir

TRIAL_PREFIX = "[essai]"


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def parse_time(stamp: str) -> datetime:
    """« 2026-11-25T10:00:00Z » (iPhone) or « …+00:00 » (PC); the oldest date when unreadable."""
    try:
        moment = datetime.fromisoformat(stamp.replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return datetime(1970, 1, 1, tzinfo=timezone.utc)
    return moment if moment.tzinfo else moment.replace(tzinfo=timezone.utc)


class Memory:
    def __init__(self, path: Path | None = None):
        self.path = path or data_dir() / "memory.json"
        self.lock = threading.Lock()
        self.name: str | None = None
        self.name_updated = "1970-01-01T00:00:00+00:00"
        self.notes: list[dict] = []
        self._load()

    def _load(self) -> None:
        if not self.path.exists():
            return
        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return
        self.name = data.get("name") or None
        self.name_updated = data.get("name_updated", self.name_updated)
        self.notes = [n for n in data.get("notes", []) if isinstance(n, dict) and n.get("text")]

    def _save(self) -> None:
        self.path.write_text(json.dumps(self.snapshot(), ensure_ascii=False, indent=2), encoding="utf-8")

    def snapshot(self) -> dict:
        return {"name": self.name, "name_updated": self.name_updated, "notes": list(self.notes)}

    def set_name(self, name: str | None) -> None:
        with self.lock:
            self.name = name
            self.name_updated = now_iso()
            self._save()

    def add_note(self, text: str) -> dict:
        note = {"id": str(uuid.uuid4()), "text": text.strip(), "created": now_iso()}
        with self.lock:
            self.notes.insert(0, note)
            self._save()
        return note

    def latest_notes(self, limit: int = 8) -> list[str]:
        return [n["text"] for n in self.notes if not n["text"].startswith(TRIAL_PREFIX)][:limit]

    def merge(self, other: dict) -> dict:
        """Union of both note lists (by id, newest first); the most recent first name wins.
        The iPhone writes ids in capitals (« 8D6E… ») and the PC in small letters: same note."""
        with self.lock:
            known = {str(n["id"]).lower() for n in self.notes if "id" in n}
            for note in other.get("notes", []) or []:
                if not (isinstance(note, dict) and note.get("text")):
                    continue
                note_id = str(note.get("id") or uuid.uuid4())
                if note_id.lower() in known:
                    continue
                self.notes.append({"id": note_id, "text": note["text"], "created": note.get("created") or now_iso()})
                known.add(note_id.lower())
            self.notes.sort(key=lambda n: parse_time(n.get("created", "")), reverse=True)
            other_updated = other.get("name_updated") or ""
            if "name" in other and parse_time(other_updated) > parse_time(self.name_updated):
                self.name = other.get("name") or None
                self.name_updated = other_updated
            self._save()
            return self.snapshot()

    def context_lines(self) -> list[str]:
        """The same lines as the iPhone gives its brain."""
        lines = []
        if self.name:
            lines.append(f"La personne qui te parle s'appelle {self.name} ; tu peux utiliser son prénom de temps en temps.")
        kept, used = [], 0
        for text in self.latest_notes():
            text = text[:140]
            if used + len(text) > 700:
                break
            kept.append(text)
            used += len(text)
        if kept:
            lines.append("Ce que cette personne t'a demandé de retenir, de la note la plus récente à la plus ancienne : " + " ; ".join(kept) + ".")
        return lines
