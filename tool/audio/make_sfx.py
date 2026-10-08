#!/usr/bin/env python3
"""Synthesizes the game's sound effects into assets/audio/ (mono 44.1 kHz WAV).

Python stdlib only. Deterministic: running it twice gives byte-identical files.

  python3 tool/audio/make_sfx.py

  thrust_loop.wav  seamless 4.5 s engine loop: roar + rumble + 42 Hz hum
  shot.wav         Talon nose cannon: triangle pitch drop 1900 -> 220 Hz, 0.14 s
  boom.wav         turret/reactor destroyed: sub thump + darkening noise + sparkle
  pickup.wav       fuel canister: double bubble glug + two-note chime (A5 -> E6)
  star.wav         octave-cascade jingle G5 -> C7, 1.08 s
  land.wav         pneumatic touchdown + hiss + E-major chime, 2.2 s
  ui_tap.wav       menu button blip 1800 -> 800 Hz, 60 ms
  alarm.wav        1 s meltdown loop: two square beeps (C6, E5)
  enemy_shot.wav   turret cannon: FM thump + low-passed whoosh, 0.18 s
  countdown.wav    3·2·1 beep (A5); countdown_go.wav: GO beep (A6)
  ui_launch.wav    LAUNCH / Retry / Next: rising power-up whoosh, 0.45 s
  ui_select.wav    tiles and secondary buttons: two-tone chirp, 70 ms
  ui_back.wav      back: descending two-tone blip, 90 ms
  ui_open.wav      panel slides in: rising filtered-noise scan + shimmer, 0.22 s
  ui_close.wav     panel slides out: the same scan falling, 0.18 s
  ui_toggle_on.wav / ui_toggle_off.wav  switch clicks, up / down, 50 ms
  ui_denied.wav    locked / can't afford: low double buzz, 0.2 s
  shield_hit.wav   hull shield meets rock: soft thump + shimmer, one hit, 0.3 s

attach.mp3 and crash.mp3 are hand-made and not generated here. A real file of
the same name can replace any of these.
"""

import math
import os
import random
import struct
import wave

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
OUT = os.path.join(ROOT, 'assets', 'audio')
SR = 44100
PEAK = 0.89125  # -1 dBFS


def write_wav(name, samples, sr=SR):
    pk = max(abs(s) for s in samples) or 1.0
    path = os.path.join(OUT, name)
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(b''.join(
            struct.pack('<h', int(s / pk * PEAK * 32767)) for s in samples))
    print(f'wrote {os.path.relpath(path, ROOT)} '
          f'({len(samples) / sr:.2f} s, {os.path.getsize(path) // 1024} KB)')


def expramp(t, t0, v0, t1, v1):
    if t <= t0:
        return v0
    if t >= t1:
        return v1
    return v0 * (v1 / v0) ** ((t - t0) / (t1 - t0))


# ── shot ────────────────────────────────────────────────────────────────────

def shot():
    rng = random.Random(7)
    dur, f0, f1, noise_mix, decay_pow = 0.14, 1900, 220, 0.08, 2.5
    n = int(SR * dur)
    att = max(1, int(0.0005 * SR))
    out, ph = [], 0.0
    for i in range(n):
        t = i / SR
        ph += 2 * math.pi * f0 * (f1 / f0) ** (t / dur) / SR
        x = ph / (2 * math.pi)
        s = 2 * abs(2 * (x - math.floor(x + 0.5))) - 1  # triangle
        s += noise_mix * rng.uniform(-1, 1) * math.exp(-t * 120)
        env = i / att if i < att else (1 - (i - att) / (n - att - 1)) ** decay_pow
        out.append(s * env)
    write_wav('shot.wav', out)


# ── boom ────────────────────────────────────────────────────────────────────

