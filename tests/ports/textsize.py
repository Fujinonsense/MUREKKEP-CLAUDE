"""Port of the text pen's size rules: HandwritingConverter.capHeight (Murekkep.swiftpm), the
hold-to-symbol size (CanvasView.textPenSymbolSize) and the late-mark size (EditorModel)."""


def cap_height(ruling_cap, spacing, scale):
    """The chosen size, but never taller than 72 % of the space between ruled lines."""
    return min(ruling_cap * scale, spacing * 0.72)


def symbol_size(pen_width):
    """A held text-pen stroke at least this big becomes a shape or picture; thick pens write big."""
    return max(28.0, 4 * pen_width)


def mark_size(pen_width):
    """A late stroke smaller than this is a dot or an accent of the word before."""
    return max(14.0, 3 * pen_width)
