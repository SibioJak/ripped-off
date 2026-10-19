#!/usr/bin/env python3
"""Ripped-Off M3 audio renderer.

Every sound in the game is synthesized here with numpy and rendered
offline, so every committed asset is reproducible:

    python3 tools/render_audio.py

Music loops are rendered as 16-bit WAV masters (into a temp dir),
then encoded to OGG (ffmpeg libvorbis, q5) under audio/music/.
SFX one-shots stay WAV under audio/sfx/. A manifest with exact
sample counts lands at audio/manifest.json for the test harness.

Musical design (Chris's spec, in his priority order): complex
pattern work first (3 rotating variants each of bass and arp),
polyrhythms (loops at 16 / 12 / 10 / 32 beats phase against each
other), syncopation (off-beat bass, pushed 16ths, displaced hat
accents), layered loops (stems fade in by rank in the game).

Tempo 134 BPM. One rounded samples-per-beat constant is used for
every loop (SPB below), so all loops are exact beat multiples on a
shared sample grid and stay phase-locked forever; the differing
beat COUNTS create the polyrhythm. Effective tempo at SPB is
44100*60/19761 = 133.90 BPM.

Kick B (Chris's locked standard): sine pitch sweep 120 -> 40 Hz,
~0.40 s body, heavy sub-80 Hz energy. The sub-80 share of one
isolated kick is measured and printed below.
"""

import json
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np

SR = 44100
BPM = 134.0
SPB = int(round(SR * 60.0 / BPM))  # 19761 samples per beat, THE grid

REPO = Path(__file__).resolve().parent.parent
MUSIC_DIR = REPO / "audio" / "music"
SFX_DIR = REPO / "audio" / "sfx"
MANIFEST = REPO / "audio" / "manifest.json"

RNG = np.random.default_rng(20261018)

LOG = []  # (name, seconds, peak, rms)


# ---------------------------------------------------------------- helpers

def n_beats(beats: float) -> int:
    return int(round(beats * SPB))


def t_axis(n: int) -> np.ndarray:
    return np.arange(n, dtype=np.float64) / SR


def norm_to(x: np.ndarray, peak: float) -> np.ndarray:
    m = float(np.max(np.abs(x))) if x.size else 0.0
    return x * (peak / m) if m > 0.0 else x


def write_wav(path: Path, data: np.ndarray) -> None:
    """data: mono (n,) or stereo (n,2) float in -1..1 -> 16-bit PCM."""
    path.parent.mkdir(parents=True, exist_ok=True)
    if data.ndim == 1:
        data = data[:, None]
    pcm = np.clip(data, -1.0, 1.0)
    pcm16 = (pcm * 32767.0).astype("<i2")
    n = pcm16.shape[0]
    ch = pcm16.shape[1]
    byte_rate = SR * ch * 2
    block = ch * 2
    data_bytes = pcm16.tobytes()
    header = (
        b"RIFF" + (36 + len(data_bytes)).to_bytes(4, "little") + b"WAVE"
        + b"fmt " + (16).to_bytes(4, "little")
        + (1).to_bytes(2, "little") + ch.to_bytes(2, "little")
        + SR.to_bytes(4, "little") + byte_rate.to_bytes(4, "little")
        + block.to_bytes(2, "little") + (16).to_bytes(2, "little")
        + b"data" + len(data_bytes).to_bytes(4, "little")
    )
    path.write_bytes(header + data_bytes)


def report(name: str, data: np.ndarray) -> None:
    peak = float(np.max(np.abs(data))) if data.size else 0.0
    rms = float(np.sqrt(np.mean(np.square(data)))) if data.size else 0.0
    LOG.append((name, data.shape[0] / SR, peak, rms))


def fft_filter(x: np.ndarray, keep) -> np.ndarray:
    """Zero-phase FFT filter; keep(freq_hz) -> gain array/scalar."""
    n = x.shape[0]
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(n, 1.0 / SR)
    spec *= keep(freqs)
    return np.fft.irfft(spec, n)


def lowpass(x: np.ndarray, fc: float) -> np.ndarray:
    return fft_filter(x, lambda f: 1.0 / np.sqrt(1.0 + (f / fc) ** 4))


def highpass(x: np.ndarray, fc: float) -> np.ndarray:
    return fft_filter(x, lambda f: (f / fc) ** 2 / np.sqrt(1.0 + (f / fc) ** 4))


