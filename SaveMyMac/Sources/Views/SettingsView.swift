import SwiftUI

/// App settings (⌘,).
struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: Preferences
    @EnvironmentObject var spaceAlert: SpaceAlert
    @EnvironmentObject var loc: Localization

    // WARNING: these `@State` values must be initialised with cheap values.
    //
    // They used to be `LaunchAtLogin.isEnabled` and `.statusDescription`, which
    // do synchronous XPC to `smd`. A `@State` initialiser runs inside the view's
    // `init()`, and SwiftUI builds the `Settings` scene content on every App body
    // evaluation — including with the Settings window closed. The result was the
    // whole app hanging in `mach_msg`.
    //
    // The rule for every view from here on: **a view initialiser does no I/O**.
    // The real value arrives through the `.task` below.
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
                languageSection
            }
            .padding(22)
        }
        .frame(width: 520, height: 560)
        .background(palette.bg2)
        .id(loc.language)
        .preferredColorScheme(state.theme.colorScheme)
        // Only now — with the Settings window actually open — is it worth asking
        // `smd`. And off the main thread.
        .task { launch = await LaunchAtLogin.refresh() }
    }

    // MARK: - Startup

    private var startupSection: some View {
        section(L("Startup"), "power") {
            Toggle(isOn: Binding(
                get: { launch.enabled },
                set: { toggleLaunch($0) }
            )) {
                Text(L("Open SaveMyMac when the Mac starts"))
                    .font(Typo.bodySmall)
                    .foregroundStyle(palette.t1)
            }
            .toggleStyle(.switch)
            // Until the query returns, flipping the switch would act on a state
            // we don't know yet.
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

            Text(L("The app uses the modern API (system Login Items) when it can. Since this build is ad-hoc signed, registration may be refused — it then falls back to a user LaunchAgent, which works the same. The text above says which mechanism is active."))
                .font(Typo.monoTiny)
                .foregroundStyle(palette.t3)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: $prefs.hideDockIcon) {
                Text(L("Hide the Dock icon"))
                    .font(Typo.bodySmall)
                    .foregroundStyle(palette.t1)
            }
            .toggleStyle(.switch)
            .padding(.top, 4)

            Text(L("With the icon hidden the app lives only in the menu bar. Worth it if you leave it open all the time. Applies immediately, no restart."))
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

    // MARK: - Menu bar

    private var menuBarSection: some View {
        section(L("Menu bar"), "menubar.rectangle") {
            if MenuBarFeature.isEnabled {
                Toggle(isOn: $prefs.showMenuBar) {
                    Text(L("Show in the menu bar"))
                        .font(Typo.bodySmall)
                        .foregroundStyle(palette.t1)
                }
                .toggleStyle(.switch)

                Text(L("With this on, the app shows the chosen metric next to the clock and the panel opens with one click, without bringing up the window."))
                    .font(Typo.monoTiny)
                    .foregroundStyle(palette.t3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(L("Turned off by the emergency switch."))
                    .font(Typo.bodySmall)
                    .foregroundStyle(palette.warn)
                // The command stays out of the translation on purpose: it is a
                // Terminal literal, and translating part of it would produce a
                // command that doesn't run.
                Text(L("The `enableMenuBar` key is false, or the app is in safe mode. To turn it back on, in Terminal:")
                     + "\ndefaults write br.com.pentagrama.savemymac enableMenuBar -bool true\n"
                     + L("then reopen the app."))
                    .font(Typo.monoTiny)
                    .foregroundStyle(palette.t3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L("What to show next to the icon"))
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

            Text(L("The icon turns into a warning triangle when free space drops below the threshold, whatever metric you picked."))
                .font(Typo.monoTiny)
                .foregroundStyle(palette.t3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Alerts

    private var alertsSection: some View {
        section(L("Low space alert"), "exclamationmark.triangle") {
            Toggle(isOn: Binding(
                get: { prefs.lowSpaceAlerts },
                set: { value in
                    prefs.lowSpaceAlerts = value
                    if value { spaceAlert.requestPermissionIfNeeded() }
                }
            )) {
                Text(L("Notify me when space runs low"))
                    .font(Typo.bodySmall)
                    .foregroundStyle(palette.t1)
            }
            .toggleStyle(.switch)

            if spaceAlert.permissionDenied {
                Text(L("Notification permission was denied. Allow it in System Settings › Notifications. The menu bar warning keeps working."))
                    .font(Typo.caption)
                    .foregroundStyle(palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L("Warn below"))
                        .font(Typo.caption)
                        .foregroundStyle(palette.t2)
                    Spacer()
                    Text(L("%d %% free", Int(prefs.lowSpaceThreshold)))
                        .font(Typo.monoCaption)
                        .foregroundStyle(palette.t1)
                }
                Slider(value: $prefs.lowSpaceThreshold, in: 3...30, step: 1)
                    .disabled(!prefs.lowSpaceAlerts)

                if let volume = state.bootVolume, volume.total > 0 {
                    let free = Double(volume.available) / Double(volume.total) * 100
                    Text(L("Now: %@ %% free on %@ (%@).",
                           String(format: "%.1f", free),
                           volume.name,
                           Fmt.bytes(volume.available)))
                        .font(Typo.monoTiny)
                        .foregroundStyle(palette.t3)
                }
            }

            Text(L("The warning fires when crossing the threshold and only rearms after space rises 3 points above it, at most one every 6 hours. Without that, a disk hovering around the threshold would notify endlessly."))
                .font(Typo.monoTiny)
                .foregroundStyle(palette.t3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        section(L("Appearance"), "paintbrush") {
            Picker("", selection: Binding(
                get: { state.theme },
                set: { state.theme = $0 }
            )) {
                ForEach(ThemeMode.allCases, id: \.self) { mode in
                    Text(mode == .dark ? L("Dark") : L("Light")).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
    }

    // MARK: - Language

    private var languageSection: some View {
        section(L("Language"), "globe") {
            Picker("", selection: Binding(
                get: { loc.language },
                set: { loc.language = $0 }
            )) {
                ForEach(Language.allCases) { language in
                    // Each language's name appears **in its own language**.
                    // Someone who opened the app in a language they don't read
                    // needs to recognise theirs in the list, and for that
                    // "Français" works and "French" does not.
                    Text(language.label).tag(language)
                }
            }
            .pickerStyle(.radioGroup)

            if loc.language == .system {
                Text(L("Following macOS: %@", loc.language.resolved.label))
                    .font(Typo.monoTiny)
                    .foregroundStyle(palette.t3)
            }

            Text(L("The interface language. \"Same as macOS\" follows your system setting; anything else overrides it. Applies immediately."))
                .font(Typo.monoTiny)
                .foregroundStyle(palette.t3)
                .fixedSize(horizontal: false, vertical: true)

            Text(L("Numbers, sizes and dates always follow your system region, not this setting."))
                .font(Typo.monoTiny)
                .foregroundStyle(palette.t3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Structure

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
