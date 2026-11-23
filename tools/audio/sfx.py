#!/usr/bin/env python3
"""Original sound effects for «Luces, Cámara, Horda», synthesized from scratch (no samples).

    python3 tools/audio/sfx.py          # every effect -> assets/sfx/<id>.wav
    python3 tools/audio/sfx.py coin     # only one

Each effect is a short recipe of oscillators, noise and envelopes (16-bit mono, 32 kHz).
"""
import os
import sys
import wave

import numpy as np

SR = 32000
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "sfx")
rng = np.random.default_rng(7)


def t(d):
    return np.arange(int(SR * d)) / SR


def env(n, a=0.005, r=None, curve=3.0):
    """Attack then exponential-ish decay over n samples."""
    x = np.ones(n)
    na = max(1, int(SR * a))
    x[:na] = np.linspace(0, 1, na)
    rest = n - na
    if rest > 0:
        x[na:] = (1 - np.linspace(0, 1, rest)) ** curve
    return x


def sq(f, d, duty=0.5):
    ph = np.cumsum(np.full(int(SR * d), f) / SR) if np.isscalar(f) else np.cumsum(f / SR)
    return np.where((ph % 1.0) < duty, 1.0, -1.0)


def tri(f, d):
    ph = np.cumsum(np.full(int(SR * d), f) / SR) if np.isscalar(f) else np.cumsum(f / SR)
    return 2 * np.abs(2 * (ph % 1.0) - 1) - 1


def noise(d):
    return rng.uniform(-1, 1, int(SR * d))


def lowpass(x, k):
    """One-pole low-pass; k in (0, 1], smaller = darker."""
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += k * (v - acc)
        y[i] = acc
    return y


def sweep(f0, f1, d):
    return np.geomspace(f0, f1, int(SR * d))


def cat(*parts):
    return np.concatenate(parts)


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


def notes(seq, dur, voice=sq, duty=0.25, gap=0.0):
    out = []
    for f in seq:
        x = (voice(f, dur, duty) if voice is sq else voice(f, dur)) * env(int(SR * dur), 0.003, curve=1.6)
        out.append(cat(x, np.zeros(int(SR * gap))))
    return cat(*out)


def midi(m):
    return 440.0 * 2 ** ((m - 69) / 12)


RECIPES = {
    # a coin from the box office: two bright square blips
    "coin": lambda: cat(sq(midi(88), 0.05, 0.25) * env(1600, 0.002, curve=1), sq(midi(95), 0.16, 0.25) * env(5120, 0.002, curve=2)) * 0.35,
    # a bite of a donut / popcorn: crunchy filtered noise bursts
    "eat": lambda: cat(*[lowpass(noise(0.05), 0.35) * env(1600, 0.002, curve=2) for _ in range(3)]) * 0.8,
    # relic found: a little fanfare in major thirds
    "relic": lambda: mix(notes([midi(m) for m in (72, 76, 79, 84)], 0.09, sq, 0.5),
                         cat(np.zeros(int(SR * 0.36)), tri(midi(84), 0.5) * env(16000, 0.01, curve=2))) * 0.3,
    # «montaje final»: a rising sweep and a sparkling chord, like a trailer sting
    "evolve": lambda: cat(sq(sweep(180, 1400, 0.35), 0.35, 0.5) * np.linspace(0.2, 1, int(SR * 0.35)) * 0.5,
                          mix(*[tri(midi(m), 0.7) * env(22400, 0.005, curve=2.5) for m in (72, 76, 79, 83)]) * 0.6) * 0.4,
    # the clapperboard: a sharp wooden clack
    "clap": lambda: mix(lowpass(noise(0.08), 0.6) * env(2560, 0.0005, curve=6), tri(sweep(900, 300, 0.05), 0.05) * env(1600, 0.0005, curve=4) * 0.6) * 0.9,
    # a set fire put out: a hiss that fades
    "fire_out": lambda: (noise(0.6) - lowpass(noise(0.6), 0.2)) * env(19200, 0.02, curve=1.5) * 0.35,
    # La Sala de Montaje cut: tape whoosh down and a splice click
    "cut": lambda: cat(lowpass(noise(0.25), 0.25) * np.linspace(1, 0, int(SR * 0.25)) ** 0.5 * sq(sweep(400, 60, 0.25), 0.25, 0.5) * 0.6,
                       lowpass(noise(0.03), 0.8) * env(960, 0.0005, curve=5)) * 0.6,
    # boss attack telegraph: two low warning beeps
    "warn": lambda: cat(sq(220, 0.09, 0.5) * env(2880, 0.003, curve=1), np.zeros(1200), sq(220, 0.09, 0.5) * env(2880, 0.003, curve=1)) * 0.22,
    # menu cursor
    "ui_move": lambda: sq(midi(84), 0.035, 0.25) * env(1120, 0.001, curve=2) * 0.18,
    # a lata (chest) opening: crank of film and a bright chime
    "reel": lambda: cat(*[lowpass(noise(0.025), 0.5) * env(800, 0.001, curve=3) * 0.5 for _ in range(5)],
                        tri(midi(91), 0.3) * env(9600, 0.003, curve=2) * 0.6) * 0.6,
}


def write(name, x):
    x = np.clip(x, -1, 1)
    pcm = (x * 32000).astype("<i2")
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


if __name__ == "__main__":
    names = sys.argv[1:] or list(RECIPES)
    for n in names:
        write(n, RECIPES[n]())
        print("sfx", n)