def bandpass(x: np.ndarray, lo: float, hi: float) -> np.ndarray:
    return lowpass(highpass(x, lo), hi)


def place(buf: np.ndarray, sig: np.ndarray, start: int) -> None:
    """Add sig into mono buf at sample start, clipping at the end."""
    if start >= buf.shape[0]:
        return
    end = min(buf.shape[0], start + sig.shape[0])
    buf[start:end] += sig[: end - start]


def place_st(buf: np.ndarray, sig: np.ndarray, start: int, pan: float) -> None:
    """Add mono sig into stereo buf (n,2); pan -1..1 (equal power)."""
    if start >= buf.shape[0]:
        return
    end = min(buf.shape[0], start + sig.shape[0])
    seg = sig[: end - start]
    ang = (pan + 1.0) * np.pi / 4.0
    buf[start:end, 0] += seg * np.cos(ang)
    buf[start:end, 1] += seg * np.sin(ang)


def place_wrap(buf: np.ndarray, sig: np.ndarray, start: int) -> None:
    """Add sig into a circular mono buffer (wraps past the end)."""
    n = buf.shape[0]
    idx = (start + np.arange(sig.shape[0])) % n
    np.add.at(buf, idx, sig)


# ---------------------------------------------------------------- synths

def kick_oneshot() -> np.ndarray:
    """Kick B: pitch sweep 120 -> 40 Hz, ~0.40 s body."""
    n = int(0.45 * SR)
    t = t_axis(n)
    freq = 40.0 + 80.0 * np.exp(-t / 0.055)
    phase = 2.0 * np.pi * np.cumsum(freq) / SR
    amp = (1.0 - np.exp(-t / 0.0025)) * np.exp(-t / 0.135)
    x = np.sin(phase) * amp
    cn = int(0.004 * SR)  # faint attack click
    ct = t_axis(cn)
    x[:cn] += 0.22 * np.sin(2.0 * np.pi * 1400.0 * ct) * np.exp(-ct / 0.0012)
    return x * 0.95


def measure_sub80(x: np.ndarray) -> float:
    """Share of total energy below 80 Hz (one beat, zero-padded)."""
    n = SPB
    buf = np.zeros(n)
    buf[: min(n, x.shape[0])] = x[: min(n, x.shape[0])]
    spec = np.fft.rfft(buf)
    freqs = np.fft.rfftfreq(n, 1.0 / SR)
    energy = np.abs(spec) ** 2
    return float(energy[freqs < 80.0].sum() / max(energy.sum(), 1e-12))


def closed_hat(dur: float = 0.045, gain: float = 1.0) -> np.ndarray:
    n = int(dur * SR)
    t = t_axis(n)
    noise = RNG.standard_normal(n)
    x = highpass(noise, 7500.0) * np.exp(-t / 0.012)
    return x * gain


def open_hat() -> np.ndarray:
    n = int(0.30 * SR)
    t = t_axis(n)
    noise = RNG.standard_normal(n)
    x = highpass(noise, 7000.0) * np.exp(-t / 0.085)
    return x


def shaker() -> np.ndarray:
    n = int(0.11 * SR)
    t = t_axis(n)
    noise = RNG.standard_normal(n)
    env = (1.0 - np.exp(-t / 0.012)) * np.exp(-t / 0.038)
    return bandpass(noise, 5200.0, 9800.0) * env


def metallic_hit(decay: float = 0.04, gain: float = 1.0) -> np.ndarray:
    n = int(0.09 * SR)
    t = t_axis(n)
    x = np.zeros(n)
    for f, g in ((6170.0, 0.50), (8450.0, 0.36), (10830.0, 0.26), (14200.0, 0.15)):
        x += g * np.sin(2.0 * np.pi * f * t) * np.exp(-t / (decay * (0.7 + 0.3 * g)))
    x += 0.30 * highpass(RNG.standard_normal(n), 9000.0) * np.exp(-t / 0.008)
    return x * gain


def clap() -> np.ndarray:
    n = int(0.30 * SR)
    t = t_axis(n)
    noise = RNG.standard_normal(n)
    env = np.exp(-t / 0.16)
    for bt in (0.0, 0.011, 0.023):
        env += np.exp(-np.abs(t - bt) / 0.0022)
    return bandpass(noise, 1100.0, 4200.0) * env