def boom():
    rng = random.Random(11)
    n = int(SR * 1.0)
    sub, noise, spk = [0.0] * n, [0.0] * n, [0.0] * n
    ph = 0.0
    for i in range(int(SR * 0.5)):  # sub thump 180 -> 30 Hz
        t = i / SR
        ph += 2 * math.pi * expramp(t, 0, 180, 0.4, 30) / SR
        sub[i] = math.sin(ph) * expramp(t, 0, 0.7, 0.5, 0.001)
    for i in range(int(SR * 0.9)):  # noise burst
        t = i / SR
        noise[i] = (rng.random() * 2 - 1) * expramp(t, 0, 0.8, 0.8, 0.001)
    # Darken the noise as it decays: one-pole low-pass 4 kHz -> 400 Hz, twice.
    for _ in range(2):
        p = 0.0
        for i in range(n):
            fc = expramp(i / SR, 0, 4000, 0.6, 400)
            p += (1 - math.exp(-2 * math.pi * fc / SR)) * (noise[i] - p)
            noise[i] = p
    ph = 0.0
    for i in range(int(SR * 0.2), int(SR * 0.9)):  # reward sparkle
        t = i / SR
        ph += 2 * math.pi * expramp(t, 0.2, 1600, 0.8, 5500) / SR
        g = 0.12 * min(1, (t - 0.25) / 0.08) if t > 0.25 else 0.0
        if t > 0.33:
            g *= expramp(t, 0.33, 1, 0.9, 0.001 / 0.12)
        spk[i] = math.sin(ph) * g
    write_wav('boom.wav', [a + 2.2 * b + c for a, b, c in zip(sub, noise, spk)])


# ── pickup ──────────────────────────────────────────────────────────────────

def pickup():
    dur, n1f, n2f = 0.40, 880.0, 1318.51
    n = int(SR * dur)
    gd = 0.08
    hd = gd / 2
    half = int(SR * gd) // 2
    out = [0.0] * n
    ph = 0.0
    for i in range(int(SR * gd)):  # two quick rising bubbles
        if i == half:
            ph = 0.0
        tl = i / SR if i < half else i / SR - hd
        f = 300 + 500 * (tl / hd) ** 1.5 if i < half else 350 + 600 * (tl / hd) ** 1.5
        ph += 2 * math.pi * f / SR
        out[i] += 0.45 * math.sin(ph) * math.sin(math.pi * tl / hd)
    for start, f, amp, h2, decay in ((0.03, n1f, 0.5, 0.3, 18.0),
                                     (0.12, n2f, 0.65, 0.35, 12.0)):
        s0 = int(start * SR)
        for i in range(s0, n):
            t = (i - s0) / SR
            out[i] += amp * (math.sin(2 * math.pi * f * t) +
                             h2 * math.sin(4 * math.pi * f * t)) * math.exp(-t * decay)
    att, fade = max(1, int(0.0005 * SR)), int(0.02 * SR)
    for i in range(n):
        e = i / att if i < att else 1.0
        if i >= n - fade:
            e = min(e, (n - 1 - i) / (fade - 1))
        out[i] *= e
    write_wav('pickup.wav', out)


# ── thrust loop ─────────────────────────────────────────────────────────────

_Q4 = (0.5412, 1.3066)  # 4th-order Butterworth as two biquads
_Q2 = (0.7071,)


def _biquad(x, kind, fc, q):
    w = 2 * math.pi * fc / SR
    al, c = math.sin(w) / (2 * q), math.cos(w)
    if kind == 'lp':
        b0, b1, b2 = (1 - c) / 2, 1 - c, (1 - c) / 2
    else:
        b0, b1, b2 = (1 + c) / 2, -(1 + c), (1 + c) / 2
    a0, a1, a2 = 1 + al, -2 * c, 1 - al
    b0, b1, b2, a1, a2 = b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
    y, x1, x2, y1, y2 = [0.0] * len(x), 0.0, 0.0, 0.0, 0.0
    for i, s in enumerate(x):
        o = b0 * s + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, s, y1, o
        y[i] = o
    return y


def _butter(x, kind, fc, qs):
    for q in qs:
        x = _biquad(x, kind, fc, q)
    return x


def _bandpass(x, lo, hi, qs):
    return _butter(_butter(x, 'hp', lo, qs), 'lp', hi, qs)


