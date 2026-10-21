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

M9 re-voice (Chris's genre call, 2026-10-21): the palette aims at
Boris Brejcha's "high-tech minimal" (his reference: Sam Paganini's
"Rave", Brejcha remix) — almost no high end, very low, builds up.
Same compositions, tempo, loop lengths and pattern structures;
the VOICES move down. The bass becomes a continuous 16th-note
ROLL whose accents/pitches are the old patterns' skeletons; hats
become dry lowpassed ticks; the perc figure becomes low knocks;
the drive layer's claps are replaced by low weight (toms, doubled
roll accents, low noise pressure); the arp drops an octave into a
dark pluck; the pad sheds its top partials. The kick stem and all
SFX are untouched.
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


TICK_RNG = np.random.default_rng(777001)  # the dry low voices' noise


def tick_burst(dur: float = 0.028, gain: float = 1.0,
               fc: float = 2500.0, tau: float = 0.0038) -> np.ndarray:
    """Dry pinpoint tick (M9 hats voice): a very short noise burst,
    hard lowpassed — a click with a body, no hat sizzle. The >6 kHz
    energy of the old highpassed-hat voice is gone by construction."""
    n = int(dur * SR)
    t = t_axis(n)
    x = lowpass(TICK_RNG.standard_normal(n), fc) * np.exp(-t / tau)
    return x * gain


def low_knock(f0: float = 205.0, f1: float = 118.0, dur: float = 0.16,
              gain: float = 1.0, tau: float = 0.052) -> np.ndarray:
    """Low percussion knock (M9 perc voice): a sine pitch-drop in
    the 90-210 Hz band with a tiny lowpassed click on the attack —
    a tom/wood knock, pitched and dry."""
    n = int(dur * SR)
    t = t_axis(n)
    freq = f1 + (f0 - f1) * np.exp(-t / 0.018)
    phase = 2.0 * np.pi * np.cumsum(freq) / SR
    x = np.sin(phase) * np.exp(-t / tau)
    x += 0.22 * np.sin(2.0 * np.pi * 2.0 * freq * t) * np.exp(-t / (tau * 0.5))
    cn = int(0.006 * SR)
    ct = t_axis(cn)
    x[:cn] += 0.30 * np.sin(2.0 * np.pi * 720.0 * ct) * np.exp(-ct / 0.0012)
    return x * gain


def tom_hit() -> np.ndarray:
    """Low tom for the drive layer: sine drop 170 -> 80 Hz."""
    n = int(0.30 * SR)
    t = t_axis(n)
    freq = 80.0 + 90.0 * np.exp(-t / 0.030)
    phase = 2.0 * np.pi * np.cumsum(freq) / SR
    x = np.sin(phase) * (1.0 - np.exp(-t / 0.003)) * np.exp(-t / 0.085)
    x += 0.25 * np.sin(2.0 * np.pi * 2.0 * freq * t) * np.exp(-t / 0.040)
    return x


def pressure_sw(dur: float) -> np.ndarray:
    """Low noise pressure (M9 drive bed): noise lowpassed to
    near-sub, swelling in and out over the bar — weight you feel
    as much as hear. No bright content by construction."""
    n = int(dur * SR)
    t = t_axis(n)
    x = lowpass(TICK_RNG.standard_normal(n), 220.0)
    env = np.sin(np.pi * np.arange(n) / max(n - 1, 1)) ** 2
    env *= 1.0 - 0.35 * np.exp(-t / 0.9)
    return norm_to(x, 1.0) * env * 0.16


def roll_note(freq: float, dur: float, accent: float = 1.0) -> np.ndarray:
    """One pulse of THE ROLL (M9 bass voice): the low squelch voice
    with a much lower filter ceiling than the old bass note —
    additive harmonics behind a curve that starts at ~430 Hz and
    settles fast, so a 16th-note pulse train reads as continuous
    low pressure with accent articulation, not separate notes."""
    n = int(dur * SR)
    t = t_axis(n)
    fc = (130.0 + 300.0 * np.exp(-t / 0.028)) * (0.75 + 0.45 * accent)
    out = np.zeros(n)
    for k in range(1, 11):
        f = k * freq
        if f > 4200.0:
            break
        g = (1.0 / k) / (1.0 + (f / fc) ** 2)
        out += g * np.sin(2.0 * np.pi * f * t)
    env = (1.0 - np.exp(-t / 0.003)) * np.exp(-t / (dur * 0.52))
    return out * env * (0.5 + 0.5 * accent)


