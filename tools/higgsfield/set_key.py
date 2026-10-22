"""Saves your Higgsfield API key to .env.local without showing it on screen. Run it yourself:

    uv run --with python-dotenv python tools/higgsfield/set_key.py
"""
import getpass
import sys

from dotenv import set_key

from env import ENV_FILE


def main() -> int:
    key = getpass.getpass("Higgsfield API anahtari (key-id:key-secret, yazarken gorunmez): ").strip()
    key_id, _, secret = key.partition(":")
    if not key_id or not secret:
        print("Bicim key-id:key-secret olmali (ortada iki nokta). Kaydedilmedi.")
        return 1
    ENV_FILE.touch(exist_ok=True)
    set_key(str(ENV_FILE), "HF_KEY", key, quote_mode="never")
    print("Kaydedildi: .env.local (Git'e gitmez). Bu pencereyi kapatabilirsin.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
