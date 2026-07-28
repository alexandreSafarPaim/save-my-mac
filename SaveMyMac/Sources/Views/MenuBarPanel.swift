import SwiftUI
import AppKit

/// O painel que abre ao clicar no ícone da barra de menus.
///
/// Ele não é uma cópia menor do Painel: mostra só o que se responde de relance
/// — espaço, pressão de memória, CPU e temperatura — e dá atalho para o resto.
struct MenuBarPanel: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: Preferences
    @EnvironmentObject var spaceAlert: SpaceAlert

    /// A forma correta de trazer a janela de volta no macOS 13. Um
    /// `NSApp.sendAction` de "nova janela" não recria a cena do WindowGroup.
    @Environment(\.openWindow) private var openWindow

    private var palette: Palette { state.palette }

    private var isLow: Bool {
        spaceAlert.isLow(volume: state.bootVolume, thresholdPercent: prefs.lowSpaceThreshold)
    }

    @ViewBuilder
    var body: some View {
        // Inerte quando o recurso está desligado: sem isto o painel continuaria
        // lendo o estado a cada atualização mesmo sem nunca ser exibido.
        if MenuBarFeature.isEnabled {
            panel
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if isLow {
                lowSpaceWarning
            }

            Divider().overlay(palette.stroke)

            metrics

            Divider().overlay(palette.stroke)

            actions
        }
        .padding(14)
        .frame(width: 320)
        .background(palette.bg2)
        .preferredColorScheme(state.theme.colorScheme)
    }

    // MARK: - Cabeçalho

    private var header: some View {
        HStack(spacing: 10) {
            BrandMark(size: 30, palette: palette)

            VStack(alignment: .leading, spacing: 1) {
                Text("SaveMyMac")
                    .font(Typo.ui(13.5, .semibold))
                    .foregroundStyle(palette.t1)
                Text(state.system.modelName)
                    .font(Typo.monoTiny)
                    .foregroundStyle(palette.t3)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text("\(state.health.score)")
                    .font(Typo.mono(19, .bold))
                    .foregroundStyle(palette.scoreTint(state.health.score))
                Text("SAÚDE")
                    .font(Typo.mono(8))
                    .tracking(1.4)
                    .foregroundStyle(palette.t3)
            }
        }
    }

    private var lowSpaceWarning: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(palette.danger)
            VStack(alignment: .leading, spacing: 1) {
                Text("Pouco espaço no disco")
                    .font(Typo.ui(12, .semibold))
                    .foregroundStyle(palette.t1)
                if let volume = state.bootVolume {
                    Text("\(Fmt.bytes(volume.available)) livres — abaixo do limiar de \(Int(prefs.lowSpaceThreshold)) %")
                        .font(Typo.monoTiny)
                        .foregroundStyle(palette.t2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.danger.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(palette.danger.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Métricas

    private var metrics: some View {
        VStack(spacing: 10) {
            if let volume = state.bootVolume {
                metricRow(
                    symbol: "internaldrive",
                    label: volume.name,
                    value: "\(Fmt.bytes(volume.available)) livres",
                    fraction: volume.usedFraction,
                    tint: palette.usageTint(volume.usedFraction)
                )
            }

            metricRow(
                symbol: "memorychip",
                label: "Memória",
                value: state.memory.pressureLabel,
                fraction: state.memory.pressureFraction,
                tint: palette.usageTint(state.memory.pressureFraction)
            )

            metricRow(
                symbol: "cpu",
                label: "Processador",
                value: Fmt.percent(state.cpu.busy),
                fraction: state.cpu.busy,
                tint: palette.usageTint(state.cpu.busy)
            )

            if let temp = state.thermal.displayTemperature {
                metricRow(
                    symbol: "thermometer.medium",
                    label: "Temperatura",
                    value: Fmt.celsius(temp),
                    fraction: (temp / 100).clamped(0, 1),
                    tint: palette.temperatureTint(temp)
                )
            } else {
                metricRow(
                    symbol: "thermometer.medium",
                    label: "Estado térmico",
                    value: state.thermal.thermalStateLabel,
                    fraction: 0,
                    tint: palette.t3
                )
            }

            if state.trash.totalBytes > 0 {
                metricRow(
                    symbol: "trash",
                    label: "Lixeira",
                    value: Fmt.bytes(state.trash.totalBytes),
                    fraction: 0,
                    tint: palette.warn
                )
            }
        }
    }

    private func metricRow(
        symbol: String,
        label: String,
        value: String,
        fraction: Double,
        tint: Color
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(palette.t3)
                .frame(width: 15)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(label)
                        .font(Typo.caption)
                        .foregroundStyle(palette.t2)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(value)
                        .font(Typo.monoCaption)
                        .foregroundStyle(tint)
                }
                if fraction > 0 {
                    GradientBar(
                        value: fraction,
                        palette: palette,
                        height: 3,
                        tint: LinearGradient(
                            colors: [tint, tint], startPoint: .leading, endPoint: .trailing
                        )
                    )
                }
            }
        }
    }

    // MARK: - Ações

    private var actions: some View {
        VStack(spacing: 4) {
            action("Abrir o SaveMyMac", "square.grid.2x2") { show(.dashboard) }
            action("Analisar o Mac", "magnifyingglass") {
                state.startScan()
                show(.cleanup)
            }
            if !state.trash.isEmpty {
                action("Esvaziar a Lixeira (\(Fmt.bytes(state.trash.totalBytes)))", "trash") {
                    show(.cleanup)
                }
            }
            action("Grandes arquivos", "square.stack.3d.up") { show(.files) }
            action("Offload", "link") { show(.offload) }

            Divider().overlay(palette.stroke).padding(.vertical, 3)

            settingsAction
            action("Encerrar o SaveMyMac", "power") { NSApp.terminate(nil) }
        }
    }

    /// O `SettingsOpener` cuida de *como* abrir; aqui só entra a aparência da
    /// linha, que é a mesma das vizinhas.
    private var settingsAction: some View {
        SettingsOpener {
            actionRow("Ajustes…", "gearshape")
        }
        .buttonStyle(MenuRowButtonStyle(palette: palette))
    }

    /// Traz a janela para a frente e leva até a aba pedida.
    ///
    /// Não mexe na política de ativação: se o usuário escondeu o ícone do Dock,
    /// o app continua `.accessory` e ainda assim mostra janela — trazer o ícone
    /// de volta aqui desfaria a preferência dele pelas costas.
    private func show(_ section: AppSection) {
        state.requestedSection = section
        openWindow(id: AppScene.main)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func action(_ title: String, _ symbol: String, _ perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            actionRow(title, symbol)
        }
        .buttonStyle(MenuRowButtonStyle(palette: palette))
    }

    /// O conteúdo visual de uma linha, separado do `Button`.
    ///
    /// Existe porque o `SettingsLink` é seu próprio controle e não aceita uma
    /// ação — ele precisa do mesmo rótulo sem o botão em volta. Sem essa
    /// separação, a linha de Ajustes ficaria com aparência diferente das outras.
    private func actionRow(_ title: String, _ symbol: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .frame(width: 15)
            Text(title)
                .font(Typo.bodySmall)
                .lineLimit(1)
            Spacer()
        }
        .foregroundStyle(palette.t1)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

/// Realce de linha de menu — o `.plain` não dá retorno nenhum ao passar o mouse.
struct MenuRowButtonStyle: ButtonStyle {
    var palette: Palette

    func makeBody(configuration: Configuration) -> some View {
        MenuRow(configuration: configuration, palette: palette)
    }

    private struct MenuRow: View {
        let configuration: Configuration
        let palette: Palette
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(
                            configuration.isPressed
                                ? palette.accent.opacity(0.28)
                                : (hovering ? palette.card2 : Color.clear)
                        )
                )
                .onHover { hovering = $0 }
        }
    }
}

