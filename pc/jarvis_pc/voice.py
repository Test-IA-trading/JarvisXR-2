"""Ears and voice of the PC Jarvis, both on this computer: faster-whisper turns speech into
text (CPU, int8), Piper speaks with the French « pierre » voice (upmc, CC BY-SA 4.0).
The models are downloaded once into %APPDATA%\\JarvisPC; no audio is ever saved."""
from __future__ import annotations

import math
import queue
import threading
import time
import urllib.request
from pathlib import Path

from . import mathsolver
from .claps import Detector
from .config import cache_dir

PIPER_BASE = "https://huggingface.co/rhasspy/piper-voices/resolve/main/fr/fr_FR/upmc/medium/"
PIPER_MODEL = "fr_FR-upmc-medium.onnx"


def _download(url: str, target: Path) -> None:
    if target.exists() and target.stat().st_size > 0:
        return
    partial = target.with_suffix(target.suffix + ".partial")
    request = urllib.request.Request(url, headers={"User-Agent": "JarvisPC/1.0"})
    with urllib.request.urlopen(request, timeout=120) as response, open(partial, "wb") as out:
        while True:
            block = response.read(1 << 20)
            if not block:
                break
            out.write(block)
    partial.replace(target)


class Speaker:
    """Text to speech with Piper; formulas are read as words (x² → « x au carré »)."""

    def __init__(self, speaker: str = "pierre", length_scale: float = 1.05, device=None):
        self.speaker_name = speaker
        self.length_scale = length_scale
        self.device = device
        self.voice = None
        self.speaking = threading.Event()
        self.lock = threading.Lock()

    def ensure(self):
        if self.voice is not None:
            return self.voice
        from piper import PiperVoice

        folder = cache_dir() / "voices"
        folder.mkdir(parents=True, exist_ok=True)
        model = folder / PIPER_MODEL
        config = folder / (PIPER_MODEL + ".json")
        _download(PIPER_BASE + PIPER_MODEL, model)
        _download(PIPER_BASE + PIPER_MODEL + ".json", config)
        self.voice = PiperVoice.load(model, config_path=config)
        return self.voice

    def synthesize(self, text: str):
        """(int16 samples, sample rate) for `text`."""
        import numpy as np
        from piper import SynthesisConfig

        voice = self.ensure()
        speaker_id = (voice.config.speaker_id_map or {}).get(self.speaker_name)
        config = SynthesisConfig(speaker_id=speaker_id, length_scale=self.length_scale)
        chunks = [chunk.audio_int16_array for chunk in voice.synthesize(mathsolver.speakable(text), syn_config=config)]
        audio = np.concatenate(chunks) if chunks else np.zeros(1, dtype=np.int16)
        return audio, voice.config.sample_rate

    def say(self, text: str) -> None:
        import sounddevice as sd

        if not text.strip():
            return
        with self.lock:
            audio, rate = self.synthesize(text)
            self.speaking.set()
            try:
                sd.play(audio, rate, device=self.device)
                sd.wait()
                time.sleep(0.3)  # the room's echo of Jarvis's own voice
            finally:
                self.speaking.clear()

    def save_wav(self, text: str, path: Path) -> None:
        import wave

        audio, rate = self.synthesize(text)
        with wave.open(str(path), "wb") as out:
            out.setnchannels(1)
            out.setsampwidth(2)
            out.setframerate(rate)
            out.writeframes(audio.tobytes())


class Transcriber:
    """Speech to text in French with faster-whisper on the CPU."""

    def __init__(self, model: str = "small"):
        self.model_name = model
        self.model = None

    def ensure(self):
        if self.model is None:
            from faster_whisper import WhisperModel

            self.model = WhisperModel(self.model_name, device="cpu", compute_type="int8",
                                      download_root=str(cache_dir() / "models"))
        return self.model

    def transcribe(self, audio, sample_rate: int = 16000) -> str:
        import numpy as np

        samples = np.asarray(audio, dtype=np.float32)
        if sample_rate != 16000:
            positions = np.linspace(0, len(samples) - 1, int(len(samples) * 16000 / sample_rate))
            samples = np.interp(positions, np.arange(len(samples)), samples).astype(np.float32)
        segments, _ = self.ensure().transcribe(samples, language="fr", beam_size=1, vad_filter=False,
                                               initial_prompt="Jarvis, assistant personnel.")
        return " ".join(segment.text.strip() for segment in segments).strip()


class Ears:
    """The microphone, cut into utterances by their level, plus the double-clap detector.
    Audio is dropped while Jarvis speaks, so it never answers its own voice."""

    rate = 16000

    def __init__(self, transcriber: Transcriber, on_utterance, on_double_clap=None, muted=None, device=None, claps: bool = True):
        self.transcriber = transcriber
        self.on_utterance = on_utterance
        self.on_double_clap = on_double_clap
        self.muted = muted or (lambda: False)
        self.device = device
        self.claps = Detector(self.rate) if claps else None
        self.queue: "queue.Queue" = queue.Queue()
        self.stream = None
        self.running = False
        self.floor = 0.004
        self.recording: list = []
        self.preroll: list = []
        self.speech_frames = 0
        self.silence = 0.0
        self.active = False

    def start(self) -> None:
        import sounddevice as sd

        self.running = True
        threading.Thread(target=self._worker, name="jarvis-ears", daemon=True).start()
        self.stream = sd.InputStream(samplerate=self.rate, channels=1, dtype="float32", blocksize=480,
                                     device=self.device, callback=self._callback)
        self.stream.start()

    def stop(self) -> None:
        self.running = False
        if self.stream is not None:
            self.stream.stop()
            self.stream.close()
        self.queue.put(None)

    def _callback(self, indata, frames, time_info, status) -> None:
        samples = indata[:, 0].copy()
        if self.muted():
            self.active, self.recording, self.speech_frames = False, [], 0
            return
        if self.claps is not None and self.claps.ingest(samples.tolist()) and self.on_double_clap:
            threading.Thread(target=self.on_double_clap, daemon=True).start()
        self.feed(samples)

    def feed(self, samples) -> None:
        """30 ms frames: speech starts after 90 ms above the room, ends after 0.8 s below."""
        rms = math.sqrt(float((samples * samples).mean())) if len(samples) else 0.0
        frame_seconds = len(samples) / self.rate
        speech = rms > max(0.012, self.floor * 3)
        if not self.active:
            self.preroll = (self.preroll + [samples])[-10:]
            self.speech_frames = self.speech_frames + 1 if speech else 0
            if not speech:
                self.floor = min(0.05, max(0.001, self.floor * 0.995 + rms * 0.005))
            if self.speech_frames >= 3:
                self.active, self.recording, self.silence = True, list(self.preroll), 0.0
            return
        self.recording.append(samples)
        self.silence = 0.0 if speech else self.silence + frame_seconds
        duration = sum(len(chunk) for chunk in self.recording) / self.rate
        if self.silence >= 0.8 or duration >= 15:
            self.queue.put(list(self.recording))
            self.active, self.recording, self.speech_frames, self.preroll = False, [], 0, []

    def _worker(self) -> None:
        import numpy as np

        while self.running:
            chunks = self.queue.get()
            if chunks is None:
                return
            audio = np.concatenate(chunks)
            if len(audio) < self.rate * 0.4:
                continue
            try:
                text = self.transcriber.transcribe(audio, self.rate)
            except Exception as error:  # noqa: BLE001 — the microphone loop must survive
                print(f"[oreilles] transcription impossible : {error}")
                continue
            if text:
                self.on_utterance(text)
