"""Port of RecordingSync (Murekkep.swiftpm/RecordingSync.swift): which ink a playing take hides, and
where tapping ink plays from.

A stroke belongs to a take when its pencil lifted between the take's start and a moment (GRACE) after
its end. While that take plays, the take's strokes whose moment is still ahead of the playhead are
hidden; everything else shows. Tapping a stroke of a take plays from LEAD_IN seconds before its moment
(the pencil lifts at the end of the line, and the words that went with it came a little before)."""
from dataclasses import dataclass

GRACE = 0.5
LEAD_IN = 1.5


@dataclass
class Recording:
    id: str
    start: float
    duration: float


def _contains(r, birth):
    return r.start <= birth <= r.start + r.duration + GRACE


def hidden(births, recording, time):
    """Ids of the strokes (id, birth) still ahead of `time` seconds into `recording`."""
    return {i for i, b in births if _contains(recording, b) and b - recording.start > time}


def seek(birth, recordings):
    """(take id, seconds into it) to play a stroke's moment from, or None."""
    for r in recordings:
        if _contains(r, birth):
            return r.id, max(0.0, min(birth - r.start, r.duration) - LEAD_IN)
    return None
