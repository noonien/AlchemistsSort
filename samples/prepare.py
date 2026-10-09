#!/usr/bin/env python3
# Makes the instrument samples in this folder from the CC0 recordings they
# come from (see SOURCES.md): each file is fetched from a pinned commit of its
# library, folded to mono, trimmed to its onset, resampled, and either faded
# out (a plucked note) or given a seamless loop (a bowed or rubbed one), then
# encoded as Ogg Vorbis; bank.txt lists each note's measured pitch and its
# loop. The game reads those files; this script only remakes them.
#
#   nix-shell -p 'python3.withPackages (ps: [ ps.numpy ps.scipy ])' vorbis-tools \
#     --run 'python3 samples/prepare.py ~/.cache/alchemists-sort-samples'

import os, subprocess, sys, tempfile, urllib.parse, urllib.request
import numpy as np
from scipy import signal
from scipy.io import wavfile

VSCO = 'https://raw.githubusercontent.com/sgossner/VSCO-2-CE/440300901dfe9275fd84e0b7763af1f8443ae62e/'
VCSL = 'https://raw.githubusercontent.com/sgossner/VCSL/c1ea7bcc3c7309650ab0da9d15c9cd1fbc4a4c7e/'

HARP = 'Chordophones/Composite Chordophones/Folk Harp/EWHarp_Normal_{}_v3_RR1.wav'
STRUM = 'Chordophones/Composite Chordophones/Strumstick/Finger/Strumstick_Finger_{}_vl3_rr1.wav'
PSALTERY = 'Chordophones/Zithers/Psaltery, Bowed and Plucked/LongBow/BowedPsaltery_{}_Main_LongBow_rr2.wav'
GLASS = 'Idiophones/Friction Idiophones/Wine Glasses/Sustains/Slow/{}_Main.wav'
CELLO = 'Strings/Cello Section/susvib/susvib_{}_v1_1.wav'
SECTION = 'Strings/Violin Section/susVib/VlnEns_susVib_{}_v1.wav'
VIOLIN = 'Strings/Solo Violin/Arco Vib/LLVln_ArcoVib_{}_p.wav'
FLUTE = 'Woodwinds/Flute/susvib/LDFlute_susvib_{}_v1_1.wav'

