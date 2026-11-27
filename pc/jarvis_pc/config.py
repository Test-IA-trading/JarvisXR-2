"""Settings of the PC Jarvis, kept in %APPDATA%\\JarvisPC (never in the repository)."""
from __future__ import annotations

import json
import os
import secrets
from dataclasses import asdict, dataclass, field
from pathlib import Path

DEFAULT_MODEL = "qwen3:30b-a3b-instruct-2507-q4_K_M"
FALLBACK_MODEL = "qwen3:8b"
DEFAULT_PORT = 8765


def data_dir() -> Path:
    base = os.environ.get("JARVIS_PC_HOME") or os.path.join(os.environ.get("APPDATA") or str(Path.home()), "JarvisPC")
    path = Path(base)
    path.mkdir(parents=True, exist_ok=True)
    return path


def cache_dir() -> Path:
    """Downloaded voice and speech models, shared by every run (even the self-test)."""
    base = os.environ.get("JARVIS_PC_CACHE") or os.path.join(os.environ.get("LOCALAPPDATA") or str(Path.home()), "JarvisPC", "cache")
    path = Path(base)
    path.mkdir(parents=True, exist_ok=True)
    return path


def new_pairing_code() -> str:
    """Eight characters the iPhone types once, e.g. « K7P2-9XQ4 » (no 0/O or 1/I)."""
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    raw = "".join(secrets.choice(alphabet) for _ in range(8))
    return raw[:4] + "-" + raw[4:]


@dataclass
class Settings:
    pairing_code: str = field(default_factory=new_pairing_code)
    model: str = DEFAULT_MODEL
    fallback_model: str = FALLBACK_MODEL
    port: int = DEFAULT_PORT
    # Free services without an account: Open-Meteo, Wikipedia, franceinfo RSS.
    internet: bool = True
    city: str = ""
    voice: bool = True
    wake_word: bool = True
    claps: bool = True
    stt_model: str = "small"
    piper_voice: str = "fr_FR-upmc-medium"
    # Jarvis's voice: speaker of the Piper model, pace and pause between sentences (pc/jarvis_pc/voiceprofile.py
    # measured them against the reference style; « python -m jarvis_pc --voix-essais » lets you compare voices).
    voice_speaker: str = "pierre"
    voice_length_scale: float = 1.10
    voice_sentence_silence: float = 0.3
    voice_pitch_semitones: float = 1.5
    # Optional: the address of a SearXNG run by the user (« http://127.0.0.1:8888 »), searched first.
    searxng_url: str = ""

    @classmethod
    def load(cls) -> "Settings":
        path = data_dir() / "settings.json"
        settings = cls()
        if path.exists():
            try:
                stored = json.loads(path.read_text(encoding="utf-8"))
                for key, value in stored.items():
                    if hasattr(settings, key):
                        setattr(settings, key, value)
            except (OSError, ValueError):
                pass
        settings.save()
        return settings

    def save(self) -> None:
        path = data_dir() / "settings.json"
        path.write_text(json.dumps(asdict(self), ensure_ascii=False, indent=2), encoding="utf-8")
