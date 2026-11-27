"""Two hand claps in a row, as on the iPhone (same rules as JarvisClapDetector.swift):
a short, loud, sudden sound that falls by 12 dB within 60 ms, twice, 0.15 to 0.8 s apart.
Only the level of each 10 ms frame is kept."""
import math


class Detector:
    def __init__(self, rate):
        self.rate = rate
        self.min_gap, self.max_gap, self.decay, self.tail, self.cool = 0.15, 0.8, 0.06, 0.12, 1.0
        self.floor = 0.003
        self.phase = ("idle",)
        self.clock = 0.0
        self.frame = []
        self.size = max(64, int(rate * 0.01))
        self.prev = 0.0
        self.last = None
        self.quiet_until = 0.0

    def ingest(self, samples):
        hit = False
        for s in samples:
            self.frame.append(s)
            if len(self.frame) == self.size:
                if self.process():
                    hit = True
                self.frame = []
        return hit

    def process(self):
        peak = max(abs(v) for v in self.frame)
        rms = math.sqrt(sum(v * v for v in self.frame) / len(self.frame))
        start = self.clock
        self.clock += len(self.frame) / self.rate
        try:
            kind = self.phase[0]
            if kind == "tail":
                if start >= self.phase[1] or rms < self.floor * 4:
                    self.phase = ("idle",)
                return False
            if kind == "sustained":
                if rms < self.floor * 4:
                    self.phase = ("idle",)
                return False
            if kind == "rising":
                ev_start, ev_peak = self.phase[1], self.phase[2]
                highest = max(ev_peak, rms)
                if rms < highest / 4:
                    self.phase = ("tail", ev_start + self.tail)
                    return self.register(ev_start)
                self.phase = ("sustained",) if start - ev_start > self.decay else ("rising", ev_start, highest)
                return False
            sudden = rms > max(self.prev, self.floor) * 3
            if peak > max(0.04, self.floor * 15) and rms > self.floor * 5 and sudden:
                self.phase = ("rising", start, rms)
                return False
            self.floor = min(0.2, max(0.0005, self.floor * 0.995 + rms * 0.005))
            return False
        finally:
            self.prev = rms

    def register(self, t):
        if t < self.quiet_until:
            return False
        if self.last is not None:
            gap = t - self.last
            if self.min_gap <= gap <= self.max_gap:
                self.last = None
                self.quiet_until = t + self.cool
                return True
        self.last = t
        return False