def arp_note(freq: float, dur: float = 0.19) -> np.ndarray:
    """Dark pluck (M9 voice): sine-weighted with the upper
    harmonics thinned out and a shorter, duller decay — the shimmer
    of the old voice is removed; the loop renderer also lowpasses
    the finished arp stem and plays it an octave down."""
    n = int(dur * SR)
    t = t_axis(n)
    x = (np.sin(2.0 * np.pi * freq * t)
         + 0.16 * np.sin(2.0 * np.pi * 2.0 * freq * t)
         + 0.04 * np.sin(2.0 * np.pi * 3.0 * freq * t))
    env = (1.0 - np.exp(-t / 0.003)) * np.exp(-t / 0.048)
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
            for k in range(1, 4):  # M9: top partials cut, stack
                # favours the fundamental and low-mid partials
                voice += (1.0 / k ** 2.0) * np.sin(2.0 * np.pi * k * f * det * t)
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
    # M9: same rhythm figure, dry pinpoint ticks instead of hats.
    # The "open" position becomes a longer, duller tick; the closed
    # accents become very short hard-lowpassed ticks.
    n = n_beats(16)
    buf = np.zeros((n, 2))
    accent16 = [0.50, 0.0, 0.85, 0.30, 0.0, 0.0, 0.95, 0.35,
                0.55, 0.0, 0.80, 0.0, 0.30, 0.90, 0.0, 0.65]
    for beat in range(16):
        # off-beat long tick (the "and" of every beat)
        place_st(buf, tick_burst(dur=0.11, gain=0.9, fc=1900.0,
                                 tau=0.020),
                 beat * SPB + SPB // 2, 0.15 if beat % 2 else -0.15)
        # syncopated tick accents on the 16th grid
        for s in range(4):
            g = accent16[s] * (0.8 + 0.2 * (beat % 4 == 3))
            if g > 0.0:
                place_st(buf, tick_burst(gain=g),
                         beat * SPB + s * SPB // 4, -0.2 + 0.1 * s)
    return buf


def render_perc_loop() -> np.ndarray:
    # M9: same 10-beat figure, low knocks instead of metal/shaker.
    # The old "metal" steps become the higher knock (205 -> 118 Hz),
    # the old "shaker" steps the lower knock (148 -> 92 Hz).
    n = n_beats(10)  # 20 eighth-steps: polyrhythm against 16
    buf = np.zeros((n, 2))
    knock_steps = {0: 1.0, 3: 0.7, 6: 0.9, 10: 1.0, 13: 0.65, 16: 0.85, 18: 0.6}
    low_steps = {4: 0.8, 9: 0.7, 14: 0.85, 19: 0.75}
    for step, g in knock_steps.items():
        place_st(buf, low_knock(205.0, 118.0, gain=g), step * SPB // 2, 0.35)
    for step, g in low_steps.items():
        place_st(buf, low_knock(148.0, 92.0, gain=g * 0.9, tau=0.060),
                 step * SPB // 2, -0.35)
    return buf


def render_drive_loop() -> np.ndarray:
    # M9: LOW DRIVE — the top of the build is weight, not claps.
    # Per bar: a low noise-pressure swell; on beats 2 and 4 a low
    # tom plus a doubled roll-accent burst (three roll pulses on
    # the bar's root); the old bright end-of-loop ping becomes a
    # single closing low knock. No clap stack, no hats, no ping.
    n = n_beats(16)
    buf = np.zeros((n, 2))
    sixteenth = SPB // 4
    for bar in range(4):
        root = ROOTS[bar]
        bar_start = bar * 4 * SPB
        place_st(buf, pressure_sw(n_beats(4) / SR), bar_start, 0.0)
        for beat_in_bar in (1, 3):  # beats 2 and 4 of each bar
            at = bar_start + beat_in_bar * SPB
            place_st(buf, tom_hit(), at, 0.0)
            for k in range(3):
                place_st(buf, roll_note(root, sixteenth / SR * 0.94, 1.0),
                         at + k * sixteenth, -0.08 if k % 2 else 0.08)
    place_st(buf, low_knock(170.0, 95.0, dur=0.22, tau=0.070),
             15 * SPB + SPB // 2, 0.25)  # last off-beat, now a knock
    return buf


def render_bass_loop(variant: str) -> np.ndarray:
    # M9: THE ROLL. A continuous 16th-note pulse train runs under
    # the whole bar at the bar's root. The variant pattern no longer
    # places sparse notes; it is the roll's skeleton — its positions
    # become accented pulses at the pattern's pitch and length,
    # while the pulses between them roll on at low accent. Variant
    # character (a: steady drive, b: the octave jump, c: fifth and
    # octave colour) is preserved exactly in the skeleton.
    n = n_beats(16)
    buf = np.zeros(n)
    pat = BASS_PATTERNS[variant]
    skeleton = {idx: (semi, length, accent)
                for idx, semi, length, accent in pat}
    sixteenth = SPB // 4
    st_sec = sixteenth / SR
    for bar in range(4):
        root = ROOTS[bar]
        for s in range(16):
            at = bar * 4 * SPB + s * sixteenth
            if s in skeleton:
                semi, length, accent = skeleton[s]
                f = root * (2.0 ** (semi / 12.0))
                place(buf, roll_note(f, length * st_sec * 0.94, accent), at)
            else:
                place(buf, roll_note(root, st_sec * 0.94, 0.30), at)
    return buf


# M9: the arp plays the same patterns an octave down — the
# melodic movement stays, the register drops into the low-mid.
ARP_TONES = [[f / 2.0 for f in chord] for chord in CHORD_TONES]


def render_arp_loop(variant: str) -> np.ndarray:
    n = n_beats(12)  # 12 beats against the 16-beat grid: polyrhythm
    buf = np.zeros((n, 2))
    pat = ARP_PATTERNS[variant]
    for step, tone_idx in enumerate(pat):
        if tone_idx < 0:
            continue
        chord = ARP_TONES[(step // 6) % 4]
        f = chord[tone_idx]
        pan = -0.3 if step % 2 == 0 else 0.3
        place_st(buf, arp_note(f), step * SPB // 2, pan)
    buf[:, 0] = lowpass(buf[:, 0], 1700.0)  # M9: stem-level darkening
    buf[:, 1] = lowpass(buf[:, 1], 1700.0)
    return buf


def render_pad_loop() -> np.ndarray:
    n = n_beats(32)  # chords every 8 beats: Am F C G, twice
    buf = np.zeros(n)
    for seg in range(4):
        chord = CHORD_TONES[seg % 4]
        seg_sig = pad_chord(chord, n_beats(8) / SR)
        place_wrap(buf, seg_sig, seg * n_beats(8))
    return lowpass(buf, 850.0)  # M9: dark pad — top band removed


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
    """Firing sound, re-aimed after Chris's M3 ear verdict: a shot
    fires constantly, so it becomes part of the soundtrack — it must
    sit IN the mix, not on top. Dry soft percussive tick: lowpassed
    noise burst (~1200 Hz) plus a very short low thump. No zap, no
    pitch sweep, no bright edge; rendered quiet (peak 0.26) and the
    game plays it back lower still (see scripts/sfx.gd)."""
    n = int(0.04 * SR)
    t = t_axis(n)
    local = np.random.default_rng(44101)  # local: global RNG untouched
    burst = lowpass(local.standard_normal(n), 1200.0) * np.exp(-t / 0.007)
    thump = np.sin(2.0 * np.pi * 170.0 * t) * np.exp(-t / 0.010)
    return norm_to(burst * 1.4 + thump * 0.9, 0.26)


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
    """Salvage pickup, re-aimed after Chris's M3 ear verdict: the old
    sine blip with a rising glide read as a water droplet / bubbles.
    This is a DRY metallic chink: a ~2 ms broadband click transient
    plus three inharmonic partials at CONSTANT frequencies (no pitch
    sweep anywhere), higher partials decaying faster. The combo pitch
    ladder in scripts/sfx.gd still steps between pickups — discrete
    steps, not a glide."""
    n = int(0.05 * SR)
    t = t_axis(n)
    local = np.random.default_rng(44102)  # local: global RNG untouched
    click = local.standard_normal(n) * np.exp(-t / 0.0008) * (t < 0.0025)
    x = 1.1 * click
    for f, g, tau in ((1560.0, 0.62, 0.013),
                      (2350.0, 0.45, 0.011),
                      (3490.0, 0.30, 0.008)):
        x += g * np.sin(2.0 * np.pi * f * t) * np.exp(-t / tau)
    return norm_to(x, 0.35)


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
# M9 peak rebalance (render-side, so the director gains — the mix
# Chris already judged — stay put): the peaks below were set from
# before/after stem-RMS measurements so each layer's RMS at its
# director gain lands near its M3 value. Ticks and knocks carry
# very different RMS per peak than the bright voices they replace:
# hats' peak rises (short ticks are RMS-poor; the rhythm must still
# read), perc/drive/pad peaks fall (knocks, toms and the darker pad
# are RMS-dense), and the bass roll sits hotter than the old sparse
# bass on purpose — it is the reference's engine — with the full
# stack's RMS held inside +/-1.5 dB of the M3 stack.
MUSIC_BUILDERS = [
    ("kick", render_kick_loop, 16, 0.70),
    ("hats", render_hats_loop, 16, 0.48),
    ("perc", render_perc_loop, 10, 0.11),
    ("drive", render_drive_loop, 16, 0.15),
    ("bass_a", lambda: render_bass_loop("a"), 16, 0.32),
    ("bass_b", lambda: render_bass_loop("b"), 16, 0.32),
    ("bass_c", lambda: render_bass_loop("c"), 16, 0.32),
    ("arp_a", lambda: render_arp_loop("a"), 12, 0.30),
    ("arp_b", lambda: render_arp_loop("b"), 12, 0.30),
    ("arp_c", lambda: render_arp_loop("c"), 12, 0.30),
    ("pad", render_pad_loop, 32, 0.25),
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
