# tools/audio/build_sounds.py (D-077) - how assets/audio/* was made from the CC0 downloads listed in CREDITS.md.
# Needs Python 3 + numpy + scipy + ffmpeg; the source packs are not in the repo (re-download them to re-run).
# Builds the game's sound files from the downloaded CC0 packs: cuts, layers, sequences, normalizes, encodes .ogg.
# Usage: python3 build_sounds.py <src dir with kenney + oga folders> <out assets/audio dir>
import subprocess, sys, os, numpy as np

SR = 44100
SRC, OUT = sys.argv[1], sys.argv[2]
rng = np.random.default_rng(7)
K = SRC + "/imp/Audio/"
R = SRC + "/rpg/Audio/"
D = "/mnt/user-data/uploads/Downloads/"


def load(p, ch=1):
    raw = subprocess.run(["ffmpeg", "-v", "quiet", "-i", p, "-ac", str(ch), "-ar", str(SR), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    x = np.frombuffer(raw, np.float32).copy()
    return x.reshape(-1, ch) if ch > 1 else x


def cut(x, a, b):
    return x[int(a * SR):int(b * SR)].copy()


def fade(x, fin=0.003, fout=0.05):
    x = x.copy()
    i, o = min(int(fin * SR), len(x)), min(int(fout * SR), len(x))
    if i: x[:i] *= np.linspace(0, 1, i)[:, None] if x.ndim > 1 else np.linspace(0, 1, i)
    if o: x[-o:] *= np.linspace(1, 0, o)[:, None] if x.ndim > 1 else np.linspace(1, 0, o)
    return x


def trim(x, start_thr=0.02, end_db=-50.0):
    """Drop leading silence (below start_thr of peak) and trailing silence (below end_db of peak, 20 ms windows)."""
    a = np.abs(x if x.ndim == 1 else x.max(1))
    if a.max() <= 0:
        return x
    idx = np.where(a > a.max() * start_thr)[0]
    s = max(idx[0] - int(0.005 * SR), 0)
    w = int(0.02 * SR); n = len(a) // w
    env = np.sqrt((a[:n * w].reshape(n, w) ** 2).mean(1))
    loud = np.where(env > a.max() * 10 ** (end_db / 20))[0]
    e = min((loud[-1] + 2) * w, len(x)) if len(loud) else len(x)
    return x[s:max(e, s + w)]


def norm(x, db=-1.0):
    pk = np.abs(x).max()
    return x * (10 ** (db / 20) / pk) if pk > 0 else x


def mix(parts, total=None):
    """parts: list of (signal, start_seconds, gain)."""
    end = max(int(s * SR) + len(x) for x, s, g in parts)
    out = np.zeros(max(end, int((total or 0) * SR)), np.float32)
    for x, s, g in parts:
        i = int(s * SR)
        out[i:i + len(x)] += x * g
    return out


def lowpass(x, hz):
    # one-pole, run twice: gentle distance muffling
    from scipy.signal import lfilter
    a = np.exp(-2 * np.pi * hz / SR)
    for _ in range(2):
        x = lfilter([1 - a], [1, -a], x).astype(np.float32)
    return x


def resample(x, rate):  # rate < 1 = lower pitch, longer
    n = int(len(x) / rate)
    return np.interp(np.linspace(0, len(x) - 1, n), np.arange(len(x)), x).astype(np.float32)


def save(event, name, x, db=-1.0):
    d = os.path.join(OUT, event)
    os.makedirs(d, exist_ok=True)
    x = norm(fade(x), db).astype(np.float32)
    ch = x.shape[1] if x.ndim > 1 else 1
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", str(ch), "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "5", os.path.join(d, name + ".ogg")],
                   input=x.tobytes(), check=True)


# --- weapons -----------------------------------------------------------------------------------------
p22 = load(D + "oga_22_Pistol.wav")
ons = [0.14, 0.59, 0.95, 1.39, 1.74]
for i, a in enumerate(ons):
    b = ons[i + 1] - 0.02 if i + 1 < len(ons) else a + 0.5
    shot = trim(cut(p22, a - 0.01, b))
    save("pistol_9mm_fire", f"pistol_{i + 1}", resample(shot, 0.86))  # a bit lower = heavier than a .22

