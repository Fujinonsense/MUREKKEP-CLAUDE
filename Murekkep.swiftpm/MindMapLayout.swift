import Foundation

/// Where each node of a mind map goes: a tidy tree from left to right. Every depth is a column as wide
/// as its widest node; children stack downwards with a gap and their parent sits at the middle of
/// them; a folded node hides its subtree.
enum MindMapLayout {
    struct Placed {
        var id: UUID
        var title: String
        var frame: CGRect
        var depth: Int
        var parent: UUID?
        var hasChildren: Bool
        var folded: Bool
    }

    static func layout(_ root: MindNode, collapsed: Set<UUID>, size: (MindNode, Int) -> CGSize,
                       columnGap: CGFloat, rowGap: CGFloat) -> [Placed] {
        // Column widths.
        var widths: [CGFloat] = []
        func measure(_ node: MindNode, _ depth: Int) {
            if widths.count <= depth { widths.append(0) }
            widths[depth] = max(widths[depth], size(node, depth).width)
            guard !collapsed.contains(node.id) else { return }
            for c in node.children { measure(c, depth + 1) }
        }
        measure(root, 0)
        var xs: [CGFloat] = []
        var x: CGFloat = 0
        for w in widths {
            xs.append(x)
            x += w + columnGap
        }

        var out: [Placed] = []
        /// Places a subtree from `top`; returns its height and the node's centre.
        @discardableResult
        func place(_ node: MindNode, _ depth: Int, _ parent: UUID?, top: CGFloat) -> (height: CGFloat, center: CGFloat) {
            let s = size(node, depth)
            let folded = collapsed.contains(node.id)
            let index = out.count
            out.append(Placed(id: node.id, title: node.title, frame: .zero, depth: depth, parent: parent,
                              hasChildren: !node.children.isEmpty, folded: folded))
            guard !folded, !node.children.isEmpty else {
                out[index].frame = CGRect(x: xs[depth], y: top, width: s.width, height: s.height)
                return (s.height, top + s.height / 2)
            }
            var y = top
            var first: CGFloat = 0
            var last: CGFloat = 0
            for (i, c) in node.children.enumerated() {
                let r = place(c, depth + 1, node.id, top: y)
                if i == 0 { first = r.center }
                last = r.center
                y += r.height + rowGap
            }
            let childrenHeight = y - rowGap - top
            var center = (first + last) / 2
            var height = childrenHeight
            if s.height > childrenHeight {
                // A tall node with short children: the children move down to its middle.
                let shift = (s.height - childrenHeight) / 2
                for i in (index + 1)..<out.count {
                    out[i].frame.origin.y += shift
                }
                center += shift
                height = s.height
            }
            out[index].frame = CGRect(x: xs[depth], y: center - s.height / 2, width: s.width, height: s.height)
            return (height, center)
        }
        place(root, 0, nil, top: 0)
        return out
    }
}