def thrust_loop():
    """Deep engine: band-passed roar, low rumble + 42 Hz hum, plasma whistle."""
    dur, fade, pre = 4.5, 0.4, 0.5
    roar_lo, roar_hi, rumble_f, plasma_f = 120, 2200, 42, 850
    rng = random.Random(3)
    total = int(SR * (pre + dur + fade))
    noise = [rng.uniform(-1, 1) for _ in range(total)]
    roar = _bandpass(noise, roar_lo, roar_hi, _Q4)
    rumble = _butter(noise, 'lp', 120, _Q4)
    plasma = _bandpass(noise, plasma_f - 150, plasma_f + 150, _Q2)
    # Whole cycles per loop, so the hum never cancels itself in the crossfade.
    rf, mf = round(rumble_f * dur) / dur, round(5 * dur) / dur
    mix = []
    for i in range(total):
        t = i / SR
        hum = math.sin(2 * math.pi * rf * t + 0.3 * math.sin(2 * math.pi * mf * t))
        mix.append(0.5 * roar[i] + 0.4 * (2.0 * rumble[i] + 0.5 * hum) + 0.2 * plasma[i])
    # Skip the filters' settling time; fade the tail's continuation into the head.
    p, n, f = int(SR * pre), int(SR * dur), int(SR * fade)
    body, over = mix[p:p + n], mix[p + n:p + n + f]
    for i in range(f):
        a = 0.5 * math.pi * i / (f - 1)
        body[i] = body[i] * math.sin(a) + over[i] * math.cos(a)
    write_wav('thrust_loop.wav', body)


# ── star ────────────────────────────────────────────────────────────────────

def star():
    """Octave cascade G5 C6 E6 G6 C7, the last note ringing."""
    notes, stagger = (783.99, 1046.50, 1318.51, 1567.98, 2093.00), 0.07
    out = [0.0] * int(SR * ((len(notes) - 1) * stagger + 0.8))
    for k, f in enumerate(notes):
        dur = 0.8 if k == len(notes) - 1 else 0.2
        s0 = int(SR * k * stagger)
        for i in range(int(SR * dur)):
            t = i / SR
            out[s0 + i] += 0.3 * (0.001 / 0.3) ** (t / dur) * math.sin(2 * math.pi * f * t)
    write_wav('star.wav', out)


# ── land ────────────────────────────────────────────────────────────────────

def land():
    """Pneumatic touchdown thud + hydraulic hiss, then a rising E-major chime."""
    rng = random.Random(3)
    dur, hiss_dur = 2.2, 0.55
    notes = (659.25, 830.61, 987.77, 1318.51)
    n = int(SR * dur)
    out = [0.7 * math.sin(2 * math.pi * 140 * i / SR) * math.exp(-i / SR * 22)
           for i in range(n)]
    hn = int(hiss_dur * SR)
    hiss = _bandpass([rng.uniform(-1, 1) for _ in range(hn)], 1200, 4800, _Q4)
    for i in range(hn):
        out[i] += 0.35 * hiss[i] * math.sin(math.pi * i / hn) ** 1.5
    att = max(1, int(0.001 * SR))
    for k, f in enumerate(notes):
        s0 = int((0.35 + k * 0.10) * SR)
        decay = 6.0 if k < len(notes) - 1 else 3.0
        for i in range(s0, n):
            t = (i - s0) / SR
            e = math.exp(-t * decay) * min(1, (i - s0) / att)
            out[i] += 0.5 * e * (0.75 * math.sin(2 * math.pi * f * t) +
                                 0.25 * math.sin(4 * math.pi * f * t))
    att, fade = max(1, int(0.0005 * SR)), int(0.04 * SR)
    for i in range(n):
        e = i / att if i < att else 1.0
        if i >= n - fade:
            e = min(e, (n - 1 - i) / (fade - 1))
        out[i] *= e
    write_wav('land.wav', out)


# ── ui tap ──────────────────────────────────────────────────────────────────

def ui_tap():
    """Soft blip: sine sweeping 1800 -> 800 Hz with a tiny noise tick, 60 ms."""
    rng = random.Random(1)
    dur, f0, f1 = 0.06, 1800, 800
    n = int(SR * dur)
    out, ph = [], 0.0
    for i in range(n):
        t = i / SR
        ph += 2 * math.pi * f0 * (f1 / f0) ** (t / dur) / SR
        s = math.sin(ph) + 0.15 * rng.uniform(-1, 1) * math.exp(-t * 150)
        out.append(s * math.exp(-t * 60))
    _edges(out, 0.005)
    write_wav('ui_tap.wav', out)


