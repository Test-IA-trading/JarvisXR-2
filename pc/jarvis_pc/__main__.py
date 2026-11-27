"""Starts the PC Jarvis: the console, the voice (micro + speakers) and the iPhone server.

    python -m jarvis_pc              everything
    python -m jarvis_pc --texte      no microphone or voice
    python -m jarvis_pc --appareils  list microphones and speakers
    python -m jarvis_pc --autotest   check every part for real (brain, voice, server)
"""
from __future__ import annotations

import argparse
import json
import queue
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

from . import __version__, wake
from .brain import OllamaBrain, SentenceStreamer
from .config import Settings
from .core import JarvisCore
from .memory import Memory
from .router import Router
from .server import JarvisServer, local_addresses


class VoiceLoop:
    """« Jarvis, … », « Jarvis ? » then the request, or two claps then the request."""

    def __init__(self, core: JarvisCore, speaker):
        self.core = core
        self.speaker = speaker
        self.listen_until = 0.0
        self.busy = threading.Lock()

    def on_utterance(self, text: str) -> None:
        if time.time() < self.listen_until:
            self.listen_until = 0.0
            return self.process(text)
        request = wake.command(text)
        if request is None:
            return
        if request == "":
            return self.answer_call()
        self.process(request)

    def on_double_clap(self) -> None:
        self.answer_call()

    def answer_call(self) -> None:
        print("Jarvis : Oui ?")
        self.speaker.say("Oui ?")
        self.listen_until = time.time() + 8

    def process(self, text: str) -> None:
        if not self.busy.acquire(blocking=False):
            return
        try:
            print(f"Vous : {text}")
            sentences: "queue.Queue" = queue.Queue()
            streamer = SentenceStreamer()

            def talk():
                while True:
                    sentence = sentences.get()
                    if sentence is None:
                        return
                    self.speaker.say(sentence)

            talker = threading.Thread(target=talk, daemon=True)
            talker.start()
            answer = self.core.handle(text, on_text=lambda partial: [sentences.put(s) for s in streamer.new_sentences(partial, False)])
            spoken_by_stream = streamer.emitted > 0
            for sentence in (streamer.new_sentences(answer.spoken, True) if spoken_by_stream else [answer.spoken]):
                sentences.put(sentence)
            sentences.put(None)
            print(f"Jarvis : {answer.display}")
            talker.join()
            # A follow-up needs no « Jarvis » for a few seconds, as on the iPhone.
            self.listen_until = time.time() + (8 if answer.data.get("listen") else 6)
            if answer.data.get("end"):
                self.listen_until = 0.0
        finally:
            self.busy.release()


def list_devices() -> None:
    import sounddevice as sd

    print(sd.query_devices())
    print("\nMicro par défaut :", sd.query_devices(kind="input")["name"])
    print("Sortie par défaut :", sd.query_devices(kind="output")["name"])


def build(settings: Settings, voice: bool):
    memory = Memory()
    brain = OllamaBrain(settings.model, settings.fallback_model)
    speaker = None
    if voice:
        from .voice import Speaker

        speaker = Speaker()
    core = JarvisCore(settings, memory, brain, Router(memory, settings), speaker)
    return core, speaker


def run(text_only: bool) -> int:
    settings = Settings.load()
    core, speaker = build(settings, voice=not text_only and settings.voice)
    server = JarvisServer(core, settings)
    server.start()
    model = core.brain.active_model()
    print(f"JARVIS PC {__version__}")
    print(f"Cerveau : {model} (prêt)" if model else "Cerveau : Ollama ne répond pas ou le modèle manque (ollama pull " + settings.model + ").")
    print(f"Code d'appairage pour l'iPhone : {settings.pairing_code}")
    print("Adresses pour l'iPhone : " + (", ".join(f"{a}:{server.port}" for a in local_addresses()) or "aucune"))
    ears = None
    if speaker is not None:
        from .voice import Ears, Transcriber

        loop = VoiceLoop(core, speaker)
        try:
            ears = Ears(Transcriber(settings.stt_model), loop.on_utterance, loop.on_double_clap if settings.claps else None,
                        muted=speaker.speaking.is_set, claps=settings.claps)
            speaker.ensure()
            ears.transcriber.ensure()
            ears.start()
            print("Voix : dites « Jarvis, … » ou tapez deux fois dans vos mains.")
        except Exception as error:  # noqa: BLE001 — the console keeps working without a microphone
            print(f"Voix indisponible : {error}")
            ears = None
    print("Écrivez une demande puis Entrée (« quitter » pour arrêter).")
    try:
        while True:
            line = input("> ").strip()
            if line.lower() in ("quitter", "exit", "quit"):
                break
            if not line:
                continue
            answer = core.handle(line, source="clavier")
            print(f"Jarvis : {answer.display}")
            if speaker is not None:
                speaker.say(answer.spoken)
    except (EOFError, KeyboardInterrupt):
        pass
    finally:
        if ears is not None:
            ears.stop()
        server.stop()
    return 0


