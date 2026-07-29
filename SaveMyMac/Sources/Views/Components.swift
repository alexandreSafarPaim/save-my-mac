import SwiftUI
import AppKit

// MARK: - Window background: grid + radial glows

/// Reproduces the design's three background layers: a 56px grid, an accent glow
/// at the top left and a cyan glow at the bottom right.
struct AtmosphereBackground: View {
    var palette: Palette

    // No `drawingGroup`, on purpose. It rasterises through Metal and, in a view
    // with `ignoresSafeArea` (unbounded proposed size), that becomes a huge
    // texture allocation. The gain doesn't justify the risk — the real cost
    // already dropped when the runtime `blur` and the continuous animations went
    // away.
    var body: some View {
        if SafeMode.isOn {
            palette.bg2.ignoresSafeArea()
        } else {
            decorated
        }
    }

    private var decorated: some View {
        ZStack {
            palette.bg2

            GridPattern(spacing: 56, color: palette.grid)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [palette.accent.opacity(0.55), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 260
                    )
                )
                .frame(width: 520, height: 420)
                .opacity(0.22)
                .offset(x: -120, y: -320)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [palette.cyan.opacity(0.5), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 280
                    )
                )
                .frame(width: 560, height: 460)
                .opacity(0.14)
                .offset(x: 300, y: 340)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct GridPattern: View {
    var spacing: CGFloat
    var color: Color

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }
            context.stroke(path, with: .color(color), lineWidth: 1)
        }
    }
}

// MARK: - Card

/// Translucent card with a thin border — the design's basic visual unit.
struct Panel<Content: View>: View {
    var palette: Palette
    var cornerRadius: CGFloat = 20
    var padding: CGFloat = 20
    var emphasized: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            // A single layer. There used to be an `.ultraThinMaterial` under
            // every card; with dozens of cards on screen the compositing cost
            // doesn't pay for itself — over a dark background the visual
            // difference is minimal.
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(palette.card2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(emphasized ? palette.stroke2 : palette.stroke, lineWidth: 1)
            )
    }
}

/// Card with the accent gradient behind it — used in the Dashboard's hero.
struct HeroPanel<Content: View>: View {
    var palette: Palette
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    LinearGradient(
                        colors: [palette.accent.opacity(0.16), palette.cyan.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    RadialGradient(
                        colors: [palette.accent.opacity(0.25), .clear],
                        center: UnitPoint(x: 0.2, y: 0.2),
                        startRadius: 0,
                        endRadius: 340
                    )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(palette.stroke2, lineWidth: 1)
            )
    }
}

// MARK: - Labels

/// "SYSTEM DASHBOARD" — mono, cyan, uppercase, widely tracked.
struct Eyebrow: View {
    var text: String
    var palette: Palette
    var color: Color? = nil

    var body: some View {
        Text(text.uppercased())
            .font(Typo.eyebrow)
            .tracking(Track.eyebrow)
            .foregroundStyle(color ?? palette.cyan)
    }
}

/// Grey section label used in the sidebar and in cards.
struct MicroLabel: View {
    var text: String
    var palette: Palette

    var body: some View {
        Text(text.uppercased())
            .font(Typo.eyebrowSmall)
            .tracking(Track.label)
            .foregroundStyle(palette.t3)
    }
}

/// Screen header: eyebrow + title + optional subtitle.
struct ScreenHeader<Trailing: View>: View {
    var eyebrow: String
    var title: String
    var subtitle: String? = nil
    var palette: Palette
    var large: Bool = false
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: eyebrow, palette: palette, color: nil)
                Text(title)
                    .font(large ? Typo.screenTitleLarge : Typo.screenTitle)
                    .tracking(-0.7)
                    .foregroundStyle(palette.t1)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(Typo.body)
                        .foregroundStyle(palette.t2)
                }
            }
            Spacer(minLength: 12)
            trailing()
        }
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(eyebrow: String, title: String, subtitle: String? = nil, palette: Palette, large: Bool = false) {
        self.init(
            eyebrow: eyebrow,
            title: title,
            subtitle: subtitle,
            palette: palette,
            large: large,
            trailing: { EmptyView() }
        )
    }
}

// MARK: - Gradient progress ring

struct GradientRing: View {
    var value: Double            // 0...1
    var palette: Palette
    var lineWidth: CGFloat = 9
    var tint: LinearGradient? = nil

    var body: some View {
        ZStack {
            Circle()
                .stroke(palette.stroke2, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, value)))
                .stroke(
                    tint ?? palette.gradient,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(Motion.ring, value: value)
        }
    }
}

/// The large health-score ring.
///
/// The continuous float was removed: a `repeatForever` animation keeps SwiftUI
/// redrawing at 60 fps forever, and in an app that stays open all day that is a
/// permanent cost for a detail nobody notices. The ring already animates when the
/// value changes, which is when movement means something.
struct ScoreRing: View {
    var score: Int
    var palette: Palette
    var caption: String = L("Health").uppercased()