# ── meltdown alarm ──────────────────────────────────────────────────────────

def alarm():
    """1 s loop: two square beeps (C6, E5), 0.4 s each, 0.1 s apart."""
    n = SR
    out = [0.0] * n
    pl, gap = int(0.4 * SR), int(0.1 * SR)
    for start, f in ((0, 1046.0), (pl + gap, 659.0)):
        for j in range(pl):
            t = j / SR
            sq = 1.0 if math.sin(2 * math.pi * f * t) >= 0 else -1.0
            out[start + j] = sq * math.sin(math.pi * t / 0.4) ** 0.5
    write_wav('alarm.wav', out)


# ── enemy shot ──────────────────────────────────────────────────────────────

def enemy_shot():
    """Turret cannon: FM thump 300 -> 55 Hz + low-passed whoosh, 0.18 s."""
    rng = random.Random(2)
    dur, f0, f1, c0, c1 = 0.18, 300, 55, 1200, 220
    n = int(SR * dur)
    noise = [rng.uniform(-1, 1) for _ in range(n)]
    for _ in range(2):  # swept low-pass, continuous across the whole sound
        p = 0.0
        for i in range(n):
            fc = c0 * (c1 / c0) ** (i / SR / dur)
            p += (1 - math.exp(-2 * math.pi * fc / SR)) * (noise[i] - p)
            noise[i] = p
    out, ph = [], 0.0
    for i in range(n):
        t = i / SR
        ph += 2 * math.pi * f0 * (f1 / f0) ** (t / dur) / SR
        thump = math.sin(ph + 1.2 * math.sin(2 * ph)) * math.exp(-t * 22)
        whoosh = noise[i] * math.sin(math.pi * t / dur) ** 1.2
        out.append(0.7 * thump + 1.35 * whoosh)
    _edges(out, 0.02)
    write_wav('enemy_shot.wav', out)


# ── start countdown ─────────────────────────────────────────────────────────

def _beep(name, f, dur, decay):
    """Clean sine beep with a soft octave overtone."""
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        s = math.sin(2 * math.pi * f * t) + 0.25 * math.sin(4 * math.pi * f * t)
        out.append(s * math.exp(-t * decay))
    _edges(out, 0.01)
    write_wav(name, out)


def countdown():
    """3 · 2 · 1 beep (A5, 0.15 s) and the GO beep an octave up (A6, 0.45 s)."""
    _beep('countdown.wav', 880.0, 0.15, 18)
    _beep('countdown_go.wav', 1760.0, 0.45, 7)


# ── space UI kit ────────────────────────────────────────────────────────────

def _sweep(dur, f0, f1, decay, harm=0.0):
    """Sine sweeping f0 -> f1 (exponential) with an optional 2nd harmonic."""
    n = int(SR * dur)
    out, ph = [], 0.0
    for i in range(n):
        t = i / SR
        ph += 2 * math.pi * f0 * (f1 / f0) ** (t / dur) / SR
        out.append((math.sin(ph) + harm * math.sin(2 * ph)) * math.exp(-t * decay))
    return out


def _lowpassed_noise(seed, n, c0, c1, dur):
    rng = random.Random(seed)
    noise = [rng.uniform(-1, 1) for _ in range(n)]
    for _ in range(2):
        p = 0.0
        for i in range(n):
            fc = c0 * (c1 / c0) ** (i / SR / dur)
            p += (1 - math.exp(-2 * math.pi * fc / SR)) * (noise[i] - p)
            noise[i] = p
    return noise


def ui_launch():
    """Power-up: sine 180 -> 1400 Hz with a fifth above, rising noise swell."""
    dur = 0.45
    n = int(SR * dur)
    noise = _lowpassed_noise(11, n, 400, 5000, dur)
    out, ph = [], 0.0
    for i in range(n):
        t = i / SR
        f = 180 * (1400 / 180) ** ((t / dur) ** 0.7)
        ph += 2 * math.pi * f / SR
        env = math.sin(math.pi * min(1.0, t / dur * 1.15)) ** 0.8
        tone = math.sin(ph) + 0.4 * math.sin(1.5 * ph) + 0.2 * math.sin(2 * ph)
        out.append((0.7 * tone + 1.6 * noise[i] * (t / dur)) * env)
    _edges(out, 0.04)
    write_wav('ui_launch.wav', out)


