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
        case .dashboard: return L("Dashboard")
        case .cleanup: return L("Cleanup")
        case .apps: return L("Apps")
        case .files: return L("Large files")
        case .duplicates: return L("Duplicates")
        case .offload: return L("Offload")
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

/// Minimal delegate, for two behaviours plain SwiftUI does not give us.
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// The earliest hook we have. The adaptor creates the delegate before any
    /// scene exists, so the trace starts before any suspect does.
    override init() {
        super.init()
        Trace.begin()
        Trace.mark("AppDelegate.init")
    }

    /// Surviving a window close ONLY makes sense if there really is a menu bar
    /// item to bring the app back.
    ///
    /// Returning `false` unconditionally was a serious mistake: if the
    /// `MenuBarExtra` doesn't appear — because it's off in preferences, or
    /// because it failed — the app is left with no window, no icon and no way to
    /// quit. Force-quitting is all that's left. An app should never be able to
    /// reach that state.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Only survives a window close if there is genuinely a menu bar item to
        // bring the app back.
        let hasStatusItem = MenuBarFeature.isEnabled
            && NSApp.windows.contains { $0.className.contains("StatusBar") }
        return !hasStatusItem
    }

    /// Changing the activation policy while the first window is being presented
    /// confuses macOS: the window may never be ordered front. By here, launch has
    /// finished.
    func applicationDidFinishLaunching(_ notification: Notification) {
        Trace.mark("applicationDidFinishLaunching")
        // Only now is there a run loop for the watchdog to check in on.
        Trace.startWatchdog()

        let hide = UserDefaults.standard.bool(forKey: "hideDockIcon")
        if hide {
            NSApp.setActivationPolicy(.accessory)
        }

        checkStatusItem()
    }

    /// Checks whether the menu bar item is actually **visible**.
    ///
    /// The previous version of this method only looked for a window with
    /// "StatusBar" in its name and wrote "✅ item present". That was an expensive
    /// false positive: SwiftUI creates the scene's window even with
    /// `isInserted: false`, so the trace claimed everything was fine while there
    /// was no icon on screen at all. A diagnostic that lies is worse than none —
    /// it cost a full round trip.
    ///
    /// It now reports the three things that decide the question, separately: the
    /// feature gate, the user preference, and whether the window is visible.
    private func checkStatusItem() {
        guard MenuBarFeature.isEnabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let wanted = UserDefaults.standard.bool(forKey: "showMenuBarExtra")
            let window = NSApp.windows.first { $0.className.contains("StatusBar") }

            Trace.mark("barra de menus — recurso: ligado · preferência showMenuBarExtra: \(wanted)")

            switch (wanted, window?.isVisible) {
            case (false, _):
                Trace.mark("⚠️  ÍCONE OCULTO: a preferência está em falso. "
                    + "Ligue em Ajustes (⌘,) ou: defaults write "
                    + "br.com.pentagrama.savemymac showMenuBarExtra -bool true")
            case (true, .some(true)):
                Trace.mark("✅ ícone visível na barra de menus")
            case (true, .some(false)):
                Trace.mark("⚠️  janela do item existe mas está invisível")
            case (true, .none):
                Trace.mark("⚠️  preferência ligada mas nenhuma janela de status foi criada")
            }
        }
    }

    /// Clicking the Dock icon with the window closed should reopen the window.
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

/// Scene identifiers, so the menu bar panel can reopen the main window with
/// `openWindow(id:)`.
enum AppScene {
    static let main = "main"
}

/// Owns the state objects — **without observing them**.
///
/// This exists because of a real hang. With `@StateObject` in the App, the App
/// body becomes a subscriber to every `@Published` of `AppState`. And the App
/// body is not an ordinary view: re-evaluating it fires `scenesDidChange`, which
/// fires `makeMainMenu`, which rebuilds the system's entire menu bar.
///
/// `AppState` publishes about ten properties per metrics tick. The result,
/// measured in the trace, was **7,200 rebuilds in 10 seconds** at 100% of a
/// core, with memory climbing 80 MB in 17 s. The graph never converged.
///
/// The things that need to react to state changes are the views, and they still
/// do, through `@EnvironmentObject`. The App only needs to **hold** the objects.
/// A singleton does that and survives recreation of the App struct, which is the
/// only reason `@StateObject` would be here.
@MainActor
final class AppRoot {
    static let shared = AppRoot()
    let state = AppState()
    let prefs = Preferences()
    let spaceAlert = SpaceAlert()
    let localization = Localization.shared
    private init() {}
}