# (our name, library, path, the note it sounds as a MIDI number, kind, seconds kept, rate).
# Several libraries name their notes an octave below where they sound; the
# MIDI number here is the sounding pitch, which the measurement refines.
ZONES = [
    ('harp_c2', VCSL, HARP.format('C1'), 36, 'pluck', 3.6, 32000),
    ('harp_fs2', VCSL, HARP.format('F#1'), 42, 'pluck', 3.3, 32000),
    ('harp_c3', VCSL, HARP.format('C2'), 48, 'pluck', 3.1, 32000),
    ('harp_fs3', VCSL, HARP.format('F#2'), 54, 'pluck', 2.8, 32000),
    ('harp_c4', VCSL, HARP.format('C3'), 60, 'pluck', 2.4, 32000),
    ('harp_fs4', VCSL, HARP.format('F#3'), 66, 'pluck', 2.0, 32000),
    ('harp_c5', VCSL, HARP.format('C4'), 72, 'pluck', 1.9, 32000),
    ('harp_fs5', VCSL, HARP.format('F#4'), 78, 'pluck', 1.5, 32000),
    ('harp_c6', VCSL, HARP.format('C5'), 84, 'pluck', 1.3, 32000),

    ('dulcimer_d3', VCSL, STRUM.format('Str1_Main_D2'), 50, 'pluck', 2.6, 32000),
    ('dulcimer_a3', VCSL, STRUM.format('Str2_Main_A2'), 57, 'pluck', 2.3, 32000),
    ('dulcimer_e4', VCSL, STRUM.format('Str3_Main_E3'), 64, 'pluck', 2.2, 32000),
    ('dulcimer_b4', VCSL, STRUM.format('Str3_Main_B3'), 71, 'pluck', 2.0, 32000),
    ('dulcimer_fs5', VCSL, STRUM.format('Str3_Main_F#4'), 78, 'pluck', 1.6, 32000),

    ('cello_c2', VSCO, CELLO.format('C1'), 36, 'sustain', 2.6, 22050),
    ('cello_g2', VSCO, CELLO.format('G1'), 43, 'sustain', 2.6, 22050),
    ('cello_d3', VSCO, CELLO.format('D2'), 50, 'sustain', 2.6, 22050),
    ('cello_a3', VSCO, CELLO.format('A2'), 57, 'sustain', 2.6, 22050),
    ('cello_e4', VSCO, CELLO.format('E3'), 64, 'sustain', 2.6, 22050),
    ('cello_b4', VSCO, CELLO.format('B3'), 71, 'sustain', 2.6, 22050),

    ('strings_g3', VSCO, SECTION.format('G2'), 55, 'sustain', 2.6, 24000),
    ('strings_d4', VSCO, SECTION.format('D3'), 62, 'sustain', 2.6, 24000),
    ('strings_a4', VSCO, SECTION.format('A3'), 69, 'sustain', 2.6, 24000),
    ('strings_e5', VSCO, SECTION.format('E4'), 76, 'sustain', 2.6, 24000),
    ('strings_b5', VSCO, SECTION.format('B4'), 83, 'sustain', 2.6, 24000),

    ('violin_a3', VSCO, VIOLIN.format('A3'), 57, 'sustain', 2.6, 24000),
    ('violin_e4', VSCO, VIOLIN.format('E4'), 64, 'sustain', 2.6, 24000),
    ('violin_a4', VSCO, VIOLIN.format('A4'), 69, 'sustain', 2.6, 24000),
    ('violin_e5', VSCO, VIOLIN.format('E5'), 76, 'sustain', 2.6, 24000),
    ('violin_a5', VSCO, VIOLIN.format('A5'), 81, 'sustain', 2.6, 24000),
    ('violin_e6', VSCO, VIOLIN.format('E6'), 88, 'sustain', 2.5, 24000),

    ('psaltery_as4', VCSL, PSALTERY.format('A#3'), 70, 'sustain', 2.8, 24000),
    ('psaltery_e5', VCSL, PSALTERY.format('E4'), 76, 'sustain', 2.8, 24000),
    ('psaltery_as5', VCSL, PSALTERY.format('A#4'), 82, 'sustain', 2.6, 24000),
    ('psaltery_e6', VCSL, PSALTERY.format('E5'), 88, 'sustain', 2.6, 24000),

    ('glass_ds5', VCSL, GLASS.format('glass1_D#4_Slow_1'), 75, 'sustain', 3.0, 22050),
    ('glass_fs5', VCSL, GLASS.format('glass2_F#4_Slow_1'), 78, 'sustain', 3.0, 22050),
    ('glass_d6', VCSL, GLASS.format('glass4_D5_Slow_2'), 86, 'sustain', 3.0, 22050),

    ('flute_a4', VSCO, FLUTE.format('A3'), 69, 'sustain', 2.6, 24000),
    ('flute_e5', VSCO, FLUTE.format('E4'), 76, 'sustain', 2.6, 24000),
    ('flute_a5', VSCO, FLUTE.format('A4'), 81, 'sustain', 2.5, 24000),
]

PLUCK_RMS_DB = -16.0        # over a pluck's first quarter second
SUSTAIN_RMS_DB = -18.0      # over a sustained note's loop
LOOP_SECONDS = (1.2, 1.9)   # the range a loop's length is chosen from
LOOP_FROM = 0.95            # and its earliest start: after the attack
FADE = 0.22                 # the crossfade baked in before a loop's end, in seconds


def fetch(cache, base, path):
    local = os.path.join(cache, path.replace('/', '__'))
    if not os.path.exists(local):
        os.makedirs(cache, exist_ok=True)
        print('fetching', path)
        urllib.request.urlretrieve(base + urllib.parse.quote(path), local + '.part')
        os.replace(local + '.part', local)
    return local