def bass_note(freq: float, dur: float, accent: float = 1.0) -> np.ndarray:
    """Dark saw-ish bass: additive harmonics behind a lowpass curve
    that opens with the note's attack and settles down (resonant
    character rendered into the sample; no runtime effects)."""
    n = int(dur * SR)
    t = t_axis(n)
    fc = (240.0 + 780.0 * np.exp(-t / 0.07)) * (0.8 + 0.45 * accent)
    out = np.zeros(n)
    for k in range(1, 15):
        f = k * freq
        if f > 9000.0:
            break
        g = (1.0 / k) / (1.0 + (f / fc) ** 2)
        out += g * np.sin(2.0 * np.pi * f * t)
    env = (1.0 - np.exp(-t / 0.004)) * np.exp(-t / (dur * 0.42))
    return out * env * (0.55 + 0.45 * accent)


def arp_note(freq: float, dur: float = 0.19) -> np.ndarray:
    """Mid-register dark pluck: sine + soft harmonics, fast decay."""
    n = int(dur * SR)
    t = t_axis(n)
    x = (np.sin(2.0 * np.pi * freq * t)
         + 0.28 * np.sin(2.0 * np.pi * 2.0 * freq * t)
         + 0.10 * np.sin(2.0 * np.pi * 3.0 * freq * t))
    env = (1.0 - np.exp(-t / 0.003)) * np.exp(-t / 0.062)
    return x * env


def pad_chord(freqs, dur: float) -> np.ndarray:
    """One chord segment for the circular pad buffer: detuned
    additive voices with slow raised-cosine edges."""
    n = int(dur * SR)
    t = t_axis(n)
    ramp = int(1.1 * SR)
    env = np.ones(n)
    env[:ramp] = 0.5 - 0.5 * np.cos(np.pi * np.arange(ramp) / ramp)
    env[-ramp:] = 0.5 + 0.5 * np.cos(np.pi * np.arange(ramp) / ramp)
    out = np.zeros(n)
    for f in freqs:
        for det, g in ((0.9977, 0.5), (1.0023, 0.5)):
            voice = np.zeros(n)
            for k in range(1, 6):
                voice += (1.0 / k ** 1.6) * np.sin(2.0 * np.pi * k * f * det * t)
            out += g * voice
    return out * env


# ---------------------------------------------------------------- music data

# A minor progression, one chord per bar: Am - F - C - G.
ROOTS = [55.00, 43.65, 65.41, 49.00]  # A1, F1, C2, G1
CHORD_TONES = [
    [110.00, 130.81, 164.81, 220.00],   # Am: A2 C3 E3 A3
    [87.31, 110.00, 130.81, 174.61],    # F:  F2 A2 C3 F3
    [130.81, 164.81, 196.00, 261.63],   # C:  C3 E3 G3 C4
    [98.00, 123.47, 146.83, 196.00],    # G:  G2 B2 D3 G3
]

# Bass patterns on a 16th-note grid per bar:
# (sixteenth_index, semitone_offset, length_in_sixteenths, accent)
BASS_PATTERNS = {
    "a": [(2, 0, 3, 0.9), (6, 0, 3, 1.0), (10, 0, 3, 0.9), (14, 0, 3, 1.0)],
    "b": [(2, 0, 3, 1.0), (6, 0, 1, 0.8), (7, 12, 2, 0.9),
          (10, 0, 3, 0.95), (14, 0, 3, 1.0)],
    "c": [(2, 0, 3, 0.95), (6, 0, 3, 0.85), (10, 7, 3, 0.9),
          (12, 0, 2, 0.8), (14, 12, 3, 1.0)],
}

# Arp variants: per 8th-step, an index into the chord's tone list,
# or -1 for a rest. 24 steps = 12 beats; chords change every 6 steps
# (3 beats), so the arp phases against the 4-bar progression.
ARP_PATTERNS = {
    "a": [0, 1, 2, 3, 2, 1] * 4,
    "b": [0, 2, 1, 3, 2, 0, 1, 3, 2, 1, 0, 2,
          3, 1, 2, 0, 2, 3, 1, 2, 0, 1, 3, 2],
    "c": [0, -1, 2, 1, -1, 3, 2, -1, 0, 3, -1, 2,
          1, -1, 3, 0, -1, 2, 3, -1, 1, 2, -1, 0],
}