def autotest() -> int:
    """Checks every part for real, and says what fails."""
    import os

    os.environ.setdefault("JARVIS_PC_HOME", tempfile.mkdtemp(prefix="jarvis-autotest-"))
    results: list[tuple[str, bool, str]] = []

    def check(name: str, ok: bool, detail: str = "") -> None:
        results.append((name, ok, detail))
        print(f"{'OK    ' if ok else 'ÉCHEC '} {name}{' — ' + detail if detail else ''}")

    settings = Settings.load()
    core, speaker = build(settings, voice=True)

    answer = core.router.route("Intégrale de 0 à 1 de x au carré")
    check("calcul exact", bool(answer and "1/3" in answer.spoken), answer.spoken if answer else "")

    model = core.brain.active_model()
    check("cerveau installé", model is not None, model or "Ollama ou le modèle manque")
    if model:
        started = time.time()
        reply = core.brain.ask("Quelle est la capitale de l'Australie ? Réponds en une phrase.")
        check("cerveau répond juste", "canberra" in reply.lower(), f"{reply} ({time.time() - started:.1f} s, {core.brain.last_tokens_per_second:.0f} jetons/s)")

    try:
        from .voice import Transcriber

        wav = Path(tempfile.mkdtemp()) / "phrase.wav"
        speaker.save_wav("Jarvis, quelle heure est-il ?", wav)
        check("voix Piper (pierre)", wav.stat().st_size > 10_000, f"{wav.stat().st_size} octets")
        import wave

        import numpy as np

        with wave.open(str(wav)) as source:
            rate = source.getframerate()
            audio = np.frombuffer(source.readframes(source.getnframes()), dtype=np.int16).astype(np.float32) / 32768
        heard = Transcriber(settings.stt_model).transcribe(audio, rate)
        request = wake.command(heard)
        check("oreilles faster-whisper", "heure" in heard.lower(), heard)
        check("réveil « Jarvis »", bool(request) and "heure" in request.lower(), str(request))
        routed = core.router.route(request or "")
        check("réponse à la phrase entendue", bool(routed and routed.spoken.startswith("Il est")), routed.spoken if routed else "")
    except Exception as error:  # noqa: BLE001
        check("voix et oreilles", False, str(error))

    server = JarvisServer(core, settings, host="127.0.0.1", port=0)
    server.start(advertise=False)
    base = f"http://127.0.0.1:{server.port}"

    def call(path: str, payload: dict | None = None, code: str | None = settings.pairing_code):
        request = urllib.request.Request(base + path, data=json.dumps(payload).encode("utf-8") if payload is not None else None,
                                         headers={"Content-Type": "application/json", **({"Authorization": "Bearer " + code} if code else {})})
        try:
            with urllib.request.urlopen(request, timeout=300) as response:
                return response.status, response.read().decode("utf-8")
        except urllib.error.HTTPError as error:
            return error.code, error.read().decode("utf-8")

    status, body = call("/v1/health", code=None)
    check("serveur : présence sans code", status == 200 and '"paired": false' in body, body)
    status, body = call("/v1/command", {"text": "Combien font 3 fois 7 ?"}, code="FAUX-CODE")
    check("serveur : refuse un mauvais code", status == 401, str(status))
    status, body = call("/v1/command", {"text": "Combien font 3 fois 7 ?"})
    check("serveur : commande de l'iPhone", status == 200 and "21" in body, body[:120])
    status, body = call("/v1/memory", {"name": "Tony", "name_updated": "2099-01-01T00:00:00+00:00", "notes": [{"id": "n1", "text": "note de l'iPhone", "created": "2026-11-25T10:00:00+00:00"}]})
    check("serveur : mémoire partagée", status == 200 and "note de l'iPhone" in body and "Tony" in body, body[:120])
    if model:
        status, body = call("/v1/ask", {"question": "Dis bonjour en une phrase.", "history": [], "context": []})
        lines = [json.loads(line) for line in body.splitlines() if line.strip()]
        final = next((line.get("final") for line in lines if "final" in line), "")
        check("serveur : question au cerveau en direct", status == 200 and bool(final) and len(lines) >= 2, f"{len(lines)} morceaux, « {final} »")
    core.handle("Envoie sur mon téléphone que le test est fini")
    status, body = call("/v1/inbox")
    check("serveur : message pour l'iPhone", status == 200 and "le test est fini" in body, body[:120])
    server.stop()

    failed = [name for name, ok, _ in results if not ok]
    print(f"\n{len(results) - len(failed)}/{len(results)} vérifications réussies." + (f" À revoir : {', '.join(failed)}." if failed else ""))
    return 1 if failed else 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="jarvis_pc", description="Jarvis pour Windows")
    parser.add_argument("--texte", action="store_true", help="sans micro ni voix")
    parser.add_argument("--appareils", action="store_true", help="liste les micros et haut-parleurs")
    parser.add_argument("--autotest", action="store_true", help="vérifie chaque partie pour de vrai")
    args = parser.parse_args(argv)
    if args.appareils:
        list_devices()
        return 0
    if args.autotest:
        return autotest()
    return run(text_only=args.texte)


if __name__ == "__main__":
    sys.exit(main())