mag = load(D + "oga_22_Magnum.wav")
for i, a in enumerate([0.23, 0.94, 1.66]):
    save("gun_fire", f"magnum_{i + 1}", trim(cut(mag, a - 0.01, a + 0.65)))
unk = load(D + "oga_Unkown.wav")
for i, a in enumerate([0.26, 2.31, 3.69, 4.87]):
    save("gun_fire", f"rifle_{i + 1}", trim(cut(unk, a - 0.01, a + 0.9)))

save("pistol_9mm_reload", "reload_1", trim(load(D + "oga_reload.wav")), -3)
save("pistol_9mm_reload", "reload_2", trim(load(D + "oga_gunreload1.wav")), -3)
save("pistol_9mm_dry", "click_1", trim(load(R + "metalClick.ogg")), -6)
save("pistol_9mm_dry", "click_2", trim(load(R + "metalLatch.ogg")), -6)

for n in [6, 7, 8, 9, 10, 11, 12, 13]:
    save("bat_baseball_swing", f"swish_{n}", trim(load(f"{SRC}/oga_swishes/swishes/swish-{n}.wav")))
for i in range(5):
    punch = trim(load(K + f"impactPunch_heavy_00{i}.ogg"))
    wood = trim(load(K + f"impactWood_medium_00{i}.ogg"))
    save("bat_baseball_hit", f"hit_{i + 1}", mix([(punch, 0, 1.0), (wood, 0.0, 0.45)]))

# --- player ------------------------------------------------------------------------------------------
for i in range(1, 6):
    save("player_hurt", f"hit_{i}", trim(load(f"{SRC}/oga_5Hit_Sounds/ogg/hit{i}.ogg")))
gr = load(D + "oga_death_pain_grunts.wav")
for i, a in enumerate([0.58, 4.11, 7.02, 8.42, 14.64, 20.55]):
    save("player_hurt", f"grunt_{i + 1}", trim(cut(gr, a - 0.03, a + 0.75)))

for i in range(1, 5):
    save("jump", f"cloth_{i}", trim(load(R + f"cloth{i}.ogg")), -6)
for i in range(5):
    save("land", f"concrete_{i + 1}", trim(load(K + f"footstep_concrete_00{i}.ogg")))
    save("land", f"grass_{i + 1}", trim(load(K + f"footstep_grass_00{i}.ogg")))

# --- using items (each ~1-3 s, matching the item's use time) -----------------------------------------
crunch = [trim(load(f"{SRC}/oga_crunch_-_tito/crunch.{i}.ogg")) for i in range(1, 8)] + [trim(load(D + "oga_apple_bite_0.ogg"))]
for v in range(4):
    pick = rng.choice(len(crunch), 4, replace=False)
    save("eat", f"eat_{v + 1}", mix([(crunch[k], j * 0.42 + rng.uniform(0, 0.08), 1.0) for j, k in enumerate(pick)]))

gulp = [trim(load(f"{SRC}/oga_MoreSounds/Drink/Drink_0{i}.wav")) for i in range(1, 7)]
for v in range(3):
    pick = rng.choice(len(gulp), 3, replace=False)
    save("drink", f"drink_{v + 1}", mix([(norm(gulp[k]), j * 0.5, 1.0) for j, k in enumerate(pick)]))

beads = trim(load(SRC + "/oga_rpg_sound_pack/RPG Sound Pack/inventory/beads.wav"))
for v, k in enumerate([3, 1]):
    save("pills", f"pills_{v + 1}", mix([(norm(beads), 0, 0.8), (norm(beads), 0.18, 0.6), (norm(gulp[k]), 0.6, 0.9)]))

velcro = [trim(load(f"{SRC}/oga_MoreSounds/Velcro/Velcro_0{i}.wav")) for i in range(1, 4)]
cloth = [trim(load(f"{SRC}/oga_MoreSounds/Cloth/Cloth_0{i}.wav")) for i in [2, 3, 6]]
for v in range(3):
    save("bandage", f"bandage_{v + 1}", mix([(norm(velcro[v]), 0, 0.9), (norm(cloth[v]), 0.55, 0.8),
                                             (norm(velcro[(v + 1) % 3]), 1.35, 0.7)]))

zippo = trim(load(D + "oga_zipclick.flac"))
breath = trim(load(f"{SRC}/oga_wind/wind/Wind3.ogg"))
save("smoke", "lighter_1", mix([(norm(zippo), 0, 1.0), (norm(breath), 0.7, 0.35)]))
save("smoke", "lighter_2", mix([(norm(zippo), 0, 1.0), (norm(zippo), 0.25, 0.7), (norm(breath), 0.9, 0.35)]))