def ui_select():
    """Two-tone chirp: 1320 Hz then 1980 Hz, 35 ms each."""
    out = _sweep(0.035, 1320, 1400, 40, 0.2) + _sweep(0.035, 1980, 2100, 60, 0.2)
    _edges(out, 0.006)
    write_wav('ui_select.wav', out)


def ui_back():
    """Descending blip: 1500 Hz then 900 Hz."""
    out = _sweep(0.045, 1500, 1350, 35, 0.2) + _sweep(0.045, 900, 760, 55, 0.2)
    _edges(out, 0.008)
    write_wav('ui_back.wav', out)


def _scan(name, seed, dur, c0, c1, f0, f1):
    n = int(SR * dur)
    noise = _lowpassed_noise(seed, n, c0, c1, dur)
    out, ph = [], 0.0
    for i in range(n):
        t = i / SR
        ph += 2 * math.pi * f0 * (f1 / f0) ** (t / dur) / SR
        env = math.sin(math.pi * t / dur) ** 1.5
        trem = 0.75 + 0.25 * math.sin(2 * math.pi * 38 * t)
        out.append((1.4 * noise[i] + 0.25 * math.sin(ph)) * env * trem)
    _edges(out, 0.02)
    write_wav(name, out)


def ui_open():
    _scan('ui_open.wav', 12, 0.22, 600, 4200, 900, 2400)


def ui_close():
    _scan('ui_close.wav', 13, 0.18, 4200, 600, 2400, 900)


def ui_toggles():
    on = _sweep(0.05, 900, 1700, 70, 0.3)
    _edges(on, 0.006)
    write_wav('ui_toggle_on.wav', on)
    off = _sweep(0.05, 1500, 700, 70, 0.3)
    _edges(off, 0.006)
    write_wav('ui_toggle_off.wav', off)


def ui_denied():
    """Low double buzz: two 75 ms square-ish pulses at 140 Hz."""
    out = []
    for k in range(2):
        n = int(0.075 * SR)
        for i in range(n):
            t = i / SR
            s = math.tanh(3 * math.sin(2 * math.pi * 140 * t))
            s += 0.3 * math.sin(2 * math.pi * 283 * t)
            out.append(s * math.sin(math.pi * t / 0.075) ** 0.6)
        if k == 0:
            out += [0.0] * int(0.04 * SR)
    _edges(out, 0.01)
    write_wav('ui_denied.wav', out)


# ── shield hit ──────────────────────────────────────────────────────────────

def shield_hit():
    """One soft deflector hit: a low thump, an electric shimmer falling
    1100 -> 650 Hz with a 34 Hz flutter, and a quick band-passed fizz."""
    rng = random.Random(11)
    dur = 0.3
    n = int(SR * dur)
    thump = _sweep(dur, 170, 85, 18)
    shimmer = _sweep(dur, 1100, 650, 11, harm=0.35)
    fizz = _bandpass([rng.uniform(-1, 1) for _ in range(n)], 2500, 7000, _Q4)
    out = []
    for i in range(n):
        t = i / SR
        flutter = 0.65 + 0.35 * math.sin(2 * math.pi * 34 * t)
        out.append(0.8 * thump[i] + 0.35 * shimmer[i] * flutter +
                   0.18 * fizz[i] * math.exp(-t * 26))
    _edges(out, 0.06)
    write_wav('shield_hit.wav', out)


def _edges(out, fade_s):
    """0.5 ms attack ramp and a linear fade-out of [fade_s]."""
    att, fade = max(1, int(0.0005 * SR)), int(fade_s * SR)
    n = len(out)
    for i in range(n):
        e = i / att if i < att else 1.0
        if i >= n - fade:
            e = min(e, (n - 1 - i) / (fade - 1))
        out[i] *= e


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    shot()
    boom()
    pickup()
    thrust_loop()
    star()
    land()
    ui_tap()
    alarm()
    enemy_shot()
    countdown()
    ui_launch()
    ui_select()
    ui_back()
    ui_open()
    ui_close()
    ui_toggles()
    ui_denied()
    shield_hit()
