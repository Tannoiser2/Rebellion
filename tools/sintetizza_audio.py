#!/usr/bin/env python3
"""Sintetizza la musica (un tappeto spaziale originale: pad di archi sintetici, ostinato di
ottoni bassi e timpani lenti) e gli effetti sonori di Rebellion.

Tutto è generato qui, senza campioni esterni e senza citare musiche esistenti: nessun problema di licenza.
Uso: python3 tools/sintetizza_audio.py   (serve ffmpeg con libvorbis per la musica)
Scrive assets/audio/musica.ogg e assets/audio/*.wav
"""
import os
import subprocess
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
rng = np.random.default_rng(1977)


def hz(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def env(n, a, r, dur):
    t = np.arange(n) / SR
    return np.clip(t / max(a, 1e-4), 0, 1) * np.clip((dur - t) / max(r, 1e-4), 0, 1)


def lowpass(x, k):
    if k <= 1:
        return x
    return np.convolve(x, np.ones(k) / k, mode="same")


def saw(ph):
    return 2 * ((ph / (2 * np.pi)) % 1.0) - 1


def pad(freq, dur, vel=1.0):
    """Archi sintetici: tre denti di sega leggermente stonati, filtrati e con attacco lento."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    s = np.zeros(n)
    for d in (-0.07, 0.0, 0.06):
        f = freq * 2 ** (d / 12)
        s += saw(2 * np.pi * f * t + rng.uniform(0, 6))
    s = lowpass(s, 9)
    return s * env(n, 1.2, 1.5, dur) * vel / 3


def brass(freq, dur, vel=1.0):
    """Ottone basso: dente di sega con un filtro che si apre all'attacco."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    s = saw(2 * np.pi * freq * t) + 0.5 * saw(2 * np.pi * freq * 1.003 * t)
    bright = lowpass(s, 4)
    dark = lowpass(s, 22)
    mix = np.clip(1 - t / 0.25, 0, 1)
    s = bright * mix * 0.6 + dark * (1 - mix * 0.6)
    return s * env(n, 0.05, 0.25, dur) * vel


def timpani(dur, freq=55.0, vel=1.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = freq * (1 + 0.25 * np.exp(-t / 0.05))
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) * np.exp(-t / 0.7)
    hit = lowpass(rng.standard_normal(n), 6) * np.exp(-t / 0.04) * 0.4
    return (body + hit) * vel


def bell(freq, dur, vel=1.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    s = np.sin(2 * np.pi * freq * t) + 0.4 * np.sin(2 * np.pi * freq * 2.76 * t) * np.exp(-t / 0.4)
    return s * np.exp(-t / 1.6) * vel * np.clip(t / 0.003, 0, 1)


def add(buf, x, at):
    i = int(at * SR)
    j = min(len(buf), i + len(x))
    if i < len(buf):
        buf[i:j] += x[: j - i]


def reverb(x, wet=0.3):
    out = x.copy()
    for d, g in ((0.031, 0.5), (0.047, 0.42), (0.071, 0.35), (0.113, 0.27), (0.173, 0.2), (0.251, 0.14)):
        k = int(d * SR)
        out[k:] += x[:-k] * g * wet * 2
    return out


def music():
    """Circa 77 secondi in re minore, 66 bpm: progressione Dm – B♭ – Gm – A, poi Dm – F – C – A."""
    bpm = 66
    beat = 60 / bpm
    bars = 21
    total = bars * 4 * beat + 4
    L = np.zeros(int(total * SR))
    R = np.zeros(int(total * SR))
    prog = [
        [50, 53, 57, 62], [46, 50, 53, 58], [43, 50, 55, 58], [45, 49, 52, 57],
        [50, 53, 57, 62], [41, 48, 53, 57], [48, 52, 55, 60], [45, 49, 52, 57],
    ]
    roots = [38, 34, 31, 33, 38, 29, 36, 33]
    for b in range(bars):
        t0 = b * 4 * beat
        ch = prog[b % len(prog)]
        r = roots[b % len(roots)]
        for i, nn in enumerate(ch):
            p = pad(hz(nn), 4 * beat + 1.2, 0.16)
            pan = 0.3 + 0.4 * (i / 3)
            add(L, p * (1 - pan), t0)
            add(R, p * pan, t0)
        # ostinato degli ottoni: lungo-corto-corto-lungo
        if b >= 2:
            for (o, d, v) in ((0, 1.4, 0.32), (1.5, 0.45, 0.22), (2.0, 0.45, 0.22), (3.0, 0.9, 0.28)):
                x = brass(hz(r), d * beat, v)
                add(L, x * 0.55, t0 + o * beat)
                add(R, x * 0.45, t0 + o * beat)
        # timpani sul primo e sul terzo tempo
        if b >= 4:
            for o in (0, 2):
                x = timpani(1.6, hz(r - 12) * 1.0, 0.45 if o == 0 else 0.3)
                add(L, x * 0.5, t0 + o * beat)
                add(R, x * 0.5, t0 + o * beat)
        # campanelle lontane, una melodia lenta di quattro note
        if b >= 8 and b % 2 == 0:
            mel = [ch[-1] + 12, ch[-2] + 12, ch[-1] + 14, ch[-1] + 12]
            for k, m in enumerate(mel):
                x = bell(hz(m), 2.5, 0.08)
                add(L, x * 0.35, t0 + k * beat)
                add(R, x * 0.65, t0 + k * beat)
    # attacco e coda per un loop morbido
    fade = int(3 * SR)
    for ch_ in (L, R):
        ch_[:fade] *= np.linspace(0, 1, fade)
        ch_[-fade:] *= np.linspace(1, 0, fade)
    L = reverb(L, 0.35)
    R = reverb(R, 0.35)
    m = max(np.abs(L).max(), np.abs(R).max())
    st = np.stack([L, R], axis=1) / m * 0.8
    raw = os.path.join(OUT, "_musica.wav")
    _write(raw, st)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", raw, "-c:a", "libvorbis", "-q:a", "4", os.path.join(OUT, "musica.ogg")], check=True)
    os.remove(raw)


# ------------------------------------------------------------------ effetti

def sfx_click():
    n = int(0.06 * SR)
    t = np.arange(n) / SR
    return np.sin(2 * np.pi * 1850 * t) * np.exp(-t / 0.012) * 0.5 + np.sin(2 * np.pi * 2780 * t) * np.exp(-t / 0.006) * 0.25


def sfx_beep():
    n = int(0.22 * SR)
    t = np.arange(n) / SR
    f = np.where(t < 0.09, 1320, 1760)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.005, 0.03, 0.22) * 0.4


def sfx_blaster():
    n = int(0.32 * SR)
    t = np.arange(n) / SR
    f = 2400 * np.exp(-t / 0.06) + 180
    ph = 2 * np.pi * np.cumsum(f) / SR
    s = np.sin(ph) + 0.35 * np.sign(np.sin(ph * 0.5))
    return s * np.exp(-t / 0.09) * 0.45


def sfx_explosion():
    n = int(1.4 * SR)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    low = lowpass(noise, 40) * 3
    mid = lowpass(noise, 8)
    s = low * np.exp(-t / 0.5) + mid * np.exp(-t / 0.12) * 0.6
    s += np.sin(2 * np.pi * 45 * t) * np.exp(-t / 0.4) * 0.6
    return s * np.clip(t / 0.004, 0, 1) * 0.6


def sfx_hyper():
    """Salto nell'iperspazio: soffio che sale e un tonfo finale."""
    n = int(0.9 * SR)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    sweep = np.zeros(n)
    for k in (3, 6, 12, 24):
        sweep += lowpass(noise, k) * np.clip(t / 0.7, 0, 1) ** (k / 6)
    f = 120 + 900 * (t / 0.9) ** 2
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.3
    s = (sweep * 0.25 + tone) * env(n, 0.3, 0.12, 0.9)
    s[int(0.75 * SR):] += np.sin(2 * np.pi * 70 * t[: n - int(0.75 * SR)]) * np.exp(-t[: n - int(0.75 * SR)] / 0.08) * 0.6
    return s


def sfx_alarm():
    n = int(1.3 * SR)
    t = np.arange(n) / SR
    f = 620 + 260 * (np.sin(2 * np.pi * 2.2 * t) > 0)
    s = saw(2 * np.pi * np.cumsum(f) / SR)
    return lowpass(s, 5) * env(n, 0.01, 0.2, 1.3) * 0.35


def sfx_card():
    n = int(0.18 * SR)
    t = np.arange(n) / SR
    s = lowpass(rng.standard_normal(n), 3) * np.exp(-((t - 0.04) / 0.03) ** 2)
    return s * 0.5


def sfx_dice():
    n = int(0.5 * SR)
    out = np.zeros(n)
    for k in range(7):
        at = int(rng.uniform(0, 0.38) * SR)
        m = int(0.03 * SR)
        tt = np.arange(m) / SR
        click = lowpass(rng.standard_normal(m), 2) * np.exp(-tt / 0.006)
        out[at:at + m] += click[: n - at] * rng.uniform(0.3, 0.7)
    return out * 0.7


def sfx_success():
    out = np.zeros(int(1.0 * SR))
    for k, m in enumerate((62, 66, 69, 74)):
        add(out, bell(hz(m + 12), 0.8, 0.3), k * 0.09)
    return out


def sfx_fail():
    n = int(0.7 * SR)
    t = np.arange(n) / SR
    f = 330 * np.exp(-t / 0.6)
    s = saw(2 * np.pi * np.cumsum(f) / SR)
    return lowpass(s, 8) * env(n, 0.01, 0.2, 0.7) * 0.35


def sfx_turn():
    n = int(0.5 * SR)
    t = np.arange(n) / SR
    s = np.sin(2 * np.pi * 880 * t) * np.exp(-t / 0.2) * 0.3 + np.sin(2 * np.pi * 1320 * t) * np.exp(-t / 0.12) * 0.15
    return s * np.clip(t / 0.003, 0, 1)


def sfx_win():
    out = np.zeros(int(3.0 * SR))
    for k, (m, d) in enumerate(((50, 0.5), (57, 0.5), (62, 0.5), (65, 1.6))):
        x = brass(hz(m), d + 0.4, 0.4)
        add(out, x, k * 0.42)
    add(out, timpani(2.0, 55, 0.6), 1.26)
    return reverb(out, 0.3)


def sfx_capture():
    n = int(0.6 * SR)
    t = np.arange(n) / SR
    s = np.sin(2 * np.pi * 180 * t) * (np.sin(2 * np.pi * 30 * t) > 0) * 0.3
    return lowpass(s, 4) * env(n, 0.01, 0.2, 0.6)


def _write(path, data):
    data = np.asarray(data)
    if data.ndim == 1:
        data = data[:, None]
    pcm = (np.clip(data, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(data.shape[1])
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def main():
    os.makedirs(OUT, exist_ok=True)
    fx = {"click": sfx_click, "beep": sfx_beep, "blaster": sfx_blaster, "explosion": sfx_explosion,
          "hyper": sfx_hyper, "alarm": sfx_alarm, "card": sfx_card, "dice": sfx_dice, "success": sfx_success,
          "fail": sfx_fail, "turn": sfx_turn, "win": sfx_win, "capture": sfx_capture}
    for name, fn in fx.items():
        x = fn()
        m = np.abs(x).max()
        if m > 0.95:
            x = x / m * 0.95
        _write(os.path.join(OUT, name + ".wav"), x)
    music()
    print("audio scritto in", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
