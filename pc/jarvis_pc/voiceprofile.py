"""What a voice sounds like, measured on this PC: pitch (median, spread, range), speaking
rate, pauses and the cleanest passages of a reference recording. Only these numbers are
kept, never the audio. Used to choose and tune Jarvis's own French voice (Piper) so that
it comes close to a reference style, without cloning anyone's voice.

    python -m jarvis_pc --analyse-voix chemin\\vers\\reference.wav
"""
from __future__ import annotations

import json
import math
import wave
from pathlib import Path

RATE = 16000
FRAME = 640  # 40 ms
HOP = 160  # 10 ms


def read_mono(path: Path, rate: int = RATE):
    """The recording as float32 mono at `rate` (channels averaged, plain decimation after a
    moving-average low-pass: enough for pitch and rhythm)."""
    import numpy as np

    with wave.open(str(path), "rb") as source:
        channels, width, source_rate = source.getnchannels(), source.getsampwidth(), source.getframerate()
        raw = source.readframes(source.getnframes())
    if width != 2:
        raise ValueError("WAV 16 bits attendu")
    samples = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    if channels > 1:
        samples = samples.reshape(-1, channels).mean(axis=1)
    step = source_rate / rate
    if step >= 2 and float(step).is_integer():
        n = int(step)
        kernel = np.ones(n, dtype=np.float32) / n
        samples = np.convolve(samples, kernel, mode="same")[::n]
    elif step != 1:
        positions = np.arange(0, len(samples) - 1, step)
        samples = np.interp(positions, np.arange(len(samples)), samples).astype(np.float32)
    return samples


