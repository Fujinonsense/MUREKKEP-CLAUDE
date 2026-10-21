"""Lecture recordings in sync with the ink (Notability's audio replay): while a take plays, the ink
written during it appears as the playhead passes the moment it was written, and tapping a line plays
from a little before it was written. Port: tests/ports/recording_sync.py, twin of
Murekkep.swiftpm/RecordingSync.swift. A stroke's birth is when the pencil lifted (seconds since the
reference date)."""
from ports.recording_sync import Recording, hidden, seek

TAKE = Recording(id="a", start=1000.0, duration=60.0)
OTHER = Recording(id="b", start=5000.0, duration=30.0)


def test_ink_from_before_the_take_always_shows():
    assert hidden([(1, 990.0)], TAKE, time=0.0) == set()


def test_ink_written_during_the_take_appears_with_the_playhead():
    births = [(1, 1005.0), (2, 1030.0)]
    assert hidden(births, TAKE, time=0.0) == {1, 2}
    assert hidden(births, TAKE, time=5.0) == {2}
    assert hidden(births, TAKE, time=40.0) == set()


def test_ink_from_after_the_take_always_shows():
    assert hidden([(1, 2000.0)], TAKE, time=0.0) == set()


def test_ink_lifted_just_after_stop_belongs_to_the_take():
    assert hidden([(1, 1060.4)], TAKE, time=59.0) == {1}


def test_tapping_a_line_plays_from_a_little_before_it():
    assert seek(1012.0, [TAKE, OTHER]) == ("a", 10.5)
    assert seek(5020.0, [TAKE, OTHER]) == ("b", 18.5)


def test_tapping_the_first_line_starts_at_zero():
    assert seek(1000.5, [TAKE]) == ("a", 0.0)


def test_ink_outside_every_take_does_not_seek():
    assert seek(3000.0, [TAKE, OTHER]) is None
