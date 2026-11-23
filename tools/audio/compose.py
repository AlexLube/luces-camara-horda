#!/usr/bin/env python3
"""Original chiptune soundtrack for «Luces, Cámara, Horda».

Every track is composed here from scratch: a chord progression, a seeded melody built
from chord tones and scale steps, a bass line, an arpeggio and a drum pattern, rendered
with simple synth voices (pulse, triangle, noise) and encoded as a seamless OGG loop.

    python3 tools/audio/compose.py            # all tracks -> assets/music/<id>.ogg
    python3 tools/audio/compose.py terror     # only one
"""
import os
import random
import subprocess
import sys
import tempfile
import wave

import numpy as np
from scipy.signal import butter, lfilter

SR = 32000
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "music")

SCALES = {
    "major": [0, 2, 4, 5, 7, 9, 11],
    "minor": [0, 2, 3, 5, 7, 8, 10],
    "harmonic": [0, 2, 3, 5, 7, 8, 11],
    "dorian": [0, 2, 3, 5, 7, 9, 10],
    "phrygian": [0, 1, 3, 5, 7, 8, 10],
    "mixolydian": [0, 2, 4, 5, 7, 9, 10],
}

# id: tempo, root (MIDI), scale, progression (scale degrees, 1 per bar), drums, swing, lead duty, seed, feel
TRACKS = {
    "titulo":   dict(bpm=108, root=50, scale="major",      prog=[0, 4, 5, 3, 0, 4, 3, 4],  drums="march",  swing=0.0,  duty=0.5,   seed=11, feel="heroic"),
    "terror":   dict(bpm=84,  root=45, scale="phrygian",   prog=[0, 1, 0, 6, 0, 1, 5, 4],  drums="slow",   swing=0.0,  duty=0.125, seed=23, feel="eerie"),
    "western":  dict(bpm=132, root=52, scale="mixolydian", prog=[0, 3, 0, 4, 0, 3, 4, 0],  drums="gallop", swing=0.0,  duty=0.25,  seed=37, feel="bright"),
    "scifi":    dict(bpm=122, root=48, scale="dorian",     prog=[0, 6, 3, 4, 0, 6, 5, 4],  drums="disco",  swing=0.0,  duty=0.25,  seed=41, feel="arp"),
    "noir":     dict(bpm=92,  root=46, scale="dorian",     prog=[0, 3, 0, 4, 1, 4, 0, 4],  drums="swing",  swing=0.33, duty=0.5,   seed=53, feel="jazz"),
    "aventura": dict(bpm=140, root=50, scale="mixolydian", prog=[0, 6, 3, 0, 0, 6, 4, 4],  drums="rock",   swing=0.0,  duty=0.25,  seed=67, feel="heroic"),
    "comedia":  dict(bpm=152, root=53, scale="major",      prog=[0, 5, 1, 4, 0, 5, 1, 4],  drums="bounce", swing=0.2,  duty=0.5,   seed=71, feel="bouncy"),
    "accion":   dict(bpm=150, root=45, scale="minor",      prog=[0, 5, 6, 4, 0, 5, 3, 4],  drums="rock",   swing=0.0,  duty=0.25,  seed=83, feel="drive"),
    "creditos": dict(bpm=96,  root=48, scale="major",      prog=[0, 3, 4, 0, 5, 3, 1, 4],  drums="slow",   swing=0.0,  duty=0.5,   seed=109, feel="bouncy"),
    "jefe":     dict(bpm=164, root=45, scale="harmonic",   prog=[0, 0, 5, 4, 0, 1, 5, 4],  drums="double", swing=0.0,  duty=0.125, seed=97, feel="drive"),
}


