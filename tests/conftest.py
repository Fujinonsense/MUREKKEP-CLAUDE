import sys
from pathlib import Path

# The handwriting model's Python code (training data, the model's input, export) is tested here too.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "ml" / "handwriting"))
