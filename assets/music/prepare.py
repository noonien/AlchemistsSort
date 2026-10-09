#!/usr/bin/env python3
# Makes the game's music (the .ogg files in this folder) from the tracks as
# they were generated, the .m4a files kept here but not in git (or in the
# folder given as the argument). Each track is kept whole, from its first
# moment to its last: brought to the same loudness as the others, given a
# short fade-in and, unless it already fades out on its own, a gentle
# fade-out over its last seconds, and encoded as Ogg Vorbis at the mixer's
# rate. The game plays a track through, rests a moment, and plays it again.
#
#   nix-shell -p 'python3.withPackages (ps: [ ps.numpy ps.scipy ])' ffmpeg vorbis-tools \
#     --run 'python3 assets/music/prepare.py'

import os, subprocess, sys, tempfile
import numpy as np
from scipy import signal
from scipy.io import wavfile

TRACKS = ['title_screen', 'apothecary', 'frost_cellar', 'glassworks', 'observatory', 'greenhouse', 'athanor']
RATE = 44100                # the mixer's own rate
LOUDNESS = -21.0            # K-weighted loudness (about LUFS) every track is brought to
PEAK = 0.89                 # and the most its peaks may reach
FADE_IN = 1.0               # seconds
FADE_OUT = 6.0              # seconds, for a track that doesn't fade out by itself
OWN_FADE = 18.0             # dB its last two seconds lie under its usual level, if it does
QUALITY = 3                 # oggenc's -q: about 112 kbps for these stereo tracks


def decode(path):
    ff = os.environ.get('FFMPEG', 'ffmpeg')
    raw = subprocess.run([ff, '-v', 'error', '-i', path, '-f', 'f32le', '-ac', '2', '-ar', str(RATE), '-'],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, '<f4').reshape(-1, 2).astype(np.float64)


def kweighted_loudness(x):
    # BS.1770's K-weighting (a high shelf and a high-pass), gated at -70 and
    # 10 below the mean, over 400 ms blocks: close to LUFS.
    f0, G, Q = 1681.97, 3.9998, 0.7072
    K = np.tan(np.pi * f0 / RATE); Vh = 10 ** (G / 20); Vb = Vh ** 0.4996
    a0 = 1 + K / Q + K * K
    y = signal.lfilter([(Vh + Vb * K / Q + K * K) / a0, 2 * (K * K - Vh) / a0, (Vh - Vb * K / Q + K * K) / a0],
                       [1, 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0], x, axis=0)
    f0, Q = 38.135, 0.5003
    K = np.tan(np.pi * f0 / RATE); a0 = 1 + K / Q + K * K
    y = signal.lfilter([1, -2, 1], [1, 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0], y, axis=0)
    n = int(0.4 * RATE)
    blocks = np.array([np.mean(np.sum(y[k:k + n] ** 2, 1)) for k in range(0, len(y) - n, n // 4)])
    lk = -0.691 + 10 * np.log10(blocks + 1e-12)
    g = blocks[lk > -70]
    rel = -0.691 + 10 * np.log10(np.mean(g)) - 10
    return -0.691 + 10 * np.log10(np.mean(blocks[lk > max(-70, rel)]))


def level_db(seg): return 10 * np.log10(np.mean(seg ** 2) + 1e-12)


def fades(x):
    # A quarter-sine in; out, a raised cosine over FADE_OUT seconds, or, for
    # a track whose own ending already dies away, only its last moment.
    n = len(x)
    usual = np.median([level_db(x[k:k + RATE]) for k in range(0, n - RATE, RATE)])
    ending = level_db(x[n - 2 * RATE:])
    own = ending < usual - OWN_FADE
    out_len = int((0.3 if own else FADE_OUT) * RATE)
    y = x.copy()
    k = int(FADE_IN * RATE)
    y[:k] *= np.sin(0.5 * np.pi * np.arange(k) / k)[:, None]
    y[n - out_len:] *= (0.5 + 0.5 * np.cos(np.pi * np.arange(out_len) / out_len))[:, None]
    return y, own, usual - ending


def write_ogg(path, y):
    pcm = np.clip(np.round(y * 32767), -32768, 32767).astype('<i2')
    with tempfile.NamedTemporaryFile(suffix='.wav') as tmp:
        wavfile.write(tmp.name, RATE, pcm)
        subprocess.run([os.environ.get('OGGENC', 'oggenc'), '-Q', '-q', str(QUALITY), '-o', path, tmp.name], check=True)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    src = sys.argv[1] if len(sys.argv) > 1 else here
    for name in TRACKS:
        x = decode(os.path.join(src, name + '.m4a'))
        gain_db = LOUDNESS - kweighted_loudness(x)
        x *= 10 ** (gain_db / 20)
        peak = np.max(np.abs(x))
        if peak > PEAK:
            x *= PEAK / peak
            gain_db += 20 * np.log10(PEAK / peak)
        y, own, drop = fades(x)
        out = os.path.join(here, name + '.ogg')
        write_ogg(out, y)
        size = os.path.getsize(out)
        print(f'{name:13s} {len(y) / RATE:6.1f} s  gain {gain_db:+5.1f} dB  ending {drop:4.1f} dB under its usual level: '
              f'{"its own fade kept" if own else f"faded over {FADE_OUT:.0f} s"}  {size / 1e6:.2f} MB, {size * 8 / (len(y) / RATE) / 1000:.0f} kbps')


if __name__ == '__main__':
    main()