@main
struct SaveMyMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    private let root = AppRoot.shared
    private var state: AppState { root.state }
    private var spaceAlert: SpaceAlert { root.spaceAlert }

    /// This one **is** observed, deliberately: `MenuBarExtra` needs
    /// `$prefs.showMenuBar`, and only a property wrapper projects a binding.
    ///
    /// It's safe here. `Preferences` changes only when the user touches Settings
    /// — a few times per session. What couldn't continue was the App observing
    /// `AppState`, which publishes ten times per metrics tick.
    @ObservedObject private var prefs = AppRoot.shared.prefs

    // The body is split into named scenes on purpose.
    //
    // All of this was inline and the compiler answered with "failed to produce
    // diagnostic for expression" — the type checker gave up on inferring the
    // whole expression. Large scenes with an embedded `.commands` are a classic
    // case; breaking it into parts with their own types fixes it and leaves the
    // file readable too.
    var body: some Scene {
        mainWindow
        menuBarScene
        settingsScene
    }

    // MARK: - Main window

    /// `Window`, **not** `WindowGroup`.
    ///
    /// A `WindowGroup` is a template: `openWindow(id:)` creates a new window on
    /// every call. Since the menu bar panel calls that on every action, clicking
    /// "Open SaveMyMac" five times opened five windows — each with its own view
    /// tree, all observing the same `AppState` and all re-rendering on every
    /// metrics tick.
    ///
    /// `Window` is a single instance. `openWindow(id:)` now brings the existing
    /// one forward, which is the right behaviour for a dashboard app: there is no
    /// document to have two of.
    ///
    /// As a bonus, `Window` removes "New Window" from the File menu by itself —
    /// the `CommandGroup(replacing: .newItem)` stays as belt and braces.
    private var mainWindow: some Scene {
        Window("SaveMyMac", id: AppScene.main) {
            RootView()
                .environmentObject(state)
                .environmentObject(prefs)
                .environmentObject(spaceAlert)
                .environmentObject(root.localization)
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

    // MARK: - Menu bar

    /// `SceneBuilder` **does not accept `if`** — it only knows how to compose a
    /// fixed list of scenes. The correct alternative is for the scene to always
    /// exist and let `isInserted` decide whether the item appears.
    ///
    /// `isInserted` has to be the projected `Binding` (`$prefs.showMenuBar`),
    /// never a `Binding(get:set:)` assembled here. A binding built in the body is
    /// a new object on every evaluation: SwiftUI compares the two, never sees
    /// them as equal, marks the scene as changed and re-evaluates — forever. It
    /// was one of the causes of the 100%-CPU loop.
    ///
    /// The feature gate lives in `Preferences.init`, where it is applied once.
    private var menuBarScene: some Scene {
        MenuBarExtra(isInserted: $prefs.showMenuBar) {
            MenuBarPanel()
                .environmentObject(state)
                .environmentObject(prefs)
                .environmentObject(spaceAlert)
                .environmentObject(root.localization)
        } label: {
            MenuBarLabel(state: state, prefs: prefs, spaceAlert: spaceAlert)
        }
        .menuBarExtraStyle(.window)
    }

    // MARK: - Settings

    /// This scene's content is built on every App body evaluation — even with
    /// the Settings window closed, even if it was never opened. And the App body
    /// used to be invalidated by every `@Published` of `AppState`.
    ///
    /// Which means: **whatever is in `SettingsView`'s `init` runs dozens of times
    /// per second.** That is why two XPC calls in there hung the whole app. The
    /// counter below exists so that frequency is visible in the trace instead of
    /// being a surprise again.
    private var settingsScene: some Scene {
        Trace.count("cena Ajustes reconstruída", every: 200)
        return Settings {
            SettingsView()
                .environmentObject(state)
                .environmentObject(prefs)
                .environmentObject(spaceAlert)
                .environmentObject(root.localization)
        }
    }
}

/// The system menu bar's "Actions" menu.
///
/// `let state`, **not** `@ObservedObject`. That is the main point of this type.
///
/// Observing `AppState` here looks harmless and isn't: the spindump showed
/// `AppDelegate.scenesDidChange` → `makeMainMenu` → `updateMainMenu` → rebuilding
/// the entire item list, with subgraph allocation and `memmove` on every pass.
/// The system menu bar was being reassembled from scratch on every CPU reading.
///
/// The buttons only need to **call** methods on the state. Calling doesn't
/// require observing. The one thing that did was the theme button's title
/// switching between "light" and "dark" — replaced with a fixed label, because a
/// menu that rebuilds itself is far too expensive for that convenience.
struct AppCommands: Commands {
    let state: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}

        CommandMenu(L("Actions")) {
            Button(L("Analyze my Mac")) { state.startScan() }
                .keyboardShortcut("r", modifiers: .command)
            Button(L("Scan files and duplicates")) { state.startFilesScan() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Button(L("Scan applications")) { state.startAppsScan() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            Button(L("Check offload links")) { state.startOffloadScan() }
                .keyboardShortcut("l", modifiers: .command)

            Divider()

            Button(L("Refresh metrics")) { state.refreshMetrics() }
                .keyboardShortcut("u", modifiers: .command)
            // Fixed label on purpose — see the note at the top of the type.
            Button(L("Switch between light and dark theme (⇧⌘T)")) { state.toggleTheme() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
        }
    }
}

struct RootView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var loc: Localization
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
        // Switching language rebuilds the subtree.
        //
        // `L()` is a global function, not an observable property, so a view that
        // merely calls `L()` has no way to know the language changed. Keying
        // identity on the language solves it in one line, instead of threading an
        // `@EnvironmentObject` through 25 files purely to invalidate.
        //
        // The `.id` goes **on the content**, not on `RootView`: that way its
        // `selection` survives and you stay on the same tab after switching.
        .id(loc.language)
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
            state.pendingForceQuit.map { L("Force quit %@?", $0.name) } ?? "",
            isPresented: Binding(
                get: { state.pendingForceQuit != nil },
                // The `!= nil` is not redundant: SwiftUI calls this setter
                // during an update, and writing `nil` over `nil` on a
                // `@Published` publishes anyway — the same mechanism that
                // produced the menu bar cycle.
                set: { if !$0 && state.pendingForceQuit != nil { state.pendingForceQuit = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let row = state.pendingForceQuit {
                Button(L("Force quit"), role: .destructive) {
                    state.forceQuit(row)
                }
            }
            Button(L("Cancel"), role: .cancel) { state.pendingForceQuit = nil }
        } message: {
            Text(L("Force quit kills the process immediately. Anything unsaved is lost, with no chance for the app to ask.\n\nIf you have not tried it yet, prefer \"Ask it to quit\"."))
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

// MARK: - Top strip

/// Replaces the mockup's fake title bar. The real window already has the macOS
/// buttons, so all that lives here is the breadcrumb and the theme button.
struct TitleStrip: View {
    @EnvironmentObject var loc: Localization
    @EnvironmentObject var state: AppState
    var sectionTitle: String

    private var palette: Palette { state.palette }

    var body: some View {
        HStack(spacing: 14) {
            // Room for the window's native buttons.
            Spacer().frame(width: 68)

            Spacer()

            // Goes through the table even though it is identical in every
            // language today: the separator may change (French puts a space
            // before the em dash), and an exception in the checker is a permanent
            // hole, whereas a key is an extension point.
            Text(L("SaveMyMac — %@", sectionTitle))
                .font(Typo.mono(12.5))
                .tracking(Track.crumb)
                .textCase(.uppercase)
                .foregroundStyle(palette.t3)

            Spacer()

            HStack(spacing: 8) {
                settingsButton
                themeButton
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background(palette.card)
    }

    /// Round and icon-only on purpose: next to the theme capsule, two controls
    /// of the same size and shape would compete for attention. Settings is a
    /// destination, not a switch.
    private var settingsButton: some View {
        SettingsOpener {
            Image(systemName: "gearshape")
                .font(.system(size: 12.5))
                .foregroundStyle(palette.t2)
                .frame(width: 28, height: 28)
                .background(Circle().fill(palette.card2))
                .overlay(Circle().strokeBorder(palette.stroke2, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(L("SaveMyMac settings (⌘,)"))
    }

    private var themeButton: some View {
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
        .help(L("Switch between light and dark theme (⇧⌘T)"))
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @EnvironmentObject var loc: Localization
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
            MicroLabel(text: L("Navigation"), palette: palette)
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
            // Without this, the badge vanished right after a cleanup to the
            // Trash, which is exactly when it matters most.
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
                MicroLabel(text: L("Startup disk"), palette: palette)
                GradientBar(value: volume.usedFraction, palette: palette, height: 8)
                HStack {
                    Text(L("%@ free", Fmt.bytes(volume.available)))
                    Spacer()
                    Text(L("of %@", Fmt.bytes(volume.total)))
                        .foregroundStyle(palette.t3)
                }
                .font(Typo.monoCaption)
                .foregroundStyle(palette.t2)
            }

            if state.totalReclaimable > 0 {
                MicroLabel(text: L("Reclaimable"), palette: palette)
                    .padding(.top, 6)
                Text(Fmt.bytes(state.totalReclaimable))
                    .font(Typo.statValue)
                    .foregroundStyle(palette.ok)
                    .shadow(color: palette.ok.opacity(0.45), radius: 12)
            }

            if state.offload.savedBytes > 0 {
                MicroLabel(text: L("Offloaded"), palette: palette)
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

// MARK: - Level card

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

                    Text(L("Level %d", game.state.level))
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
                     ? L("No active week yet")
                     : Lp("Streak: %d week", "Streak: %d weeks",
                          count: game.state.streak))
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

// MARK: - Notice banner

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
