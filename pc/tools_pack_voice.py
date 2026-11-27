"""Builds the « Jarvis voice » package the iPhone downloads once, so that it speaks with the
same Piper voice as Jarvis PC, without the PC (JarvisLocalVoice.swift, sherpa-onnx 1.13.8).

The package is one file: an 8-byte header length, a JSON index ({"files": [{"path",
"offset", "size"}], "voice": {...}}), then the files one after the other. It holds the
Piper « fr_FR-upmc-medium » model (CC BY-SA 4.0), its tokens, and the French part of
espeak-ng-data (GPL-3.0, like JarvisXR), with their license notes.

    pc\\.venv\\Scripts\\python pc\\tools_pack_voice.py vits-piper-fr_FR-upmc-medium.tar.bz2 sortie.pack
"""
from __future__ import annotations

import hashlib
import json
import struct
import sys
import tarfile
from pathlib import Path

# What espeak-ng needs to phonemize French, nothing more.
ESPEAK_KEEP = ("phontab", "phonindex", "phondata", "intonations", "fr_dict", "lang/roa/fr")
VOICE = {"name": "pierre", "speaker_id": 1, "length_scale": 1.10, "pitch_semitones": 1.5, "sentence_silence": 0.3,
         "model": "model.onnx", "tokens": "tokens.txt", "data_dir": "espeak-ng-data", "version": 1}
NOTICE = """Voix de Jarvis : Piper « fr_FR-upmc-medium », locuteur « pierre » (UPMC, CC BY-SA 4.0),
https://huggingface.co/rhasspy/piper-voices — via sherpa-onnx (Apache 2.0).
Phonémisation : espeak-ng (GPL-3.0), données françaises de espeak-ng-data.
"""


def keep(name: str) -> bool:
    inside = name.split("espeak-ng-data/", 1)[1]
    return inside in ESPEAK_KEEP or inside.startswith("lang/roa/fr")


def build(source: Path, target: Path) -> dict:
    files: list[tuple[str, bytes]] = []
    with tarfile.open(source, "r:bz2") as archive:
        for member in archive.getmembers():
            if not member.isfile():
                continue
            name = member.name.split("/", 1)[1]
            data = archive.extractfile(member).read()
            if name.endswith(".onnx"):
                files.append(("model.onnx", data))
            elif name == "tokens.txt":
                files.append(("tokens.txt", data))
            elif name == "MODEL_CARD":
                files.append(("MODEL_CARD", data))
            elif name.startswith("espeak-ng-data/") and keep(name):
                files.append((name, data))
    files.append(("LISEZMOI.txt", NOTICE.encode("utf-8")))
    index, offset = [], 0
    for path, data in files:
        index.append({"path": path, "offset": offset, "size": len(data)})
        offset += len(data)
    header = json.dumps({"files": index, "voice": VOICE}, ensure_ascii=False).encode("utf-8")
    with open(target, "wb") as out:
        out.write(struct.pack("<Q", len(header)))
        out.write(header)
        for _, data in files:
            out.write(data)
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    return {"size": target.stat().st_size, "sha256": digest, "files": len(files)}


def unpack(pack: Path, folder: Path) -> dict:
    """The same reading as the iPhone (for the test)."""
    raw = pack.read_bytes()
    length = struct.unpack("<Q", raw[:8])[0]
    header = json.loads(raw[8:8 + length])
    base = 8 + length
    for item in header["files"]:
        path = folder / item["path"]
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(raw[base + item["offset"]:base + item["offset"] + item["size"]])
    return header["voice"]


if __name__ == "__main__":
    print(json.dumps(build(Path(sys.argv[1]), Path(sys.argv[2]))))
