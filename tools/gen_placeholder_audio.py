#!/usr/bin/env python3
"""Synthesises KENGEKI's placeholder audio from scratch (noise, sines, Karplus-Strong).
Everything produced here is original and free to use; replace any file by dropping a new
.wav/.ogg/.mp3 into the same audio/sfx/<category>/ folder (see docs/AUDIO.md).

Usage: python3 tools/gen_placeholder_audio.py
"""
import math
import os
import wave

import numpy as np

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio")
SR = 44100
rng = np.random.default_rng(7)


def write(path, data, sr=SR):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = np.asarray(data, dtype=np.float64)
    peak = np.max(np.abs(data)) or 1.0
    data = data / peak * 0.89
    pcm = (data * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())


def t_axis(dur, sr=SR):
    return np.arange(int(dur * sr)) / sr


def biquad(x, kind, f0, q=0.707, sr=SR):
    """RBJ biquad (lowpass/highpass/bandpass), constant coefficients."""
    w0 = 2 * math.pi * f0 / sr
    alpha = math.sin(w0) / (2 * q)
    c = math.cos(w0)
    if kind == "lp":
        b = [(1 - c) / 2, 1 - c, (1 - c) / 2]
    elif kind == "hp":
        b = [(1 + c) / 2, -(1 + c), (1 + c) / 2]
    else:  # band-pass, constant peak gain
        b = [alpha, 0.0, -alpha]
    a = [1 + alpha, -2 * c, 1 - alpha]
    b = [v / a[0] for v in b]
    a1, a2 = a[1] / a[0], a[2] / a[0]
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for i, xi in enumerate(x):
        yi = b[0] * xi + b[1] * x1 + b[2] * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, xi, y1, yi
        y[i] = yi
    return y


def sweep_bandpass(x, f_start, f_end, q=1.2, sr=SR, block=256):
    """Band-pass whose centre frequency glides (processed in blocks)."""
    out = np.zeros_like(x)
    state = [0.0, 0.0, 0.0, 0.0]
    n = len(x)
    for start in range(0, n, block):
        frac = start / max(n - 1, 1)
        f0 = f_start * (f_end / f_start) ** frac
        w0 = 2 * math.pi * f0 / sr
        alpha = math.sin(w0) / (2 * q)
        c = math.cos(w0)
        a0 = 1 + alpha
        b0, b2 = alpha / a0, -alpha / a0
        a1, a2 = -2 * c / a0, (1 - alpha) / a0
        x1, x2, y1, y2 = state
        for i in range(start, min(start + block, n)):
            xi = x[i]
            yi = b0 * xi + b2 * x2 - a1 * y1 - a2 * y2
            x2, x1, y2, y1 = x1, xi, y1, yi
            out[i] = yi
        state = [x1, x2, y1, y2]
    return out


def env_ar(n, attack, sr=SR, curve=2.0):
    a = int(attack * sr)
    e = np.ones(n)
    if a > 0:
        e[:a] = np.linspace(0, 1, a)
    rel = n - a
    e[a:] = np.linspace(1, 0, rel) ** curve
    return e


def noise(dur):
    return rng.uniform(-1, 1, int(dur * SR))


def metal(f0, dur, partials=(1.0, 2.76, 5.40, 8.93, 13.34), decays=(3.0, 4.5, 7.0, 10.0, 14.0), amps=(1, .7, .5, .35, .25)):
    t = t_axis(dur)
    y = np.zeros_like(t)
    for p, d, a in zip(partials, decays, amps):
        detune = 1 + rng.uniform(-0.004, 0.004)
        y += a * np.sin(2 * math.pi * f0 * p * detune * t + rng.uniform(0, 6)) * np.exp(-d * t)
    return y


def thump(f_start, f_end, dur, decay=18.0):
    t = t_axis(dur)
    f = f_end + (f_start - f_end) * np.exp(-t * 30)
    phase = 2 * math.pi * np.cumsum(f) / SR
    return np.sin(phase) * np.exp(-decay * t)


def place(dst, src, at):
    i = int(at * SR)
    end = min(len(dst), i + len(src))
    dst[i:end] += src[: end - i]
    return dst


def sfx(cat, idx, data):
    write(os.path.join(ROOT, "sfx", cat, f"{cat}_{idx:02d}.wav"), data)


