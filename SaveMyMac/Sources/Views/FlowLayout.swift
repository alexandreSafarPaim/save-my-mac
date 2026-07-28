import SwiftUI

/// Layout que coloca os filhos em linha e **passa para a linha de baixo** quando
/// não cabem — o equivalente ao `flex-wrap: wrap` do CSS, que o design usa em
/// várias barras de ação.
///
/// Sem isso, um `HStack` comprime os filhos até o texto truncar ("Limp ar…").
/// Aqui cada filho recebe o tamanho ideal dele e a quebra acontece no espaço
/// entre eles, onde deveria.
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

        // Largura inválida (0, negativa, NaN ou infinita) vinda de uma proposta
        // intermediária do SwiftUI faria a quebra de linha se comportar de
        // forma imprevisível. Trata como "cabe tudo numa linha".
        let limit = (maxWidth.isFinite && maxWidth > 1) ? maxWidth : .greatestFiniteMagnitude

        for index in subviews.indices {
            // `.unspecified` dá a cada filho o tamanho ideal dele, sem compressão.
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

        // `min` com uma proposta infinita devolveria infinito; o SwiftUI então
        // proporia outra largura e poderia oscilar. Devolver sempre finito.
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