def frames(samples):
    import numpy as np

    count = max(0, 1 + (len(samples) - FRAME) // HOP)
    index = np.arange(FRAME)[None, :] + HOP * np.arange(count)[:, None]
    return samples[index] * np.hanning(FRAME).astype(np.float32)


def pitch_track(samples, low: float = 60.0, high: float = 400.0):
    """(f0 per 10 ms frame, 0 when unvoiced; frame energy in dB) by normalized
    autocorrelation, computed with FFTs."""
    import numpy as np

    blocks = frames(samples)
    energy = 10 * np.log10(np.mean(blocks ** 2, axis=1) + 1e-10)
    spectrum = np.fft.rfft(blocks, n=2 * FRAME, axis=1)
    acf = np.fft.irfft(np.abs(spectrum) ** 2, axis=1)[:, :FRAME]
    acf /= acf[:, :1] + 1e-10
    lo, hi = int(RATE / high), int(RATE / low)
    window = acf[:, lo:hi]
    lag = window.argmax(axis=1) + lo
    peak = window.max(axis=1)
    floor = np.percentile(energy, 20)
    voiced = (peak > 0.6) & (energy > floor + 12)
    f0 = np.where(voiced, RATE / lag, 0.0)
    return f0, energy


def semitones(values, reference: float):
    import numpy as np

    return 12 * np.log2(np.asarray(values) / reference)


def runs(mask):
    """[(start, end)] frame indices of consecutive True values."""
    out, start = [], None
    for i, value in enumerate(mask):
        if value and start is None:
            start = i
        elif not value and start is not None:
            out.append((start, i))
            start = None
    if start is not None:
        out.append((start, len(mask)))
    return out


def analyse(samples) -> dict:
    """The numbers that describe a voice's style."""
    import numpy as np

    f0, energy = pitch_track(samples)
    voiced = f0 > 0
    if voiced.sum() < 50:
        raise ValueError("pas assez de parole voisée")
    # Octave errors (music, a breath) are dropped: only values within an octave of the median count.
    rough = float(np.median(f0[voiced]))
    voiced &= (f0 > rough * 0.6) & (f0 < rough * 1.7)
    pitch = f0[voiced]
    median = float(np.median(pitch))
    tones = semitones(pitch, median)
    # Speech = voiced or loud enough; pauses = silences between 0.15 and 2 s inside speech.
    floor = np.percentile(energy, 20)
    speech = voiced | (energy > floor + 15)
    silences = [(e - s) * HOP / RATE for s, e in runs(~speech)]
    pauses = [d for d in silences if 0.15 <= d <= 2.0]
    speech_seconds = float(speech.sum() * HOP / RATE)
    # Syllables ≈ peaks of the voiced energy envelope (de Jong & Wempe, simplified).
    envelope = np.convolve(np.where(voiced, energy, floor), np.ones(5) / 5, mode="same")
    peaks = (envelope[1:-1] > envelope[:-2]) & (envelope[1:-1] >= envelope[2:]) & (envelope[1:-1] > floor + 18)
    syllables = int(peaks.sum())
    # Intonation of each voiced stretch: how far the pitch moves inside a phrase.
    phrase_ranges = []
    for s, e in runs(voiced):
        if e - s >= 15:
            seg = semitones(f0[s:e], median)
            phrase_ranges.append(float(np.percentile(seg, 90) - np.percentile(seg, 10)))
    return {
        "f0_median_hz": round(median, 1),
        "f0_p10_hz": round(float(np.percentile(pitch, 10)), 1),
        "f0_p90_hz": round(float(np.percentile(pitch, 90)), 1),
        "f0_spread_semitones": round(float(np.percentile(tones, 90) - np.percentile(tones, 10)), 2),
        "phrase_range_semitones": round(float(np.median(phrase_ranges)), 2) if phrase_ranges else 0.0,
        "syllables_per_second": round(syllables / max(speech_seconds, 1e-6), 2),
        "pause_median_s": round(float(np.median(pauses)), 2) if pauses else 0.0,
        "pause_p90_s": round(float(np.percentile(pauses, 90)), 2) if pauses else 0.0,
        "pauses_per_minute": round(len(pauses) / max(speech_seconds / 60, 1e-6), 1),
        "speech_seconds": round(speech_seconds, 1),
    }


def clean_passages(samples, window_s: float = 6.0, keep: int = 12) -> list[dict]:
    """The windows with the most clear speech (voiced, well above the noise floor, little
    sound between words): where the style is measured."""
    import numpy as np

    f0, energy = pitch_track(samples)
    per = int(window_s * RATE / HOP)
    floor = np.percentile(energy, 20)
    scored = []
    for start in range(0, len(f0) - per, per // 2):
        e = energy[start:start + per]
        v = f0[start:start + per] > 0
        gaps = e[~v]
        quiet = float(np.mean(gaps < floor + 8)) if len(gaps) else 0.0  # clean silences, no music under the voice
        score = float(v.mean()) * 0.6 + quiet * 0.4
        scored.append((score, start))
    scored.sort(reverse=True)
    chosen, taken = [], []
    for score, start in scored:
        if any(abs(start - other) < per for other in taken):
            continue
        taken.append(start)
        chosen.append({"start_s": round(start * HOP / RATE, 1), "end_s": round((start + per) * HOP / RATE, 1), "score": round(score, 3)})
        if len(chosen) >= keep:
            break
    return sorted(chosen, key=lambda c: c["start_s"])


def analyse_reference(path: Path) -> dict:
    """Style of a reference recording, measured on its cleanest passages only."""
    import numpy as np

    samples = read_mono(path)
    passages = clean_passages(samples)
    pieces = [samples[int(p["start_s"] * RATE):int(p["end_s"] * RATE)] for p in passages]
    profile = analyse(np.concatenate(pieces)) if pieces else analyse(samples)
    return {"fichier": path.name, "duree_s": round(len(samples) / RATE, 1), "passages_propres": passages, "style": profile}


def distance(a: dict, b: dict) -> float:
    """How far two styles are: pitch in semitones first, then rate, spread and pauses."""
    pitch = abs(12 * math.log2(a["f0_median_hz"] / b["f0_median_hz"])) / 2.0
    rate = abs(a["syllables_per_second"] - b["syllables_per_second"]) / 1.0
    spread = abs(a["f0_spread_semitones"] - b["f0_spread_semitones"]) / 3.0
    return pitch + rate + spread


def tuning(reference: dict, voice: dict, current_length_scale: float = 1.0) -> dict:
    """Piper settings that bring `voice` toward `reference`: length_scale for the rate, and
    the silence between sentences for the pauses."""
    ratio = voice["syllables_per_second"] / max(reference["syllables_per_second"], 0.1)
    length_scale = min(1.35, max(0.8, current_length_scale * ratio))
    sentence_silence = min(0.6, max(0.08, reference.get("pause_median_s", 0.25)))
    return {"length_scale": round(length_scale, 2), "sentence_silence": round(sentence_silence, 2)}


def save(profile: dict, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(profile, ensure_ascii=False, indent=2), encoding="utf-8")
