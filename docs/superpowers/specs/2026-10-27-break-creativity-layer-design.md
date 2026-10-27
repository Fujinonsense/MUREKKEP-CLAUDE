# Break corner: the creativity layer

2026-10-27. The user asked for "oyun paneline yaratıcılık katmanı" and said "beni şaşırt". They
work without questions (standing rule), so every choice below is my call, made to be checked on the
iPad.

## Intent

The break card has six games to play. A note app whose whole point is the pencil should also let a
student make something in a break: a calm, beautiful few minutes that feel nothing like homework.
The surprise is that what they make behaves like the real thing: paint floats and spreads like on an
ebru tray, a doodle swims away like a living thing.

## What changes

- The card's picker gets two layers in a segmented control: **Oyunlar** (bubbles, XOX, flyer,
  colour popper, Sudoku) and **Yaratıcılık** (Ebru, Canlı mürekkep, Mürekkep mandalası). The last
  layer chosen is remembered (`@AppStorage("break.layer")`, Oyunlar the first time, since the
  corner's tile is a game controller).
- **Ebru** (new): traditional Turkish marbling on water.
  - Tools: *Damla* (touch to drop paint; it keeps spreading while the pencil is held, and a moving
    pencil leaves a trail of drops), *Biz* (the needle drags paint along its path), *Tarak* (a comb
    across the whole tray, pulled along the axis of the first movement).
  - Six traditional pigments: çivit mavisi, lal kırmızısı, zırnık sarısı, yeşil, toprak, beyaz.
  - *Serp*: sprinkles about thirty drops of the chosen colour over the tray (battal ebru), falling
    one by one.
  - *Desen* menu: Gelgit, Taraklı, Şal, Bülbül yuvası, each played as an animation over the paint
    already on the tray.
  - *Geri al* (up to 10 steps); the header's restart button empties the tray.
  - Model: every paint is a closed outline; moves are the closed-form marbling maps (drop
    p' = c + (p−c)·√(1 + r²/|p−c|²), tine lines z = αλ/(d+λ), vortices, a needle with a Gaussian
    reach), so paint never overlaps and keeps its area. Outlines are refined to edges of 3 pt while
    the tray holds under 60 000 points, and paint pushed wholly off the tray is dropped.
- **Canlı mürekkep** (new): draw a creature in one of the five game inks; 0.8 s after the pencil
  lifts, it wakes with a shake and swims off from exactly where it was drawn.
  - Which way it faces: the end whose outer slices are taller is the tail (a fish's tail fin is
    wider than its snout); when the ends are alike, the stroke's first point marks the head.
  - It swims with a wave running from head to tail, tilts up and down, turns around with a
    flat-flip at the walls and now and then on its own, and chases food from *Yem ver*.
  - A tap on a creature startles it. At most 8 creatures; the oldest fades out for a ninth.
- **Mürekkep mandalası** moves to the creative layer unchanged.

## Constraints

- Logic Foundation-only in `EbruLogic.swift` and `LivingInkLogic.swift`, checked by
  `tools/gamescheck` on the Windows Swift toolchain; views follow the existing games (Canvas,
  `TimelineView(.animation(paused:))`, `DragGesture(minimumDistance: 0)`, `.gameBoard()`).
- No network, no assets, not Pro-gated, Reduce Motion respected (animations apply at once).
- Every Turkish string has its English entry.
- No CI build until the user says so.

## Not in this version

Saving or sharing an ebru, an ebru as the library background, creatures flying in the other games.
