# tools/audio/build_scare_sounds.py (D-114) - makes the zombie scare sounds with no downloads.
#   heartbeat, zombie_breath: synthesized here (original, CC0 like the rest of the game's own work).
#   zombie_groan, zombie_scream, zombie_attack: derived from the six CC0 moans already in
#   assets/audio/ambience_distant/moan_zombie-*.ogg ("Zombies Sound Pack", artisticdude) by pitch, layering,
#   saturation and filtering. Each event is its own folder, so better CC0 recordings can simply replace these.
# Needs Python 3 + numpy + scipy + ffmpeg.  Usage: python3 build_scare_sounds.py <assets/audio dir>
import subprocess, sys, os, glob, numpy as np
from scipy.signal import butter, sosfilt

SR = 44100
AUD = sys.argv[1]
rng = np.random.default_rng(114)


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


def resample(x, rate):  # rate > 1 = higher pitch, shorter
    n = int(len(x) / rate)
    return np.interp(np.linspace(0, len(x) - 1, n), np.arange(len(x)), x).astype(np.float32)


def env(n, a, d):  # attack a s, then decay over the rest with time constant d s
    t = np.arange(n) / SR
    return np.minimum(t / max(a, 1e-4), 1.0) * np.exp(-np.maximum(t - a, 0) / d)


def fade(x, fin=0.005, fout=0.06):
    x = x.copy()
    i, o = min(int(fin * SR), len(x)), min(int(fout * SR), len(x))
    x[:i] *= np.linspace(0, 1, i)
    x[-o:] *= np.linspace(1, 0, o)
    return x


def trim(x, thr=0.02):
    a = np.abs(x)
    idx = np.where(a > a.max() * thr)[0]
    return x[max(idx[0] - 200, 0):idx[-1] + 400]


def save(event, name, x, db=-1.0):
    d = os.path.join(AUD, event)
    os.makedirs(d, exist_ok=True)
    x = fade(x)
    x = x * (10 ** (db / 20) / max(np.abs(x).max(), 1e-6))
    p = os.path.join(d, name + ".ogg")
    subprocess.run(["ffmpeg", "-v", "quiet", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "4", p], input=x.astype(np.float32).tobytes(), check=True)
    print(p)


moans = [trim(load(p)) for p in sorted(glob.glob(os.path.join(AUD, "ambience_distant", "moan_zombie-*.ogg")))]
assert moans, "no moans found in ambience_distant"

# --- heartbeat: one lub-dub, low thumps (played once per beat by Dread, faster as a zombie closes in) ---
for i, (f, gap) in enumerate([(52, 0.30), (48, 0.27), (56, 0.32)]):
    n = int(0.75 * SR)
    t = np.arange(n) / SR
    out = np.zeros(n, np.float32)
    for start, g, ff in [(0.0, 1.0, f), (gap, 0.7, f * 0.9)]:
        tt = np.maximum(t - start, 0)
        sweep = ff * (1 + 0.6 * np.exp(-tt / 0.02))
        thump = np.roll(env(n, 0.006, 0.07), int(start * SR)) * np.sin(2 * np.pi * sweep * tt)
        out += (g * thump).astype(np.float32)
    out += band(rng.standard_normal(n).astype(np.float32), hi=120) * 0.15 * env(n, 0.01, 0.12)
    save("heartbeat", "beat_%d" % (i + 1), np.tanh(out * 1.6))

# --- zombie_breath: wet, ragged in-out rasps, close range ---
for i in range(4):
    dur = rng.uniform(1.6, 2.4)
    n = int(dur * SR)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n).astype(np.float32)
    shape = np.zeros(n)
    split = rng.uniform(0.4, 0.55) * dur
    shape += np.sin(np.pi * np.clip(t / split, 0, 1)) ** 2 * (t < split)
    shape += 1.3 * np.sin(np.pi * np.clip((t - split) / (dur - split), 0, 1)) ** 1.5 * (t >= split)
    rasp = 1 + 0.8 * np.sign(np.sin(2 * np.pi * rng.uniform(28, 45) * t)) * rng.uniform(0.3, 0.6)  # throat flutter
    x = band(noise, 300, 2600) * shape * rasp
    x += band(noise, 90, 300) * shape * 0.6
    gurgle = moans[i % len(moans)][: n]
    x[: len(gurgle)] += band(resample(gurgle, 0.8)[: len(gurgle)], 80, 900) * 0.35
    save("zombie_breath", "breath_%d" % (i + 1), x.astype(np.float32), -3.0)

# --- zombie_groan: close moans with more body (pitch down, a little grit) ---
for i, m in enumerate(moans):
    x = resample(m, rng.uniform(0.82, 0.95))
    x = np.tanh(x / np.abs(x).max() * 2.2) + band(x, 60, 400) * 0.5
    save("zombie_groan", "groan_%d" % (i + 1), x.astype(np.float32), -2.0)

# --- zombie_scream: the spotting shriek - pitched-up, layered moans, hard saturation brings back the highs ---
for i in range(4):
    a, b = moans[i % len(moans)], moans[(i + 2) % len(moans)]
    l1 = resample(a, 1.9 + 0.15 * i)
    l2 = resample(b, 2.6 + 0.1 * i)
    l3 = resample(a, 1.2)
    n = max(len(l1), len(l2), len(l3))
    x = np.zeros(n, np.float32)
    for layer, g in [(l1, 1.0), (l2, 0.6), (l3, 0.5)]:
        x[: len(layer)] += layer / np.abs(layer).max() * g
    t = np.arange(n) / SR
    x *= 1 + 0.25 * np.sin(2 * np.pi * 7.5 * t)  # vibrato-ish tremble
    x = np.tanh(x * 5.0)
    x = band(x, 250, None) + band(rng.standard_normal(n).astype(np.float32), 1800, 6000) * 0.12 * np.abs(x)
    x *= env(n, 0.03, 0.9)
    save("zombie_scream", "scream_%d" % (i + 1), x.astype(np.float32), -1.0)

# --- zombie_attack: short snarl on the swing ---
for i, m in enumerate(moans[:4]):
    seg = m[int(0.05 * SR): int(0.05 * SR) + int(0.55 * SR)]
    x = resample(seg, 1.35)
    x = np.tanh(x / np.abs(x).max() * 4.0) * env(len(x), 0.01, 0.25)
    x += band(rng.standard_normal(len(x)).astype(np.float32), 600, 3500) * 0.25 * env(len(x), 0.005, 0.12)
    save("zombie_attack", "snarl_%d" % (i + 1), x.astype(np.float32), -1.0)