    var body: some View {
        ZStack {
            GradientRing(value: Double(score) / 100.0, palette: palette, lineWidth: 9)
            VStack(spacing: 5) {
                Text("\(score)")
                    .font(Typo.scoreValue)
                    .foregroundStyle(palette.t1)
                    .contentTransition(.numericText())
                MicroLabel(text: caption, palette: palette)
            }
        }
    }
}

// MARK: - Barras

/// Barra fina com gradiente, crescendo da esquerda.
struct GradientBar: View {
    var value: Double            // 0...1
    var palette: Palette
    var height: CGFloat = 5
    var tint: LinearGradient? = nil
    var glow: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.bg)
                Capsule()
                    .fill(tint ?? palette.gradientHorizontal)
                    .frame(width: max(0, geo.size.width * min(1, max(0, value))))
                    .shadow(color: glow ? palette.accent.opacity(0.7) : .clear, radius: 10)
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(palette.stroke, lineWidth: 1))
    }
}

/// Barra de progresso indeterminada com a faixa varrendo (`smScan`).
struct ScanBar: View {
    var palette: Palette
    @State private var offset: CGFloat = -0.35

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.bg)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.clear, palette.cyan, palette.accent, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * 0.32)
                    .offset(x: offset * geo.size.width)
            }
            .animation(Motion.scan, value: offset)
            .onAppear { offset = 1.05 }
        }
        .frame(height: 5)
        .clipShape(Capsule())
    }
}

// MARK: - Pressure chart

/// The last few minutes as a curve. Shape only — the scale is always 0…1,
/// because memory pressure is a fraction and rescaling would hide exactly what
/// matters (how far it is from the top).
struct PressureChart: View {
    var values: [Double]
    var palette: Palette
    var height: CGFloat = 46

