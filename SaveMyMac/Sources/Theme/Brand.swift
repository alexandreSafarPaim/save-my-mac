import SwiftUI

/// O sparkle de 4 pontas da marca.
///
/// Mesma geometria do ícone e do design: pontas nos eixos, cintura na diagonal
/// a 30 % da distância da ponta. Desenhado como `Shape` para escalar sem perda
/// em qualquer tamanho.
struct Sparkle: Shape {
    var waistRatio: CGFloat = 0.30

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let tip = min(rect.width, rect.height) / 2
        let w = tip * waistRatio

        var path = Path()
        path.move(to: CGPoint(x: c.x, y: c.y - tip))
        path.addLine(to: CGPoint(x: c.x + w, y: c.y - w))
        path.addLine(to: CGPoint(x: c.x + tip, y: c.y))
        path.addLine(to: CGPoint(x: c.x + w, y: c.y + w))
        path.addLine(to: CGPoint(x: c.x, y: c.y + tip))
        path.addLine(to: CGPoint(x: c.x - w, y: c.y + w))
        path.addLine(to: CGPoint(x: c.x - tip, y: c.y))
        path.addLine(to: CGPoint(x: c.x - w, y: c.y - w))
        path.closeSubpath()
        return path
    }
}

/// A marca do app: quadrado com gradiente, anel de progresso a 78 % e o sparkle
/// no centro. É o mesmo desenho do `.icns`, gerado por `tools/make-icon.py`.
///
/// Abaixo de 40 pt o anel e o sparkle se encostam e viram um borrão, então
/// nesse tamanho fica só o sparkle — a mesma decisão tomada no iconset.
struct BrandMark: View {
    var size: CGFloat = 34
    var palette: Palette
    /// Força a arte simplificada independentemente do tamanho.
    var simplified: Bool?

    private var useSimple: Bool { simplified ?? (size < 40) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2245, style: .continuous)
                .fill(palette.gradient)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.2245, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [Color.white.opacity(0.16), .clear],
                                center: UnitPoint(x: 0.22, y: 0.18),
                                startRadius: 0,
                                endRadius: size * 0.85
                            )
                        )
                )

            if useSimple {
                Sparkle(waistRatio: 0.36)
                    .fill(Color.white)
                    .frame(width: size * 0.60, height: size * 0.60)
            } else {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.25), lineWidth: size * 0.068)
                    Circle()
                        .trim(from: 0, to: 0.78)
                        .stroke(
                            Color.white,
                            style: StrokeStyle(lineWidth: size * 0.068, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: size * 0.67, height: size * 0.67)

                Sparkle()
                    .fill(Color.white)
                    .frame(width: size * 0.41, height: size * 0.41)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: palette.accent.opacity(0.45), radius: size * 0.3)
    }
}

/// Marca + nome, para a sidebar.
struct BrandLockup: View {
    var palette: Palette
    var version: String = "v1.0"

    var body: some View {
        HStack(spacing: 11) {
            BrandMark(size: 34, palette: palette)

            VStack(alignment: .leading, spacing: 1) {
                Text("SaveMyMac")
                    .font(Typo.ui(15, .bold))
                    .tracking(-0.2)
                    .foregroundStyle(palette.t1)
                Text(version)
                    .font(Typo.monoTiny)
                    .tracking(1.2)
                    .foregroundStyle(palette.t3)
            }
        }
    }
}
