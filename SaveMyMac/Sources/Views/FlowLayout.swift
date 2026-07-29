import SwiftUI

/// A layout that places children in a row and **wraps to the next line** when
/// they don't fit — the equivalent of CSS `flex-wrap: wrap`, which the design
/// uses in several action bars.
///
/// Without it, an `HStack` compresses the children until the text truncates
/// ("Clea n…"). Here each child gets its ideal size and the break happens in the
/// space between them, where it should.
struct FlowLayout: Layout {

    var spacing: CGFloat = 10
    var lineSpacing: CGFloat = 10

    private struct Row {
        var indices: [Int] = []
        var sizes: [CGSize] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var result: [Row] = []
        var current = Row()

        // An invalid width (0, negative, NaN or infinite) coming from an
        // intermediate SwiftUI proposal would make line breaking behave
        // unpredictably. Treat it as "everything fits on one line".
        let limit = (maxWidth.isFinite && maxWidth > 1) ? maxWidth : .greatestFiniteMagnitude

        for index in subviews.indices {
            // `.unspecified` gives each child its ideal size, with no compression.
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width

            if !current.indices.isEmpty && needed > limit {
                result.append(current)
                current = Row()
                current.indices = [index]
                current.sizes = [size]
                current.width = size.width
                current.height = size.height
            } else {
                current.indices.append(index)
                current.sizes.append(size)
                current.width = needed
                current.height = max(current.height, size.height)
            }
        }

        if !current.indices.isEmpty { result.append(current) }
        return result
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        let lines = rows(maxWidth: maxWidth, subviews: subviews)

        let width = lines.map(\.width).max() ?? 0
        let height = lines.map(\.height).reduce(0, +)
            + lineSpacing * CGFloat(max(0, lines.count - 1))

        // `min` against an infinite proposal would return infinity; SwiftUI
        // would then propose another width and could oscillate. Always return
        // something finite.
        let resolved = maxWidth.isFinite ? Swift.min(width, maxWidth) : width
        return CGSize(width: resolved.isFinite ? resolved : 0, height: height.isFinite ? height : 0)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let lines = rows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY

        for line in lines {
            var x = bounds.minX
            for (offset, index) in line.indices.enumerated() {
                let size = line.sizes[offset]
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (line.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }
}