# --- disc golf -------------------------------------------------------------------------------------
chain = [trim(load(f"{SRC}/oga_80-CC0-RPG-SFX_0/chain_0{i}.ogg")) for i in (1, 2, 3)]
mail = [trim(load(SRC + f"/oga_rpg_sound_pack/RPG Sound Pack/inventory/chainmail{i}.wav")) for i in (1, 2)]
for v in range(4):
    hit = trim(load(K + f"impactMetal_light_00{v}.ogg"))
    save("disc_chains", f"chains_{v + 1}", mix([(norm(chain[v % 3]), 0, 1.0), (norm(mail[v % 2]), 0.02, 0.7),
                                                (norm(hit), 0, 0.35), (norm(chain[(v + 1) % 3]), 0.12, 0.5)]))
for i in range(5):
    save("disc_basket_clank", f"clank_{i + 1}", mix([(trim(load(K + f"impactMetal_light_00{i}.ogg")), 0, 1.0),
                                                      (trim(load(K + f"impactPlate_light_00{i}.ogg")), 0, 0.5)]))

# --- ambience ---------------------------------------------------------------------------------------
# Wind bed: 64 s stereo, the whoosh loop (two offset copies, one per side) under random gusts, made to loop
# seamlessly by crossfading its tail into its head.
L = 64.0
base = load(D + "oga_wind_woosh_loop.ogg")
gusts = [load(f"{SRC}/oga_wind/wind/{n}") for n in ("Wind.ogg", "Wind2.ogg")]
n = int(L * SR)
def tile(x, off):
    reps = int(np.ceil((n + off) / len(x))) + 1
    return np.tile(x, reps)[off:off + n]
left, right = tile(base, 0), tile(base, int(2.7 * SR))
t = 0.0
while t < L - 7:
    g = norm(gusts[rng.integers(2)]) * rng.uniform(0.25, 0.55)
    pan = rng.uniform(0.2, 0.8)
    i = int(t * SR); j = min(i + len(g), n)
    left[i:j] += g[:j - i] * (1 - pan); right[i:j] += g[:j - i] * pan
    t += rng.uniform(4, 9)
bed = np.stack([lowpass(left, 1800), lowpass(right, 1800)], 1)
xf = int(3 * SR)
head = bed[:xf].copy(); w = np.linspace(0, 1, xf)[:, None]
bed = bed[xf:].copy(); bed[-xf:] = bed[-xf:] * (1 - w) + head * w
d = os.path.join(OUT, "ambience_wind"); os.makedirs(d, exist_ok=True)
x = norm(bed, -6).astype(np.float32)
subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "2", "-i", "-",
                "-c:a", "libvorbis", "-q:a", "4", os.path.join(d, "prairie_wind.ogg")], input=x.tobytes(), check=True)

far = lambda x: lowpass(x, 2500)
save("ambience_distant", "crow_caw", trim(load(D + "oga_crow_caw.wav")))
crows = load(D + "oga_Crows.ogg")
save("ambience_distant", "crows_1", trim(cut(crows, 0, 4.5)))
save("ambience_distant", "crows_2", trim(cut(crows, 4.5, 9.3)))
save("ambience_distant", "tree_creak", trim(load(D + "oga_tree_creak_0.ogg")))
for i in (1, 2, 3):
    save("ambience_distant", f"creak_{i}", trim(load(R + f"creak{i}.ogg")))
for i in (2, 5, 9, 7):
    save("ambience_distant", f"metal_clang_{i}", far(trim(load(f"{SRC}/oga_clangs/clang - Marker #{i}.wav"))))
zfiles = sorted(os.listdir(f"{SRC}/oga_zombies/zombies"))
zl = sorted(((len(load(f"{SRC}/oga_zombies/zombies/{f}")), f) for f in zfiles if f.endswith(".wav")), reverse=True)
for _, f in zl[:6]:  # the six longest = moans rather than short grunts
    save("ambience_distant", f"moan_{f[:-4]}", far(trim(load(f"{SRC}/oga_zombies/zombies/{f}"))))
save("ambience_distant", "door_slam", far(trim(load(R + "doorClose_4.ogg"))))
print("done")
