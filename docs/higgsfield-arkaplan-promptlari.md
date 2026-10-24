# Higgsfield arka plan promptları

Kitaplığın Pro arka planları: konu değil, malzeme ve ışık. Stüdyo makro fotoğrafı ve 3B render arası soyut görseller. 12 konseptten en iyi 10'u uygulamaya girer.

## Ayarlar

| Ayar | Değer |
|---|---|
| Model | GPT Image 2.5, Sunburst |
| Oran | 1:1 |
| Çözünürlük | 4K (2880 px) |
| Kalite | max |
| Adet | 2 varyant (iyisini seçeriz) |

## Üretme

Higgsfield CLI girişliyken hepsini birden üretmek için:

```
python tools/higgsfield/backgrounds.py <klasör> --variants 2
```

Tek tek yeniden üretmek için konseptin adını ekle. Sonra `python tools/make_backgrounds.py <klasör>` seçilenleri uygulamaya 2752 px olarak koyar.

Her promptun sonuna aynı kapanış eklenir:

```
Ultra high-end abstract wallpaper, award-winning, extraordinary fine detail, physically accurate light and materials, rich depth, flawless and clean. Leave one calm, uncluttered area so interface text can sit on it. No text, no letters, no numbers, no logos, no watermark, no people, no frame, edge to edge.
```

## Promptlar

### 1. glass.png

```
Sculptural ribbons of clear liquid glass twisting through the frame, thick and glossy, with prismatic dispersion splitting light into delicate rainbow edges, bright caustics falling on a pale warm grey seamless studio backdrop, macro lens, shallow depth of field, high-end 3D render.
```

### 2. silk.png

```
Monumental flowing folds of champagne and pearl silk satin sweeping diagonally across the frame, soft directional window light, deep luminous shadows inside the folds, visible fine weave, editorial luxury fashion photography.
```

### 3. molten.png

```
Molten liquid gold and glossy obsidian black swirling into each other in slow marbled currents, mirror-like reflective surface, dramatic rim light catching the gold, macro fluid art photography, deep dark background.
```

### 4. prism.png

```
Sunlight refracted through a crystal prism casting spectral rainbow beams and sharp caustic patterns across a textured warm white plaster wall, soft natural shadows, minimal architectural composition, serene morning light.
```

### 5. paperwave.png

```
Layered sculpted paper waves cut from thick paper, a gradient from coral to soft blush to warm cream, gentle soft shadows between the layers, top-down soft light, elegant paper art, tactile and precise.
```

### 6. reeded.png

```
Vivid glowing colour fields of tangerine, magenta and cobalt seen through fluted reeded glass, vertical ribbed refraction stretching and bending the colours, soft luminous haze, modern architectural glass, premium and calm.
```

### 7. ferro.png

```
Ferrofluid sculpture: a field of black magnetic fluid spikes rising in a smooth wave, glossy surface with iridescent oil-slick sheen of violet, teal and gold, dramatic studio lighting on a deep black background, macro photography.
```

### 8. holo.png

```
Macro of softly crumpled holographic foil, iridescent reflections shifting from pink to cyan to pale gold along sharp delicate creases, soft studio light, glossy and luminous, pastel overall.
```

### 9. dunes.png

```
Abstract aerial view of desert sand dunes at golden hour, sweeping sculptural curves of warm light and long violet shadows, fine wind ripples in the sand, terracotta, apricot and dusk violet, minimal and majestic.
```

### 10. orbs.png

```
Floating glossy glass spheres of different sizes suspended in soft air, pastel refractions and gentle reflections inside each sphere, over a smooth gradient backdrop of lilac, peach and pale aqua, dreamy depth of field, high-end 3D render.
```

### 11. lightpaint.png

```
Long-exposure light painting: silky luminous arcs and ribbons of warm gold and cool electric blue sweeping across a deep black background, fine glowing filaments, elegant motion, high-end abstract photography.
```

### 12. pearl.png

```
Extreme macro of mother-of-pearl nacre surface, iridescent rainbow sheen of soft pink, mint, lilac and silver flowing in fine layered waves, polished and luminous, soft diffused light.
```
