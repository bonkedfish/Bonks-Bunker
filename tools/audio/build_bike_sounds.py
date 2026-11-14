# tools/audio/build_bike_sounds.py (D-083) - synthesizes the motorcycle sounds (no downloads): an engine loop per
# engine type (single, twin, inline4, vtwin) at three rev bands, plus the shift / start / stall / crash / refuel events.
# Engine: one firing pulse per cylinder per two revs (4-stroke, with each type's firing order spacing), each pulse
# ringing through a few exhaust resonances, plus intake noise; every loop is a whole number of engine cycles so it
# loops without a click. Writes assets/audio/bike_engine/<engine>_<band>.ogg, the rpm each loop was made at to
# data/audio/bike_engines.json (BikeSound pitches each loop by rpm / that rpm), and assets/audio/bike_<event>/*.ogg.
# Needs Python 3 + numpy + ffmpeg (libvorbis). Usage: python3 build_bike_sounds.py <project root>
import json, os, subprocess, sys
import numpy as np

SR = 44100
ROOT = sys.argv[1]
rng = np.random.default_rng(83)

# cylinder firing angles (degrees of crank, 720 per cycle), resonances (Hz, decay s, gain), noise level, drive
ENGINES = {
    "single": {"fire": [0], "res": [(95, 0.030, 1.0), (310, 0.012, 0.55), (1100, 0.004, 0.25)], "noise": 0.10, "grit": 1.4},
    "twin": {"fire": [0, 270], "res": [(110, 0.028, 1.0), (360, 0.010, 0.5), (1300, 0.004, 0.22)], "noise": 0.08, "grit": 1.2},
    "inline4": {"fire": [0, 180, 360, 540], "res": [(160, 0.016, 0.8), (520, 0.008, 0.6), (1900, 0.003, 0.35)], "noise": 0.07, "grit": 1.0},
    "vtwin": {"fire": [0, 315], "res": [(70, 0.040, 1.0), (230, 0.016, 0.6), (800, 0.005, 0.2)], "noise": 0.09, "grit": 1.6},
}
BANDS = {"low": 1800.0, "mid": 5200.0, "high": 9500.0}
LOOP_S = 1.2


