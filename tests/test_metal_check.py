"""tools/metal_check.py hands CI's Metal compiler exactly the shader text the app compiles at run time."""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import metal_check  # noqa: E402


def test_every_runtime_shader_is_found_whole(tmp_path):
    paths = metal_check.write_all(tmp_path)
    assert [p.name for p in paths] == ["InkShaders.metal", "Stickers.metal", "InkLayer.metal"]
    for p in paths:
        text = p.read_text(encoding="utf-8")
        assert text.startswith("#include <metal_stdlib>\nusing namespace metal;"), p.name
        assert '"""' not in text, p.name
        assert text.count("{") == text.count("}"), p.name
    ink = paths[0].read_text(encoding="utf-8")
    for fn in ("flower_fragment", "flower_vertex", "blade_fragment"):
        assert f" {fn}(" in ink


def test_without_a_metal_compiler_it_warns_and_passes():
    out = subprocess.run([sys.executable, str(ROOT / "tools" / "metal_check.py")], capture_output=True, text=True)
    if "xcrun" in out.stdout or "toolchain" in out.stdout:
        assert out.returncode == 0 and out.stdout.startswith("warning:")


def test_the_workflow_compiles_the_shaders_before_the_build():
    flow = (ROOT / ".github" / "workflows" / "main.yml").read_text(encoding="utf-8")
    assert flow.index("name: Murekkep Shaderlarini Derle") < flow.index("name: IPA Derle")
    assert "run: python3 tools/metal_check.py" in flow
