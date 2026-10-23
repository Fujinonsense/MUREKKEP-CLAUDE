"""Trains the online (stroke trajectory) handwriting model (online.py) with CTC loss.

Training lines: 75 % from the Kinematic Stroke Generator (kinematic.py: the app's letters in a hand's
drawing order, sloppy), 25 % from handwriting-font skeletons chained into pen trails (trails.py), so
the model also copes with strokes in an unusual order. Validation: 2,000 kinematic lines from a seed
never trained on, and 1,000 trail lines from the held-out fonts.

With --real FILE (real_lines.py: the user's own lines, strokes in the order they were written) a
share of every batch is the user's writing, changed a little each time with its stroke order kept,
and the held-out real lines are measured too.

usage: python train_online.py [--steps 60000] [--batch 64] [--workers 16] [--out DIR] [--real FILE]"""
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

import kinematic
import online
import real_lines
import synth
import texts
import trails
from charset import NUM_CLASSES, decode, encode

RUNS = Path(os.environ.get("MRK_RUNS", "C:/Users/orsyu/mrk-ml/runs"))
TRAIL_SHARE = 0.25


def trail_sample(rng, pool, text=None):
    text = text if text is not None else texts.sample(rng)
    seg = synth.compose(rng, synth.pick_source(rng, pool, text), text)
    if len(seg) == 0:
        return None
    return [[(x, y) for x, y in t] for t in trails.polylines(seg)], text


def item(rng, pool, trail_share=TRAIL_SHARE, real=None, real_share=0.0):
    """(features, text) or None when the line is too short for its text."""
    if real and rng.random() < real_share:
        text, strokes = real[int(rng.integers(len(real)))]
        got = [s.tolist() for s in real_lines.augment(rng, strokes, text.count(" "))], text
    elif rng.random() < trail_share:
        got = trail_sample(rng, pool)
    else:
        got = kinematic.make_sample(rng)
    if got is None:
        return None
    strokes, text = got
    f = online.features(strokes)
    if not text or online.frames(len(f)) < 2 * len(text) + 1:
        return None
    return f, text


def collate(items):
    n = max(len(f) for f, _ in items)
    x = np.zeros((len(items), n, online.FEATURES), np.float32)
    for i, (f, _) in enumerate(items):
        x[i, :len(f)] = f
    targets = [encode(t) for _, t in items]
    return (torch.from_numpy(x), torch.tensor([online.frames(len(f)) for f, _ in items]),
            torch.tensor([i for t in targets for i in t]), torch.tensor([len(t) for t in targets]),
            [t for _, t in items])


class Lines(IterableDataset):
    def __init__(self, fonts, batch, seed, real=None, real_share=0.0):
        self.fonts, self.batch, self.seed = fonts, batch, seed
        self.real, self.real_share = real or [], real_share

    def __iter__(self):
        info = torch.utils.data.get_worker_info()
        rng = np.random.default_rng([self.seed, info.id if info else 0])
        pool = synth.FontPool(self.fonts)
        while True:
            items = []
            while len(items) < self.batch:
                it = item(rng, pool, real=self.real, real_share=self.real_share)
                if it is not None:
                    items.append(it)
            yield collate(items)


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


def edit_distance(a, b):
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def evaluate(model, batches, device):
    model.eval()
    errors = chars = 0
    with torch.no_grad():
        for x, lengths, _, _, truth in batches:
            logits = model(x.to(device))
            for t, g in zip(truth, greedy(logits, lengths)):
                errors += edit_distance(t, g)
                chars += len(t)
    model.train()
    return errors / max(chars, 1)


def fixed(rng, make, n):
    items = []
    while len(items) < n:
        it = make(rng)
        if it is not None:
            items.append(it)
    return [collate(items[i:i + 50]) for i in range(0, n, 50)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--steps", type=int, default=60_000)
    ap.add_argument("--batch", type=int, default=64)
    ap.add_argument("--workers", type=int, default=16)
    ap.add_argument("--lr", type=float, default=1e-3)
    ap.add_argument("--warmup", type=int, default=1000)
    ap.add_argument("--eval-every", type=int, default=2000)
    ap.add_argument("--resume", type=str, default=None)
    ap.add_argument("--real", type=str, default=None)
    ap.add_argument("--real-share", type=float, default=0.25)
    ap.add_argument("--out", type=str, default=str(RUNS / ("online-" + datetime.datetime.now().strftime("%Y%m%d-%H%M"))))
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    log = open(out / "log.txt", "a", encoding="utf-8")

    def say(msg):
        line = f"{time.strftime('%H:%M:%S')} {msg}"
        print(line, flush=True)
        log.write(line + "\n")
        log.flush()

    device = "cuda" if torch.cuda.is_available() else "cpu"
    train_fonts, val_fonts = synth.split_fonts()
    rng = np.random.default_rng(12345)
    val_pool = synth.FontPool(val_fonts)
    val_kin = fixed(rng, lambda r: item(r, val_pool, trail_share=0.0), 2000)
    val_trail = fixed(rng, lambda r: item(r, val_pool, trail_share=1.0), 1000)
    say(f"device {device}; validation {sum(len(b[4]) for b in val_kin)} kinematic + {sum(len(b[4]) for b in val_trail)} trail lines")
    real_train, real_val = real_lines.load(args.real) if args.real else ([], [])
    val_real = [collate([(online.features([s.tolist() for s in st]), t) for t, st in real_val])] if real_val else []

    model = online.OnlineNet(NUM_CLASSES).to(device)
    if args.resume:
        model.load_state_dict(torch.load(args.resume, map_location=device))
        say(f"weights from {args.resume}")
    opt = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=1e-4)
    ctc = nn.CTCLoss(blank=0, zero_infinity=True)

    def lr_at(step):
        if step < args.warmup:
            return args.lr * (step + 1) / args.warmup
        t = (step - args.warmup) / max(1, args.steps - args.warmup)
        return args.lr * (0.01 + 0.99 * 0.5 * (1 + math.cos(math.pi * t)))

    loader = DataLoader(Lines(train_fonts, args.batch, 11, real_train, args.real_share), batch_size=None, num_workers=args.workers,
                        persistent_workers=True, prefetch_factor=4)
    best = math.inf
    started = time.time()
    for step, (x, lengths, targets, target_lengths, _) in enumerate(loader):
        if step >= args.steps:
            break
        for g in opt.param_groups:
            g["lr"] = lr_at(step)
        logits = model(x.to(device))
        lp = logits.log_softmax(-1).transpose(0, 1)
        loss = ctc(lp, targets, lengths, target_lengths)
        opt.zero_grad()
        loss.backward()
        nn.utils.clip_grad_norm_(model.parameters(), 5.0)
        opt.step()
        if step % 200 == 0:
            say(f"step {step} loss {loss.item():.3f} lr {lr_at(step):.2e} {step / max(time.time() - started, 1e-6):.1f} it/s")
        if step and step % args.eval_every == 0:
            kin = evaluate(model, val_kin, device)
            tr = evaluate(model, val_trail, device)
            score = kin + tr
            if val_real:
                real_cer = evaluate(model, val_real, device)
                score = real_cer
                say(f"   real held-out CER {real_cer:.4f}")
            if score < best:
                best = score
                torch.save(model.state_dict(), out / "best.pt")
                online.write(model.cpu(), out / "hwonline.bin")
                model.to(device)
            say(f"eval step {step}: CER kinematic {kin:.4f}, trails {tr:.4f} (best sum {best:.4f})")
            torch.save(model.state_dict(), out / "last.pt")
    say("done")


if __name__ == "__main__":
    main()