def encode(x, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    x = np.clip(x, -1, 1).astype(np.float32)
    subprocess.run(["ffmpeg", "-v", "quiet", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "5", path], input=x.tobytes(), check=True)


def norm(x, db=-2.0):
    pk = np.abs(x).max()
    return x * (10 ** (db / 20) / pk) if pk > 0 else x


def ring(n, res):
    t = np.arange(n) / SR
    out = np.zeros(n)
    for f, decay, g in res:
        out += g * np.sin(2 * np.pi * f * t) * np.exp(-t / decay)
    return out


def engine_loop(e, rpm):
    cycles = max(1, round(LOOP_S * rpm / 120.0))  # engine cycles (2 revs) in the loop
    real_rpm = cycles * 120.0 / LOOP_S
    n = int(LOOP_S * SR)
    cyc = n / cycles
    kernel = ring(int(0.08 * SR), e["res"])
    x = np.zeros(n + len(kernel))
    for c in range(cycles):
        for ang in e["fire"]:
            i = int(c * cyc + ang / 720.0 * cyc)
            amp = 1.0 + rng.normal(0, 0.06)  # combustion varies a little
            x[i:i + len(kernel)] += amp * kernel
    # wrap the tail into the start so the loop is seamless
    tail = x[n:]
    x = x[:n]
    x[:len(tail)] += tail
    noise = rng.normal(0, 1, n)
    # intake / mechanical noise, pulsed with the firing
    env = np.convolve(np.abs(x), np.ones(64) / 64, mode="same")
    x = np.tanh(x * e["grit"]) + e["noise"] * noise * (0.4 + env / (env.max() + 1e-9))
    return norm(x, -3.0), real_rpm


def tone(f0, f1, dur, decay=None, noise=0.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = np.linspace(f0, f1, n)
    ph = 2 * np.pi * np.cumsum(f) / SR
    x = np.sin(ph) + 0.3 * np.sin(2 * ph)
    if noise:
        x += noise * rng.normal(0, 1, n)
    if decay:
        x *= np.exp(-t / decay)
    return x


def events():
    out = {}
    # shift: a clunk (low thump + metal tick)
    n = int(0.18 * SR)
    t = np.arange(n) / SR
    clunk = np.sin(2 * np.pi * 85 * t) * np.exp(-t / 0.03) + 0.4 * np.sin(2 * np.pi * 1700 * t) * np.exp(-t / 0.006)
    out["bike_shift"] = [norm(clunk, -4)]
    # start: starter whine then the engine catching
    whine = tone(380, 520, 0.6, noise=0.05) * 0.4
    catch, _ = engine_loop(ENGINES["single"], 2400)
    catch = catch[:int(0.6 * SR)] * np.linspace(0.2, 1.0, int(0.6 * SR))
    out["bike_start"] = [norm(np.concatenate([whine, catch]), -3)]
    # stall: the engine coughing down to nothing
    parts = []
    for rpm in (1500, 1100, 800, 500):
        loop, _ = engine_loop(ENGINES["single"], rpm)
        parts.append(loop[:int(0.12 * SR)] * (rpm / 1500.0))
    st = np.concatenate(parts)
    st *= np.linspace(1, 0, len(st)) ** 0.5
    out["bike_stall"] = [norm(st, -5)]
    # crash: impact thump, scrape noise, metal clangs
    n = int(1.4 * SR)
    t = np.arange(n) / SR
    crash = 1.2 * np.sin(2 * np.pi * 55 * t) * np.exp(-t / 0.08)
    scrape = rng.normal(0, 1, n) * np.exp(-t / 0.5)
    scrape = np.convolve(scrape, np.ones(6) / 6, mode="same")
    crash += 0.7 * scrape
    for at, f in ((0.0, 900), (0.15, 1400), (0.42, 700), (0.7, 1100)):
        i = int(at * SR)
        m = n - i
        tt = np.arange(m) / SR
        crash[i:] += 0.5 * np.sin(2 * np.pi * f * tt) * np.exp(-tt / 0.09)
    out["bike_crash"] = [norm(np.tanh(crash), -1)]
    # refuel: glugging liquid
    n = int(1.6 * SR)
    t = np.arange(n) / SR
    glug = np.zeros(n)
    for k in range(9):
        i = int((0.08 + k * 0.16 + rng.uniform(-0.02, 0.02)) * SR)
        m = int(0.12 * SR)
        tt = np.arange(m) / SR
        f = rng.uniform(220, 320)
        glug[i:i + m] += np.sin(2 * np.pi * (f + 600 * tt) * tt) * np.exp(-tt / 0.04)
    glug += 0.05 * rng.normal(0, 1, n)
    out["bike_refuel"] = [norm(glug, -6)]
    return out


def main():
    sound_rpm = {}
    for name, e in ENGINES.items():
        sound_rpm[name] = {}
        for band, rpm in BANDS.items():
            x, real = engine_loop(e, rpm)
            encode(x, os.path.join(ROOT, "assets/audio/bike_engine", "%s_%s.ogg" % (name, band)))
            sound_rpm[name][band] = round(real, 1)
    meta = {"note": "Written by tools/audio/build_bike_sounds.py (D-083): the rpm each engine loop in "
                    "assets/audio/bike_engine/<engine>_<band>.ogg was made at. BikeSound plays each loop at "
                    "pitch rpm / this rpm and crossfades the three bands.", "engines": sound_rpm}
    os.makedirs(os.path.join(ROOT, "data/audio"), exist_ok=True)
    with open(os.path.join(ROOT, "data/audio/bike_engines.json"), "w") as f:
        json.dump(meta, f, indent="\t")
        f.write("\n")
    for ev, takes in events().items():
        for i, x in enumerate(takes):
            encode(x, os.path.join(ROOT, "assets/audio", ev, "%s_%d.ogg" % (ev, i + 1)))
    print("bike sounds written:", sound_rpm)


main()
