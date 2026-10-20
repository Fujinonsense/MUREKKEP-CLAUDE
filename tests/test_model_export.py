import numpy as np
import pytest

torch = pytest.importorskip("torch")

import export  # noqa: E402
import infer_np  # noqa: E402
import model  # noqa: E402
from charset import CHARSET, NUM_CLASSES  # noqa: E402


def random_model():
    torch.manual_seed(0)
    m = model.CRNN(NUM_CLASSES)
    for mod in m.modules():
        if isinstance(mod, torch.nn.BatchNorm2d):
            mod.running_mean.uniform_(-0.2, 0.2)
            mod.running_var.uniform_(0.5, 1.5)
            mod.weight.data.uniform_(0.5, 1.5)
            mod.bias.data.uniform_(-0.2, 0.2)
    return m.eval()


def test_numpy_matches_torch():
    m = random_model()
    w = infer_np.Weights(export.tensors(m))
    for width in (64, 400):
        img = np.random.default_rng(width).random((48, width)).astype(np.float32)
        with torch.no_grad():
            ref = m(torch.from_numpy(img)[None, None]).log_softmax(-1)[0].numpy()
        got = infer_np.log_probs(w, img)
        assert got.shape == ref.shape == (width // 4, NUM_CLASSES)
        assert np.abs(got - ref).max() < 2e-3


def test_export_roundtrip(tmp_path):
    m = random_model()
    path = tmp_path / "hwmodel.bin"
    export.write(m, path)
    data = path.read_bytes()
    assert data[:8] == b"MRKHW1\0\0"
    loaded = infer_np.load(path)
    assert loaded.charset == CHARSET
    original = export.tensors(m)
    assert len(loaded.tensors) == len(original) == 26
    for a, b in zip(loaded.tensors, original):
        assert a.shape == b.shape
        assert np.array_equal(a, b.astype(np.float16).astype(np.float32))
