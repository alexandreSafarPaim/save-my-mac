import SwiftUI
import AppKit

/// The panel that opens when you click the menu bar icon.
///
/// It is not a smaller copy of the Dashboard: it shows only what can be answered
/// at a glance — space, memory pressure, CPU and temperature — and links out for
/// the rest.
struct MenuBarPanel: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: Preferences
    @EnvironmentObject var spaceAlert: SpaceAlert
    @EnvironmentObject var loc: Localization

    /// The correct way to bring the window back on macOS 13. An
    /// `NSApp.sendAction` for "new window" does not recreate the scene.
    @Environment(\.openWindow) private var openWindow

    private var palette: Palette { state.palette }

    private var isLow: Bool {
        spaceAlert.isLow(volume: state.bootVolume, thresholdPercent: prefs.lowSpaceThreshold)
    }

    @ViewBuilder
    var body: some View {
        // Inert when the feature is off: without this the panel would keep
        // reading state on every update despite never being shown.
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
        .id(loc.language)
        .preferredColorScheme(state.theme.colorScheme)
    }

    // MARK: - Header

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
                Text(L("Health").uppercased())
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
                Text(L("Low disk space"))
                    .font(Typo.ui(12, .semibold))
                    .foregroundStyle(palette.t1)
                if let volume = state.bootVolume {
                    Text(L("%@ free — below the %d %% threshold", Fmt.bytes(volume.available), Int(prefs.lowSpaceThreshold)))
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

    // MARK: - Metrics

    private var metrics: some View {
        VStack(spacing: 10) {
            if let volume = state.bootVolume {
                metricRow(
                    symbol: "internaldrive",
                    label: volume.name,
                    value: L("%@ free", Fmt.bytes(volume.available)),
                    fraction: volume.usedFraction,
                    tint: palette.usageTint(volume.usedFraction)
                )
            }

            metricRow(
                symbol: "memorychip",
                label: L("Memory"),
                value: state.memory.pressureLabel,
                fraction: state.memory.pressureFraction,
                tint: palette.usageTint(state.memory.pressureFraction)
            )

            metricRow(
                symbol: "cpu",
                label: L("Processor"),
                value: Fmt.percent(state.cpu.busy),
                fraction: state.cpu.busy,
                tint: palette.usageTint(state.cpu.busy)
            )

            if let temp = state.thermal.displayTemperature {
                metricRow(
                    symbol: "thermometer.medium",
                    label: L("Temperature"),
                    value: Fmt.celsius(temp),
                    fraction: (temp / 100).clamped(0, 1),
                    tint: palette.temperatureTint(temp)
                )
            } else {
                metricRow(
                    symbol: "thermometer.medium",
                    label: L("Thermal state"),
                    value: state.thermal.thermalStateLabel,
                    fraction: 0,
                    tint: palette.t3
                )
            }

            if state.trash.totalBytes > 0 {
                metricRow(
                    symbol: "trash",
                    label: L("Trash"),
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

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 4) {
            action(L("Open SaveMyMac"), "square.grid.2x2") { show(.dashboard) }
            action(L("Analyze my Mac"), "magnifyingglass") {
                state.startScan()
                show(.cleanup)
            }
            if !state.trash.isEmpty {
                action(L("Empty the Trash (%@)", Fmt.bytes(state.trash.totalBytes)), "trash") {
                    show(.cleanup)
                }
            }
            action(L("Large files"), "square.stack.3d.up") { show(.files) }
            action(L("Offload"), "link") { show(.offload) }

            Divider().overlay(palette.stroke).padding(.vertical, 3)

            settingsAction
            action(L("Quit SaveMyMac"), "power") { NSApp.terminate(nil) }
        }
    }

    /// `SettingsOpener` handles *how* to open; all that goes here is the row's
    /// appearance, which is the same as its neighbours'.
    private var settingsAction: some View {
        SettingsOpener {
            actionRow(L("Settings…"), "gearshape")
        }
        .buttonStyle(MenuRowButtonStyle(palette: palette))
    }

    /// Brings the window forward and takes it to the requested tab.
    ///
    /// Does not touch the activation policy: if the user hid the Dock icon, the
    /// app stays `.accessory` and still shows a window — bringing the icon back
    /// here would undo their preference behind their back.
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

    /// A row's visual content, separated from the `Button`.
    ///
    /// It exists because the settings opener needs the same label without a
    /// button wrapped around it. Without that separation, the Settings row would
    /// look different from all the others.
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

/// Menu row highlight — `.plain` gives no hover feedback at all.
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

// MARK: - Label next to the clock

/// What appears in the menu bar. Kept tiny on purpose: the bar is shared space
/// and a maintenance app should not dominate it.
struct MenuBarLabel: View {
    @ObservedObject var state: AppState
    @ObservedObject var prefs: Preferences
    @ObservedObject var spaceAlert: SpaceAlert

    private var isLow: Bool {
        spaceAlert.isLow(volume: state.bootVolume, thresholdPercent: prefs.lowSpaceThreshold)
    }

    @ViewBuilder
    var body: some View {
        // Kept minimal on purpose. Apple documents limited support for views in
        // a MenuBarExtra label, and it re-renders on every 2 s tick — anything
        // heavier here costs all day long.
        //
        // The counter is this feature's safety net. It observes `AppState`, which
        // publishes several times per tick; if that ever becomes a cycle again,
        // the number shows up in the trace before the app stops responding. In
        // normal use it should grow slowly.
        let _ = Trace.count("menu bar label", every: 300)

        if !MenuBarFeature.isEnabled {
            EmptyView()
        } else if let text = valueText {
            // `.titleAndIcon` is mandatory here.
            //
            // A `Label` in a status bar item uses only the icon by default — the
            // title is dropped with no warning. The item did appear, but as a
            // lone `sparkle` among six other icons, which is indistinguishable
            // from "it didn't appear".
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
