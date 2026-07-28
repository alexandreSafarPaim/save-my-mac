import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var state: AppState
    @Binding var selection: AppSection
    @State private var showFactors = false

    private var palette: Palette { state.palette }
    /// 420 de mínimo: abaixo disso o hero (anel de 150 + texto + dois botões)
    /// fica apertado, então numa janela estreita ele passa a ocupar a linha toda.
    private let wideColumns = [GridItem(.adaptive(minimum: 420, maximum: 700), spacing: 18)]
    private let metricColumns = [GridItem(.adaptive(minimum: 250, maximum: 460), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                LazyVGrid(columns: wideColumns, spacing: 18) {
                    heroCard
                    achievementsCard
                }

                LazyVGrid(columns: metricColumns, spacing: 16) {
                    memoryCard
                    cpuCard
                    thermalCard
                    storageCard
                }

                LazyVGrid(columns: wideColumns, spacing: 18) {
                    processesCard
                    historyCard
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 34)
            .riseIn()
        }
    }

    // MARK: - Cabeçalho

    private var header: some View {
        ScreenHeader(
            eyebrow: "Painel do sistema",
            title: state.system.modelName,
            subtitle: "\(state.system.modelIdentifier) · \(Fmt.bytes(state.system.totalMemory)) de RAM · \(state.system.osVersion)",
            palette: palette,
            large: true
        ) {
            VStack(alignment: .trailing, spacing: 3) {
                Text("Ligado há \(Fmt.duration(state.system.uptime))")
                    .font(Typo.monoCaption)
                    .foregroundStyle(palette.t2)
                HStack(spacing: 6) {
                    LiveDot(palette: palette)
                    Text("ao vivo · 2 s")
                        .font(Typo.monoTiny)
                        .foregroundStyle(palette.t3)
                }
            }
        }
    }

    // MARK: - Hero: score de saúde

    private var heroCard: some View {
        HeroPanel(palette: palette) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 22) {
                    ScoreRing(score: state.health.score, palette: palette)
                        .frame(width: 140, height: 140)
                        .layoutPriority(-1)

                    VStack(alignment: .leading, spacing: 12) {
                        Text(state.health.headline)
                            .font(Typo.ui(19, .semibold))
                            .foregroundStyle(palette.t1)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(heroDetail)
                            .font(Typo.bodySmall)
                            .foregroundStyle(palette.t2)
                            .fixedSize(horizontal: false, vertical: true)

                        FlowLayout(spacing: 10, lineSpacing: 10) {
                            PrimaryButton(
                                title: state.categories.isEmpty ? "Analisar o Mac" : "Limpar agora",
                                palette: palette
                            ) {
                                if state.categories.isEmpty {
                                    state.startScan()
                                }
                                selection = .cleanup
                            }
                            GhostButton(title: "Ver o que ocupa espaço", palette: palette) {
                                if state.files.isEmpty { state.startFilesScan() }
                                selection = .files
                            }
                        }
                    }
                }

                Divider().overlay(palette.stroke)

                Button {
                    showFactors.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showFactors ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                        Text("Como esse número é calculado")
                            .font(Typo.caption)
                    }
                    .foregroundStyle(palette.t2)
                }
                .buttonStyle(.plain)

                if showFactors {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("O score é do próprio app, não do macOS. Cada fator entra com um peso:")
                            .font(Typo.caption)
                            .foregroundStyle(palette.t3)
                            .fixedSize(horizontal: false, vertical: true)

                        ForEach(state.health.factors) { factor in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(Int(factor.weight))")
                                    .font(Typo.monoTiny)
                                    .frame(width: 22, alignment: .trailing)
                                    .foregroundStyle(palette.t3)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(factor.name)
                                        .font(Typo.caption)
                                        .foregroundStyle(palette.t1)
                                    Text(factor.detail)
                                        .font(Typo.monoTiny)
                                        .foregroundStyle(palette.t2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 8)
                                Text(Fmt.percent(factor.quality))
                                    .font(Typo.monoTiny)
                                    .foregroundStyle(
                                        factor.quality < 0.5 ? palette.danger
                                            : factor.quality < 0.8 ? palette.warn : palette.ok
                                    )
                            }
                        }
                    }
                }
            }
        }
    }

    private var heroDetail: String {
        if state.categories.isEmpty {
            return "Nenhuma análise feita ainda. Uma varredura completa leva menos de um minuto e não apaga nada."
        }
        let count = state.categories.count
        return "Encontramos \(Fmt.bytes(state.totalReclaimable)) de lixo recuperável em \(count) categoria\(count == 1 ? "" : "s")."
    }

    // MARK: - Conquistas

    private var achievementsCard: some View {
        Panel(palette: palette) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Conquistas")
                        .font(Typo.cardTitle)
                        .foregroundStyle(palette.t1)
                    Spacer()
                    Text("\(state.game.state.unlocked.count) / \(Achievements.all.count)")
                        .font(Typo.monoCaption)
                        .foregroundStyle(palette.t3)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach(Achievements.all) { achievement in
                        let unlocked = state.game.isUnlocked(achievement.id)
                        ZStack {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(palette.card2)
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(
                                    unlocked ? palette.accent.opacity(0.5) : palette.stroke,
                                    lineWidth: 1
                                )
                            Image(systemName: achievement.symbol)
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(unlocked ? palette.t1 : palette.t3)
                        }
                        .aspectRatio(1, contentMode: .fit)
                        .opacity(unlocked ? 1 : 0.32)
                        .help("\(achievement.name) — \(achievement.requirement)")
                    }
                }

                Divider().overlay(palette.stroke)

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Meta do mês · \(Fmt.bytes(state.game.state.monthlyGoalBytes))")
                            .font(Typo.caption)
                            .foregroundStyle(palette.t2)
                        Spacer()
                        Text("\(Fmt.bytes(state.game.state.freedThisMonth)) / \(Fmt.bytes(state.game.state.monthlyGoalBytes))")
                            .font(Typo.monoCaption)
                            .foregroundStyle(palette.t1)
                    }
                    GradientBar(
                        value: state.game.state.monthlyGoalProgress,
                        palette: palette,
                        height: 7,
                        tint: palette.gradientOk
                    )
                }
            }
        }
    }

    // MARK: - Métricas

    private var memoryCard: some View {
        Panel(palette: palette, cornerRadius: 18, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    MicroLabel(text: "Memória", palette: palette)
                    Spacer()
                    Text(Fmt.bytes(state.memory.total))
                        .font(Typo.monoCaption)
                        .foregroundStyle(palette.t2)
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.0f", state.memory.usedFraction * 100))
                        .font(Typo.metricValue)
                        .tracking(-1.1)
                        .foregroundStyle(palette.t1)
                    Text("%")
                        .font(Typo.mono(14))
                        .foregroundStyle(palette.t3)
                }

                GradientBar(value: state.memory.usedFraction, palette: palette)

                VStack(alignment: .leading, spacing: 5) {
                    StatRow(key: "Disponível", value: Fmt.bytes(state.memory.available), palette: palette)
                    StatRow(key: "Em uso", value: Fmt.bytes(state.memory.used), palette: palette)
                    StatRow(key: "Pressão", value: state.memory.pressureLabel, palette: palette)
                    StatRow(
                        key: "Swap",
                        value: state.swap.used == 0 ? "não usado" : Fmt.bytes(state.swap.used),
                        palette: palette
                    )
                }

                Divider().overlay(palette.stroke)

                // A pressão ao longo do tempo responde a pergunta que o número
                // instantâneo não responde: preciso de mais RAM ou não?
                MicroLabel(text: "Pressão de memória", palette: palette)
                PressureChart(values: state.memoryHistory.pressureCurve, palette: palette)

                Text(state.memoryHistory.verdict ?? "Coletando amostras…")
                    .font(Typo.monoTiny)
                    .foregroundStyle(palette.t3)
                    .fixedSize(horizontal: false, vertical: true)

                Text("No macOS, RAM livre é RAM desperdiçada: o sistema usa a sobra como cache de disco. O que importa é esta curva, não o percentual.")
                    .font(Typo.monoTiny)
                    .foregroundStyle(palette.t3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var cpuCard: some View {
        MetricCard(
            label: "Processador",
            tag: shortChip,
            value: String(format: "%.0f", state.cpu.busy * 100),
            unit: "%",
            fraction: state.cpu.busy,
            rows: [
                ("Núcleos", coreDescription),
                ("Load average", String(format: "%.2f", state.cpu.loadAverage.first ?? 0)),
                ("Processos", "\(state.cpu.processCount)"),
                ("Sistema / usuário", "\(Fmt.percent(state.cpu.system)) / \(Fmt.percent(state.cpu.user))")
            ],
            palette: palette
        )
    }

    private var shortChip: String {
        let chip = state.system.chip
        if chip.contains("Apple") { return chip }
        return String(chip.prefix(22))
    }

    private var coreDescription: String {
        let info = state.system
        if info.performanceCores > 0 && info.efficiencyCores > 0 {
            return "\(info.logicalCores) (\(info.performanceCores)P + \(info.efficiencyCores)E)"
        }
        return "\(info.logicalCores) / \(info.physicalCores) físicos"
    }

    private var thermalCard: some View {
        Panel(palette: palette, cornerRadius: 18, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    MicroLabel(text: "Temperatura", palette: palette)
                    Spacer()
                    Text(state.thermal.sensors.isEmpty ? state.thermal.thermalStateLabel : "\(state.thermal.sensors.count) sensores")
                        .font(Typo.monoCaption)
                        .foregroundStyle(palette.t2)
                }

                if let temp = state.thermal.displayTemperature {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(String(format: "%.0f", temp))
                            .font(Typo.metricValue)
                            .tracking(-1.1)
                            .foregroundStyle(palette.temperatureTint(temp))
                        Text("°C")
                            .font(Typo.mono(14))
                            .foregroundStyle(palette.t3)
                    }
                    GradientBar(
                        value: (temp / 100).clamped(0, 1),
                        palette: palette,
                        tint: LinearGradient(
                            colors: [palette.ok, palette.warn, palette.danger],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                } else {
                    Text(state.thermal.thermalStateLabel)
                        .font(Typo.ui(24, .bold))
                        .foregroundStyle(palette.t1)
                    GradientBar(value: 0, palette: palette)
                }

                VStack(alignment: .leading, spacing: 5) {
                    StatRow(key: "Estado térmico", value: state.thermal.thermalStateLabel, palette: palette)
                    if let cpu = state.thermal.cpuTemperature {
                        StatRow(key: "CPU / SoC", value: Fmt.celsius(cpu), palette: palette)
                    }
                    if let battery = state.thermal.batteryTemperature {
                        StatRow(key: "Bateria", value: Fmt.celsius(battery), palette: palette)
                    }
                    if !state.thermal.fans.isEmpty {
                        StatRow(
                            key: state.thermal.fans.count > 1 ? "Ventoinhas" : "Ventoinha",
                            value: state.thermal.fans.map { "\($0) rpm" }.joined(separator: " / "),
                            palette: palette
                        )
                    }
                }

                if state.thermal.cpuTemperature == nil {
                    Button {
                        state.readTemperatureElevated()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "lock.open")
                                .font(.system(size: 9))
                            Text("Ler sensores com senha de admin")
                                .font(Typo.monoTiny)
                        }
                        .foregroundStyle(palette.cyan)
                    }
                    .buttonStyle(.plain)
                    .help("Executa powermetrics uma vez. O macOS pedirá sua senha.")
                }
            }
        }
    }

    private var storageCard: some View {
        Panel(palette: palette, cornerRadius: 18, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    MicroLabel(text: "Armazenamento", palette: palette)
                    Spacer()
                    Text("\(state.volumes.count) volume\(state.volumes.count == 1 ? "" : "s")")
                        .font(Typo.monoCaption)
                        .foregroundStyle(palette.t2)
                }

                if let boot = state.bootVolume {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(String(format: "%.0f", boot.usedFraction * 100))
                            .font(Typo.metricValue)
                            .tracking(-1.1)
                            .foregroundStyle(palette.usageTint(boot.usedFraction))
                        Text("%")
                            .font(Typo.mono(14))
                            .foregroundStyle(palette.t3)
                    }
                    GradientBar(value: boot.usedFraction, palette: palette)
                }

                VStack(alignment: .leading, spacing: 5) {
                    ForEach(state.volumes) { volume in
                        StatRow(
                            key: volume.name,
                            value: "\(Fmt.bytes(volume.used)) / \(Fmt.bytes(volume.total))",
                            palette: palette,
                            valueColor: volume.usedFraction > 0.9 ? palette.danger : nil
                        )
                    }
                }

                if state.offload.savedBytes > 0 {
                    HStack(spacing: 5) {
                        Image(systemName: "link")
                            .font(.system(size: 9))
                        Text("\(Fmt.bytes(state.offload.savedBytes)) fora do disco do Mac")
                            .font(Typo.monoTiny)
                    }
                    .foregroundStyle(palette.cyan)
                }

                if !state.trash.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "trash")
                            .font(.system(size: 9))
                        Text("\(Fmt.bytes(state.trash.totalBytes)) parados na Lixeira")
                            .font(Typo.monoTiny)
                    }
                    .foregroundStyle(palette.warn)
                }
            }
        }
    }

    // MARK: - Processos

    private var processesCard: some View {
        Panel(palette: palette) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Quem está consumindo")
                        .font(Typo.cardTitle)
                        .foregroundStyle(palette.t1)
                    Spacer()
                    if !state.topByCPU.isEmpty {
                        Text("\(state.cpu.processCount) processos")
                            .font(Typo.monoTiny)
                            .foregroundStyle(palette.t3)
                    }
                }

                if state.topByCPU.isEmpty && state.topByMemory.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "hourglass")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.t3)
                        Text(state.processFailure ?? "Lendo a lista de processos…")
                            .font(Typo.caption)
                            .foregroundStyle(state.processFailure == nil ? palette.t3 : palette.warn)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !state.topByMemory.isEmpty {
                    MicroLabel(text: "Por memória", palette: palette)
                    VStack(spacing: 0) {
                        ForEach(state.topByMemory.prefix(6)) { row in
                            processRow(row, value: Fmt.bytes(row.memoryBytes))
                        }
                    }
                }

                if !state.topByCPU.isEmpty {
                    MicroLabel(text: "Por CPU", palette: palette)
                        .padding(.top, 4)
                    VStack(spacing: 0) {
                        ForEach(state.topByCPU.prefix(6)) { row in
                            processRow(row, value: String(format: "%.1f%%", row.cpuPercent))
                        }
                    }
                }

                Text("Encerrar pede ao app para sair, e ele pode perguntar sobre trabalho não salvo. Forçar só com confirmação.")
                    .font(Typo.monoTiny)
                    .foregroundStyle(palette.t3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func processRow(_ row: ProcessInfoRow, value: String) -> some View {
        HStack(spacing: 9) {
            if let bundle = row.bundlePath {
                AppIconView(path: bundle, size: 18)
            } else {
                Image(systemName: "gearshape")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.t3)
                    .frame(width: 18)
            }

            Text(row.name)
                .font(Typo.bodySmall)
                .foregroundStyle(palette.t1)
                .lineLimit(1)
                .truncationMode(.middle)

            if let extra = state.growthAmount(row) {
                Chip(text: "+\(Fmt.bytes(extra))", palette: palette, color: palette.warn)
                    .help("Cresceu \(Fmt.bytes(extra)) desde que o app começou a observar. Pode ser vazamento.")
            }

            Spacer(minLength: 6)

            Text(value)
                .font(Typo.monoCaption)
                .foregroundStyle(palette.t1)

            Menu {
                if let reason = state.quitReason(row) {
                    Text(reason)
                } else {
                    if let warning = state.quitWarning(row) {
                        Text(warning)
                        Divider()
                    }
                    Button("Pedir para encerrar") { state.requestQuit(row) }
                    Button("Forçar encerramento…", role: .destructive) {
                        state.pendingForceQuit = row
                    }
                }
                Divider()
                Text("pid \(row.pid)")
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(state.canQuit(row) ? palette.t2 : palette.t3.opacity(0.5))
            }
            .menuIndicator(.hidden)
            .frame(width: 24)
            .disabled(!state.canQuit(row))
        }
        .padding(.vertical, 4)
    }

    // MARK: - Histórico

    private var historyCard: some View {
        Panel(palette: palette) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Histórico")
                        .font(Typo.cardTitle)
                        .foregroundStyle(palette.t1)
                    Spacer()
                    Text("\(Fmt.bytes(state.game.state.totalFreedBytes)) no total")
                        .font(Typo.monoCaption)
                        .foregroundStyle(palette.ok)
                }

                if state.game.state.history.isEmpty {
                    Text("Nada registrado ainda. Cada limpeza, cache removido ou app desinstalado entra aqui com data e tamanho real.")
                        .font(Typo.caption)
                        .foregroundStyle(palette.t3)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(state.game.state.history.prefix(8)) { record in
                            HStack(spacing: 10) {
                                Text(record.kind)
                                    .font(Typo.monoTiny)
                                    .foregroundStyle(palette.t3)
                                    .frame(width: 86, alignment: .leading)
                                Text(Fmt.shortDate(record.date))
                                    .font(Typo.monoTiny)
                                    .foregroundStyle(palette.t2)
                                Spacer(minLength: 8)
                                Text(Fmt.bytes(record.bytes))
                                    .font(Typo.monoCaption)
                                    .foregroundStyle(palette.t1)
                            }
                        }
                    }
                }
            }
        }
    }
}
