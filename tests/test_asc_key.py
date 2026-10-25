"""The App Store Connect key CI writes from the ASC_KEY_P8 secret (tools/asc_key.py).

xcodebuild reads it with swift-crypto, which wants a strict PEM: the BEGIN line first, the END
line last and every body line but the last exactly 64 characters. A key pasted into the GitHub
secret page can lose that shape, and xcodebuild then fails with invalidPEMDocument."""
import base64
import json
import shutil
import sys
from pathlib import Path

import pytest
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import encode_dss_signature

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import asc_key  # noqa: E402


@pytest.fixture(scope="module")
def key():
    return ec.generate_private_key(ec.SECP256R1())


@pytest.fixture(scope="module")
def pem(key):
    # Apple's AuthKey_*.p8: PKCS#8, 64-character lines.
    return key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                             serialization.NoEncryption()).decode()


def body(pem):
    return "".join(pem.strip().splitlines()[1:-1])


def pasted(pem):
    b = body(pem)
    return {
        "as is": pem,
        "windows line endings": pem.replace("\n", "\r\n"),
        "no final newline": pem.rstrip("\n"),
        "indented lines": "\n".join("  " + line + " " for line in pem.splitlines()),
        "blank lines around": "\n\n" + pem + "\n\n",
        "one long line": "-----BEGIN PRIVATE KEY-----\n" + b + "\n-----END PRIVATE KEY-----",
        "wrapped at 76": "-----BEGIN PRIVATE KEY-----\n"
                         + "\n".join(b[i:i + 76] for i in range(0, len(b), 76))
                         + "\n-----END PRIVATE KEY-----\n",
        "everything on one line": pem.replace("\n", " "),
        "body only": b,
        "whole file in base64": base64.b64encode(pem.encode()).decode(),
    }


@pytest.mark.parametrize("case", list(pasted("x\nx\nx").keys()))
def test_any_paste_becomes_the_strict_pem(pem, case):
    out = asc_key.normalize(pasted(pem)[case])
    assert out == pem
    lines = out.splitlines()
    assert lines[0] == "-----BEGIN PRIVATE KEY-----" and lines[-1] == "-----END PRIVATE KEY-----"
    assert all(len(line) == 64 for line in lines[1:-2]) and 0 < len(lines[-2]) <= 64
    serialization.load_pem_private_key(out.encode(), password=None)


@pytest.mark.parametrize("raw", ["", "   \n", "not a key", "-----BEGIN PRIVATE KEY-----\n@@@\n-----END PRIVATE KEY-----",
                                 base64.b64encode(b"hello world, not DER").decode()])
def test_something_that_is_not_a_key_is_refused(raw):
    with pytest.raises(ValueError):
        asc_key.normalize(raw)


def test_the_description_shows_the_shape_but_none_of_the_key(pem):
    raw = pasted(pem)["indented lines"].replace("\n", "\r\n")
    text = asc_key.describe(raw)
    b = body(pem)
    assert not any(b[i:i + 8] in text for i in range(len(b) - 8))
    assert "CR" in text and "BEGIN" in text
    assert asc_key.describe("") == "empty"


def test_the_token_is_a_signed_es256_jwt_for_app_store_connect(key, pem, tmp_path):
    if not shutil.which("openssl"):
        pytest.skip("openssl is not on PATH")
    path = tmp_path / "AuthKey_TEST.p8"
    path.write_text(pem)
    token = asc_key.token(path, "ABC123DEFG", "4d38139a-0000-0000-0000-000000000000", now=1_800_000_000)
    head, claims, sig = token.split(".")
    unb64 = lambda s: base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))
    assert json.loads(unb64(head)) == {"alg": "ES256", "kid": "ABC123DEFG", "typ": "JWT"}
    assert json.loads(unb64(claims)) == {"iss": "4d38139a-0000-0000-0000-000000000000", "iat": 1_800_000_000,
                                         "exp": 1_800_000_000 + 600, "aud": "appstoreconnect-v1"}
    raw = unb64(sig)
    assert len(raw) == 64
    der = encode_dss_signature(int.from_bytes(raw[:32], "big"), int.from_bytes(raw[32:], "big"))
    key.public_key().verify(der, f"{head}.{claims}".encode(), ec.ECDSA(hashes.SHA256()))
