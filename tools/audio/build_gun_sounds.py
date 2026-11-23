# tools/audio/build_gun_sounds.py (D-122) - per-gun shots and the reload / casing sounds, with no downloads.
#   <gun>_fire: each gun's shot is built from the five CC0 pistol shots already in assets/audio/pistol_9mm_fire
#     (OpenGameArt "Gunshots", see CREDITS.md) - pitched, layered with a synthesized low boom, a supersonic crack
#     for rifles and a longer reverb tail, then softly saturated. The pistol keeps its recordings.
#   gun_mag_out, gun_mag_in, gun_slide, gun_pump, gun_bolt, revolver_open, revolver_close, shell_in,
#   casing_drop, shell_drop: synthesized here (damped metal modes + filtered noise; original, CC0 like the rest).
#   Each event is its own folder, so better CC0 recordings can replace any of these later.
# Needs Python 3 + numpy + scipy + ffmpeg.  Usage: python3 build_gun_sounds.py <assets/audio dir>
import subprocess, sys, os, glob, numpy as np
from scipy.signal import butter, sosfilt

SR = 44100
AUD = sys.argv[1]
rng = np.random.default_rng(122)


def load(p):
    raw = subprocess.run(["ffmpeg", "-v", "quiet", "-i", p, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).copy()


def band(x, lo=None, hi=None, order=2):
    if lo and hi:
        sos = butter(order, [lo, hi], "bandpass", fs=SR, output="sos")
    elif lo:
        sos = butter(order, lo, "highpass", fs=SR, output="sos")
    else:
        sos = butter(order, hi, "lowpass", fs=SR, output="sos")
    return sosfilt(sos, x).astype(np.float32)


def resample(x, rate):
    n = int(len(x) / rate)
    return np.interp(np.linspace(0, len(x) - 1, n), np.arange(len(x)), x).astype(np.float32)


def env(n, a, d):
    t = np.arange(n) / SR
    return (np.minimum(t / max(a, 1e-4), 1.0) * np.exp(-np.maximum(t - a, 0) / d)).astype(np.float32)


def pad(x, n):
    return np.pad(x, (0, max(0, n - len(x))))[:n]


def save(event, name, x, peak=0.9):
    x = x / max(np.abs(x).max(), 1e-6) * peak
    d = os.path.join(AUD, event)
    os.makedirs(d, exist_ok=True)
    p = os.path.join(d, name + ".ogg")
    subprocess.run(["ffmpeg", "-v", "quiet", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "5", p], input=x.astype(np.float32).tobytes(), check=True)


def metal(n, freqs, decay, amp=1.0):  # a struck piece of metal: a few damped modes
    t = np.arange(n) / SR
    out = np.zeros(n, np.float32)
    for i, f in enumerate(freqs):
        out += np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * np.exp(-t / (decay / (1 + i * 0.6))) / (1 + i * 0.5)
    return out * amp


def click(dur, freqs, decay, noise=0.6, lo=1500, hi=9000):
    n = int(dur * SR)
    x = metal(n, freqs, decay)
    x += band(rng.normal(0, 1, n).astype(np.float32), lo, hi) * env(n, 0.0005, 0.004) * noise * 4
    return x


def slide(dur, lo, hi, amp=0.5):  # metal sliding on metal
    n = int(dur * SR)
    return band(rng.normal(0, 1, n).astype(np.float32), lo, hi) * np.hanning(n).astype(np.float32) * amp


def seq(parts, total):  # [(time s, signal)]
    out = np.zeros(int(total * SR), np.float32)
    for t, s in parts:
        i = int(t * SR)
        s = s[:len(out) - i]
        out[i:i + len(s)] += s
    return out


# --- shots -------------------------------------------------------------------------------
shots = [load(p) for p in sorted(glob.glob(os.path.join(AUD, "pistol_9mm_fire", "*.ogg")))]
GUNS = {  # pitch, boom (low body), boom_hz, crack (rifle snap), tail_s, tail amount, length s
    "revolver_44": (0.84, 0.75, 70, 0.0, 0.55, 0.35, 0.9),
    "smg_9mm": (1.14, 0.25, 110, 0.15, 0.22, 0.18, 0.45),
    "shotgun_pump": (0.66, 1.0, 55, 0.0, 0.8, 0.45, 1.3),
    "rifle_hunting": (0.78, 0.7, 65, 0.7, 1.0, 0.4, 1.6),
    "rifle_ar": (1.0, 0.45, 85, 0.55, 0.5, 0.3, 0.9),
    "rifle_sniper": (0.62, 0.9, 50, 0.9, 1.4, 0.45, 2.0),
}
for gun, (pitch, boom, boom_hz, crack, tail_s, tail_amt, length) in GUNS.items():
    for v in range(3):
        n = int(length * SR)
        base = pad(resample(shots[(v * 2 + len(gun)) % len(shots)], pitch * rng.uniform(0.97, 1.03)), n)
        t = np.arange(n) / SR
        f = boom_hz * (1.6 * np.exp(-t / 0.03) + 1.0)
        body = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.001, 0.09 + boom * 0.08) * boom * 1.4
        snap = band(rng.normal(0, 1, n).astype(np.float32), 2500, 12000) * env(n, 0.0002, 0.003) * crack * 3.0
        tail = band(rng.normal(0, 1, n).astype(np.float32), 120, 1800) * env(n, 0.01, tail_s * 0.4) * tail_amt
        x = base + body + snap + tail
        x = np.tanh(x * 1.6) / np.tanh(1.6)
        x *= np.minimum(1.0, (n - np.arange(n)) / (0.05 * SR))  # fade the very end
        save(gun + "_fire", "shot_%d" % (v + 1), x.astype(np.float32), 0.95)

