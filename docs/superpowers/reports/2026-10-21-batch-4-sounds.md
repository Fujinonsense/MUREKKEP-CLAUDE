# Batch 4 — pen sound assets and their sources

Every pen plays its own family of recordings (`SoundFamily` in `Murekkep.swiftpm/PaperSound.swift`).

The pencil keeps its bundled recordings, `kagit-1…3`: "Pencil #1, #3, #4" by Joseph Sardin, BigSoundBank, CC0.

The other recordings are Freesound HQ previews.
- `C:/Users/orsyu/mrk-ml/tools/fs_fetch.py` downloaded them only after it found the CC0 1.0 deed (`creativecommons.org/publicdomain/zero/1.0/`) on each sound's page and no other license link.
- `C:/Users/orsyu/mrk-ml/tools/pen_sounds.py` then processed them:
  - a 4th-order high-pass (220 Hz for writing, lower for water and lava)
  - only the sounding stretches; writing recordings also lose their clicks and taps
  - at most 5–6 s from 15 % in
  - an even loudness (RMS 0.11, soft-limited peaks with room for MP3)
  - 64 kbps mono MP3

Two recordings were left out:
- 870749, "Slow Viscous Mystery Bubbles": one pitched tone held most of its energy, a drone rather than lava.
- 396014, "Rustling Grass 1": 0.4 s of sound, too short.

The sparkle family (glitter, galaxy) is synthesized by the same tool: sparse soft chimes over a faint hiss. It is CC0 as well.

| Asset | Family | Seconds | Source | Author |
|---|---|---|---|---|
| ses-pen-1 | pen | 6.0 | [Freesound - writing.wav by hatshoeba](https://freesound.org/people/hatshoeba/sounds/560086/) | hatshoeba |
| ses-pen-2 | pen | 6.0 | [Freesound - 16_ballpoint pen, writing.WAV by 16F_Panska_TisonD](https://freesound.org/people/16F_Panska_TisonD/sounds/499189/) | 16F_Panska_TisonD |
| ses-pen-3 | pen | 6.0 | [Freesound - Writing On Paper.wav by 190099](https://freesound.org/people/190099/sounds/492355/) | 190099 |
| ses-nib-1 | nib | 5.0 | [Freesound - Writing with Fountain Pen Nib by black_trillium](https://freesound.org/people/black_trillium/sounds/397282/) | black_trillium |
| ses-nib-2 | nib | 5.0 | [Freesound - Fountain Pen Scratching Paper by DataJuggler](https://freesound.org/people/DataJuggler/sounds/750171/) | DataJuggler |
| ses-nib-3 | nib | 4.23 | [Freesound - Writing quickly - fountain pen by Valerie-Vivegnis](https://freesound.org/people/Valerie-Vivegnis/sounds/843922/) | Valerie-Vivegnis |
| ses-nib-4 | nib | 1.39 | [Freesound - Fountainpen_Write_1_Texture by hanasmusic](https://freesound.org/people/hanasmusic/sounds/841413/) | hanasmusic |
| ses-felt-1 | felt | 4.33 | [Freesound - writing - sharpie 01.wav by Anthousai](https://freesound.org/people/Anthousai/sounds/337088/) | Anthousai |
| ses-felt-2 | felt | 5.0 | [Freesound - Marker Lines.WAV by TubbsMedia](https://freesound.org/people/TubbsMedia/sounds/377124/) | TubbsMedia |
| ses-felt-3 | felt | 2.38 | [Freesound - fast and slow marker strokes by MBPiM](https://freesound.org/people/MBPiM/sounds/351145/) | MBPiM |
| ses-felt-4 | felt | 5.0 | [Freesound - Marker Writing on Paper.aif by ftpalad](https://freesound.org/people/ftpalad/sounds/119926/) | ftpalad |
| ses-brush-1 | brush | 5.0 | [Freesound - painting_1.aif by ssalo](https://freesound.org/people/ssalo/sounds/482891/) | ssalo |
| ses-brush-2 | brush | 0.85 | [Freesound - Pincel en lienzo by Pipe98x](https://freesound.org/people/Pipe98x/sounds/409608/) | Pipe98x |
| ses-brush-3 | brush | 5.0 | [Freesound - brush painting sounds by digital.arts.MA](https://freesound.org/people/digital.arts.MA/sounds/729108/) | digital.arts.MA |
| ses-water-1 | water | 6.0 | [Freesound - Gentle Stream Natural Stream Sound by BurghRecords](https://freesound.org/people/BurghRecords/sounds/446019/) | BurghRecords |
| ses-water-2 | water | 6.0 | [Freesound - Babbling Brook by deleted_user_2906614](https://freesound.org/people/deleted_user_2906614/sounds/241095/) | deleted_user_2906614 |
| ses-water-3 | water | 6.0 | [Freesound - gentle river flow by Garuda1982](https://freesound.org/people/Garuda1982/sounds/707576/) | Garuda1982 |
| ses-lava-1 | lava | 6.0 | [Freesound - Hot Bubbling Mud by Breviceps](https://freesound.org/people/Breviceps/sounds/456806/) | Breviceps |
| ses-lava-2 | lava | 6.0 | [Freesound - Bubbling Mud with Steam by ProductionNow](https://freesound.org/people/ProductionNow/sounds/352904/) | ProductionNow |
| ses-grass-1 | grass | 4.02 | [Freesound - Rustling Grass by alegemaate](https://freesound.org/people/alegemaate/sounds/364712/) | alegemaate |
| ses-grass-2 | grass | 5.0 | [Freesound - Dry Grass Rustle.wav by TheSupremeMuffinPooter](https://freesound.org/people/TheSupremeMuffinPooter/sounds/525268/) | TheSupremeMuffinPooter |
| ses-spark-1 | spark | 6.0 | [Freesound - Light Electricity crackling  by ihitokage](https://freesound.org/people/ihitokage/sounds/238597/) | ihitokage |
| ses-spark-2 | spark | 6.0 | [Freesound - Electricity crackling by ihitokage](https://freesound.org/people/ihitokage/sounds/187363/) | ihitokage |
| ses-ice-1 | ice | 5.0 | [Freesound - Ice - Styrofoam - Crackling - Foley by td6d](https://freesound.org/people/td6d/sounds/184225/) | td6d |
| ses-ice-2 | ice | 3.0 | [Freesound - ice1.wav by jwb4](https://freesound.org/people/jwb4/sounds/135446/) | jwb4 |
| ses-ice-3 | ice | 1.03 | [Freesound - ice2.wav by jwb4](https://freesound.org/people/jwb4/sounds/135445/) | jwb4 |
| ses-sparkle-1 | sparkle | 7.0 | synthesized by tools/pen_sounds.py | Mürekkep |
| ses-sparkle-2 | sparkle | 7.0 | synthesized by tools/pen_sounds.py | Mürekkep |

Brush → family:
- pencil → pencil
- pen → pen
- fountain, calligraphy → nib
- gold, chrome, pearl → metal (the nib recordings, faster and brighter)
- highlighter, neon → felt
- watercolor, wet, impasto, rainbow → brush
- jelly → gel (the brush recordings, slower and darker)
- sea, wave → water
- lava → lava
- grass → grass
- lightning → spark
- ice → ice
- glitter, galaxy → sparkle
- eraser → the pencil's recordings, darker and slower
