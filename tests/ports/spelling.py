"""Port of how Spelling.polish picks among Vision's readings of a line: another reading must score
clearly higher (by more than MARGIN) to replace the first. Scores are the share of known words, 0...1.
Each score costs dictionary lookups on the main thread."""

MARGIN = 0.15


def choose(scores):
    """(index of the chosen reading, how many readings were scored)."""
    best, best_score = 0, scores[0]
    scored = 1
    for i, s in enumerate(scores[1:], start=1):
        # No score passes 1: once the bar is there, no other reading can win.
        if best_score + MARGIN >= 1.0:
            break
        scored += 1
        if s > best_score + MARGIN:
            best, best_score = i, s
    return best, scored