def load(path):
    sr, x = wavfile.read(path)
    if x.dtype == np.int16: x = x / 32768.0
    elif x.dtype == np.int32: x = x / 2147483648.0
    x = x.astype(np.float64)
    if x.ndim == 2:
        left, right = x[:, 0], x[:, 1]
        # A spaced pair can cancel when summed: then one microphone is the better mono.
        if np.corrcoef(left, right)[0, 1] > 0.5: x = 0.5 * (left + right)
        else: x = left if np.sum(left ** 2) >= np.sum(right ** 2) else right
    return sr, x


def envelope(x, sr, seconds):
    w = max(1, int(sr * seconds))
    return np.sqrt(np.convolve(x * x, np.ones(w) / w, 'same') + 1e-20)


def trim_onset(x, sr):
    env = envelope(x, sr, 0.005)
    i = int(np.argmax(env > env.max() * 0.03))
    i = max(0, i - int(0.004 * sr))
    y = x[i:].copy()
    n = int(0.003 * sr)
    y[:n] *= np.sin(0.5 * np.pi * np.arange(n) / n) ** 2
    return y


def measure_midi(x, sr, midi, t0, t1):
    # The weighted mean of the first harmonics' peaks, each divided by its number.
    f = 440 * 2 ** ((midi - 69) / 12)
    a, b = int(t0 * sr), min(len(x), int(t1 * sr))
    seg = x[a:b] * np.hanning(b - a)
    N = 1 << 20
    S = np.abs(np.fft.rfft(seg, N))
    ests, ws = [], []
    for h in range(1, 7):
        fh = f * h
        if fh > sr / 2 - 500: break
        lo, hi = int(fh * 2 ** (-0.7 / 12) * N / sr), int(fh * 2 ** (0.7 / 12) * N / sr)
        k = lo + int(np.argmax(S[lo:hi]))
        y0, y1, y2 = np.log(S[k - 1:k + 2] + 1e-12)
        d = 0.5 * (y0 - y2) / (y0 - 2 * y1 + y2)
        ests.append((k + d) * sr / N / h)
        ws.append(S[k])
    f0 = np.dot(ests, ws) / np.sum(ws)
    return 69 + 12 * np.log2(f0 / 440)


def make_pluck(x, sr, keep):
    env = envelope(x, sr, 0.05)
    peak = int(np.argmax(env))
    quiet = np.where(env[peak:] < env.max() * 10 ** (-48 / 20))[0]
    n = min(len(x), int(keep * sr), peak + (int(quiet[0]) if len(quiet) else len(x)))
    y = x[:n].copy()
    f = int(n * 0.3)
    y[n - f:] *= np.cos(0.5 * np.pi * np.arange(f) / f) ** 2
    y *= 10 ** (PLUCK_RMS_DB / 20) / np.sqrt(np.mean(y[:int(0.25 * sr)] ** 2))
    return y, 0, 0


