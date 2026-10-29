# Mürekkep for Android: how the port is put together

The iPad app lives in `Murekkep.swiftpm/` (SwiftUI + UIKit canvas + Metal). This folder is the
Android edition: Kotlin, Jetpack Compose for the chrome, OpenGL ES 3.0 for the ink (the Metal
renderer's twin). Package `com.murekkep.notebook`, minSdk 26, compileSdk/targetSdk 36, Kotlin 2.2,
AGP 8.11, Gradle 8.14.3, JDK 17. Builds run on Codemagic (workflow `android-build`, branch
`android`); there is no Android SDK on the development PC, so code must compile without trying it
locally. Every build costs free minutes: write carefully, keep types exact, no new dependencies
beyond `app/build.gradle.kts` unless a file states why.

## Folders and who writes them

| Folder | What | Port of |
|---|---|---|
| `ink/` | model, pens, stroke shaping, ribbon meshes, eraser, mesh plans, grass | `InkModel.swift`, `Brushes.swift`, `StrokeBuilder.swift`, `RibbonBuilder.swift`, `InkEraser.swift`, `InkMeshPlan.swift`, `GrassGenerator.swift` |
| `render/` | GLSL programs (`InkShaders.kt`), the GL renderer (`InkRenderer.kt`) | `InkShaders.swift`, `InkRenderer.swift` |
| `canvas/` | the drawing view: pen input, gestures, pages, frame loop | `CanvasView.swift` |
| `ui/` | Compose screens, editor state, theme, strings | `EditorModel.swift`, `LibraryView`, toolbars |
| `data/` | notebooks on disk | `LibraryStore.swift` |

Kotlin files carry the iPad file they port in their header comment. Behaviour and numbers stay the
iPad's unless Android needs otherwise (say so in a comment).

## Shared types (exist: `ink/InkModel.kt`, `ink/Brush.kt`)

`InkColor`, `Vec2`, `InkPoint(x, y, r, ink)`, `InkRect`, `Stroke(brush, color, width, birth, seed,
points, duration)` with `id`, `bounds`, `maxRadius`, `withPoints`; `PageInk(strokes, version)`;
`Brush` (raw values as on iPad, `defaultWidth`, `widthRange`, `pressureSensitivity`, `isAnimated`,
`isFastAnimated`, `castsShadow`, `blendsOnce`, `relaxesCorners`, `growsFlowers`, `shading`,
`palette`, `group`, `isPremium`, `titleTr`, `titleEn`); `referenceNow()` = seconds since 2001-01-01.

## Pen input (`ink/InputSample.kt`, written with the StrokeBuilder port)

```kotlin
data class InputSample(
    val x: Float, val y: Float,        // page points
    val force: Float,                  // iPad scale: UITouch.force / maximumPossibleForce is 0...1; see StrokeBuilder
    val timestamp: Double,             // seconds, any monotonic clock
    val altitude: Float = 1.5707964f,  // radians: pi/2 = upright, 0 = flat (Android: pi/2 - AXIS_TILT)
    val azimuth: Float = 0f,           // radians in page space, 0 = +x, clockwise (Android: AXIS_ORIENTATION - pi/2)
    val roll: Float = 0f,              // barrel roll, radians (none on Android pens)
    val isPencil: Boolean = true,
    val predicted: Boolean = false,
)
```

StrokeBuilder keeps the iPad API: `StrokeBuilder(brush, color, width, seed)`, `add(sample)`,
`preview(predicted: List<InputSample>): List<InkPoint>`, `finish(): List<InkPoint>`, and the same
properties the canvas reads (`brush`, `color`, `width`, `seed`, `nibAngle`, `useRoll`, `editable`
may be left out until shapes are ported).

## GL interface (renderer and shaders)

GLSL ES 3.00 (`#version 300 es`). Every program declares `precision highp float; precision highp int;`.

**Ribbon vertex** (one interleaved VBO per page, 48 bytes, same as `RibbonVertexGPU`):

| location | name | type | bytes |
|---|---|---|---|
| 0 | `a_center` | vec2 | 0 |
| 1 | `a_offset` | vec2 | 8 |
| 2 | `a_tangent` | vec2 | 16 |
| 3 | `a_r` | float | 24 |
| 4 | `a_u` | float | 28 |
| 5 | `a_side` | float | 32 |
| 6 | `a_arc` | float | 36 |
| 7 | `a_ink` | float | 40 |
| 8 | `a_stroke` | uint (`glVertexAttribIPointer`) | 44 |

**Stroke records** (`StrokeGPU`): an RGBA32F texture `u_strokes`, 3 texels per record, 512 records
a row (texture width 1536): record `k` is at row `k / 512`, columns `(k % 512) * 3 + j`:
texel 0 = color rgba (straight, not premultiplied), texel 1 = (brush, birth, width, seed),
texel 2 = (order, 0, 0, 0). Read with `texelFetch(u_strokes, ivec2(col, row), 0)`. `brush` is the
shading raw value; `order` is the stroke's place in the drawing order (its depth), as on iPad
(`StrokeGPU.order`); the live stroke is record 0 of its own small table with order 0.

**Uniforms** (names as in `FrameUniforms` / `SegUniforms`, prefixed `u_`): `u_drawableSize` vec2
(pixels), `u_viewOffset` vec2 (pixels), `u_scale` float (pixels per page point), `u_pixelSize`,
`u_time`, `u_dryDuration`, `u_waveTime`, `u_coolDuration`; per draw `u_pageOrigin` vec2 (document
points), `u_orderOffset` uint, `u_depthStep` float, `u_depthOnly` uint. Quads add `u_rect` vec4,
`u_uvRect` vec4, `u_pageSize` vec2, `u_style` uint, `u_shadowRadius` float; quads draw 4 vertices as a
triangle strip from `gl_VertexID` (no attributes).

**Depth**: Metal's NDC depth is 0...1, GL's is -1...1 with the default `glDepthRangef(0, 1)`: vertex
shaders write `gl_Position.z = zBase * 2.0 - 1.0` (w = 1), fragment shaders that wrote `[[depth]]`
write `gl_FragDepth` with the same 0...1 value. Depth tests as on iPad: write = `GL_LESS` + mask on,
off = `GL_ALWAYS` + mask off, nearest-only = `GL_LEQUAL` + mask off.

**Blending** (premultiplied output, as the Metal pipelines): ink and grass `ONE, ONE_MINUS_SRC_ALPHA`;
the shadow and page shadow straight alpha `SRC_ALPHA, ONE_MINUS_SRC_ALPHA`; the highlighter the
iPad's multiply blend; paper and textures opaque. `InkShaders.kt` lists each program with its blend.

## Editor state (`ui/EditorState.kt`), what the canvas uses

```kotlin
class EditorState {
    val pages: List<PageInk>             // snapshot; pages never go, a blank page always ends the notebook
    val pageSize: Pair<Float, Float>     // A4 in points: 595.28 x 841.89
    var tool: Tool                       // Tool.Brush(brush), Tool.Eraser, (Tool.Lasso later)
    val activeBrush: Brush               // the last brush (for tools that draw)
    fun color(brush: Brush): InkColor
    fun width(brush: Brush): Float
    var eraserMode: EraserMode           // STROKE, PARTIAL
    var eraserSize: Float                // points, 18 by default
    var temporaryEraser: Boolean         // the pen's side button / squeeze held: erases, then goes back
    fun addStroke(page: Int, stroke: Stroke)
    fun beginErase(page: Int); fun erase(page: Int, from: Vec2, to: Vec2); fun endErase(); fun cancelErase()
    fun undo(); fun redo(); val canUndo: Boolean; val canRedo: Boolean
    var onInkChange: (() -> Unit)?       // the canvas asks for a frame
}
```

Pages are stacked vertically with a gap, centered; the canvas owns scrolling and zooming.

## Ribbon meshes (`ink/RibbonBuilder.kt`)

`RibbonBuilder.append(points: List<InkPoint>, stroke: Int, relax: Boolean, out: RibbonOut)` appends
one stroke's mesh. `RibbonOut` is growable and GL-ready: `vertices: FloatArray` with 12 floats a
vertex in the order of the table above (the 12th holds the stroke slot's bits:
`Float.fromBits(slot)`, read back with `toRawBits()`), `vertexCount: Int`, `indices: IntArray`,
`indexCount: Int`, `clear()`. Indices are absolute in `out` (offset by the vertices already there).

## The canvas (`canvas/InkCanvasView.kt`)

`class InkCanvasView(context: Context, state: EditorState) : GLSurfaceView(context)`: the screens
create it with `AndroidView(factory = { InkCanvasView(it, state) })` and call `onPause()` /
`onResume()` with the screen's lifecycle and `release()` when it leaves.