// MARK: - Rótulo ao lado do relógio

/// O que aparece na barra de menus. Mantido minúsculo de propósito: a barra é
/// espaço compartilhado e um app de manutenção não deve dominá-la.
struct MenuBarLabel: View {
    @ObservedObject var state: AppState
    @ObservedObject var prefs: Preferences
    @ObservedObject var spaceAlert: SpaceAlert

    private var isLow: Bool {
        spaceAlert.isLow(volume: state.bootVolume, thresholdPercent: prefs.lowSpaceThreshold)
    }

    @ViewBuilder
    var body: some View {
        // Mantido no mínimo de propósito. A Apple documenta suporte limitado a
        // views no rótulo do MenuBarExtra, e ele re-renderiza a cada tique de
        // 2 s — qualquer coisa mais pesada aqui custa caro o dia inteiro.
        //
        // O contador é a rede de segurança deste recurso. Ele observa o
        // `AppState`, que publica várias vezes por tique; se algum dia isso
        // virar ciclo outra vez, o número aparece no rastro antes de o app
        // ficar sem resposta. Em uso normal deve crescer devagar.
        let _ = Trace.count("rótulo da barra de menus", every: 300)

        if !MenuBarFeature.isEnabled {
            EmptyView()
        } else if let text = valueText {
            // `.titleAndIcon` é obrigatório aqui.
            //
            // Um `Label` num item de barra de status usa, por padrão, só o
            // ícone — o título é descartado sem aviso. O item aparecia, mas
            // como um `sparkle` solitário no meio de seis outros ícones, o que
            // é indistinguível de "não apareceu".
            Label(text, systemImage: symbol)
                .labelStyle(.titleAndIcon)
        } else {
            Image(systemName: symbol)
        }
    }

    private var symbol: String {
        isLow ? "exclamationmark.triangle.fill" : "sparkle"
    }

    private var valueText: String? {
        switch prefs.menuBarMetric {
        case .none:
            return nil
        case .disk:
            guard let volume = state.bootVolume, volume.total > 0 else { return nil }
            let free = Double(volume.available) / Double(volume.total) * 100
            return String(format: "%.0f%%", free)
        case .memory:
            return String(format: "%.0f%%", state.memory.pressureFraction * 100)
        case .cpu:
            return String(format: "%.0f%%", state.cpu.busy * 100)
        case .temperature:
            guard let temp = state.thermal.displayTemperature else { return nil }
            return String(format: "%.0f°", temp)
        }
    }
}