    private var tint: Color {
        let peak = values.max() ?? 0
        if peak < 0.35 { return palette.ok }
        if peak < 0.60 { return palette.warn }
        return palette.danger
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // reference bands: 35% and 60%, the same cutoffs as the label
                ForEach([0.35, 0.60], id: \.self) { level in
                    Path { path in
                        let y = geo.size.height * (1 - level)
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(palette.stroke, style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                }

                if values.count > 1 {
                    Curve(values: values, closed: true)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.30), tint.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    Curve(values: values, closed: false)
                        .stroke(tint, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private struct Curve: Shape {
        var values: [Double]
        var closed: Bool

        func path(in rect: CGRect) -> Path {
            var path = Path()
            guard values.count > 1 else { return path }

            let step = rect.width / CGFloat(values.count - 1)
            for (index, value) in values.enumerated() {
                let x = rect.minX + step * CGFloat(index)
                let y = rect.maxY - rect.height * CGFloat(value.clamped(0, 1))
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            if closed {
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.closeSubpath()
            }
            return path
        }
    }
}

// MARK: - Label/value row

struct StatRow: View {
    var key: String
    var value: String
    var palette: Palette
    var valueColor: Color? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key)
                .font(Typo.bodySmall)
                .foregroundStyle(palette.t2)
            Spacer(minLength: 10)
            Text(value)
                .font(Typo.monoCaption)
                .foregroundStyle(valueColor ?? palette.t1)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Metric card

struct MetricCard: View {
    var label: String
    var tag: String
    var value: String
    var unit: String
    var fraction: Double
    var rows: [(String, String)]
    var palette: Palette
    var tint: Color? = nil

    var body: some View {
        Panel(palette: palette, cornerRadius: 18, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    MicroLabel(text: label, palette: palette)
                    Spacer()
                    Text(tag)
                        .font(Typo.monoCaption)
                        .foregroundStyle(palette.t2)
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value)
                        .font(Typo.metricValue)
                        .tracking(-1.1)
                        .foregroundStyle(tint ?? palette.t1)
                    Text(unit)
                        .font(Typo.mono(14))
                        .foregroundStyle(palette.t3)
                }

                GradientBar(value: fraction, palette: palette)

                VStack(alignment: .leading, spacing: 5) {
                    ForEach(rows.indices, id: \.self) { index in
                        StatRow(key: rows[index].0, value: rows[index].1, palette: palette)
                    }
                }
            }
        }
    }
}

// MARK: - Risk pill

struct RiskPill: View {
    var text: String
    var score: Int
    var palette: Palette

    var body: some View {
        Text(text.uppercased())
            .font(Typo.monoTiny)
            .tracking(0.8)
            .padding(.horizontal, 8)
            .padding(.vertical, 2.5)
            .overlay(
                Capsule().strokeBorder(palette.riskTint(score), lineWidth: 1)
            )
            .foregroundStyle(palette.riskTint(score))
    }
}

/// Medidor "RISCO n/10" com barra fina.
struct RiskMeter: View {
    var score: Int
    var palette: Palette

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Text(L("RISK %d/10", score))
                .font(Typo.monoTiny)
                .foregroundStyle(palette.t3)
            GradientBar(
                value: Double(score) / 10.0,
                palette: palette,
                height: 4,
                tint: LinearGradient(
                    colors: [palette.riskTint(score), palette.riskTint(score)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
        .frame(width: 110)
    }
}

// MARK: - Generic tag

struct Chip: View {
    var text: String
    var palette: Palette
    var color: Color? = nil
    var mono: Bool = true

    var body: some View {
        Text(text)
            .font(mono ? Typo.monoTiny : Typo.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill((color ?? palette.accent).opacity(0.18))
            )
            .overlay(
                Capsule().strokeBorder((color ?? palette.accent).opacity(0.45), lineWidth: 1)
            )
            .foregroundStyle(color ?? palette.t1)
    }
}

/// Chip de caminho usado na tela de duplicados.
struct PathChip: View {
    var text: String
    var palette: Palette

    var body: some View {
        Text(text)
            .font(Typo.monoCaption)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(palette.bg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(palette.stroke, lineWidth: 1)
            )
            .foregroundStyle(palette.t2)
    }
}

// MARK: - Checkbox com gradiente

struct GradientCheckbox: View {
    /// true = tudo, false = nada, nil = parcial
    var state: Bool?
    var palette: Palette
    var size: CGFloat = 22
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(palette.bg)
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(palette.stroke2, lineWidth: 1)

                if state != false {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(palette.gradient)
                        .padding(1)
                        .shadow(color: palette.accent.opacity(0.6), radius: 7)
                        .overlay {
                            if state == true {
                                Image(systemName: "checkmark")
                                    .font(.system(size: size * 0.52, weight: .heavy))
                                    .foregroundStyle(.white)
                            } else {
                                Image(systemName: "minus")
                                    .font(.system(size: size * 0.52, weight: .heavy))
                                    .foregroundStyle(.white)
                            }
                        }
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Buttons

/// Primary button with the accent gradient.
struct PrimaryButton: View {
    var title: String
    var systemImage: String? = nil
    var suffix: String? = nil
    var palette: Palette
    var height: CGFloat = 40
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .font(Typo.ui(13.5, .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if let suffix {
                    Text(suffix)
                        .font(Typo.monoCaption)
                        .opacity(0.85)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(palette.gradientHorizontal)
            )
            .shadow(color: palette.accent.opacity(0.45), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
    }
}

/// Secondary button: card background, thin border.
struct GhostButton: View {
    var title: String
    var systemImage: String? = nil
    var palette: Palette
    var height: CGFloat = 38
    var tint: Color? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .font(Typo.ui(13, .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(tint ?? palette.t1)
            .padding(.horizontal, 16)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill((tint ?? palette.t1).opacity(tint == nil ? 0 : 0.10))
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(palette.card2)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(tint?.opacity(0.4) ?? palette.stroke2, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Ponto "ao vivo"

/// The "live" dot.
///
/// Static on purpose. The pulsing version used `repeatForever`, which forces
/// SwiftUI to redraw continuously — and since this dot lives on the Dashboard,
/// which is the default screen, the cost was permanent. The text beside it
/// already says the refresh is every 2 s.
struct LiveDot: View {
    var palette: Palette
    var color: Color? = nil

    var body: some View {
        Circle()
            .fill(color ?? palette.ok)
            .frame(width: 6, height: 6)
    }
}

// MARK: - Estado vazio

struct EmptyStateView: View {
    var symbol: String
    var title: String
    var message: String
    var palette: Palette
    var hint: String? = nil

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 44))
                .foregroundStyle(palette.t3)
            Text(title)
                .font(Typo.ui(17, .medium))
                .foregroundStyle(palette.t1)
            Text(message)
                .font(Typo.body)
                .foregroundStyle(palette.t2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let hint {
                Text(hint)
                    .font(Typo.caption)
                    .foregroundStyle(palette.t3)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Banner de varredura

struct ScanningBanner: View {
    var status: String
    var progress: Double
    var palette: Palette
    var indeterminate: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(status)
                    .font(Typo.monoCaption)
                    .foregroundStyle(palette.t1)
                    .lineLimit(1)
                Spacer()
                Text(indeterminate ? "analisando" : Fmt.percent(progress))
                    .font(Typo.monoCaption)
                    .foregroundStyle(palette.cyan)
            }
            if indeterminate {
                ScanBar(palette: palette)
            } else {
                GradientBar(value: progress, palette: palette, glow: true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [palette.cyan.opacity(0.10), palette.accent.opacity(0.06)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(palette.cyan.opacity(0.35), lineWidth: 1)
        )
    }
}

// MARK: - Tiled icon

/// Quadrado arredondado com um SF Symbol dentro — substitui os emojis do mockup.
struct IconTile: View {
    var symbol: String
    var palette: Palette
    var size: CGFloat = 38
    var gradient: Bool = false
    var tint: Color? = nil

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .fill(gradient ? AnyShapeStyle(palette.gradient) : AnyShapeStyle(palette.card2))
            if !gradient {
                RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                    .strokeBorder(palette.stroke, lineWidth: 1)
            }
            Image(systemName: symbol)
                .font(.system(size: size * 0.44, weight: .medium))
                .foregroundStyle(gradient ? Color.white : (tint ?? palette.t1))
        }
        .frame(width: size, height: size)
    }
}

/// An app's real icon, read from the bundle.
struct AppIconView: View {
    var path: String
    var size: CGFloat = 42

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .frame(width: size, height: size)
    }
}

// MARK: - Sticky action bar

/// Opens the Settings window, with whatever label you want.
///
/// It exists so the decision of *how* to open Settings lives in one place, and
/// the label is all a caller provides — which is what keeps the menu bar panel's
/// Settings row identical to its neighbours.
///
/// An action, **not** a `SettingsLink`.
///
/// `SettingsLink` works from a window and **does not work from a
/// `MenuBarExtra`**: the menu bar popover doesn't leave the app active, and
/// opening Settings without the app active doesn't bring a window forward. From
/// the user's side it looked like the click did nothing — you had to open the
/// main window first for Settings to work.
///
/// `openSettings` is the same capability in the form of an action, and being an
/// action means we can **activate the app before calling it**, which was the
/// missing step.
struct SettingsOpener<Label: View>: View {
    @ViewBuilder var label: () -> Label

    var body: some View {
        // `@Environment(\.openSettings)` only exists on macOS 14. Declaring the
        // property here would break the build for the 13 target, even inside an
        // `if #available` — property availability is checked at the declaration,
        // not at the use. So it lives in an `@available` type that is only
        // mentioned inside the test.
        if #available(macOS 14.0, *) {
            ModernSettingsOpener(label: label)
        } else {
            Button(action: openLegacy, label: label)
        }
    }

    /// macOS 13: tries both selectors, **without** checking `responds(to:)`.
    /// `sendAction` already walks the responder chain and reports whether anyone
    /// handled it; the check only served to discard the correct path, because the
    /// selector belongs to SwiftUI's internal delegate and not to ours.
    private func openLegacy() {
        NSApp.activate(ignoringOtherApps: true)
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}

@available(macOS 14.0, *)
private struct ModernSettingsOpener<Label: View>: View {
    @Environment(\.openSettings) private var openSettings
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button {
            // Order matters: activating after opening leaves the window behind
            // the others in some situations.
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        } label: {
            label()
        }
    }
}

struct StickyActionBar<Content: View>: View {
    var palette: Palette
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(palette.card2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(palette.stroke2, lineWidth: 1)
            )
            .shadow(color: palette.shadow, radius: 30, y: 14)
    }
}

// MARK: - Permission notice

/// Shown when a scan was blocked by Full Disk Access rather than finding nothing.
///
/// This exists because the two states looked identical. A blocked scan finished in
/// under a second, found zero files, and the screen showed the same "Nothing
/// scanned yet" message a genuinely tidy Mac would show. The user clicked
/// "Analyze", waited, and got no result and no reason.
///
/// The fix is not a friendlier empty state — it is telling the truth: the scan
/// could not read N folders, here are some of them, and here is the button that
/// fixes it.
struct PermissionNotice: View {
    var palette: Palette
    var deniedCount: Int
    var examples: [String]
    var grant: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(palette.warn)
                Text(L("The scan was blocked"))
                    .font(Typo.cardTitle)
                    .foregroundStyle(palette.t1)
            }

            Text(L("%d folder(s) could not be read, including %@.",
                   deniedCount,
                   examples.prefix(4).joined(separator: ", ")))
                .font(Typo.bodySmall)
                .foregroundStyle(palette.t2)
                .fixedSize(horizontal: false, vertical: true)

            Text(L("Without Full Disk Access, macOS blocks Desktop, Documents, Downloads, Movies, Music and Pictures — which is exactly where large files live. The numbers below are not wrong, they are incomplete."))
                .font(Typo.monoTiny)
                .foregroundStyle(palette.t3)
                .fixedSize(horizontal: false, vertical: true)

            GhostButton(
                title: L("Grant Full Disk Access"),
                systemImage: "lock.shield",
                palette: palette,
                tint: palette.cyan,
                action: grant
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.warn.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.warn.opacity(0.38), lineWidth: 1)
        )
    }
}
