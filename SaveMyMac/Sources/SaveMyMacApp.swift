import SwiftUI
import AppKit

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard
    case cleanup
    case apps
    case files
    case duplicates
    case offload

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Painel"
        case .cleanup: return "Limpeza"
        case .apps: return "Aplicativos"
        case .files: return "Grandes arquivos"
        case .duplicates: return "Duplicados"
        case .offload: return "Offload"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: return "circle.circle"
        case .cleanup: return "sparkles"
        case .apps: return "square.grid.2x2"
        case .files: return "square.stack.3d.up"
        case .duplicates: return "square.on.square"
        case .offload: return "link"
        }
    }
}

/// Delegate mínimo, para dois comportamentos que o SwiftUI puro não dá.
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// O ponto mais cedo que temos. O adaptor cria o delegate antes de qualquer
    /// cena existir, então o rastro começa antes de qualquer suspeito.
    override init() {
        super.init()
        Trace.begin()
        Trace.mark("AppDelegate.init")
    }

    /// Sobreviver ao fechar a janela SÓ faz sentido se houver de fato um item na
    /// barra de menus para trazer o app de volta.
    ///
    /// Retornar `false` incondicionalmente foi um erro grave: se o
    /// `MenuBarExtra` não aparece — porque está desligado nas preferências, ou
    /// porque falhou —, o app fica sem janela, sem ícone e sem forma de sair.
    /// Só resta forçar o encerramento. Um app nunca deve poder chegar nesse
    /// estado.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Só sobrevive ao fechar a janela se houver mesmo um item na barra de
        // menus para trazer o app de volta.
        let hasStatusItem = MenuBarFeature.isEnabled
            && NSApp.windows.contains { $0.className.contains("StatusBar") }
        return !hasStatusItem
    }

    /// Mexer na política de ativação durante a apresentação da primeira janela
    /// deixa o macOS confuso: a janela pode nunca ser ordenada para a frente.
    /// Aqui o lançamento já terminou.
    func applicationDidFinishLaunching(_ notification: Notification) {
        Trace.mark("applicationDidFinishLaunching")
        // Só agora existe run loop para o vigia bater ponto.
        Trace.startWatchdog()

        let hide = UserDefaults.standard.bool(forKey: "hideDockIcon")
        if hide {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Clicar no ícone do Dock com a janela fechada deve reabrir a janela.
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
        return true
    }
}

/// Identificadores de cena, para o painel da barra de menus poder reabrir a
/// janela principal com `openWindow(id:)`.
enum AppScene {
    static let main = "main"
}

/// Dono dos objetos de estado — **sem observá-los**.
///
/// Isto existe por causa de um travamento real. Com `@StateObject` no App, o
/// corpo do App vira assinante de todo `@Published` do `AppState`. E o corpo do
/// App não é uma view qualquer: reavaliá-lo dispara `scenesDidChange`, que
/// dispara `makeMainMenu`, que reconstrói a barra de menus inteira do sistema.
///
/// O `AppState` publica umas dez propriedades por tique de métricas. O
/// resultado, medido no rastro, foi **7.200 reconstruções em 10 segundos** a
/// 100 % de CPU, com a memória subindo 80 MB em 17 s. O grafo nunca convergia.
///
/// Quem precisa reagir a mudança de estado são as views, e elas continuam
/// reagindo pelo `@EnvironmentObject`. O App só precisa **segurar** os objetos.
/// Um singleton faz isso e sobrevive à recriação do struct do App, que é a
/// única razão de `@StateObject` existir aqui.
@MainActor
final class AppRoot {
    static let shared = AppRoot()
    let state = AppState()
    let prefs = Preferences()
    let spaceAlert = SpaceAlert()
    private init() {}
}

