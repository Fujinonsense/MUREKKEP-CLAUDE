"""Trains the handwriting recognizer on synthetic lines (synth.py) with CTC loss.

Validation uses 2,000 fixed lines written with fonts never trained on. The run stops at --steps or
once the character error rate is ≤ 4 % and Turkish letters (ç ğ ı ö ş ü Ç Ğ İ Ö Ş Ü) are ≥ 97 %
right, after at least --min-steps.

usage: python train.py [--steps 120000] [--batch 48] [--workers 20] [--out DIR]"""
import argparse
import datetime
import math
import os
import time
from pathlib import Path

import numpy as np
import torch
from torch import nn
from torch.utils.data import DataLoader, IterableDataset

import synth
from charset import NUM_CLASSES, decode, encode
from model import CRNN

TURKISH = set("çğıöşüÇĞİÖŞÜ")
RUNS = Path(os.environ.get("MRK_RUNS", "C:/Users/orsyu/mrk-ml/runs"))


def collate(items):
    widths = [img.shape[1] for img, _ in items]
    x = np.zeros((len(items), 1, 48, max(widths)), np.float32)
    for i, (img, _) in enumerate(items):
        x[i, 0, :, :img.shape[1]] = img
    targets = [encode(t) for _, t in items]
    return (torch.from_numpy(x), torch.tensor([w // 4 for w in widths]),
            torch.tensor([i for t in targets for i in t]), torch.tensor([len(t) for t in targets]),
            [t for _, t in items])


class Lines(IterableDataset):
    """Endless batches of synthetic lines; every worker has its own random stream."""

    def __init__(self, fonts, batch, seed):
        self.fonts, self.batch, self.seed = fonts, batch, seed

    def __iter__(self):
        info = torch.utils.data.get_worker_info()
        rng = np.random.default_rng([self.seed, info.id if info else 0])
        pool = synth.FontPool(self.fonts)
        while True:
            yield collate([synth.make_line(rng, pool) for _ in range(self.batch)])


def greedy(logits, lengths):
    best = logits.argmax(-1).cpu().numpy()
    out = []
    for row, n in zip(best, lengths.tolist()):
        ids, prev = [], 0
        for k in row[:n]:
            if k != prev and k != 0:
                ids.append(int(k))
            prev = k
        out.append(decode(ids))
    return out


def alignment(truth, guess):
    """(edit distance, set of truth positions read correctly)."""
    n, m = len(truth), len(guess)
    d = np.zeros((n + 1, m + 1), dtype=np.int32)
    d[:, 0] = np.arange(n + 1)
    d[0, :] = np.arange(m + 1)
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            d[i, j] = min(d[i - 1, j] + 1, d[i, j - 1] + 1, d[i - 1, j - 1] + (truth[i - 1] != guess[j - 1]))
    i, j, ok = n, m, set()
    while i > 0 and j > 0:
        if truth[i - 1] == guess[j - 1] and d[i, j] == d[i - 1, j - 1]:
            ok.add(i - 1)
            i, j = i - 1, j - 1
        elif d[i, j] == d[i - 1, j - 1] + 1:
            i, j = i - 1, j - 1
        elif d[i, j] == d[i - 1, j] + 1:
            i -= 1
        else:
            j -= 1
    return int(d[n, m]), ok


def evaluate(model, batches, device):
    model.eval()
    errors = chars = tr_total = tr_ok = 0
    examples = []
    with torch.no_grad():
        for x, lengths, _, _, texts in batches:
            with torch.autocast("cuda", dtype=torch.bfloat16):
                logits = model(x.to(device))
            for truth, guess in zip(texts, greedy(logits.float(), lengths)):
                dist, ok = alignment(truth, guess)
                errors += dist
                chars += len(truth)
                for i, c in enumerate(truth):
                    if c in TURKISH:
                        tr_total += 1
                        tr_ok += i in ok
                if len(examples) < 8 and truth != guess:
                    examples.append((truth, guess))
    model.train()
    return errors / max(chars, 1), tr_ok / max(tr_total, 1), examples


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--steps", type=int, default=120_000)
    ap.add_argument("--min-steps", type=int, default=30_000)
    ap.add_argument("--batch", type=int, default=48)
    ap.add_argument("--workers", type=int, default=20)
    ap.add_argument("--lr", type=float, default=1e-3)
    ap.add_argument("--eval-every", type=int, default=2000)
    ap.add_argument("--resume", type=str, default=None, help="checkpoint whose weights to start from")
    ap.add_argument("--warmup", type=int, default=1000)
    ap.add_argument("--out", type=str, default=str(RUNS / datetime.datetime.now().strftime("%Y%m%d-%H%M")))
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    log = open(out / "log.txt", "a", encoding="utf-8")

    def say(msg):
        line = f"{datetime.datetime.now():%H:%M:%S} {msg}"
        print(line, flush=True)
        log.write(line + "\n")
        log.flush()

    device = "cuda"
    train_fonts, val_fonts = synth.split_fonts()
    rng = np.random.default_rng(1234)
    val_pool = synth.FontPool(val_fonts)
    val = [collate([synth.make_line(rng, val_pool) for _ in range(50)]) for _ in range(40)]
    say(f"fonts {len(train_fonts)} train / {len(val_fonts)} held out; {sum(len(b[4]) for b in val)} validation lines")

    model = CRNN(NUM_CLASSES).to(device)
    if args.resume:
        model.load_state_dict(torch.load(args.resume, map_location=device)["model"])
        say(f"weights from {args.resume}")
    opt = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=1e-4)
    warm = args.warmup

    def lr_at(step):
        if step < warm:
            return args.lr * (step + 1) / warm
        p = (step - warm) / max(args.steps - warm, 1)
        return 1e-5 + (args.lr - 1e-5) * 0.5 * (1 + math.cos(math.pi * min(p, 1.0)))

    ctc = nn.CTCLoss(blank=0, zero_infinity=True)
    loader = DataLoader(Lines(train_fonts, args.batch, 7), batch_size=None, num_workers=args.workers,
                        persistent_workers=True, prefetch_factor=4, pin_memory=True)
    best = float("inf")
    t0 = time.time()
    running = 0.0
    for step, (x, lengths, targets, target_lengths, _) in enumerate(loader):
        if step >= args.steps:
            break
        for g in opt.param_groups:
            g["lr"] = lr_at(step)
        with torch.autocast("cuda", dtype=torch.bfloat16):
            logits = model(x.to(device, non_blocking=True))
        lp = logits.float().log_softmax(-1).transpose(0, 1)
        loss = ctc(lp, targets, lengths, target_lengths)
        opt.zero_grad(set_to_none=True)
        loss.backward()
        nn.utils.clip_grad_norm_(model.parameters(), 5.0)
        opt.step()
        running = 0.98 * running + 0.02 * loss.item() if step else loss.item()
        if step % 200 == 0:
            say(f"step {step} loss {running:.3f} lr {lr_at(step):.2e} {step / max(time.time() - t0, 1e-6):.1f} it/s")
        if step and step % args.eval_every == 0:
            cer, tr, examples = evaluate(model, val, device)
            state = {"model": model.state_dict(), "step": step, "cer": cer, "tr": tr}
            torch.save(state, out / "last.pt")
            if cer < best:
                best = cer
                torch.save(state, out / "best.pt")
            say(f"eval step {step}: CER {cer:.4f} Turkish letters {tr:.4f} (best CER {best:.4f})")
            for truth, guess in examples[:4]:
                say(f"   {truth!r} -> {guess!r}")
            if step >= args.min_steps and cer <= 0.04 and tr >= 0.97:
                say("target reached")
                break
    say("done")


if __name__ == "__main__":
    main()