def make_sustain(x, sr, keep):
    n = min(len(x), int(keep * sr))
    # Even out the slow swells after the attack, so the loop neither pumps
    # nor fades: the game shapes each note's dynamics itself.
    settle = int(0.45 * sr)
    env = envelope(x, sr, 0.3)
    ref = np.mean(env[settle:n])
    gain = np.ones(len(x))
    ramp = np.clip((np.arange(len(x)) - settle * 0.6) / (settle * 0.4), 0, 1)
    gain = 1 + ramp * (ref / env - 1)
    x = x * gain
    # The loop ends where the kept part does; its start is where the sound
    # best matches the sound around the end.
    end = n - 1
    w = int(0.03 * sr)
    template = x[end - w:end + w]
    lo = max(end - int(LOOP_SECONDS[1] * sr), int(LOOP_FROM * sr))
    hi = max(lo + w, end - int(LOOP_SECONDS[0] * sr))
    region = x[lo - w:hi + w]
    c = signal.correlate(region, template, mode='valid')
    energy = np.sqrt(np.convolve(region ** 2, np.ones(2 * w), 'valid')[:len(c)] * np.sum(template ** 2)) + 1e-12
    score = c / energy
    start = lo + int(np.argmax(score))
    best = float(np.max(score))
    # Bake a crossfade into the samples before the end, so that playing on
    # from the loop's start after its end is seamless.
    f = int(FADE * sr)
    y = x[:end + 1].copy()
    t = np.arange(f) / f
    # Two well matched stretches crossfade at equal gain; two that differ
    # (a psaltery's beating courses) at equal power, so the level holds.
    if best > 0.85: fade_in, fade_out = np.sin(0.5 * np.pi * t) ** 2, np.cos(0.5 * np.pi * t) ** 2
    else: fade_in, fade_out = np.sin(0.5 * np.pi * t), np.cos(0.5 * np.pi * t)
    y[end + 1 - f:end + 1] = x[end + 1 - f:end + 1] * fade_out + x[start - f:start] * fade_in
    y *= 10 ** (SUSTAIN_RMS_DB / 20) / np.sqrt(np.mean(y[start:end + 1] ** 2))
    return y, start, end, best


QUALITY = 4                 # oggenc's -q: about 70 kbps for these mono notes


def write_ogg(path, y, rate):
    # Through a 16-bit WAV, dithered, into oggenc.
    pcm = np.clip(np.round(y * 32767 + np.random.default_rng(1).triangular(-1, 0, 1, len(y))), -32768, 32767).astype('<i2')
    with tempfile.NamedTemporaryFile(suffix='.wav') as tmp:
        wavfile.write(tmp.name, rate, pcm)
        subprocess.run([os.environ.get('OGGENC', 'oggenc'), '-Q', '-q', str(QUALITY), '-o', path, tmp.name], check=True)


def main():
    if len(sys.argv) != 2: sys.exit('usage: prepare.py CACHE_DIR')
    cache = sys.argv[1]
    here = os.path.dirname(os.path.abspath(__file__))
    total = 0
    manifest = ['# The recorded notes: instrument, file (.ogg), the MIDI pitch it sounds at,',
                '# and the frames its loop starts at and ends after (0 0: it rings out).',
                '# Written by prepare.py.']
    for name, base, path, midi, kind, keep, rate in ZONES:
        sr, x = load(fetch(cache, base, path))
        b, a = signal.butter(2, 30 / (sr / 2), 'high')
        x = trim_onset(signal.filtfilt(b, a, x), sr)
        x = x[:int((keep + 0.3) * sr)]
        g = np.gcd(rate, sr)
        x = signal.resample_poly(x, rate // g, sr // g)
        measured = measure_midi(x, rate, midi, 0.25, min(len(x) / rate - 0.1, 2.0))
        if kind == 'pluck':
            y, start, end = make_pluck(x, rate, keep)
            note = ''
        else:
            y, start, end, match = make_sustain(x, rate, keep)
            note = f' loop {start / rate:.2f}-{end / rate:.2f} s, match {match:.3f}'
        peak = np.max(np.abs(y))
        if peak > 0.97: y *= 0.97 / peak
        out = os.path.join(here, name + '.ogg')
        write_ogg(out, y, rate)
        total += os.path.getsize(out)
        manifest.append(f'{name.split("_")[0]} {name} {measured:.3f} {start} {end}')
        print(f'{name:14s} {measured:6.2f} ({measured - midi:+.2f}) {len(y) / rate:4.2f} s, peak {20 * np.log10(np.max(np.abs(y))):5.1f} dB{note}')
    with open(os.path.join(here, 'bank.txt'), 'w') as f: f.write('\n'.join(manifest) + '\n')
    print(f'{total / 1e6:.2f} MB')


if __name__ == '__main__':
    main()