@main
struct SaveMyMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    private let root = AppRoot.shared
    private var state: AppState { root.state }
    private var spaceAlert: SpaceAlert { root.spaceAlert }

    /// Este **é** observado, e de propósito: o `MenuBarExtra` precisa de
    /// `$prefs.showMenuBar`, e só um wrapper de propriedade projeta binding.
    ///
    /// Aqui é seguro. `Preferences` só muda quando o usuário mexe em Ajustes —
    /// algumas vezes por sessão. O que não podia continuar era o App observar o
    /// `AppState`, que publica dez vezes por tique de métricas.
    @ObservedObject private var prefs = AppRoot.shared.prefs

    // O corpo é dividido em cenas nomeadas de propósito.
    //
    // Tudo isto estava inline e o compilador respondeu com
    // "failed to produce diagnostic for expression" — o type-checker desistiu
    // de inferir a expressão inteira. Cenas grandes com `.commands` embutido
    // são um caso clássico; quebrar em partes com tipo próprio resolve e ainda
    // deixa o arquivo legível.
    var body: some Scene {
        mainWindow
        menuBarScene
        settingsScene
    }

    // MARK: - Janela principal

    private var mainWindow: some Scene {
        WindowGroup("SaveMyMac", id: AppScene.main) {
            RootView()
                .environmentObject(state)
                .environmentObject(prefs)
                .environmentObject(spaceAlert)
                .frame(minWidth: 1080, minHeight: 700)
                // `.preferredColorScheme` saiu daqui e foi para dentro das
                // views. Lido aqui, `state.theme` obrigaria o corpo do App a
                // observar o `AppState` — exatamente o que causou o loop.
                // Dentro da view, o `@EnvironmentObject` faz o trabalho sem
                // envolver a cena.
                .onAppear {
                    Trace.mark("RootView.onAppear")
                    state.start()
                    state.attach(preferences: prefs, spaceAlert: spaceAlert)
                    Trace.mark("RootView.onAppear concluído")
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands { AppCommands(state: state) }
    }

    // MARK: - Barra de menus

    /// `SceneBuilder` **não aceita `if`** — só sabe compor uma lista fixa de
    /// cenas. A alternativa correta é a cena existir sempre e o `isInserted`
    /// decidir se o item aparece.
    ///
    /// O `isInserted` precisa ser o `Binding` projetado (`$prefs.showMenuBar`),
    /// nunca um `Binding(get:set:)` montado aqui. Um binding construído no corpo
    /// é um objeto novo a cada avaliação: o SwiftUI compara os dois, nunca os vê
    /// iguais, marca a cena como alterada e reavalia — para sempre. Foi um dos
    /// motivos do loop de 100 % de CPU.
    ///
    /// A trava do recurso mora no `Preferences.init`, onde é aplicada uma vez.
    private var menuBarScene: some Scene {
        MenuBarExtra(isInserted: $prefs.showMenuBar) {
            MenuBarPanel()
                .environmentObject(state)
                .environmentObject(prefs)
                .environmentObject(spaceAlert)
        } label: {
            MenuBarLabel(state: state, prefs: prefs, spaceAlert: spaceAlert)
        }
        .menuBarExtraStyle(.window)
    }

    // MARK: - Ajustes

    /// O conteúdo desta cena é construído a cada avaliação do corpo do App —
    /// mesmo com a janela de Ajustes fechada, mesmo sem ela nunca ter sido
    /// aberta. E o corpo do App é invalidado a cada `@Published` do `AppState`.
    ///
    /// Ou seja: **o que estiver no `init` do `SettingsView` roda dezenas de
    /// vezes por segundo.** Foi por isso que duas chamadas XPC ali dentro
    /// travaram o app inteiro. O contador abaixo existe para essa frequência
    /// ficar visível no rastro em vez de ser surpresa de novo.
    private var settingsScene: some Scene {
        Trace.count("cena Ajustes reconstruída", every: 200)
        return Settings {
            SettingsView()
                .environmentObject(state)
                .environmentObject(prefs)
                .environmentObject(spaceAlert)
        }
    }
}

/// Menu "Ações" da barra de menus do sistema.
///
/// `let state`, **não** `@ObservedObject`. Isso é o ponto principal deste tipo.
///
/// Observar o `AppState` aqui parece inofensivo e não é: o spindump mostrou
/// `AppDelegate.scenesDidChange` → `makeMainMenu` → `updateMainMenu` →
/// reconstrução da lista inteira de itens, com alocação de subgrafo e `memmove`
/// a cada passagem. A barra de menus do sistema estava sendo remontada do zero
/// a cada leitura de CPU.
///
/// Os botões só precisam **chamar** métodos do estado. Chamar não exige
/// observar. A única coisa que exigia era o título do botão de tema mudar entre
/// "claro" e "escuro" — trocado por um rótulo fixo, porque um menu que se
/// reconstrói sozinho custa caro demais para essa conveniência.
struct AppCommands: Commands {
    let state: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}

        CommandMenu("Ações") {
            Button("Analisar o Mac") { state.startScan() }
                .keyboardShortcut("r", modifiers: .command)
            Button("Analisar arquivos e duplicados") { state.startFilesScan() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Button("Analisar aplicativos") { state.startAppsScan() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            Button("Verificar links de offload") { state.startOffloadScan() }
                .keyboardShortcut("l", modifiers: .command)

            Divider()

            Button("Atualizar métricas") { state.refreshMetrics() }
                .keyboardShortcut("u", modifiers: .command)
            // Rótulo fixo de propósito — ver a nota no topo do tipo.
            Button("Alternar tema claro/escuro") { state.toggleTheme() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
        }
    }
}

struct RootView: View {
    @EnvironmentObject var state: AppState
    @State private var selection: AppSection = .dashboard

    private var palette: Palette { state.palette }

    var body: some View {
        ZStack {
            AtmosphereBackground(palette: palette)

            HStack(spacing: 0) {
                Sidebar(selection: $selection)
                    .frame(width: 232)

                Rectangle()
                    .fill(palette.stroke)
                    .frame(width: 1)

                VStack(spacing: 0) {
                    TitleStrip(sectionTitle: selection.title)
                    Rectangle().fill(palette.stroke).frame(height: 1)
                    detail
                }
            }

            if let banner = state.banner {
                VStack {
                    Spacer()
                    BannerView(banner: banner, palette: palette) {
                        state.dismissBanner()
                    }
                    .padding(.bottom, 22)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let celebration = state.celebration {
                CelebrationOverlay(celebration: celebration, palette: palette) {
                    state.dismissCelebration()
                }
            }
        }
        .preferredColorScheme(state.theme.colorScheme)
        .animation(.easeInOut(duration: 0.25), value: state.banner?.id)
        .animation(Motion.pop, value: state.celebration?.id)
        // O painel da barra de menus pede uma aba; a janela obedece aqui.
        .onChange(of: state.requestedSection) { requested in
            if let requested {
                selection = requested
                state.requestedSection = nil
            }
        }
        .confirmationDialog(
            state.pendingForceQuit.map { "Forçar o encerramento de \($0.name)?" } ?? "",
            isPresented: Binding(
                get: { state.pendingForceQuit != nil },
                // O `!= nil` não é redundante: o SwiftUI chama este setter
                // durante a atualização, e escrever `nil` sobre `nil` num
                // `@Published` publica mesmo assim — o mesmo mecanismo que
                // gerou o ciclo da barra de menus.
                set: { if !$0 && state.pendingForceQuit != nil { state.pendingForceQuit = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let row = state.pendingForceQuit {
                Button("Forçar encerramento", role: .destructive) {
                    state.forceQuit(row)
                }
            }
            Button("Cancelar", role: .cancel) { state.pendingForceQuit = nil }
        } message: {
            Text("Forçar mata o processo na hora. Tudo que não foi salvo é perdido, sem chance de o app perguntar.\n\nSe ainda não tentou, prefira \"Pedir para encerrar\".")
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .dashboard:
            DashboardView(selection: $selection)
        case .cleanup:
            CleanupView()
        case .apps:
            AppsView()
        case .files:
            BigFilesView(selection: $selection)
        case .duplicates:
            DuplicatesView()
        case .offload:
            OffloadView()
        }
    }
}

// MARK: - Faixa do topo

/// Substitui a barra de título falsa do mockup. A janela real já tem os botões
/// do macOS, então aqui ficam só a trilha e o botão de tema.
struct TitleStrip: View {
    @EnvironmentObject var state: AppState
    var sectionTitle: String

    private var palette: Palette { state.palette }

    var body: some View {
        HStack(spacing: 14) {
            // Espaço para os botões nativos da janela.
            Spacer().frame(width: 68)

            Spacer()

            Text("SaveMyMac — \(sectionTitle)")
                .font(Typo.mono(12.5))
                .tracking(Track.crumb)
                .textCase(.uppercase)
                .foregroundStyle(palette.t3)

            Spacer()

            Button {
                state.toggleTheme()
            } label: {
                HStack(spacing: 7) {
                    Circle()
                        .fill(palette.cyan)
                        .frame(width: 8, height: 8)
                        .shadow(color: palette.cyan, radius: 5)
                    Text(state.theme.label)
                        .font(Typo.mono(11.5))
                        .tracking(0.9)
                }
                .foregroundStyle(palette.t2)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Capsule().fill(palette.card2))
                .overlay(Capsule().strokeBorder(palette.stroke2, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Alternar entre tema claro e escuro (⇧⌘T)")
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background(palette.card)
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @EnvironmentObject var state: AppState
    @Binding var selection: AppSection

    private var palette: Palette { state.palette }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                logo
                navigation
                LevelCard(palette: palette, game: state.game)
                diskSummary
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 18)
        }
        .background(palette.card)
    }

    private var logo: some View {
        BrandLockup(palette: palette)
            .padding(.horizontal, 6)
    }

    private var navigation: some View {
        VStack(alignment: .leading, spacing: 4) {
            MicroLabel(text: "Navegação", palette: palette)
                .padding(.horizontal, 8)
                .padding(.bottom, 2)

            ForEach(AppSection.allCases) { section in
                NavRow(
                    section: section,
                    isActive: selection == section,
                    badge: badge(for: section),
                    palette: palette
                ) {
                    selection = section
                }
            }
        }
    }

    private func badge(for section: AppSection) -> String? {
        switch section {
        case .cleanup:
            let count = state.selectedCategoryCount
            if count > 0 { return "\(count)" }
            // Sem isto o aviso desaparecia justamente depois de uma limpeza para
            // a Lixeira, que é quando ele mais importa.
            return state.trash.isEmpty ? nil : Fmt.bytes(state.trash.totalBytes)
        case .duplicates:
            let total = state.files.duplicateTotal
            return total > 0 ? Fmt.bytes(total) : nil
        case .apps:
            return state.appInventory.staleCount > 0 ? "\(state.appInventory.staleCount)" : nil
        case .offload:
            return state.offload.brokenCount > 0 ? "!" : nil
        default:
            return nil
        }
    }

    private var diskSummary: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let volume = state.bootVolume {
                MicroLabel(text: "Disco de inicialização", palette: palette)
                GradientBar(value: volume.usedFraction, palette: palette, height: 8)
                HStack {
                    Text("\(Fmt.bytes(volume.available)) livres")
                    Spacer()
                    Text("de \(Fmt.bytes(volume.total))")
                        .foregroundStyle(palette.t3)
                }
                .font(Typo.monoCaption)
                .foregroundStyle(palette.t2)
            }

            if state.totalReclaimable > 0 {
                MicroLabel(text: "Recuperável", palette: palette)
                    .padding(.top, 6)
                Text(Fmt.bytes(state.totalReclaimable))
                    .font(Typo.statValue)
                    .foregroundStyle(palette.ok)
                    .shadow(color: palette.ok.opacity(0.45), radius: 12)
            }

            if state.offload.savedBytes > 0 {
                MicroLabel(text: "Descarregado", palette: palette)
                    .padding(.top, 6)
                Text(Fmt.bytes(state.offload.savedBytes))
                    .font(Typo.mono(18, .bold))
                    .foregroundStyle(palette.cyan)
            }
        }
        .padding(.horizontal, 4)
    }
}

struct NavRow: View {
    var section: AppSection
    var isActive: Bool
    var badge: String?
    var palette: Palette
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: section.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                Text(section.title)
                    .font(Typo.ui(13.5, .medium))
                Spacer(minLength: 4)
                if let badge {
                    Text(badge)
                        .font(Typo.monoTiny)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(palette.accent.opacity(0.22))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(palette.accent.opacity(0.4), lineWidth: 1)
                        )
                }
            }
            .foregroundStyle(isActive ? palette.t1 : (hovering ? palette.t1 : palette.t2))
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(background)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var background: some View {
        ZStack(alignment: .leading) {
            if isActive {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [palette.accent.opacity(0.30), palette.cyan.opacity(0.10)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(palette.accent.opacity(0.45), lineWidth: 1)
                    )
                // Marca luminosa na borda esquerda.
                UnevenRoundedRectangle(
                    topLeadingRadius: 0, bottomLeadingRadius: 0,
                    bottomTrailingRadius: 3, topTrailingRadius: 3
                )
                .fill(palette.cyan)
                .frame(width: 3)
                .padding(.vertical, 9)
                .shadow(color: palette.cyan, radius: 6)
            } else if hovering {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(palette.card2)
            }
        }
    }
}

// MARK: - Card de nível

struct LevelCard: View {
    var palette: Palette
    @ObservedObject var game: GameStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(palette.gradient)
                        Text("\(game.state.level)")
                            .font(Typo.mono(11, .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 26, height: 26)

                    Text("Nível \(game.state.level)")
                        .font(Typo.ui(12.5, .semibold))
                        .foregroundStyle(palette.t1)
                }
                Spacer()
                Text("\(game.state.xpInLevel)/\(GameState.xpPerLevel)")
                    .font(Typo.monoTiny)
                    .foregroundStyle(palette.t3)
            }

            GradientBar(value: game.state.xpProgress, palette: palette, height: 6, glow: true)

            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.warn)
                Text(game.state.streak == 0
                     ? "Nenhuma semana ativa ainda"
                     : "Streak de \(game.state.streak) semana\(game.state.streak == 1 ? "" : "s")")
                    .font(Typo.caption)
                    .foregroundStyle(palette.t2)
            }
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.card2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.stroke, lineWidth: 1)
        )
    }
}

// MARK: - Banner de aviso

struct BannerView: View {
    var banner: AppState.Banner
    var palette: Palette
    var dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: banner.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(banner.isError ? palette.danger : palette.ok)
            Text(banner.text)
                .font(Typo.bodySmall)
                .foregroundStyle(palette.t1)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.t3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 640)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.card2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    (banner.isError ? palette.danger : palette.ok).opacity(0.45),
                    lineWidth: 1
                )
        )
        .shadow(color: palette.shadow, radius: 24, y: 10)
    }
}
