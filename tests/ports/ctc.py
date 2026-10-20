"""Port of CTC in HandwritingModel.swift: beam search over the model's per-column log-probabilities,
the probability of a given text, and where the best path writes each character. Class 0 is the blank;
class i is charset[i - 1]."""
import math

NEG = -math.inf
TOP = 12  # characters tried per frame


def lse(*xs):
    m = max(xs)
    if m == NEG:
        return NEG
    return m + math.log(sum(math.exp(x - m) for x in xs))


def beam(lp, charset, width=8):
    """[(text, log probability)] best first (prefix beam search)."""
    t_len, classes = lp.shape
    beams = {(): (0.0, NEG)}  # prefix → (log P ending in blank, log P ending in its last character)
    for t in range(t_len):
        row = lp[t]
        tops = sorted(range(1, classes), key=lambda k: -row[k])[:TOP]
        nxt = {}

        def add(prefix, pb=NEG, pnb=NEG):
            ob, onb = nxt.get(prefix, (NEG, NEG))
            nxt[prefix] = (lse(ob, pb), lse(onb, pnb))

        for prefix, (pb, pnb) in beams.items():
            add(prefix, pb=lse(pb, pnb) + row[0])
            for k in tops:
                p = row[k]
                if prefix and prefix[-1] == k:
                    add(prefix + (k,), pnb=pb + p)  # a repeat needs a blank in between
                    add(prefix, pnb=pnb + p)  # the same character held over more frames
                else:
                    add(prefix + (k,), pnb=lse(pb, pnb) + p)
        beams = dict(sorted(nxt.items(), key=lambda kv: -lse(*kv[1]))[:width])
    out = [("".join(charset[k - 1] for k in prefix), lse(*v)) for prefix, v in beams.items()]
    return sorted(out, key=lambda kv: -kv[1])


def score(text, lp, charset):
    """log P(text) summed over all paths (forward algorithm), or None when a character is not in
    the charset."""
    if any(c not in charset for c in text):
        return None
    labels = [0]
    for c in text:
        labels += [charset.index(c) + 1, 0]
    s_len = len(labels)
    alpha = [NEG] * s_len
    alpha[0] = lp[0, labels[0]]
    if s_len > 1:
        alpha[1] = lp[0, labels[1]]
    for t in range(1, lp.shape[0]):
        new = [NEG] * s_len
        for s in range(s_len):
            terms = [alpha[s]]
            if s >= 1:
                terms.append(alpha[s - 1])
            if s >= 2 and labels[s] != 0 and labels[s] != labels[s - 2]:
                terms.append(alpha[s - 2])
            new[s] = lse(*terms) + lp[t, labels[s]]
        alpha = new
    return lse(alpha[-1], alpha[-2]) if s_len > 1 else alpha[-1]


def alignment(lp):
    """Frame of each character the greedy path writes."""
    frames, prev = [], 0
    for t in range(lp.shape[0]):
        k = int(lp[t].argmax())
        if k != prev and k != 0:
            frames.append(t)
        prev = k
    return frames
