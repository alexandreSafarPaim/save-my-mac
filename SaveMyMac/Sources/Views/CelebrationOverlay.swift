import SwiftUI

/// Overlay de conclusão: ondas concêntricas, tamanho liberado, XP e conquistas
/// recém-desbloqueadas.
struct CelebrationOverlay: View {
    var celebration: AppState.Celebration
    var palette: Palette
    var dismiss: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()
                .background(.ultraThinMaterial)
                .onTapGesture { dismiss() }

            ExpandingRing(color: palette.cyan, delay: 0)
            ExpandingRing(color: palette.accent, delay: 0.5)

            VStack(spacing: 14) {
                BrandMark(size: 62, palette: palette, simplified: false)

                Eyebrow(text: celebration.title, palette: palette)

                Text(Fmt.bytes(celebration.bytes))
                    .font(Typo.mono(44, .bold))
                    .tracking(-1.4)
                    .foregroundStyle(palette.t1)

                HStack(spacing: 6) {
                    Text((celebration.wentToTrash ? L("moved to the Trash") : L("freed"))
                         + L(" · health %d · ", celebration.score))
                        .font(Typo.bodySmall)
                        .foregroundStyle(palette.t2)
                    Text("+\(celebration.xp) XP")
                        .font(Typo.ui(13, .semibold))
                        .foregroundStyle(palette.accent)
                }

                if celebration.wentToTrash {
                    Text(L("The space only comes back when you empty the Trash."))
                        .font(Typo.monoTiny)
                        .foregroundStyle(palette.t3)
                }

                if !celebration.unlocked.isEmpty {
                    VStack(spacing: 8) {
                        Divider().overlay(palette.stroke).frame(width: 200)
                        MicroLabel(
                            text: celebration.unlocked.count == 1 ? L("Achievement unlocked") : L("Achievements unlocked"),
                            palette: palette
                        )
                        HStack(spacing: 10) {
                            ForEach(celebration.unlocked) { achievement in
                                VStack(spacing: 4) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(palette.gradient)
                                        Image(systemName: achievement.symbol)
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundStyle(.white)
                                    }
                                    .frame(width: 44, height: 44)
                                    .shadow(color: palette.accent.opacity(0.6), radius: 10)

                                    Text(achievement.name)
                                        .font(Typo.monoTiny)
                                        .foregroundStyle(palette.t2)
                                        .frame(width: 84)
                                        .multilineTextAlignment(.center)
                                }
                            }
                        }
                    }
                }

                PrimaryButton(title: "Boa", palette: palette) { dismiss() }
                    .padding(.top, 6)
            }
            .padding(.horizontal, 46)
            .padding(.vertical, 34)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(palette.bg2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(palette.stroke2, lineWidth: 1)
            )
            .shadow(color: palette.shadow, radius: 40, y: 18)
            .scaleEffect(appeared ? 1 : 0.7)
            .opacity(appeared ? 1 : 0)
            .onAppear {
                withAnimation(Motion.pop) { appeared = true }
            }
        }
    }
}

/// Uma onda que cresce e desvanece, em loop (`smRing`).
struct ExpandingRing: View {
    var color: Color
    var delay: Double

    @State private var expanded = false

    var body: some View {
        Circle()
            .strokeBorder(color, lineWidth: 2)
            .frame(width: 260, height: 260)
            .scaleEffect(expanded ? 2.6 : 0.4)
            .opacity(expanded ? 0 : 0.9)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(Motion.expandingRing) { expanded = true }
                }
            }
            .allowsHitTesting(false)
    }
}