def mtof(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


def env(n, a=0.005, d=0.08, s=0.6, r=0.05):
    t = np.arange(n) / SR
    e = np.ones(n) * s
    na, nd, nr = int(a * SR), int(d * SR), int(r * SR)
    e[:na] = np.linspace(0, 1, max(na, 1))[:min(na, n)] if na else e[:0]
    if nd and na < n:
        seg = e[na:na + nd]
        e[na:na + nd] = np.linspace(1, s, nd)[:len(seg)]
    if nr and n > nr:
        e[-nr:] *= np.linspace(1, 0, nr)
    return e


def pulse(f, n, duty=0.5, vib=0.0):
    t = np.arange(n) / SR
    ph = np.cumsum(np.full(n, f) * (1 + vib * np.sin(2 * np.pi * 5.5 * t) * np.clip(t * 3, 0, 1))) / SR
    return np.where((ph % 1.0) < duty, 1.0, -1.0)


def tri(f, n):
    ph = (np.arange(n) * f / SR) % 1.0
    return 4 * np.abs(ph - 0.5) - 1


def noise(n, seed):
    return np.random.default_rng(seed).uniform(-1, 1, n)


class Song:
    def __init__(self, tid, spec):
        self.id, self.s = tid, spec
        self.rng = random.Random(spec["seed"])
        self.beat = 60.0 / spec["bpm"]
        self.bars = 32
        self.n = int(round(self.bars * 4 * self.beat * SR))
        self.mix = np.zeros(self.n + SR * 2)
        sc = SCALES[spec["scale"]]
        self.scale = [spec["root"] + o * 12 + d for o in range(-2, 4) for d in sc]

    def chord(self, bar):
        prog = self.s["prog"]
        deg = prog[bar % len(prog)]
        sc = SCALES[self.s["scale"]]
        return [self.s["root"] + sc[(deg + k) % 7] + 12 * ((deg + k) // 7) for k in (0, 2, 4)]

    def t(self, bar, beat):
        sw = self.s["swing"]
        frac = beat % 1.0
        if sw and abs(frac - 0.5) < 1e-6: beat += sw * 0.5
        return int(round((bar * 4 + beat) * self.beat * SR))

    def add(self, at, sig, gain):
        end = min(len(self.mix), at + len(sig))
        self.mix[at:end] += sig[:end - at] * gain

    # ---- parts ----
    def bass(self):
        feel = self.s["feel"]
        for bar in range(self.bars):
            root = self.chord(bar)[0] - 12
            if feel in ("drive",): pat = [(b * 0.5, 0.45, root if b % 2 == 0 else root + 12) for b in range(8)]
            elif feel == "jazz": pat = [(b, 0.9, self.near(root, k)) for b, k in enumerate([0, 2, 4, 5])]
            elif feel in ("bouncy", "bright"): pat = [(0, 0.45, root), (1, 0.45, root + 7), (2, 0.45, root), (3, 0.45, root + 7)]
            elif feel == "eerie": pat = [(0, 3.8, root)]
            else: pat = [(0, 0.9, root), (1.5, 0.45, root), (2, 0.9, root + 7), (3, 0.9, root)]
            for st, ln, m in pat:
                nn = int(ln * self.beat * SR)
                self.add(self.t(bar, st), tri(mtof(m), nn) * env(nn, 0.004, 0.05, 0.8, 0.03), 0.30)

    def near(self, root, step):
        i = min(range(len(self.scale)), key=lambda k: abs(self.scale[k] - root))
        return self.scale[i + step]

    def arp(self):
        feel = self.s["feel"]
        step = 0.25 if feel in ("arp", "drive", "eerie") else 0.5
        for bar in range(self.bars):
            if bar % 16 < 2 and feel != "eerie": continue   # breathe at the start of each half
            ch = [m + 12 for m in self.chord(bar)]
            order = ch + [ch[1]] if feel != "eerie" else [ch[0], ch[2], ch[1] + 12, ch[2]]
            b = 0.0
            k = 0
            while b < 4.0:
                m = order[k % len(order)]
                nn = int(step * 0.9 * self.beat * SR)
                self.add(self.t(bar, b), pulse(mtof(m), nn, 0.125) * env(nn, 0.002, 0.04, 0.3, 0.02), 0.07 if feel != "eerie" else 0.09)
                b += step
                k += 1

    def melody(self):
        rng = self.rng
        rhythms = [
            [(0, 1), (1, 1), (2, 1.5), (3.5, 0.5)],
            [(0, 0.5), (0.5, 0.5), (1, 1), (2, 2)],
            [(0, 1.5), (1.5, 0.5), (2, 1), (3, 1)],
            [(0, 0.5), (0.5, 0.5), (1, 0.5), (1.5, 0.5), (2, 1), (3, 1)],
            [(0, 2), (2, 1), (3, 1)],
            [(0, 1), (1.5, 0.5), (2, 0.5), (2.5, 0.5), (3, 1)],
        ]
        if self.s["feel"] == "eerie": rhythms = [[(0, 2), (2, 2)], [(0, 3), (3, 1)], [(0, 1), (1, 3)]]
        lo = self.s["root"] + 12
        cur = lo + 7
        # phrase A (4 bars) is made once and reused, B is new; form A A' B A over 16 bars, twice
        def phrase(start_bar, seed):
            r = random.Random(seed)
            notes = []
            c = cur
            for b in range(4):
                bar = start_bar + b
                rh = r.choice(rhythms)
                ch = self.chord(bar)
                for st, ln in rh:
                    strong = st in (0, 2)
                    if strong:
                        cands = [m + 12 * o for m in ch for o in (0, 1, 2) if lo <= m + 12 * o <= lo + 19]
                        c = min(cands, key=lambda m: abs(m - c) + r.random() * 3)
                    else:
                        i = min(range(len(self.scale)), key=lambda k: abs(self.scale[k] - c))
                        c = self.scale[max(0, min(len(self.scale) - 1, i + r.choice([-2, -1, -1, 1, 1, 2])))]
                        c = max(lo, min(lo + 19, c))
                    notes.append((b, st, ln, c))
            # end the phrase on the root
            if notes:
                b, st, ln, _ = notes[-1]
                notes[-1] = (b, st, ln, min([self.chord(start_bar + 3)[0] + 12 * o for o in (1, 2)], key=lambda m: abs(m - c)))
            return notes
        A = phrase(0, rng.random())
        B = phrase(8, rng.random())
        form = [A, A, B, A, A, A, B, A]
        for sec, ph in enumerate(form):
            base = sec * 4
            for b, st, ln, m in ph:
                if sec in (1, 5) and b == 3: m += 2 if m + 2 in self.scale else 0   # A': small variation
                nn = int(ln * self.beat * SR * 0.95)
                sig = pulse(mtof(m), nn, self.s["duty"], vib=0.006 if ln >= 1 else 0.0) * env(nn, 0.006, 0.1, 0.55, 0.06)
                g = 0.16 if sec not in (0, 4) or self.s["feel"] == "eerie" else 0.12
                self.add(self.t(base + b, st), sig, g)
                if self.s["feel"] in ("heroic", "drive") and sec in (2, 6):   # harmony a third below in B
                    h = self.near(m, -2)
                    self.add(self.t(base + b, st), pulse(mtof(h), nn, 0.5) * env(nn, 0.006, 0.1, 0.5, 0.06), 0.06)

    def drums(self):
        style = self.s["drums"]
        kick_n = int(0.18 * SR)
        tk = np.arange(kick_n) / SR
        kick = np.sin(2 * np.pi * np.cumsum(60 + 120 * np.exp(-tk * 30)) / SR) * np.exp(-tk * 18)
        sn_n = int(0.16 * SR)
        snare = noise(sn_n, 5) * np.exp(-np.arange(sn_n) / SR * 22) * 0.8 + np.sin(2 * np.pi * 190 * np.arange(sn_n) / SR) * np.exp(-np.arange(sn_n) / SR * 30) * 0.4
        hh_n = int(0.05 * SR)
        hat = np.diff(noise(hh_n + 1, 9)) * np.exp(-np.arange(hh_n) / SR * 80) * 0.5
        pats = {
            "march":  ("x...x...x...x...", "....o.......o.o.", "x.x.x.x.x.x.x.x."),
            "slow":   ("x.......x.......", "........o.......", "....x.......x..."),
            "gallop": ("x..x..x.x..x..x.", "....o.......o...", "x.xxx.xxx.xxx.xx"),
            "disco":  ("x...x...x...x...", "....o.......o...", "..x...x...x...x."),
            "swing":  ("x.......x.......", "....o.......o...", "x..xx..xx..xx..x"),
            "rock":   ("x.....x.x.......", "....o.......o...", "x.x.x.x.x.x.x.x."),
            "bounce": ("x...x...x...x...", "..o...o...o...o.", "x.x.x.x.x.x.x.x."),
            "double": ("x.x.x.x.x.x.x.x.", "....o.......o...", "xxxxxxxxxxxxxxxx"),
        }
        k, s, h = pats[style]
        for bar in range(self.bars):
            if bar % 16 == 0 and style not in ("slow",): fill = False
            last = bar % 8 == 7
            for i in range(16):
                b = i / 4.0
                if k[i] == "x": self.add(self.t(bar, b), kick, 0.55)
                if s[i] == "o" or (last and i >= 12 and i % 2 == 0): self.add(self.t(bar, b), snare, 0.25)
                if h[i] == "x": self.add(self.t(bar, b), hat, 0.12)

    def render(self):
        self.bass(); self.arp(); self.melody(); self.drums()
        # wrap the tail (reverb-ish release past the end) onto the start for a seamless loop
        tail = self.mix[self.n:]
        out = self.mix[:self.n].copy()
        out[:len(tail)] += tail
        # simple echo for space
        d = int(self.beat * 0.75 * SR)
        echo = np.zeros_like(out)
        echo[d:] = out[:-d] * 0.18
        echo[:d] += out[-d:] * 0.18
        out += echo
        # soften the raw square waves a little (gentle low-pass, applied over the loop twice so it wraps)
        b, a = butter(2, 6500 / (SR / 2))
        out = lfilter(b, a, np.concatenate([out, out]))[len(out):]
        out = np.tanh(out * 1.1) * 0.85
        return out


def write(tid, spec):
    data = Song(tid, spec).render()
    os.makedirs(OUT, exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        tmp = f.name
    with wave.open(tmp, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(data, -1, 1) * 32000).astype(np.int16).tobytes())
    dst = os.path.join(OUT, tid + ".ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", "3", dst], check=True)
    os.remove(tmp)
    print(f"{dst}: {len(data) / SR:.1f} s")


if __name__ == "__main__":
    for tid in sys.argv[1:] or TRACKS:
        write(tid, TRACKS[tid])
