"""Generates the library's Pro backgrounds with the Higgsfield CLI (GPT Image 2.5, Sunburst, 4K,
square, max quality) from docs/higgsfield-arkaplan-promptlari.md, all at once, and downloads each
result as <name>.png (2880 px) into the output folder. Names given on the command line are made
again; --fetch only downloads the finished jobs again.
usage: python tools/higgsfield/backgrounds.py <out folder> [--fetch] [name ...]"""
import json
import re
import shutil
import subprocess
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DOC = ROOT / "docs" / "higgsfield-arkaplan-promptlari.md"


def prompts():
    text = DOC.read_text(encoding="utf-8")
    return {m.group(1): m.group(2).strip() for m in re.finditer(r"### \d+\. (\w+)\.png\s+```\s*(.+?)```", text, re.S)}


def make(name, prompt, out):
    cli = shutil.which("higgsfield")
    run = subprocess.run([cli, "generate", "create", "gpt_image_2_5", "--prompt", prompt, "--aspect_ratio", "1:1",
                          "--resolution", "4k", "--quality", "max", "--variant", "sunburst",
                          "--wait", "--wait-timeout", "25m", "--json"],
                         capture_output=True, text=True, encoding="utf-8", timeout=1800)
    (out / f"{name}.job.json").write_text(run.stdout + run.stderr, encoding="utf-8")
    if run.returncode:
        return f"{name}: failed ({run.returncode}) {run.stderr.strip()[-200:]}"
    return fetch(name, out)


def fetch(name, out):
    """The job's full-size PNG (result_url; min_result_url is a small WebP preview)."""
    text = (out / f"{name}.job.json").read_text(encoding="utf-8")
    jobs = json.loads(text[text.find("["):text.rfind("]") + 1])
    url = jobs[0].get("result_url") if jobs and jobs[0].get("status") == "completed" else None
    if not url:
        return f"{name}: no result"
    with urllib.request.urlopen(url, timeout=300) as r:
        (out / f"{name}.png").write_bytes(r.read())
    return f"{name}: ok"


if __name__ == "__main__":
    args = sys.argv[1:]
    only_fetch = "--fetch" in args
    args = [a for a in args if a != "--fetch"]
    out = Path(args[0])
    out.mkdir(parents=True, exist_ok=True)
    every = prompts()
    assert len(every) == 10, sorted(every)
    names = args[1:] or list(every)
    # The Plus plan runs 8 jobs at once.
    with ThreadPoolExecutor(max_workers=1 if only_fetch else 8) as pool:
        work = (lambda n: fetch(n, out)) if only_fetch else (lambda n: make(n, every[n], out))
        for line in pool.map(work, names):
            print(line, flush=True)
