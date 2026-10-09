# Instrument samples

The music is played on recordings of single notes, read by `src/app/bank.goose`
and played by `src/app/voices.goose`. Every recording here comes from one of
two sample libraries by Versilian Studios, both dedicated to the public domain
under **CC0 1.0 Universal** (no attribution required, no restrictions):

| Library | Source | Commit | License |
|---|---|---|---|
| VSCO-2 CE (Versilian Studios Chamber Orchestra 2, Community Edition) | https://github.com/sgossner/VSCO-2-CE | `440300901dfe9275fd84e0b7763af1f8443ae62e` | CC0 1.0 ([LICENSE](https://github.com/sgossner/VSCO-2-CE/blob/440300901dfe9275fd84e0b7763af1f8443ae62e/LICENSE)) |
| VCSL (Versilian Community Sample Library) | https://github.com/sgossner/VCSL | `c1ea7bcc3c7309650ab0da9d15c9cd1fbc4a4c7e` | CC0 1.0 ([LICENSE](https://github.com/sgossner/VCSL/blob/c1ea7bcc3c7309650ab0da9d15c9cd1fbc4a4c7e/LICENSE)) |

`prepare.py` remakes these files from those commits: it folds each recording
to mono, trims it to its onset, resamples it, measures its pitch, fades out a
plucked note or gives a held one a seamless loop (a crossfade baked in before
the loop's end), and encodes it as mono Ogg Vorbis (oggenc -q 4, about
70 kbps); `bank.txt` lists each note's instrument, measured pitch and loop.
Those are the only changes; the recordings are otherwise as the libraries
have them. The game decodes them with stb_vorbis (`src/c/`).

The strumstick plays the part of a dulcimer, and the bowed psaltery and the
rubbed wine glasses that of a glass harmonica. The singing bowls, the choir
and the drone are synthesized, not recorded.