# --- mechanics ----------------------------------------------------------------------------
for v in range(2):
    j = rng.uniform(0.95, 1.05)
    save("gun_mag_out", "mag_out_%d" % (v + 1), seq([(0.0, click(0.08, [2300 * j, 3900 * j], 0.02, 0.5)),
                                                     (0.03, slide(0.12, 900, 4000, 0.35))], 0.25), 0.7)
    save("gun_mag_in", "mag_in_%d" % (v + 1), seq([(0.0, slide(0.06, 700, 3000, 0.3)),
                                                   (0.05, click(0.1, [1800 * j, 3100 * j, 5200 * j], 0.03, 0.9)),
                                                   (0.05, metal(int(0.1 * SR), [190 * j], 0.03, 0.8))], 0.25), 0.8)
    save("gun_slide", "slide_%d" % (v + 1), seq([(0.0, click(0.05, [2600 * j, 4400 * j], 0.012, 0.5)),
                                                 (0.01, slide(0.09, 1200, 6000, 0.4)),
                                                 (0.13, click(0.12, [2100 * j, 3500 * j, 6100 * j], 0.035, 1.0))], 0.3), 0.8)
    save("gun_pump", "pump_%d" % (v + 1), seq([(0.0, slide(0.12, 300, 2500, 0.6)),
                                               (0.1, click(0.1, [900 * j, 1700 * j], 0.03, 0.8, 600, 5000)),
                                               (0.22, slide(0.1, 300, 2500, 0.6)),
                                               (0.31, click(0.14, [1100 * j, 2000 * j, 3300 * j], 0.04, 1.0, 600, 6000))], 0.5), 0.85)
    save("gun_bolt", "bolt_%d" % (v + 1), seq([(0.0, click(0.06, [1900 * j, 3200 * j], 0.015, 0.6)),
                                               (0.06, slide(0.1, 800, 4500, 0.45)),
                                               (0.2, slide(0.09, 800, 4500, 0.45)),
                                               (0.3, click(0.12, [1700 * j, 2900 * j, 4600 * j], 0.035, 1.0))], 0.5), 0.8)
    save("revolver_open", "open_%d" % (v + 1), seq([(0.0, click(0.06, [2400 * j, 4100 * j], 0.02, 0.6))] +
                                                   [(0.08 + k * 0.035, click(0.03, [3800 * j], 0.008, 0.3)) for k in range(6)], 0.4), 0.7)
    save("revolver_close", "close_%d" % (v + 1), seq([(0.0, click(0.12, [1500 * j, 2700 * j, 4300 * j], 0.04, 1.0))], 0.2), 0.8)
    save("shell_in", "shell_%d" % (v + 1), seq([(0.0, slide(0.05, 500, 3000, 0.3)),
                                                (0.04, click(0.07, [1300 * j, 2400 * j], 0.02, 0.6, 800, 5000))], 0.15), 0.6)
    save("casing_drop", "casing_%d" % (v + 1), seq([(0.0 + k * 0.11 * (0.7 ** k), metal(int(0.12 * SR), [5200 * j, 7900 * j, 11500 * j], 0.03, 0.8 ** k))
                                                    for k in range(4)], 0.5), 0.5)
    save("shell_drop", "shell_%d" % (v + 1), seq([(0.0 + k * 0.12 * (0.7 ** k), click(0.08, [700 * j, 1500 * j], 0.012, 0.8, 300, 3000) * (0.75 ** k))
                                                   for k in range(3)], 0.45), 0.5)
print("gun sounds written to", AUD)