def voice(f0, dur, formants=(700, 1200), drop=0.25, rough=0.3):
    """Very rough synthetic grunt: glottal saw through two formant band-passes."""
    t = t_axis(dur)
    f = f0 * (1 - drop * t / dur)
    phase = np.cumsum(f) / SR
    saw = 2 * (phase % 1.0) - 1
    src = saw + rough * noise(dur)[: len(t)]
    y = sum(biquad(src, "bp", fm, q=4.0) for fm in formants)
    return y * env_ar(len(t), 0.02, curve=1.5)


# --- Sound effects ----------------------------------------------------------------

def gen_sfx():
    for i in range(3):  # light katana swings: short whistling air cut
        d = 0.26 + 0.03 * i
        n = noise(d)
        y = sweep_bandpass(n, 900 + 200 * i, 3800 + 400 * i, q=2.0) * env_ar(len(n), 0.11, curve=2.5)
        sfx("swing_light", i, y)
    for i in range(2):  # heavy swings: longer, lower
        d = 0.42
        n = noise(d)
        y = sweep_bandpass(n, 500 + 100 * i, 2200, q=1.4) * env_ar(len(n), 0.2, curve=2.2)
        sfx("swing_heavy", i, y)
    for i in range(3):  # cut impacts (cloth/flesh): thud + damp noise
        d = 0.3
        th = thump(180 + 30 * i, 70, d, decay=16)
        n = biquad(noise(d), "lp", 1800) * np.exp(-28 * t_axis(d))
        sfx("impact", i, th * 0.9 + n * 1.2)
    for i in range(3):  # sword clashes: bright inharmonic ring + transient
        d = 0.9
        y = metal(950 + 170 * i, d)
        y[: int(0.004 * SR)] += noise(0.004) * 2
        sfx("clash", i, y + biquad(noise(d), "hp", 3000) * np.exp(-40 * t_axis(d)) * 0.6)
    for i in range(2):  # blocks: duller clank
        d = 0.4
        y = metal(620 + 90 * i, d, decays=(9, 12, 16, 20, 26)) + thump(220, 90, d, 25) * 0.6
        sfx("block", i, y)
    for i in range(2):  # parries: long bright ring
        d = 1.4
        y = metal(1500 + 220 * i, d, decays=(1.8, 2.5, 4, 6, 9)) + metal(2260 + 140 * i, d, decays=(2.2, 3, 5, 7, 11)) * 0.5
        y[: int(0.003 * SR)] += noise(0.003) * 3
        sfx("parry", i, y)
    d = 0.7  # guard break: clank + heavy thud
    sfx("guard_break", 0, metal(540, d, decays=(6, 8, 11, 15, 20)) + thump(140, 45, d, 9) * 1.4)
    for i in range(2):  # dodge: cloth whoosh + gravel scuff
        d = 0.32
        n = noise(d)
        y = sweep_bandpass(n, 1400, 500, q=0.9) * env_ar(len(n), 0.05, curve=2.0)
        scuff = biquad(noise(d), "hp", 2500) * np.exp(-14 * t_axis(d)) * 0.4
        sfx("dodge", i, y + scuff)
    for i in range(4):  # footsteps on gravel: clustered grains
        d = 0.18
        y = np.zeros(int(d * SR))
        for g in range(14):
            grain = biquad(noise(0.01), "bp", rng.uniform(1500, 5000), q=2.0) * np.hanning(int(0.01 * SR))
            place(y, grain * rng.uniform(0.3, 1.0), rng.uniform(0, 0.08))
        y += thump(110, 60, d, 40) * 0.35
        sfx("footstep", i, y)
    for i in range(3):  # enemy hurt grunts
        sfx("enemy_hurt", i, voice(115 + 15 * i, 0.28, formants=(650 + 40 * i, 1100)))
    for i in range(2):  # player hurt
        sfx("player_hurt", i, voice(135 + 12 * i, 0.24, formants=(720, 1250 + 60 * i)))
    for i in range(2):  # death: long falling grunt + body hitting the ground
        d = 1.2
        y = np.zeros(int(d * SR))
        place(y, voice(120 - 10 * i, 0.6, formants=(600, 1000), drop=0.45), 0.0)
        place(y, thump(120, 40, 0.5, 10) * 1.2 + biquad(noise(0.5), "lp", 900) * np.exp(-12 * t_axis(0.5)) * 0.8, 0.62)
        sfx("death", i, y)
    d = 0.35  # heavy attack warning: hyoshigi-like wooden clack
    y = np.zeros(int(d * SR))
    clack = biquad(noise(0.05), "bp", 1250, q=12) * np.exp(-60 * t_axis(0.05))
    place(y, clack, 0.0)
    sfx("heavy_warn", 0, y)
    d = 1.6  # counter stinger: taiko + ring
    y = thump(130, 55, d, 4.5) * 1.3 + metal(1300, d, decays=(2, 3, 5, 7, 10)) * 0.5
    sfx("counter", 0, y)
    d = 2.0  # finisher stinger: deeper taiko double hit
    y = np.zeros(int(d * SR))
    place(y, thump(110, 45, 1.5, 3.5) * 1.3, 0.0)
    place(y, thump(95, 40, 1.4, 3.0), 0.28)
    sfx("finisher", 0, y)
    d = 0.08  # UI
    sfx("ui_click", 0, biquad(noise(d), "bp", 2400, q=8) * np.exp(-70 * t_axis(d)))
    sfx("ui_open", 0, karplus(392.0, 0.6, damping=0.993) * 0.8)