| File | Library | Path in the library | Kept |
|---|---|---|---|
| harp_c2.ogg | VCSL | `Chordophones/Composite Chordophones/Folk Harp/EWHarp_Normal_C1_v3_RR1.wav` | pluck, 3.6 s, 32000 Hz |
| harp_fs2.ogg | VCSL | `Chordophones/Composite Chordophones/Folk Harp/EWHarp_Normal_F#1_v3_RR1.wav` | pluck, 3.3 s, 32000 Hz |
| harp_c3.ogg | VCSL | `Chordophones/Composite Chordophones/Folk Harp/EWHarp_Normal_C2_v3_RR1.wav` | pluck, 3.1 s, 32000 Hz |
| harp_fs3.ogg | VCSL | `Chordophones/Composite Chordophones/Folk Harp/EWHarp_Normal_F#2_v3_RR1.wav` | pluck, 2.8 s, 32000 Hz |
| harp_c4.ogg | VCSL | `Chordophones/Composite Chordophones/Folk Harp/EWHarp_Normal_C3_v3_RR1.wav` | pluck, 2.4 s, 32000 Hz |
| harp_fs4.ogg | VCSL | `Chordophones/Composite Chordophones/Folk Harp/EWHarp_Normal_F#3_v3_RR1.wav` | pluck, 2.0 s, 32000 Hz |
| harp_c5.ogg | VCSL | `Chordophones/Composite Chordophones/Folk Harp/EWHarp_Normal_C4_v3_RR1.wav` | pluck, 1.9 s, 32000 Hz |
| harp_fs5.ogg | VCSL | `Chordophones/Composite Chordophones/Folk Harp/EWHarp_Normal_F#4_v3_RR1.wav` | pluck, 1.5 s, 32000 Hz |
| harp_c6.ogg | VCSL | `Chordophones/Composite Chordophones/Folk Harp/EWHarp_Normal_C5_v3_RR1.wav` | pluck, 1.3 s, 32000 Hz |
| dulcimer_d3.ogg | VCSL | `Chordophones/Composite Chordophones/Strumstick/Finger/Strumstick_Finger_Str1_Main_D2_vl3_rr1.wav` | pluck, 2.6 s, 32000 Hz |
| dulcimer_a3.ogg | VCSL | `Chordophones/Composite Chordophones/Strumstick/Finger/Strumstick_Finger_Str2_Main_A2_vl3_rr1.wav` | pluck, 2.3 s, 32000 Hz |
| dulcimer_e4.ogg | VCSL | `Chordophones/Composite Chordophones/Strumstick/Finger/Strumstick_Finger_Str3_Main_E3_vl3_rr1.wav` | pluck, 2.2 s, 32000 Hz |
| dulcimer_b4.ogg | VCSL | `Chordophones/Composite Chordophones/Strumstick/Finger/Strumstick_Finger_Str3_Main_B3_vl3_rr1.wav` | pluck, 2.0 s, 32000 Hz |
| dulcimer_fs5.ogg | VCSL | `Chordophones/Composite Chordophones/Strumstick/Finger/Strumstick_Finger_Str3_Main_F#4_vl3_rr1.wav` | pluck, 1.6 s, 32000 Hz |
| cello_c2.ogg | VSCO-2 CE | `Strings/Cello Section/susvib/susvib_C1_v1_1.wav` | sustain, 2.6 s, 22050 Hz |
| cello_g2.ogg | VSCO-2 CE | `Strings/Cello Section/susvib/susvib_G1_v1_1.wav` | sustain, 2.6 s, 22050 Hz |
| cello_d3.ogg | VSCO-2 CE | `Strings/Cello Section/susvib/susvib_D2_v1_1.wav` | sustain, 2.6 s, 22050 Hz |
| cello_a3.ogg | VSCO-2 CE | `Strings/Cello Section/susvib/susvib_A2_v1_1.wav` | sustain, 2.6 s, 22050 Hz |
| cello_e4.ogg | VSCO-2 CE | `Strings/Cello Section/susvib/susvib_E3_v1_1.wav` | sustain, 2.6 s, 22050 Hz |
| cello_b4.ogg | VSCO-2 CE | `Strings/Cello Section/susvib/susvib_B3_v1_1.wav` | sustain, 2.6 s, 22050 Hz |
| strings_g3.ogg | VSCO-2 CE | `Strings/Violin Section/susVib/VlnEns_susVib_G2_v1.wav` | sustain, 2.6 s, 24000 Hz |
| strings_d4.ogg | VSCO-2 CE | `Strings/Violin Section/susVib/VlnEns_susVib_D3_v1.wav` | sustain, 2.6 s, 24000 Hz |
| strings_a4.ogg | VSCO-2 CE | `Strings/Violin Section/susVib/VlnEns_susVib_A3_v1.wav` | sustain, 2.6 s, 24000 Hz |
| strings_e5.ogg | VSCO-2 CE | `Strings/Violin Section/susVib/VlnEns_susVib_E4_v1.wav` | sustain, 2.6 s, 24000 Hz |
| strings_b5.ogg | VSCO-2 CE | `Strings/Violin Section/susVib/VlnEns_susVib_B4_v1.wav` | sustain, 2.6 s, 24000 Hz |
| violin_a3.ogg | VSCO-2 CE | `Strings/Solo Violin/Arco Vib/LLVln_ArcoVib_A3_p.wav` | sustain, 2.6 s, 24000 Hz |
| violin_e4.ogg | VSCO-2 CE | `Strings/Solo Violin/Arco Vib/LLVln_ArcoVib_E4_p.wav` | sustain, 2.6 s, 24000 Hz |
| violin_a4.ogg | VSCO-2 CE | `Strings/Solo Violin/Arco Vib/LLVln_ArcoVib_A4_p.wav` | sustain, 2.6 s, 24000 Hz |
| violin_e5.ogg | VSCO-2 CE | `Strings/Solo Violin/Arco Vib/LLVln_ArcoVib_E5_p.wav` | sustain, 2.6 s, 24000 Hz |
| violin_a5.ogg | VSCO-2 CE | `Strings/Solo Violin/Arco Vib/LLVln_ArcoVib_A5_p.wav` | sustain, 2.6 s, 24000 Hz |
| violin_e6.ogg | VSCO-2 CE | `Strings/Solo Violin/Arco Vib/LLVln_ArcoVib_E6_p.wav` | sustain, 2.5 s, 24000 Hz |
| psaltery_as4.ogg | VCSL | `Chordophones/Zithers/Psaltery, Bowed and Plucked/LongBow/BowedPsaltery_A#3_Main_LongBow_rr2.wav` | sustain, 2.8 s, 24000 Hz |
| psaltery_e5.ogg | VCSL | `Chordophones/Zithers/Psaltery, Bowed and Plucked/LongBow/BowedPsaltery_E4_Main_LongBow_rr2.wav` | sustain, 2.8 s, 24000 Hz |
| psaltery_as5.ogg | VCSL | `Chordophones/Zithers/Psaltery, Bowed and Plucked/LongBow/BowedPsaltery_A#4_Main_LongBow_rr2.wav` | sustain, 2.6 s, 24000 Hz |
| psaltery_e6.ogg | VCSL | `Chordophones/Zithers/Psaltery, Bowed and Plucked/LongBow/BowedPsaltery_E5_Main_LongBow_rr2.wav` | sustain, 2.6 s, 24000 Hz |
| glass_ds5.ogg | VCSL | `Idiophones/Friction Idiophones/Wine Glasses/Sustains/Slow/glass1_D#4_Slow_1_Main.wav` | sustain, 3.0 s, 22050 Hz |
| glass_fs5.ogg | VCSL | `Idiophones/Friction Idiophones/Wine Glasses/Sustains/Slow/glass2_F#4_Slow_1_Main.wav` | sustain, 3.0 s, 22050 Hz |
| glass_d6.ogg | VCSL | `Idiophones/Friction Idiophones/Wine Glasses/Sustains/Slow/glass4_D5_Slow_2_Main.wav` | sustain, 3.0 s, 22050 Hz |
| flute_a4.ogg | VSCO-2 CE | `Woodwinds/Flute/susvib/LDFlute_susvib_A3_v1_1.wav` | sustain, 2.6 s, 24000 Hz |
| flute_e5.ogg | VSCO-2 CE | `Woodwinds/Flute/susvib/LDFlute_susvib_E4_v1_1.wav` | sustain, 2.6 s, 24000 Hz |
| flute_a5.ogg | VSCO-2 CE | `Woodwinds/Flute/susvib/LDFlute_susvib_A4_v1_1.wav` | sustain, 2.5 s, 24000 Hz |
