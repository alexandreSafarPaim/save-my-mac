import SwiftUI

/// Ajustes do app (⌘,).
struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: Preferences
    @EnvironmentObject var spaceAlert: SpaceAlert

    // ATENÇÃO: estes `@State` precisam ser inicializados com valores baratos.
    //
    // Antes eram `LaunchAtLogin.isEnabled` e `.statusDescription`, que fazem XPC
    // síncrono para o `smd`. Um inicializador de `@State` roda dentro do
    // `init()` da view, e o SwiftUI constrói o conteúdo da cena `Settings` a
    // cada avaliação do corpo do App — inclusive com a janela de Ajustes
    // fechada. O resultado foi o app inteiro travar em `mach_msg`.
    //
    // Regra que vale para qualquer view daqui em diante: **inicializador de view
    // não faz I/O**. O valor real chega pelo `.task` abaixo.
    @State private var launch = LaunchAtLogin.snapshot
    @State private var launchMessage: String?
    @State private var launchMessageIsError = false
    @State private var launchBusy = false

    private var palette: Palette { state.palette }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                startupSection
                menuBarSection
                alertsSection
                appearanceSection
            }
            .padding(22)
        }
        .frame(width: 520, height: 560)
        .background(palette.bg2)
        .preferredColorScheme(state.theme.colorScheme)
        // Só agora — com a janela de Ajustes realmente aberta — vale consultar
        // o `smd`. E fora da thread principal.
        .task { launch = await LaunchAtLogin.refresh() }
    }

    // MARK: - Inicialização

    private var startupSection: some View {
        section("Inicialização", "power") {
            Toggle(isOn: Binding(
                get: { launch.enabled },
                set: { toggleLaunch($0) }
            )) {
                Text("Abrir o SaveMyMac ao ligar o Mac")
                    .font(Typo.bodySmall)
                    .foregroundStyle(palette.t1)
            }
            .toggleStyle(.switch)
            // Enquanto a consulta não volta, mexer no interruptor agiria sobre
            // um estado que ainda não conhecemos.
            .disabled(!launch.isKnown || launchBusy)

            Text(launch.description)
                .font(Typo.monoTiny)
                .foregroundStyle(palette.t3)
                .fixedSize(horizontal: false, vertical: true)

            if let launchMessage {
                Text(launchMessage)
                    .font(Typo.caption)
                    .foregroundStyle(launchMessageIsError ? palette.danger : palette.ok)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("O app usa a API moderna (Itens de Início do sistema) quando consegue. Como este build é assinado ad-hoc, o registro pode ser recusado — nesse caso ele cai para um LaunchAgent do usuário, que funciona igual. O texto acima diz qual mecanismo está ativo.")
                .font(Typo.monoTiny)
                .foregroundStyle(palette.t3)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: $prefs.hideDockIcon) {
                Text("Esconder o ícone do Dock")
                    .font(Typo.bodySmall)
                    .foregroundStyle(palette.t1)
            }
            .toggleStyle(.switch)
            .padding(.top, 4)

            Text("Com o ícone escondido o app vive só na barra de menus. Vale a pena se você deixa ele aberto o tempo todo. Aplica na hora, sem reiniciar.")
                .font(Typo.monoTiny)
                .foregroundStyle(palette.t3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func toggleLaunch(_ enabled: Bool) {
        guard !launchBusy else { return }
        launchBusy = true
        Task {
            let result = await LaunchAtLogin.setEnabled(enabled)
            launchMessage = result.message
            launchMessageIsError = result.isError
            launch = LaunchAtLogin.snapshot
            launchBusy = false
        }
    }

    // MARK: - Barra de menus

    private var menuBarSection: some View {
        section("Barra de menus", "menubar.rectangle") {
            if MenuBarFeature.isEnabled {
                Toggle(isOn: $prefs.showMenuBar) {
                    Text("Mostrar na barra de menus")
                        .font(Typo.bodySmall)
                        .foregroundStyle(palette.t1)
                }
                .toggleStyle(.switch)

                Text("Com isto ligado o app mostra a métrica escolhida ao lado do relógio e o painel abre com um clique, sem precisar trazer a janela.")
                    .font(Typo.monoTiny)
                    .foregroundStyle(palette.t3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Desligada pelo interruptor de emergência.")
                    .font(Typo.bodySmall)
                    .foregroundStyle(palette.warn)
                Text("A chave `enableMenuBar` está em falso, ou o app está em modo seguro. Para religar, no Terminal:\ndefaults write br.com.pentagrama.savemymac enableMenuBar -bool true\ne reabra o app.")
                    .font(Typo.monoTiny)
                    .foregroundStyle(palette.t3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("O que mostrar ao lado do ícone")
                    .font(Typo.caption)
                    .foregroundStyle(palette.t2)
                Picker("", selection: $prefs.menuBarMetric) {
                    ForEach(Preferences.MenuBarMetric.allCases) { metric in
                        Text(metric.label).tag(metric)
                    }
                }
                .pickerStyle(.radioGroup)
                .disabled(!prefs.showMenuBar)
            }
            .padding(.top, 2)

            Text("O ícone troca para um triângulo de alerta quando o espaço livre cai abaixo do limiar, independente da métrica escolhida.")
                .font(Typo.monoTiny)
                .foregroundStyle(palette.t3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Alertas

    private var alertsSection: some View {
        section("Alerta de pouco espaço", "exclamationmark.triangle") {
            Toggle(isOn: Binding(
                get: { prefs.lowSpaceAlerts },
                set: { value in
                    prefs.lowSpaceAlerts = value
                    if value { spaceAlert.requestPermissionIfNeeded() }
                }
            )) {
                Text("Notificar quando faltar espaço")
                    .font(Typo.bodySmall)
                    .foregroundStyle(palette.t1)
            }
            .toggleStyle(.switch)

            if spaceAlert.permissionDenied {
                Text("A permissão de notificação foi negada. Libere em Ajustes do Sistema › Notificações. O aviso na barra de menus continua funcionando.")
                    .font(Typo.caption)
                    .foregroundStyle(palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Avisar abaixo de")
                        .font(Typo.caption)
                        .foregroundStyle(palette.t2)
                    Spacer()
                    Text("\(Int(prefs.lowSpaceThreshold)) % livres")
                        .font(Typo.monoCaption)
                        .foregroundStyle(palette.t1)
                }
                Slider(value: $prefs.lowSpaceThreshold, in: 3...30, step: 1)
                    .disabled(!prefs.lowSpaceAlerts)

                if let volume = state.bootVolume, volume.total > 0 {
                    let free = Double(volume.available) / Double(volume.total) * 100
                    Text("Agora: \(String(format: "%.1f", free)) % livres em \(volume.name) (\(Fmt.bytes(volume.available))).")
                        .font(Typo.monoTiny)
                        .foregroundStyle(palette.t3)
                }
            }

            Text("O aviso dispara ao cruzar o limiar e só rearma depois de o espaço subir 3 pontos acima dele, com no máximo um por 6 horas. Sem isso, um disco oscilando em torno do limiar notificaria sem parar.")
                .font(Typo.monoTiny)
                .foregroundStyle(palette.t3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Aparência

    private var appearanceSection: some View {
        section("Aparência", "paintbrush") {
            Picker("", selection: Binding(
                get: { state.theme },
                set: { state.theme = $0 }
            )) {
                ForEach(ThemeMode.allCases, id: \.self) { mode in
                    Text(mode == .dark ? "Escuro" : "Claro").tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
    }

    // MARK: - Estrutura

    private func section<Content: View>(
        _ title: String,
        _ symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.accent)
                Text(title)
                    .font(Typo.cardTitle)
                    .foregroundStyle(palette.t1)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.stroke, lineWidth: 1)
        )
    }
}
