import SwiftUI
import AppKit

// MARK: - Fundo da janela: grade + halos radiais

/// Reproduz as três camadas de fundo do design: grade de 56px, halo de acento
/// no topo à esquerda e halo ciano embaixo à direita.
struct AtmosphereBackground: View {
    var palette: Palette

    // Sem `drawingGroup` de propósito. Ele rasteriza via Metal e, numa view
    // com `ignoresSafeArea` (tamanho proposto sem limite), isso vira alocação
    // de textura gigante. O ganho não compensa o risco — o custo real já caiu
    // ao remover o `blur` em runtime e as animações contínuas.
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

/// Card translúcido com borda fina — a unidade visual básica do design.
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
            // Uma camada só. Antes havia um `.ultraThinMaterial` por baixo de
            // cada card; com dezenas de cards na tela, o custo de composição
            // não se paga — sobre fundo escuro a diferença visual é mínima.
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

/// Card com o gradiente de acento no fundo — usado no hero do Painel.
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

// MARK: - Rótulos

/// "PAINEL DO SISTEMA" — mono, ciano, maiúsculas, muito espaçado.
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

/// Rótulo cinza de seção na sidebar e nos cards.
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

/// Cabeçalho de tela: eyebrow + título + subtítulo opcional.
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

// MARK: - Anel de progresso com gradiente

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

/// Anel grande do score de saúde.
///
/// A flutuação contínua foi removida: uma animação `repeatForever` mantém o
/// SwiftUI redesenhando a 60 fps para sempre, e num app que fica aberto o dia
/// todo isso é custo permanente por um detalhe que ninguém nota. O anel já
/// anima quando o valor muda, que é quando o movimento significa algo.
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

// MARK: - Gráfico de pressão

/// Curva dos últimos minutos. Só a forma — a escala é sempre 0…1, porque
/// pressão de memória é uma fração e reescalar esconderia justamente o que
/// interessa (a distância até o topo).
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
                // faixas de referência: 35 % e 60 %, os mesmos cortes do rótulo
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

// MARK: - Linha rótulo/valor

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

// MARK: - Card de métrica

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

// MARK: - Pílula de risco

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

// MARK: - Etiqueta genérica

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

// MARK: - Botões

/// Botão principal com o gradiente de acento.
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

/// Botão secundário: fundo do card, borda fina.
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

/// Ponto "ao vivo".
///
/// Estático de propósito. A versão pulsante usava `repeatForever`, o que obriga
/// o SwiftUI a redesenhar continuamente — e como este ponto vive no Painel, que
/// é a tela padrão, o custo era permanente. O texto ao lado já diz que a
/// atualização é a cada 2 s.
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

// MARK: - Ícone em tile

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

/// Ícone real de um app, lido do bundle.
struct AppIconView: View {
    var path: String
    var size: CGFloat = 42

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .frame(width: size, height: size)
    }
}

// MARK: - Rodapé fixo de ação

/// Abre a janela de Ajustes, com o rótulo que você quiser.
///
/// Existe para a decisão de *como* abrir Ajustes ficar num lugar só. A primeira
/// tentativa mandava `showSettingsWindow:` pela cadeia de resposta e falhava em
/// silêncio: esse seletor pertence ao delegate interno do SwiftUI, e com
/// `NSApplicationDelegateAdaptor` o nosso delegate ocupa aquele lugar.
///
/// `SettingsLink` é a API oficial e não depende de adivinhar nome de seletor.
/// Vale do macOS 14 em diante; abaixo, tenta os dois seletores — sem checar
/// `responds(to:)`, que era justamente o que descartava o caminho certo.
///
/// Um detalhe que só aparece no uso: `SettingsLink` é um controle próprio, não
/// um `Button` com ação. Por isso este tipo recebe apenas o rótulo, e quem usa
/// aplica o `.buttonStyle` por fora — é o que mantém a linha do painel da barra
/// de menus idêntica às vizinhas.
/// Ação, não `SettingsLink`.
///
/// `SettingsLink` funciona numa janela e **não funciona a partir de um
/// `MenuBarExtra`**: o popover da barra de menus não deixa o app ativo, e abrir
/// Ajustes sem o app ativo não traz janela para a frente. Do lado do usuário
/// parecia que o clique não fazia nada — era preciso abrir a janela principal
/// primeiro para Ajustes funcionar.
///
/// `openSettings` é a mesma capacidade em forma de ação, e por ser ação dá para
/// **ativar o app antes de chamar**, que era o passo que faltava.
struct SettingsOpener<Label: View>: View {
    @ViewBuilder var label: () -> Label

    var body: some View {
        // `@Environment(\.openSettings)` só existe no macOS 14. Declarar a
        // propriedade aqui quebraria a compilação para o alvo 13, mesmo dentro
        // de um `if #available` — disponibilidade de propriedade é checada na
        // declaração, não no uso. Por isso ela mora num tipo `@available`, que só
        // é mencionado dentro do teste.
        if #available(macOS 14.0, *) {
            ModernSettingsOpener(label: label)
        } else {
            Button(action: openLegacy, label: label)
        }
    }

    /// macOS 13: tenta os dois seletores, **sem** checar `responds(to:)`.
    /// O `sendAction` já percorre a cadeia de resposta e informa se alguém
    /// tratou; a checagem só servia para descartar o caminho certo, porque o
    /// seletor pertence ao delegate interno do SwiftUI e não ao nosso.
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
            // A ordem importa: ativar depois de abrir deixa a janela atrás das
            // outras em algumas situações.
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
