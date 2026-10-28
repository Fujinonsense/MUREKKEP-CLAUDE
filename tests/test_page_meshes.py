"""Page meshes (InkRenderer): neighbouring pages are made off the main thread, and the shadow passes
draw only the raised inks' triangles. Both must leave the picture as it was."""
import re
from pathlib import Path

APP = Path(__file__).resolve().parent.parent / "Murekkep.swiftpm"
RENDERER = (APP / "InkRenderer.swift").read_text(encoding="utf-8")


def body(source, signature):
    """The text of the function that starts with `signature`, up to its closing brace."""
    start = source.index(signature)
    depth, i = 0, source.index("{", start)
    while True:
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                return source[start:i + 1]
        i += 1


def without_demo(text):
    return re.sub(r"#if DEMO.*?#endif", "", text, flags=re.S)


def test_every_ink_the_shader_shadows_is_in_the_shadow_list():
    shaders = (APP / "InkShaders.swift").read_text(encoding="utf-8")
    height = body(shaders, "static float shadowHeight(")
    shaded = {name.lower() for name in re.findall(r"BRUSH_(\w+)", height)}
    brushes = (APP / "Brushes.swift").read_text(encoding="utf-8")
    casts = body(brushes, "var castsShadow: Bool")
    flat = set(re.findall(r"\.(\w+)", re.search(r"case (.*?): return false", casts).group(1)))
    assert "return true" in casts and {"wave", "gold", "galaxy", "ice", "jelly"} <= shaded
    # A brush the shader gives a shadow but Swift leaves out of the list would lose its shadow.
    assert not shaded & flat, shaded & flat


def test_the_shadow_passes_draw_the_raised_inks_list():
    draw = body(RENDERER, "private func drawStrokes(")
    assert "shadowTriangles(gpu, ink: indices)" in draw
    pick = without_demo(body(RENDERER, "private func shadowTriangles("))
    assert "gpu.shadowIndices" in pick and "inkIndexCount" not in pick
    # A whole page and appended strokes alike put each raised stroke's triangles on the list.
    fill = body(RENDERER, "private static func fill(")
    assert "if s.brush.castsShadow {" in fill and "shadowIdxs.append(contentsOf: idxs[start...])" in fill
    append = body(RENDERER, "private func append(_ added: [Stroke]")
    assert "if s.brush.castsShadow {" in append and "gpu.shadowIndexCount += shadowIdxs.count" in append


def test_neighbouring_pages_are_made_off_the_main_thread():
    prewarm = without_demo(body(RENDERER, "private func prewarm("))
    assert "meshQueue.async" in prewarm and "cached(" not in prewarm
    # Late meshes are kept only if nothing built the page meanwhile and the cache was not thrown away.
    assert "generation == self.cacheGeneration" in prewarm and "== started" in prewarm
    # The mesh maker touches only its arguments: no renderer state off the main thread.
    fill = body(RENDERER, "private static func fill(")
    assert "self." not in fill and "grassCache" not in fill and "pageCache" not in fill
