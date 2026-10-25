"""Writes the App Store Connect API key from the ASC_KEY_P8 secret as the strict PEM xcodebuild reads,
and with --check-api asks Apple whether the key, ASC_KEY_ID and ASC_ISSUER_ID work, before the long
build. It prints the key's shape, never its content. Standard library and openssl only (CI's Mac).

    python3 tools/asc_key.py <out.p8> [--check-api]
"""
import base64
import binascii
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

BEGIN, END = "-----BEGIN PRIVATE KEY-----", "-----END PRIVATE KEY-----"
BUNDLE_ID = "com.murekkep.notebook"


def normalize(raw):
    """The key as swift-crypto wants it: BEGIN line, body in 64-character lines, END line."""
    text = raw.strip()
    if not text:
        raise ValueError("it is empty")
    if "-----" not in text:  # maybe the whole file, base64-encoded once more
        try:
            decoded = base64.b64decode(re.sub(r"\s", "", text), validate=True).decode()
        except (binascii.Error, UnicodeDecodeError, ValueError):
            decoded = ""
        if BEGIN in decoded:
            text = decoded.strip()
    m = re.search(re.escape(BEGIN) + "(.*?)" + re.escape(END), text, re.S)
    b64 = re.sub(r"\s", "", m.group(1) if m else text)
    try:
        der = base64.b64decode(b64, validate=True)
    except (binascii.Error, ValueError):
        raise ValueError("its body is not base64") from None
    if not der or der[0] != 0x30:  # PKCS#8 is an ASN.1 SEQUENCE
        raise ValueError("it is not a PKCS#8 private key")
    return "\n".join([BEGIN, *(b64[i:i + 64] for i in range(0, len(b64), 64)), END]) + "\n"


def describe(raw):
    """Line count, line lengths, line endings and where the BEGIN/END lines are: nothing of the key."""
    if not raw.strip():
        return "empty"
    lines = raw.replace("\r\n", "\n").split("\n")
    def where(marker, at):
        if lines[at] == marker:
            return f"{marker[5:-5]} line in place"
        return f"{marker[5:-5]} line misplaced or padded" if marker in raw else f"no {marker[5:-5]} line"
    return "; ".join([
        f"{len(raw)} characters in {len(lines)} lines",
        "CR LF line endings" if "\r" in raw else "LF line endings",
        where(BEGIN, 0), where(END, -1 if lines[-1] else -2),
        "line lengths " + ",".join(str(len(line)) for line in lines),
        "spaces at line edges" if any(line != line.strip() for line in lines) else "no stray spaces",
    ])


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def token(path, key_id, issuer, now=None):
    """An ES256 JWT for the App Store Connect API, valid for ten minutes."""
    now = int(time.time()) if now is None else now
    head = b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    claims = b64url(json.dumps({"iss": issuer, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}).encode())
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", str(path)], input=f"{head}.{claims}".encode(),
                         capture_output=True, check=True).stdout
    # openssl gives SEQUENCE { INTEGER r, INTEGER s }; a JWT wants r and s as 32 bytes each.
    raw, i = b"", 2
    for _ in range(2):
        n = der[i + 1]
        raw += der[i + 2:i + 2 + n].lstrip(b"\0").rjust(32, b"\0")
        i += 2 + n
    return f"{head}.{claims}.{b64url(raw)}"


def check_api(path):
    key_id, issuer = os.environ.get("ASC_KEY_ID", ""), os.environ.get("ASC_ISSUER_ID", "")
    for name, value in (("ASC_KEY_ID", key_id), ("ASC_ISSUER_ID", issuer)):
        if value != value.strip():
            print(f"{name} has spaces or a line break around it (ignored).")
    key_id, issuer = key_id.strip(), issuer.strip()
    print("ASC_KEY_ID is", "10 letters/digits" if re.fullmatch(r"[A-Z0-9]{10}", key_id) else f"{len(key_id)} characters, not the 10 of a Key ID")
    print("ASC_ISSUER_ID is", "a UUID" if re.fullmatch(r"[0-9a-f-]{36}", issuer) else f"{len(issuer)} characters, not a UUID")
    query = urllib.parse.urlencode({"filter[bundleId]": BUNDLE_ID, "fields[apps]": "name,bundleId"})
    request = urllib.request.Request(f"https://api.appstoreconnect.apple.com/v1/apps?{query}",
                                     headers={"Authorization": "Bearer " + token(path, key_id, issuer)})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            apps = json.load(response)["data"]
    except urllib.error.HTTPError as e:
        hint = {401: "Apple did not accept the key: ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_P8 must come from the same key, and the key must not be revoked.",
                403: "The key may not read apps; give it the App Manager or Admin role."}.get(e.code, "")
        print(f"::error::App Store Connect API answered {e.code}. {hint}")
        return 1
    if not apps:
        print(f"::error::The key works, but it sees no app with the bundle ID {BUNDLE_ID}.")
        return 1
    print(f"The App Store Connect key works: {apps[0]['attributes']['name']} (Apple ID {apps[0]['id']}).")
    return 0


def main(argv):
    out = argv[1]
    raw = os.environ.get("ASC_KEY_P8", "")
    print("ASC_KEY_P8 as stored:", describe(raw))
    try:
        pem = normalize(raw)
    except ValueError as e:
        print(f"::error::ASC_KEY_P8 is not a usable key: {e}. Paste the whole AuthKey_<Key ID>.p8 file into the secret again, BEGIN and END lines included.")
        return 1
    if pem != raw:
        print("Rewrote it as a strict PEM.")
    fd = os.open(out, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(pem)
    if subprocess.run(["openssl", "pkey", "-in", out, "-noout"], capture_output=True).returncode != 0:
        print("::error::ASC_KEY_P8 has the shape of a key, but openssl cannot read it. Paste the .p8 file again.")
        return 1
    return check_api(out) if "--check-api" in argv else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
