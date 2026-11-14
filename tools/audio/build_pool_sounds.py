# tools/audio/build_pool_sounds.py (D-084) - synthesizes the pool table sounds (no downloads): the cue tip striking the
# cue ball, ball-on-ball clacks, a ball thudding off a cushion, a ball dropping into a pocket. Writes
# assets/audio/pool_<event>/pool_<event>_<n>.ogg (a few variants each; Sfx picks one at random).
# Needs Python 3 + numpy + ffmpeg (libvorbis). Usage: python3 build_pool_sounds.py <project root>
import os, subprocess, sys
import numpy as np

SR = 44100
ROOT = sys.argv[1]
rng = np.random.default_rng(84)


def encode(x, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    x = np.clip(x, -1, 1).astype(np.float32)
    subprocess.run(["ffmpeg", "-v", "quiet", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "5", path], input=x.tobytes(), check=True)


def norm(x, db):
    return x * (10 ** (db / 20) / max(np.abs(x).max(), 1e-9))


def ping(dur, parts, noise=0.0, noise_decay=0.002):
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for f, decay, g in parts:
        x += g * np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * np.exp(-t / decay)
    if noise:
        x += noise * rng.normal(0, 1, n) * np.exp(-t / noise_decay)
    return x


def main():
    for i in range(3):  # phenolic balls: a bright, very short click
        f = rng.uniform(0.95, 1.05)
        encode(norm(ping(0.12, [(3100 * f, 0.012, 1.0), (5200 * f, 0.006, 0.6), (1800 * f, 0.02, 0.4)], 0.6, 0.0015), -3),
               os.path.join(ROOT, "assets/audio/pool_clack/pool_clack_%d.ogg" % (i + 1)))
    for i in range(2):  # leather tip on the cue ball: softer, lower
        encode(norm(ping(0.12, [(1500, 0.01, 1.0), (2600, 0.006, 0.4)], 0.5, 0.003), -6),
               os.path.join(ROOT, "assets/audio/pool_cue/pool_cue_%d.ogg" % (i + 1)))
    for i in range(2):  # cushion: a dull rubber thump
        encode(norm(ping(0.15, [(180, 0.03, 1.0), (420, 0.015, 0.4)], 0.2, 0.004), -8),
               os.path.join(ROOT, "assets/audio/pool_rail/pool_rail_%d.ogg" % (i + 1)))
    for i in range(2):  # pocket: a knock on the pocket, then the ball rolling down the return
        knock = ping(0.25, [(240, 0.05, 1.0), (700, 0.02, 0.5)], 0.3, 0.005)
        n = int(0.9 * SR)
        t = np.arange(n) / SR
        roll = rng.normal(0, 1, n)
        roll = np.convolve(roll, np.ones(40) / 40, mode="same") * (0.5 + 0.5 * np.sin(2 * np.pi * 9 * t)) * np.exp(-t / 0.4) * 0.6
        x = np.concatenate([knock, np.zeros(int(0.05 * SR))])
        x = np.concatenate([x, roll])
        encode(norm(x, -5), os.path.join(ROOT, "assets/audio/pool_pocket/pool_pocket_%d.ogg" % (i + 1)))
    print("pool sounds written")


main()
