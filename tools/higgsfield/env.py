"""The Higgsfield API key lives in the repository's .env.local (ignored by Git) as HF_KEY, in the
key-id:key-secret form. It is loaded into the process at run time and never printed."""
import os
from pathlib import Path

from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[2]
ENV_FILE = ROOT / ".env.local"


def load_key() -> bool:
    """Loads .env.local; true when the SDK will find credentials."""
    load_dotenv(ENV_FILE)
    return bool(os.environ.get("HF_KEY")) or bool(os.environ.get("HF_API_KEY") and os.environ.get("HF_API_SECRET"))
