"""Page meshes (InkRenderer): neighbouring pages are made off the main thread, the shadow passes draw
only the raised inks' triangles, and erasing or moving strokes keeps the other strokes' meshes. All
of it must leave the picture as it was."""
import re
from pathlib import Path

APP = Path(__file__).resolve().parent.parent / "Murekkep.swiftpm"
RENDERER = (APP / "InkRenderer.swift").read_text(encoding="utf-8")
SHADERS = (APP / "InkShaders.swift").read_text(encoding="utf-8")


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


def test_the_records_carry_the_drawing_order_on_both_sides():
    swift = re.findall(r"var (\w+):", body(RENDERER, "struct StrokeGPU {"))
    metal = re.findall(r"^\s*\w+\s+(\w+);", body(SHADERS, "struct StrokeGPU {"), flags=re.M)
    assert swift == metal == ["color", "brush", "birth", "width", "seed", "order"]
    # Depth comes from the record's place in the drawing order, not from its slot.
    ribbon = body(SHADERS, "static RibbonOut makeRibbon(")
    assert "float order = float(su.orderOffset + rank);" in ribbon
    for fn in ("vertex RibbonOut ribbon_vertex(", "vertex RibbonOut ribbon_shadow_vertex("):
        assert "makeRibbon(v, s.order," in body(SHADERS, fn)
    # A rebuilt page's slots are its drawing order; appended strokes come after every other one.
    assert "seed: s.seed, order: idx)" in body(RENDERER, "private static func fill(")
    assert "order: UInt32(firstOrder + infos.count)" in body(RENDERER, "private func append(_ added: [Stroke]")


def test_erasing_keeps_the_other_strokes_meshes():
    cached = without_demo(body(RENDERER, "private func cached("))
    assert "case .keep:" in cached and "if !keep(gpu, page: page) {" in cached
    keep = body(RENDERER, "private func keep(")
    assert "records[Int(span.slot)].order = UInt32(rank)" in keep
    # Grass blades are numbered by slot: a page with grass is rebuilt.
    assert "gpu.bladeCount == 0" in keep and "growsFlowers" in keep
    # Only strokes without a mesh are meshed; the rest is copied from the old list.
    assert keep.count("RibbonBuilder.append") == 1 and "if let known = gpu.spans[s.id], let mesh = gpu.ribbons[s.id]" in keep