# --- Music ----------------------------------------------------------------------

def karplus(freq, dur, sr=SR, damping=0.996, brightness=0.5):
    n = int(dur * sr)
    period = max(2, int(sr / freq))
    buf = rng.uniform(-1, 1, period)
    out = np.zeros(n)
    prev = 0.0
    idx = 0
    for i in range(n):
        v = buf[idx]
        out[i] = v
        nxt = damping * (brightness * v + (1 - brightness) * prev)
        prev = v
        buf[idx] = nxt
        idx = (idx + 1) % period
    return out


def gen_music():
    sr = 22050
    bpm = 72
    beat = 60.0 / bpm
    bars = 16
    dur = bars * 4 * beat
    n = int(dur * sr)
    mix = np.zeros(n + sr * 3)
    # Miyako-bushi (in) scale on E: E F A B C
    scale = [164.81, 174.61, 220.0, 246.94, 261.63, 329.63, 349.23, 440.0, 493.88]
    phrases = [
        [5, None, 4, 3, None, 2, 3, None], [4, 3, 2, None, 1, None, 0, None],
        [2, None, 3, 5, None, 6, 5, None], [4, None, 3, 2, 1, None, 0, None],
    ]
    def add(sig, at, gain):
        i = int(at * sr)
        end = min(len(mix), i + len(sig))
        mix[i:end] += sig[: end - i] * gain
    t = 0.0
    for bar in range(bars):
        phrase = phrases[bar % 4]
        for step, note in enumerate(phrase):
            if note is None:
                continue
            f = scale[note] * (0.5 if bar % 8 >= 4 and step % 4 == 0 else 1.0)
            add(karplus(f, 2.2, sr=sr, damping=0.9965, brightness=0.55), t + step * beat * 0.5, 0.55)
        # sparse taiko pulse on beats 1 and 3, with a softer pickup
        for b, g in ((0, 1.0), (2, 0.6), (3.5, 0.35)):
            tt = np.arange(int(1.0 * sr)) / sr
            f = 40 + 70 * np.exp(-tt * 25)
            drum = np.sin(2 * math.pi * np.cumsum(f) / sr) * np.exp(-tt * 5)
            add(drum, t + b * beat, 0.6 * g)
        t += 4 * beat
    # low drone (E2 + B2) with slow swell
    tt = np.arange(n) / sr
    drone = (np.sin(2 * math.pi * 82.41 * tt) + 0.5 * np.sin(2 * math.pi * 123.47 * tt)) * (0.5 + 0.5 * np.sin(2 * math.pi * tt / (8 * beat)))
    mix[:n] += drone * 0.12
    # Fold the tail into the start so the loop is seamless.
    tail = mix[n:]
    mix = mix[:n]
    mix[: len(tail)] += tail
    write(os.path.join(ROOT, "music", "courtyard_theme_placeholder.wav"), mix, sr=sr)


if __name__ == "__main__":
    gen_sfx()
    gen_music()
    print("audio generated in", os.path.normpath(ROOT))