def render_kick_loop() -> np.ndarray:
    n = n_beats(16)
    buf = np.zeros(n)
    one = kick_oneshot()
    for b in range(16):
        place(buf, one, b * SPB)
    return buf


def render_hats_loop() -> np.ndarray:
    n = n_beats(16)
    buf = np.zeros((n, 2))
    oh = open_hat()
    accent16 = [0.50, 0.0, 0.85, 0.30, 0.0, 0.0, 0.95, 0.35,
                0.55, 0.0, 0.80, 0.0, 0.30, 0.90, 0.0, 0.65]
    for beat in range(16):
        # off-beat open hat (the "and" of every beat)
        place_st(buf, oh, beat * SPB + SPB // 2, 0.15 if beat % 2 else -0.15)
        # syncopated closed-hat accents on the 16th grid
        for s in range(4):
            g = accent16[s] * (0.8 + 0.2 * (beat % 4 == 3))
            if g > 0.0:
                place_st(buf, closed_hat(gain=g),
                         beat * SPB + s * SPB // 4, -0.2 + 0.1 * s)
    return buf


def render_perc_loop() -> np.ndarray:
    n = n_beats(10)  # 20 eighth-steps: polyrhythm against 16
    buf = np.zeros((n, 2))
    metal_steps = {0: 1.0, 3: 0.7, 6: 0.9, 10: 1.0, 13: 0.65, 16: 0.85, 18: 0.6}
    shaker_steps = {4: 0.8, 9: 0.7, 14: 0.85, 19: 0.75}
    for step, g in metal_steps.items():
        place_st(buf, metallic_hit(gain=g), step * SPB // 2, 0.35)
    for step, g in shaker_steps.items():
        place_st(buf, shaker() * g, step * SPB // 2, -0.35)
    return buf


def render_drive_loop() -> np.ndarray:
    n = n_beats(16)
    buf = np.zeros((n, 2))
    cl = clap()
    for bar in range(4):
        for beat_in_bar in (1, 3):  # beats 2 and 4 of each bar
            place_st(buf, cl, (bar * 4 + beat_in_bar) * SPB, 0.0)
    for step in range(64):  # extra 16th closed hats, driving
        g = 0.30 + (0.25 if step % 4 == 2 else 0.0)
        place_st(buf, closed_hat(dur=0.03, gain=g), step * SPB // 4,
                 0.1 if step % 2 else -0.1)
    ping_t = t_axis(int(0.25 * SR))
    ping = (np.sin(2.0 * np.pi * 5870.0 * ping_t)
            + 0.6 * np.sin(2.0 * np.pi * 8450.0 * ping_t)) * np.exp(-ping_t / 0.07)
    place_st(buf, ping * 0.20, 15 * SPB + SPB // 2, 0.3)  # last off-beat lift
    return buf


def render_bass_loop(variant: str) -> np.ndarray:
    n = n_beats(16)
    buf = np.zeros(n)
    pat = BASS_PATTERNS[variant]
    sixteenth = SPB // 4
    for bar in range(4):
        root = ROOTS[bar]
        for idx, semi, length, accent in pat:
            f = root * (2.0 ** (semi / 12.0))
            note = bass_note(f, length * sixteenth / SR * 0.96, accent)
            place(buf, note, bar * 4 * SPB + idx * sixteenth)
    return buf


def render_arp_loop(variant: str) -> np.ndarray:
    n = n_beats(12)  # 12 beats against the 16-beat grid: polyrhythm
    buf = np.zeros((n, 2))
    pat = ARP_PATTERNS[variant]
    for step, tone_idx in enumerate(pat):
        if tone_idx < 0:
            continue
        chord = CHORD_TONES[(step // 6) % 4]
        f = chord[tone_idx]
        pan = -0.3 if step % 2 == 0 else 0.3
        place_st(buf, arp_note(f), step * SPB // 2, pan)
    return buf


def render_pad_loop() -> np.ndarray:
    n = n_beats(32)  # chords every 8 beats: Am F C G, twice
    buf = np.zeros(n)
    for seg in range(4):
        chord = CHORD_TONES[seg % 4]
        seg_sig = pad_chord(chord, n_beats(8) / SR)
        place_wrap(buf, seg_sig, seg * n_beats(8))
    return buf


def render_title_loop() -> np.ndarray:
    """Sparse robo-minimal: a soft half-time pulse, long bass notes
    with air around them, one quiet arp figure. 16 beats."""
    n = n_beats(16)
    buf = np.zeros((n, 2))
    pt = t_axis(int(0.55 * SR))
    pulse = np.sin(2.0 * np.pi * (46.0 + 24.0 * np.exp(-pt / 0.09)) * pt) \
        * (1.0 - np.exp(-pt / 0.006)) * np.exp(-pt / 0.20)
    for beat in (0, 10):  # half-time pulse, second hit pushed
        place_st(buf, pulse * 0.8, beat * SPB, 0.0)
    for start_beat, root in ((0, 55.00), (8, 43.65)):
        dur = n_beats(5.5) / SR
        tt = t_axis(int(dur * SR))
        note = (np.sin(2.0 * np.pi * root * tt)
                + 0.22 * np.sin(2.0 * np.pi * 2.0 * root * tt)) \
            * (1.0 - np.exp(-tt / 0.03)) * np.exp(-tt / 1.5)
        place_st(buf, note * 0.5, start_beat * SPB, 0.0)
    for step in (0, 6, 12, 18, 24, 30):  # one quiet figure, wide gaps
        f = [220.00, 261.63, 329.63, 261.63, 220.00, 164.81][(step // 6) % 6]
        place_st(buf, arp_note(f, 0.30) * 0.35, step * SPB // 2, 0.2)
    return buf


# ---------------------------------------------------------------- SFX synths

def sfx_shot() -> np.ndarray:
    """Constant-fire sound: very short, low-mid body, nothing harsh."""
    n = int(0.075 * SR)
    t = t_axis(n)
    freq = 300.0 + 620.0 * np.exp(-t / 0.012)
    phase = 2.0 * np.pi * np.cumsum(freq) / SR
    x = np.sin(phase) * np.exp(-t / 0.020)
    x += 0.35 * np.sin(2.0 * np.pi * 190.0 * t) * np.exp(-t / 0.030)
    return norm_to(x, 0.50)


def sfx_death_grabber() -> np.ndarray:
    """Mid thud-pop: a soft body giving way."""
    n = int(0.26 * SR)
    t = t_axis(n)
    freq = 58.0 + 165.0 * np.exp(-t / 0.030)
    phase = 2.0 * np.pi * np.cumsum(freq) / SR
    x = np.sin(phase) * np.exp(-t / 0.075)
    x += 0.40 * lowpass(RNG.standard_normal(n), 900.0) * np.exp(-t / 0.045)
    return norm_to(x, 0.70)


def sfx_death_gunner() -> np.ndarray:
    """Same family, different material: tighter crack, metallic edge."""
    n = int(0.20 * SR)
    t = t_axis(n)
    freq = 115.0 + 390.0 * np.exp(-t / 0.016)
    phase = 2.0 * np.pi * np.cumsum(freq) / SR
    x = np.sin(phase) * np.exp(-t / 0.048)
    for f, g in ((1244.0, 0.30), (1873.0, 0.20), (2510.0, 0.12)):
        x += g * np.sin(2.0 * np.pi * f * t) * np.exp(-t / 0.020)
    x += 0.30 * highpass(RNG.standard_normal(n), 2600.0) * np.exp(-t / 0.010)
    return norm_to(x, 0.68)


def sfx_hit_tick() -> np.ndarray:
    """Tiny confirm tick (rendered now; armoured targets come later)."""
    n = int(0.03 * SR)
    t = t_axis(n)
    x = np.sin(2.0 * np.pi * 1350.0 * t) * np.exp(-t / 0.008)
    return norm_to(x, 0.32)


def sfx_shard_collect() -> np.ndarray:
    """Soft blip; the game steps its pitch up during a combo."""
    n = int(0.07 * SR)
    t = t_axis(n)
    freq = 660.0 + 220.0 * (1.0 - np.exp(-t / 0.010))
    phase = 2.0 * np.pi * np.cumsum(freq) / SR
    x = np.sin(phase) * (1.0 - np.exp(-t / 0.002)) * np.exp(-t / 0.020)
    return norm_to(x, 0.42)


def _warm_note(freq: float, dur: float, gain: float) -> np.ndarray:
    n = int(dur * SR)
    t = t_axis(n)
    x = (np.sin(2.0 * np.pi * freq * t)
         + 0.30 * np.sin(2.0 * np.pi * 2.0 * freq * t)
         + 0.10 * np.sin(2.0 * np.pi * 3.0 * freq * t))
    env = (1.0 - np.exp(-t / 0.008)) * np.exp(-t / (dur * 0.38))
    return x * env * gain


def sfx_recovery(size: str) -> np.ndarray:
    """Deposit completion, three sizes: bigger haul, bigger sound.
    Warm low/mid notes in the game's synth voice — no sparkle."""
    if size == "small":
        return norm_to(_warm_note(196.00, 0.20, 0.8), 0.55)
    if size == "mid":
        out = np.zeros(int(0.34 * SR))
        place(out, _warm_note(196.00, 0.22, 0.8), 0)
        place(out, _warm_note(261.63, 0.24, 0.8), int(0.10 * SR))
        return norm_to(out, 0.58)
    out = np.zeros(int(0.52 * SR))
    place(out, _warm_note(196.00, 0.22, 0.8), 0)
    place(out, _warm_note(261.63, 0.24, 0.85), int(0.11 * SR))
    place(out, _warm_note(329.63, 0.30, 0.9), int(0.23 * SR))
    return norm_to(out, 0.62)


def sfx_buzz() -> np.ndarray:
    n = int(0.045 * SR)
    t = t_axis(n)
    freq = 720.0 + 180.0 * np.exp(-t / 0.010)
    phase = 2.0 * np.pi * np.cumsum(freq) / SR
    x = np.sin(phase) * np.exp(-t / 0.013)
    return norm_to(x, 0.26)  # subtle on purpose: it can fire often


def sfx_tow_latch() -> np.ndarray:
    """Soft click-lock: two mechanical clicks over a low thunk."""
    n = int(0.10 * SR)
    t = t_axis(n)
    x = 0.55 * np.sin(2.0 * np.pi * 130.0 * t) * np.exp(-t / 0.028)
    click = highpass(RNG.standard_normal(n), 3000.0)
    for at, g in ((0.0, 0.5), (0.035, 0.65)):
        s = int(at * SR)
        x[s:s + int(0.008 * SR)] += g * click[s:s + int(0.008 * SR)] \
            * np.exp(-t_axis(int(0.008 * SR)) / 0.002)
    return norm_to(x, 0.55)


def sfx_canister_stolen() -> np.ndarray:
    """Low warning two-tone: a canister just left the arena."""
    n = int(0.38 * SR)
    t = t_axis(n)
    freq = np.where(t < 0.16, 220.0, 164.81)
    tone = np.sin(2.0 * np.pi * np.cumsum(freq) / SR) \
        + 0.25 * np.sin(2.0 * np.pi * 3.0 * np.cumsum(freq) / SR)
    gate = ((t < 0.15) | ((t > 0.19) & (t < 0.36))).astype(np.float64)
    gate *= 1.0 - np.exp(-t / 0.004)
    return norm_to(tone * gate * np.exp(-np.maximum(t - 0.34, 0.0) / 0.02), 0.55)


def sfx_player_death() -> np.ndarray:
    """Aversive and unmistakable: low boom, noise burst, fall."""
    n = int(0.65 * SR)
    t = t_axis(n)
    freq = 32.0 + 130.0 * np.exp(-t / 0.045)
    phase = 2.0 * np.pi * np.cumsum(freq) / SR
    x = 1.15 * np.sin(phase) * np.exp(-t / 0.16)
    x += 0.55 * lowpass(RNG.standard_normal(n), 1400.0) * np.exp(-t / 0.07)
    sweep_f = 65.0 + 340.0 * np.exp(-t / 0.30)
    sweep_p = 2.0 * np.pi * np.cumsum(sweep_f) / SR
    x += 0.22 * np.sin(sweep_p) * np.exp(-t / 0.22) * (t > 0.02)
    return norm_to(x, 0.85)


def sfx_wave_start() -> np.ndarray:
    out = np.zeros(int(0.45 * SR))
    for i, f in enumerate((261.63, 329.63, 392.00)):
        place(out, _warm_note(f, 0.22, 0.7), int(i * 0.09 * SR))
    return norm_to(out, 0.55)


def sfx_game_over() -> np.ndarray:
    out = np.zeros(int(1.0 * SR))
    for i, f in enumerate((392.00, 329.63, 261.63, 196.00)):
        place(out, _warm_note(f, 0.30, 0.7), int(i * 0.17 * SR))
    return norm_to(out, 0.55)


def sfx_ui_start() -> np.ndarray:
    n = int(0.09 * SR)
    t = t_axis(n)
    freq = 520.0 + 150.0 * (1.0 - np.exp(-t / 0.012))
    phase = 2.0 * np.pi * np.cumsum(freq) / SR
    x = np.sin(phase) * (1.0 - np.exp(-t / 0.003)) * np.exp(-t / 0.026)
    return norm_to(x, 0.45)


SFX_BUILDERS = {
    "shot": sfx_shot,
    "death_grabber": sfx_death_grabber,
    "death_gunner": sfx_death_gunner,
    "hit_tick": sfx_hit_tick,
    "shard_collect": sfx_shard_collect,
    "recovery_small": lambda: sfx_recovery("small"),
    "recovery_mid": lambda: sfx_recovery("mid"),
    "recovery_large": lambda: sfx_recovery("large"),
    "buzz": sfx_buzz,
    "tow_latch": sfx_tow_latch,
    "canister_stolen": sfx_canister_stolen,
    "player_death": sfx_player_death,
    "wave_start": sfx_wave_start,
    "game_over": sfx_game_over,
    "ui_start": sfx_ui_start,
}

# (name, builder, beats, peak target)
MUSIC_BUILDERS = [
    ("kick", render_kick_loop, 16, 0.70),
    ("hats", render_hats_loop, 16, 0.30),
    ("perc", render_perc_loop, 10, 0.26),
    ("drive", render_drive_loop, 16, 0.34),
    ("bass_a", lambda: render_bass_loop("a"), 16, 0.40),
    ("bass_b", lambda: render_bass_loop("b"), 16, 0.40),
    ("bass_c", lambda: render_bass_loop("c"), 16, 0.40),
    ("arp_a", lambda: render_arp_loop("a"), 12, 0.30),
    ("arp_b", lambda: render_arp_loop("b"), 12, 0.30),
    ("arp_c", lambda: render_arp_loop("c"), 12, 0.30),
    ("pad", render_pad_loop, 32, 0.26),
    ("title", render_title_loop, 16, 0.45),
]


def to_ogg(wav: Path, ogg: Path) -> None:
    ogg.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav),
         "-c:a", "libvorbis", "-q:a", "5", str(ogg)],
        check=True)


def main() -> int:
    MUSIC_DIR.mkdir(parents=True, exist_ok=True)
    SFX_DIR.mkdir(parents=True, exist_ok=True)
    manifest = {"sample_rate": SR, "bpm": BPM, "samples_per_beat": SPB,
                "music": {}, "sfx": {}}

    print(f"tempo {BPM} BPM, samples/beat {SPB}, grid-lock loops")
    sub80 = measure_sub80(kick_oneshot())
    print(f"KICK B one-shot: sub-80 Hz energy share = {sub80:.3f} "
          f"(target >= 0.18)")

    with tempfile.TemporaryDirectory() as tmp:
        tmpdir = Path(tmp)
        for name, builder, beats, peak in MUSIC_BUILDERS:
            data = norm_to(builder(), peak)
            expected = n_beats(beats)
            assert data.shape[0] == expected, (name, data.shape[0], expected)
            wav = tmpdir / f"music_{name}.wav"
            write_wav(wav, data)
            ogg = MUSIC_DIR / f"music_{name}.ogg"
            to_ogg(wav, ogg)
            report(ogg.name, data)
            manifest["music"][name] = {
                "file": f"audio/music/music_{name}.ogg",
                "beats": beats, "samples": expected}

    for name, builder in SFX_BUILDERS.items():
        data = builder()
        wav = SFX_DIR / f"{name}.wav"
        write_wav(wav, data)
        report(wav.name, data)
        manifest["sfx"][name] = {
            "file": f"audio/sfx/{name}.wav", "samples": int(data.shape[0])}

    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"\n{'file':26s} {'seconds':>8s} {'peak':>7s} {'rms':>7s}")
    for name, secs, peak, rms in LOG:
        print(f"{name:26s} {secs:8.3f} {peak:7.3f} {rms:7.3f}")
    print(f"\nwrote {len(manifest['music'])} music loops, "
          f"{len(manifest['sfx'])} sfx, manifest -> {MANIFEST}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
