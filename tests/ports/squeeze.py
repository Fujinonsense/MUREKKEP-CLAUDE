"""Port of the Apple Pencil Pro squeeze and the borrowed eraser (CanvasView squeeze handling,
finishErasing; EditorModel.beginTemporaryEraser / endTemporaryEraser / leaveEraser)."""

# A squeeze held at least this long is a hold: letting go gives the pen back even without erasing.
HOLD = 0.5


class Pencil:
    def __init__(self, tool="pen"):
        self.tool = tool
        self.previous = "eraser"
        self.eraser_return = None
        self.squeeze_held = False
        self.squeeze_start = 0.0
        self.erased_during_squeeze = False
        self.squeeze_took_eraser = False
        self.last_squeeze_end = -10.0
        self.erasing = False
        self.now = 0.0

    # EditorModel
    def select(self, tool):
        if tool != self.tool:
            self.previous = self.tool
            if tool != "eraser":
                self.eraser_return = None
            self.tool = tool

    def begin_temporary_eraser(self):
        if self.tool == "eraser":
            return
        back = self.tool
        self.select("eraser")
        self.eraser_return = back

    @property
    def is_temporary_eraser(self):
        return self.eraser_return is not None and self.tool == "eraser"

    def end_temporary_eraser(self):
        back = self.eraser_return
        if back is None:
            return
        self.eraser_return = None
        if self.tool == "eraser":
            self.select(back)

    def leave_eraser(self):
        if self.tool != "eraser":
            return
        if self.eraser_return is not None:
            self.end_temporary_eraser()
        else:
            self.select(self.previous if self.previous != "eraser" else "pen")

    # CanvasView
    @property
    def squeeze_is_held(self):
        return self.squeeze_held and self.now - self.squeeze_start < 20

    def start_squeeze(self, at):
        self.squeeze_held = True
        self.squeeze_start = at
        self.erased_during_squeeze = False
        if self.tool == "eraser":
            self.squeeze_took_eraser = False
            self.leave_eraser()
        else:
            self.squeeze_took_eraser = True
            self.begin_temporary_eraser()

    def end_squeeze(self, at):
        held_long = at - self.squeeze_start >= HOLD
        self.squeeze_held = False
        self.last_squeeze_end = at
        if (self.squeeze_took_eraser and (self.erased_during_squeeze or held_long) and not self.erasing
                and self.is_temporary_eraser):
            self.end_temporary_eraser()
        self.squeeze_took_eraser = False

    def squeeze(self, phase, at, handled=None):
        """`at` is the squeeze's own time (UIPencilInteraction.Squeeze.timestamp), which decides a
        click from a hold; `handled` is when the main thread got to it (later while it is busy)."""
        self.now = at if handled is None else handled
        if phase == "began":
            self.start_squeeze(at)
        elif phase == "changed":
            if not self.squeeze_is_held and at - self.last_squeeze_end > 0.3:
                self.start_squeeze(at)
        elif phase == "ended":
            if not self.squeeze_is_held:
                if not at - self.last_squeeze_end > 0.3:
                    return
                self.start_squeeze(at)
            self.end_squeeze(at)

    def erase_begin(self, at):
        self.now = at
        if self.tool != "eraser":
            return False
        if self.squeeze_is_held:
            self.erased_during_squeeze = True
        self.erasing = True
        return True

    def erase_end(self, at):
        self.now = at
        self.erasing = False
        if self.is_temporary_eraser and not self.squeeze_is_held:
            self.end_temporary_eraser()
