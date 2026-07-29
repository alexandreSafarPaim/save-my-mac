import Foundation
import SwiftUI
import AppKit
import Combine

@MainActor
final class AppState: ObservableObject {

    init() {
        // `GameStore` é um ObservableObject aninhado: sem repassar o sinal, as
        // views que leem XP, nível e conquistas não recarregariam.
        game.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Métricas ao vivo

    @Published var system = SystemInfoSnapshot()
    @Published var memory = MemorySnapshot()
    @Published var swap = SwapSnapshot()
    @Published var cpu = CPUSnapshot()
    @Published var volumes: [VolumeInfo] = []
    @Published var battery = BatterySnapshot()
    @Published var thermal = ThermalSnapshot()
    @Published var topByCPU: [ProcessInfoRow] = []
    @Published var topByMemory: [ProcessInfoRow] = []
    /// Motivo pelo qual a lista de processos está vazia, quando está.
    @Published var processFailure: String?
    @Published var memoryHistory = MemoryHistory()
    private var growth = GrowthTracker()
    /// Processo aguardando confirmação de encerramento forçado.
    @Published var pendingForceQuit: ProcessInfoRow?

    /// Aba pedida de fora (pelo painel da barra de menus). A janela consome e
    /// zera.
    @Published var requestedSection: AppSection?

    // MARK: - Aparência

    @Published var theme: ThemeMode = .dark {
        didSet { game.setTheme(theme) }
    }

    var palette: Palette { Palette.of(theme) }

    // MARK: - Saúde e progresso

    @Published var health = HealthReport(score: 0, factors: [])
    let game = GameStore()

    // MARK: - Limpeza

    @Published var categories: [CleanupCategory] = []
    @Published var selectedItemIDs: Set<UUID> = []
    @Published var isScanning = false
    @Published var scanProgress: Double = 0
    @Published var scanStatus = ""
    @Published var lastScanDate: Date?

    @Published var isRemoving = false
    @Published var removeProgress: Double = 0
    @Published var removeStatus = ""
    @Published var cleanupMode: CleanupMode = .trash

    @Published var trash = TrashInfo()
    @Published var isEmptyingTrash = false
    // Progresso próprio: compartilhar `removeProgress` com a limpeza fazia um
    // card mostrar o status do outro.
    @Published var trashProgress: Double = 0
    @Published var trashStatus = ""

    // MARK: - Arquivos grandes e duplicados

    @Published var files = FileScanResult()
    @Published var isScanningFiles = false
    @Published var filesProgress: Double = 0
    @Published var filesStatus = ""
    @Published var lastFilesScanDate: Date?
    @Published var selectedDuplicateIDs: Set<UUID> = []

    // MARK: - Aplicativos

    @Published var appInventory = AppInventoryResult()
    @Published var isScanningApps = false
    @Published var appsProgress: Double = 0
    @Published var appsStatus = ""
    @Published var lastAppsScanDate: Date?
    @Published var appFilter: AppFilter = .all
    @Published var appSearch = ""

    // MARK: - Offload

    @Published var offload = OffloadInventory()
    @Published var isScanningOffload = false
    @Published var offloadProgress: Double = 0
    @Published var offloadStatus = ""
    @Published var lastOffloadScanDate: Date?

    @Published var candidates: [OffloadCandidate] = []
    @Published var journal = MigrationJournal()
    @Published var destinationRoot: String = ""

    @Published var isMigrating = false
    @Published var migrationProgress: Double = 0
    @Published var migrationStatus = ""
    @Published var migrationPhase: MigrationPhase = .preflight

    // MARK: - Diálogos

    @Published var celebration: Celebration?
    @Published var banner: Banner?

    struct Celebration: Identifiable {
        let id = UUID()
        var bytes: Int64
        var xp: Int
        var score: Int
        var title: String
        var unlocked: [Achievement]
        /// Quando o destino foi a Lixeira, o espaço só volta ao esvaziá-la —
        /// e a interface precisa dizer isso em vez de "liberados".
        var wentToTrash: Bool = false
    }

    struct Banner: Identifiable {
        let id = UUID()
        var text: String
        var isError: Bool
    }

    enum AppFilter: String, CaseIterable, Identifiable {
        case all
        case stale
        case heavyCache

        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return L("All")
            case .stale: return L("Unused for 90 d")
            case .heavyCache: return L("Heavy cache")
            }
        }
    }

    // MARK: - Internos

    private let cpuMonitor = CPUMonitor()
    private var timer: Timer?
    private var tick = 0
    // Travas de reentrância do trabalho caro — ver `refreshMetrics()`.
    private var volumesBusy = false
    private var thermalBusy = false
    private var processesBusy = false
    private let cancelFlag = CancellationFlag()
    private let offloadCancelFlag = CancellationFlag()
    private let filesCancelFlag = CancellationFlag()
    private let appsCancelFlag = CancellationFlag()
    private let engine = MigrationEngine()
    private weak var preferences: Preferences?
    private weak var spaceAlert: SpaceAlert?
    private let queue = DispatchQueue(label: "br.com.pentagrama.savemymac.work", qos: .userInitiated)
    private static let destinationKey = "offloadDestinationRoot"

    // MARK: - Derivados

    var selectedItems: [CleanupItem] {
        categories.flatMap(\.items).filter { selectedItemIDs.contains($0.id) }
    }

    var selectedSize: Int64 {
        selectedItems.reduce(0) { $0 + $1.size }
    }

    var selectedCategoryCount: Int {
        categories.filter { category in
            category.items.contains { selectedItemIDs.contains($0.id) }
        }.count
    }

    var totalReclaimable: Int64 {
        categories.reduce(0) { $0 + $1.totalSize }
    }

    var bootVolume: VolumeInfo? {
        volumes.first { $0.path == "/" } ?? volumes.first
    }

    var selectedDuplicates: [DuplicateCopy] {
        files.duplicates
            .filter { selectedDuplicateIDs.contains($0.id) }
            .flatMap(\.removable)
    }

    var selectedDuplicateSize: Int64 {
        files.duplicates
            .filter { selectedDuplicateIDs.contains($0.id) }
            .reduce(0) { $0 + $1.reclaimable }
    }

    var filteredApps: [InstalledApp] {
        var list = appInventory.apps
        switch appFilter {
        case .all: break
        case .stale: list = list.filter(\.isStale)
        case .heavyCache: list = list.filter { $0.cacheSize > 100 * 1024 * 1024 }
        }
        let query = appSearch.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            list = list.filter {
                $0.name.lowercased().contains(query) || $0.bundleID.lowercased().contains(query)
            }
        }
        return list
    }

    var destinationURL: URL? {
        destinationRoot.isEmpty ? nil : URL(fileURLWithPath: destinationRoot)
    }

    /// Volume de destino sugerido: o maior volume externo com espaço.
    var suggestedDestinationVolume: VolumeInfo? {
        volumes.first { $0.path != "/" && $0.available > 10 * 1_073_741_824 }
    }

    // MARK: - Ciclo de vida

    func start() {
        guard timer == nil else { return }
        Trace.mark("AppState.start")
        theme = game.state.theme
        destinationRoot = UserDefaults.standard.string(forKey: AppState.destinationKey) ?? ""
        Trace.span("SystemInfo.read") { system = SystemInfo.read() }
        Trace.span("engine.loadJournal") { journal = engine.loadJournal() }
        // Uma leitura síncrona só no lançamento, para a janela já abrir com o
        // disco preenchido. Depois disso os volumes são sempre lidos fora da
        // thread principal.
        Trace.span("DiskMonitor.volumes (lançamento)") { volumes = DiskMonitor.volumes() }
        refreshMetrics()
        Trace.span("refreshTrash") { refreshTrash() }
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshMetrics() }
        }
        Trace.mark("AppState.start concluído")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Liga as preferências e o alerta de espaço ao ciclo de métricas.
    /// Feito por injeção em vez de `AppState` criar os dois, para que a cena de
    /// Ajustes e a da barra de menus compartilhem exatamente as mesmas
    /// instâncias.
    func attach(preferences: Preferences, spaceAlert: SpaceAlert) {
        self.preferences = preferences
        self.spaceAlert = spaceAlert
        // A permissão NÃO é pedida aqui.
        //
        // `UNUserNotificationCenter.current()` exige um bundle registrado e
        // assinado; num app ad-hoc rodando de um caminho qualquer ele pode
        // lançar exceção ou bloquear. Fazer isso no caminho de lançamento
        // significa travar antes de a janela existir. Agora só acontece quando
        // o usuário liga a opção em Ajustes, que é quando ele está esperando
        // um diálogo de permissão de qualquer forma.
    }

    func toggleTheme() {
        theme = theme.toggled
    }

    // MARK: - Métricas

    /// Um tique de métricas.
    ///
    /// Nem tudo aqui custa a mesma coisa, e antes tudo rodava na mesma cadência
    /// de 2 segundos. As três correções:
    ///
    /// 1. **Cadências separadas.** Memória e CPU são leituras de contador do
    ///    kernel e podem ser lidas a 2 s. Enumerar volumes, ler sensores e
    ///    rodar o `/bin/ps` são ordens de grandeza mais caros e não mudam nesse
    ///    ritmo — passam a cada 6 s.
    /// 2. **Volumes saem da thread principal.** `mountedVolumeURLs` toca todo
    ///    disco montado. Com um SSD externo que entra em repouso, essa chamada
    ///    bloqueia — e bloquear ali é congelar a janela.
    /// 3. **Trabalho pesado não se acumula.** As tarefas destacadas eram
    ///    disparadas sem nenhuma trava: se uma demorasse mais que o intervalo,
    ///    a próxima começava por cima. Sob carga isso vira crescimento sem
    ///    limite de threads e subprocessos. Agora cada uma tem um cadeado.
    func refreshMetrics() {
        defer { tick &+= 1 }

        // Barato, todo tique.
        Trace.mark("tique \(tick)")
        memory = MemoryMonitor.read()
        swap = MemoryMonitor.readSwap()
        memoryHistory.record(memory: memory, swap: swap)
        cpu = cpuMonitor.read()
        system.uptime = SystemInfo.uptimeSeconds()
        recomputeHealth()

        let heavyTick = tick % AppState.heavyEvery == 0
        guard heavyTick else { return }

        refreshVolumesAndBattery()
        refreshThermal()
        refreshProcesses()
    }

    /// Intervalo do timer é 2 s; o trabalho caro roda a cada 3 tiques (6 s).
    private static let heavyEvery = 3

    private func refreshVolumesAndBattery() {
        guard !volumesBusy else { return }
        volumesBusy = true
        Task.detached(priority: .utility) {
            let volumes = Trace.span("DiskMonitor.volumes") { DiskMonitor.volumes() }
            let battery = Trace.span("BatteryMonitor.read") { BatteryMonitor.read() }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.volumesBusy = false
                self.volumes = volumes
                self.battery = battery
                self.recomputeHealth()

                if let preferences = self.preferences, let spaceAlert = self.spaceAlert {
                    spaceAlert.evaluate(
                        volume: self.bootVolume,
                        thresholdPercent: preferences.lowSpaceThreshold,
                        enabled: preferences.lowSpaceAlerts
                    )
                }
            }
        }
    }

    /// Separada da leitura de processos de propósito. Estavam na mesma tarefa,
    /// com a térmica primeiro: como ela passa por API privada da Apple via
    /// `dlsym`, qualquer lentidão ali impedia a lista de processos de sequer
    /// rodar — e o card "Quem está consumindo" ficava permanentemente vazio.
    private func refreshThermal() {
        guard !thermalBusy else { return }
        thermalBusy = true
        Task.detached(priority: .utility) {
            let thermal = Trace.span("ThermalMonitor.read") { ThermalMonitor.read() }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.thermalBusy = false
                if self.thermal.source.contains("powermetrics") && thermal.cpuTemperature == nil {
                    self.thermal.thermalState = thermal.thermalState
                    self.thermal.batteryTemperature = thermal.batteryTemperature
                } else {
                    self.thermal = thermal
                }
                self.recomputeHealth()
            }
        }
    }

    private func refreshProcesses() {
        guard !processesBusy else { return }
        processesBusy = true
        Task.detached(priority: .utility) {
            let top = Trace.span("ProcessMonitor.top") { ProcessMonitor.top() }
            let failure = ProcessMonitor.lastFailure
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.processesBusy = false
                Trace.mark("enrich (\(top.byCPU.count + top.byMemory.count) linhas, MAIN)")
                // O crescimento é rastreado pelas linhas cruas (pid + bytes);
                // o enriquecimento com AppKit só vale para o que vai à tela.
                self.growth.update(with: top.byMemory + top.byCPU)
                self.topByCPU = ProcessMonitor.enrich(top.byCPU)
                self.topByMemory = ProcessMonitor.enrich(top.byMemory)
                self.processFailure = failure
            }
        }
    }

    func recomputeHealth() {
        health = HealthScore.evaluate(
            bootVolume: bootVolume,
            memory: memory,
            swap: swap,
            thermal: thermal,
            reclaimable: totalReclaimable,
            duplicateBytes: files.duplicateTotal,
            brokenLinks: offload.brokenCount
        )
    }

    func readTemperatureElevated() {
        Task.detached(priority: .userInitiated) {
            let snapshot = ThermalMonitor.readElevated()
            await MainActor.run { [weak self] in
                guard let self, let snapshot else { return }
                self.thermal = snapshot
                self.recomputeHealth()
            }
        }
    }

    // MARK: - Varredura de limpeza

    func startScan() {
        guard !isScanning else { return }
        isScanning = true
        cancelFlag.reset()
        scanProgress = 0
        scanStatus = "Preparando…"
        categories = []
        selectedItemIDs = []

        let flag = cancelFlag
        queue.async { [weak self] in
            let result = CleanupScanner().scan(
                progress: { status, fraction in
                    Task { @MainActor [weak self] in
                        self?.scanStatus = status
                        self?.scanProgress = fraction
                    }
                },
                isCancelled: { flag.isCancelled }
            )

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.categories = result
                self.isScanning = false
                self.scanProgress = 1
                self.lastScanDate = Date()
                self.scanStatus = flag.isCancelled ? "Cancelada" : L("Done")
                self.selectedItemIDs = Set(
                    result.filter { $0.risk == .safe }.flatMap(\.items).map(\.id)
                )
                self.recomputeHealth()
                self.refreshTrash()
            }
        }
    }

    func cancelScan() {
        cancelFlag.cancel()
        scanStatus = "Cancelando…"
    }

    // MARK: - Varredura de arquivos

    func startFilesScan() {
        guard !isScanningFiles else { return }
        isScanningFiles = true
        filesCancelFlag.reset()
        filesProgress = 0
        filesStatus = "Preparando…"
        selectedDuplicateIDs = []

        let flag = filesCancelFlag
        queue.async { [weak self] in
            let result = FileScanner().scan(
                progress: { status, fraction in
                    Task { @MainActor [weak self] in
                        self?.filesStatus = status
                        self?.filesProgress = fraction
                    }
                },
                isCancelled: { flag.isCancelled }
            )

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.files = result
                self.isScanningFiles = false
                self.filesProgress = 1
                self.lastFilesScanDate = Date()
                self.filesStatus = flag.isCancelled ? "Cancelada" : L("Done")
                self.recomputeHealth()
                self.game.evaluateAchievements(
                    score: self.health.score,
                    duplicateBytes: result.duplicateTotal,
                    offloadedBytes: nil
                )
            }
        }
    }

    func cancelFilesScan() {
        filesCancelFlag.cancel()
        filesStatus = "Cancelando…"
    }

    // MARK: - Varredura de apps

    func startAppsScan() {
        guard !isScanningApps else { return }
        isScanningApps = true
        appsCancelFlag.reset()
        appsProgress = 0
        appsStatus = "Preparando…"

        let flag = appsCancelFlag
        queue.async { [weak self] in
            let result = AppInventoryScanner().scan(
                progress: { status, fraction in
                    Task { @MainActor [weak self] in
                        self?.appsStatus = status
                        self?.appsProgress = fraction
                    }
                },
                isCancelled: { flag.isCancelled }
            )

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.appInventory = result
                self.isScanningApps = false
                self.appsProgress = 1
                self.lastAppsScanDate = Date()
                self.appsStatus = flag.isCancelled ? "Cancelada" : L("Done")
            }
        }
    }

    func cancelAppsScan() {
        appsCancelFlag.cancel()
        appsStatus = "Cancelando…"
    }

    // MARK: - Varredura de offload

    func startOffloadScan() {
        guard !isScanningOffload else { return }
        isScanningOffload = true
        offloadCancelFlag.reset()
        offloadProgress = 0
        offloadStatus = "Preparando…"

        let flag = offloadCancelFlag
        queue.async { [weak self] in
            let inventory = OffloadScanner().scan(
                progress: { status, fraction in
                    Task { @MainActor [weak self] in
                        self?.offloadStatus = status
                        self?.offloadProgress = fraction * 0.7
                    }
                },
                isCancelled: { flag.isCancelled }
            )

            let candidates = CandidateScanner().scan(
                progress: { status, fraction in
                    Task { @MainActor [weak self] in
                        self?.offloadStatus = status
                        self?.offloadProgress = 0.7 + fraction * 0.3
                    }
                },
                isCancelled: { flag.isCancelled }
            )

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.offload = inventory
                self.candidates = candidates
                self.isScanningOffload = false
                self.offloadProgress = 1
                self.lastOffloadScanDate = Date()
                self.offloadStatus = flag.isCancelled ? "Cancelada" : L("Done")
                self.recomputeHealth()
                self.game.evaluateAchievements(
                    score: self.health.score,
                    duplicateBytes: nil,
                    offloadedBytes: inventory.savedBytes
                )
            }
        }
    }

    func cancelOffloadScan() {
        offloadCancelFlag.cancel()
        offloadStatus = "Cancelando…"
    }

    // MARK: - Seleção de limpeza

    func isSelected(_ item: CleanupItem) -> Bool {
        selectedItemIDs.contains(item.id)
    }

    func toggle(_ item: CleanupItem) {
        if selectedItemIDs.contains(item.id) {
            selectedItemIDs.remove(item.id)
        } else {
            selectedItemIDs.insert(item.id)
        }
    }

    func selectionState(for category: CleanupCategory) -> Bool? {
        let ids = Set(category.items.map(\.id))
        guard !ids.isEmpty else { return false }
        let selected = ids.intersection(selectedItemIDs)
        if selected.isEmpty { return false }
        return selected.count == ids.count ? true : nil
    }

    func toggleCategory(_ category: CleanupCategory) {
        let ids = Set(category.items.map(\.id))
        if selectionState(for: category) == true {
            selectedItemIDs.subtract(ids)
        } else {
            selectedItemIDs.formUnion(ids)
        }
    }

    func selectAll(maximumRisk: RiskLevel) {
        selectedItemIDs = Set(
            categories.filter { $0.risk <= maximumRisk }.flatMap(\.items).map(\.id)
        )
    }

    func clearSelection() {
        selectedItemIDs = []
    }

    // MARK: - Remoção da limpeza

    func removeSelected() {
        let items = selectedItems
        guard !items.isEmpty, !isRemoving else { return }

        isRemoving = true
        removeProgress = 0
        removeStatus = "Iniciando…"
        let mode = cleanupMode

        queue.async { [weak self] in
            let result = CleanupRemover.remove(items: items, mode: mode) { label, fraction in
                Task { @MainActor [weak self] in
                    self?.removeStatus = label
                    self?.removeProgress = fraction
                }
            }

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isRemoving = false

                let removedIDs = Set(items.map(\.id))
                self.categories = self.categories.compactMap { category -> CleanupCategory? in
                    var copy = category
                    copy.items = category.items.filter { !removedIDs.contains($0.id) }
                    return copy.isEmpty ? nil : copy
                }
                self.selectedItemIDs = []
                self.refreshMetrics()
                self.refreshTrash()

                let xp = self.game.record(
                    bytes: result.freedBytes,
                    itemCount: result.removedCount,
                    kind: "limpeza",
                    currentScore: self.health.score
                )
                self.celebrate(
                    title: L("Cleanup finished"),
                    bytes: result.freedBytes,
                    xp: xp,
                    failures: result.failures
                )
            }
        }
    }

    // MARK: - Processos

    func isGrowing(_ row: ProcessInfoRow) -> Bool {
        growth.isGrowing(row.pid)
    }

    func growthAmount(_ row: ProcessInfoRow) -> Int64? {
        growth.growth(for: row.pid)
    }

    func canQuit(_ row: ProcessInfoRow) -> Bool {
        ProcessController.canQuit(row)
    }

    func quitReason(_ row: ProcessInfoRow) -> String? {
        ProcessController.rejectionReason(for: row)
    }

    func quitWarning(_ row: ProcessInfoRow) -> String? {
        ProcessController.warning(for: row)
    }

    /// Pedido gentil. O app pode perguntar sobre trabalho não salvo — é ele que
    /// decide, e é assim que deve ser.
    func requestQuit(_ row: ProcessInfoRow) {
        let outcome = ProcessController.requestQuit(row)
        banner = Banner(text: outcome.message, isError: outcome.isError)
        // Dá tempo do processo sair antes de reler a lista.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            self?.refreshMetrics()
        }
    }

    func forceQuit(_ row: ProcessInfoRow) {
        let outcome = ProcessController.forceQuit(row)
        banner = Banner(text: outcome.message, isError: outcome.isError)
        pendingForceQuit = nil
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            self?.refreshMetrics()
        }
    }

    // MARK: - Lixeira

    /// Medir a Lixeira percorre pastas, então sai da thread principal.
    func refreshTrash() {
        queue.async { [weak self] in
            let info = TrashManager.inspect()
            Task { @MainActor [weak self] in
                self?.trash = info
            }
        }
    }

    /// Esvaziar é permanente por definição — a confirmação fica na interface.
    func emptyTrash() {
        guard !isEmptyingTrash, !isRemoving, !trash.isEmpty else { return }

        isEmptyingTrash = true
        trashProgress = 0
        trashStatus = "Esvaziando a Lixeira…"

        queue.async { [weak self] in
            let result = TrashManager.empty { name, fraction in
                Task { @MainActor [weak self] in
                    self?.trashStatus = "Removendo \(name)…"
                    self?.trashProgress = fraction
                }
            }

            let info = TrashManager.inspect()

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isEmptyingTrash = false
                self.trash = info
                self.refreshMetrics()

                // Sem isto, uma Lixeira já vazia ou itens travados renderiam
                // 20 XP de piso, marcariam a semana no streak e mostrariam
                // "Lixeira esvaziada" sem nada ter saído.
                guard result.removedCount > 0 else {
                    self.banner = Banner(
                        text: result.failures.isEmpty
                            ? L("The Trash was already empty.")
                            : L("No item could be removed: %@", result.failures.first?.reason ?? L("unknown reason")),
                        isError: !result.failures.isEmpty
                    )
                    return
                }

                let xp = self.game.record(
                    bytes: result.freedBytes,
                    itemCount: result.removedCount,
                    kind: "lixeira",
                    currentScore: self.health.score
                )
                // Aqui o espaço volta de verdade: não é "movido para a Lixeira".
                self.celebrate(
                    title: L("Trash emptied"),
                    bytes: result.freedBytes,
                    xp: xp,
                    failures: result.failures,
                    toTrash: false
                )
            }
        }
    }

    // MARK: - Duplicados

    func toggleDuplicateGroup(_ group: DuplicateGroup) {
        if selectedDuplicateIDs.contains(group.id) {
            selectedDuplicateIDs.remove(group.id)
        } else {
            selectedDuplicateIDs.insert(group.id)
        }
    }

    func selectAllDuplicates() {
        selectedDuplicateIDs = Set(files.duplicates.map(\.id))
    }

    func removeSelectedDuplicates() {
        let groups = files.duplicates.filter { selectedDuplicateIDs.contains($0.id) }
        guard !groups.isEmpty, !isRemoving else { return }

        isRemoving = true
        removeProgress = 0
        removeStatus = L("Verifying content…")
        let mode = cleanupMode

        queue.async { [weak self] in
            // O hash da varredura é por amostras. Antes de apagar, cada cópia é
            // comparada integralmente com a original — apagar por engano aqui
            // seria perda de dados silenciosa.
            var verified: [CleanupItem] = []
            var expected: Int64 = 0
            var mismatched = 0

            for group in groups {
                guard let original = group.copies.first(where: \.isOriginal) else { continue }
                let originalURL = URL(fileURLWithPath: original.path)
                for copy in group.removable {
                    Task { @MainActor [weak self] in
                        self?.removeStatus = "Conferindo \((copy.path as NSString).lastPathComponent)…"
                    }
                    guard FileComparator.identical(originalURL, URL(fileURLWithPath: copy.path)) else {
                        mismatched += 1
                        continue
                    }
                    expected += group.fileSize
                    verified.append(CleanupItem(
                        path: copy.path,
                        displayName: (copy.path as NSString).lastPathComponent,
                        size: group.fileSize,
                        modified: copy.modified,
                        isDirectory: false,
                        note: nil
                    ))
                }
            }

            let items = verified
            let unverified = mismatched

            guard !items.isEmpty else {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isRemoving = false
                    self.banner = Banner(
                        text: unverified > 0
                            ? L("No copy removed: %d failed the byte-by-byte check. They are different files of the same size.", unverified)
                            : "Nada a remover.",
                        isError: true
                    )
                }
                return
            }

            let result = CleanupRemover.remove(items: items, mode: mode) { label, fraction in
                Task { @MainActor [weak self] in
                    self?.removeStatus = label
                    self?.removeProgress = fraction
                }
            }

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isRemoving = false
                let removedPaths = Set(result.removedCount > 0 ? items.map(\.path) : [])
                self.files.duplicates = self.files.duplicates.compactMap { group -> DuplicateGroup? in
                    guard self.selectedDuplicateIDs.contains(group.id) else { return group }
                    var copy = group
                    copy.copies = group.copies.filter { !removedPaths.contains($0.path) }
                    return copy.copies.count > 1 ? copy : nil
                }
                self.selectedDuplicateIDs = []
                self.refreshMetrics()
                self.refreshTrash()

                let freed = result.freedBytes
                let xp = self.game.record(
                    bytes: freed,
                    itemCount: result.removedCount,
                    kind: "limpeza",
                    currentScore: self.health.score
                )
                self.celebrate(
                    title: L("Duplicates removed"),
                    bytes: freed,
                    xp: xp,
                    failures: result.failures
                )
                if unverified > 0 {
                    self.banner = Banner(
                        text: L("%d copies were preserved: they failed the byte-by-byte check.", unverified),
                        isError: false
                    )
                }
            }
        }
    }

    // MARK: - Ações de app

    func clearCache(of app: InstalledApp) {
        guard !isRemoving else { return }
        isRemoving = true
        removeStatus = L("Clearing %@ cache…", app.name)
        removeProgress = 0

        queue.async { [weak self] in
            let result = AppUninstaller.clearCache(of: app) { label, fraction in
                Task { @MainActor [weak self] in
                    self?.removeStatus = "Limpando \(label)…"
                    self?.removeProgress = fraction
                }
            }

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isRemoving = false
                self.applyAppResult(result, app: app, kind: "cache", title: L("Cache cleared"))
            }
        }
    }

    func uninstall(app: InstalledApp) {
        guard !isRemoving else { return }
        isRemoving = true
        removeStatus = "Desinstalando \(app.name)…"
        removeProgress = 0

        queue.async { [weak self] in
            let result = AppUninstaller.uninstall(app: app) { label, fraction in
                Task { @MainActor [weak self] in
                    self?.removeStatus = "Removendo \(label)…"
                    self?.removeProgress = fraction
                }
            }

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isRemoving = false
                self.applyAppResult(result, app: app, kind: L("uninstall"), title: L("%@ removed", app.name))
            }
        }
    }

    private func applyAppResult(
        _ result: UninstallResult,
        app: InstalledApp,
        kind: String,
        title: String
    ) {
        let removed = Set(result.removedPaths)

        appInventory.apps = appInventory.apps.compactMap { current -> InstalledApp? in
            guard current.id == app.id else { return current }
            if result.bundleRemoved { return nil }
            var copy = current
            copy.residues = current.residues.filter { !removed.contains($0.path) }
            return copy
        }
        appInventory.staleCount = appInventory.apps.filter(\.isStale).count
        refreshMetrics()
        refreshTrash()

        let xp = game.record(
            bytes: result.freedBytes,
            itemCount: result.removedPaths.count,
            kind: kind,
            currentScore: health.score
        )
        celebrate(
            title: title,
            bytes: result.freedBytes,
            xp: xp,
            failures: result.failures,
            toTrash: true
        )
    }

    // MARK: - Offload: destino e migração

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Usar esta pasta"
        panel.message = L("Choose the destination folder on the external disk. Suggestion: create a dedicated folder, such as mac-offload.")
        if let volume = suggestedDestinationVolume {
            panel.directoryURL = URL(fileURLWithPath: volume.path)
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }

        if let problem = MigrationEngine.destinationProblem(url, needing: 0) {
            banner = Banner(text: problem, isError: true)
            return
        }

        destinationRoot = url.path
        UserDefaults.standard.set(url.path, forKey: AppState.destinationKey)
        banner = Banner(text: L("Destination set: %@", url.path), isError: false)
    }

    func migrate(candidate: OffloadCandidate) {
        guard !isMigrating else { return }
        guard let destination = destinationURL else {
            banner = Banner(text: L("Choose the destination folder first."), isError: true)
            return
        }

        isMigrating = true
        migrationProgress = 0
        migrationPhase = .preflight
        migrationStatus = "Preparando…"

        let source = URL(fileURLWithPath: candidate.path)
        let engine = self.engine

        queue.async { [weak self] in
            let outcome = engine.migrate(
                source: source,
                destinationRoot: destination,
                progress: { phase, status, fraction in
                    Task { @MainActor [weak self] in
                        self?.migrationPhase = phase
                        self?.migrationStatus = status
                        self?.migrationProgress = fraction
                    }
                },
                isCancelled: { false }   // migração não é cancelável no meio, por segurança
            )

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isMigrating = false
                self.journal = engine.loadJournal()
                self.banner = Banner(text: outcome.message, isError: !outcome.succeeded)

                if outcome.succeeded {
                    self.candidates.removeAll { $0.id == candidate.id }
                    let xp = self.game.record(
                        bytes: 0,   // o espaço só volta quando a quarentena é liberada
                        itemCount: 1,
                        kind: "offload",
                        currentScore: self.health.score
                    )
                    self.celebration = Celebration(
                        bytes: outcome.entry.bytes,
                        xp: xp,
                        score: self.health.score,
                        title: L("Offload finished"),
                        unlocked: self.game.lastUnlocked
                    )
                    self.game.clearRecentUnlocks()
                }
                self.startOffloadScan()
            }
        }
    }

    func restore(_ entry: MigrationJournalEntry) {
        guard !isMigrating else { return }
        isMigrating = true
        migrationStatus = "Revertendo \(entry.name)…"

        let engine = self.engine
        queue.async { [weak self] in
            let outcome = engine.restore(entry)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isMigrating = false
                self.journal = engine.loadJournal()
                self.banner = Banner(text: outcome.message, isError: !outcome.succeeded)
                self.refreshMetrics()
                self.startOffloadScan()
            }
        }
    }

    func releaseQuarantine(_ entry: MigrationJournalEntry) {
        guard !isMigrating else { return }
        isMigrating = true
        migrationStatus = L("Releasing quarantine for %@…", entry.name)

        let engine = self.engine
        queue.async { [weak self] in
            let outcome = engine.releaseQuarantine(entry)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isMigrating = false
                self.journal = engine.loadJournal()
                self.banner = Banner(text: outcome.message, isError: !outcome.succeeded)
                self.refreshMetrics()

                if outcome.succeeded {
                    let xp = self.game.record(
                        bytes: entry.bytes,
                        itemCount: 1,
                        kind: "limpeza",
                        currentScore: self.health.score
                    )
                    self.celebrate(title: L("Space returned"), bytes: entry.bytes, xp: xp, failures: [], toTrash: true)
                }
            }
        }
    }

    func releaseAllQuarantines() {
        let entries = journal.quarantined
        guard !entries.isEmpty, !isMigrating else { return }

        isMigrating = true
        migrationStatus = "Liberando \(entries.count) quarentena(s)…"

        let engine = self.engine
        queue.async { [weak self] in
            var freed: Int64 = 0
            var failures = 0

            for entry in entries {
                Task { @MainActor [weak self] in
                    self?.migrationStatus = "Liberando \(entry.name)…"
                }
                let outcome = engine.releaseQuarantine(entry)
                if outcome.succeeded { freed += entry.bytes } else { failures += 1 }
            }

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isMigrating = false
                self.journal = engine.loadJournal()
                self.refreshMetrics()

                if freed > 0 {
                    let xp = self.game.record(
                        bytes: freed,
                        itemCount: entries.count - failures,
                        kind: "limpeza",
                        currentScore: self.health.score
                    )
                    self.celebrate(title: L("Space returned"), bytes: freed, xp: xp, failures: [], toTrash: true)
                }
                if failures > 0 {
                    self.banner = Banner(
                        text: L("%d quarantine(s) could not be released. Check that the link and the target are intact.", failures),
                        isError: true
                    )
                }
            }
        }
    }

    // MARK: - Comemoração

    private func celebrate(
        title: String,
        bytes: Int64,
        xp: Int,
        failures: [(path: String, reason: String)],
        toTrash: Bool? = nil
    ) {
        celebration = Celebration(
            bytes: bytes,
            xp: xp,
            score: health.score,
            title: title,
            unlocked: game.lastUnlocked,
            wentToTrash: toTrash ?? (cleanupMode == .trash)
        )
        game.clearRecentUnlocks()

        if !failures.isEmpty {
            banner = Banner(
                text: L("%d item(s) could not be removed: %@", failures.count, failures.first?.reason ?? L("unknown reason")),
                isError: true
            )
        }
    }

    func dismissCelebration() {
        celebration = nil
    }

    func dismissBanner() {
        banner = nil
    }

    // MARK: - Utilidades

    func reveal(_ path: String) {
        CleanupRemover.revealInFinder(path)
    }

    /// `selectFile` revelaria a pasta oculta dentro da Home; para a Lixeira o
    /// certo é abri-la.
    func openTrashInFinder() {
        NSWorkspace.shared.open(TrashManager.trashURL)
    }

    /// Abre direto o painel de Acesso Total ao Disco. Conceder a permissão não
    /// pode ser automatizado — é decisão do usuário, por design do macOS —, mas
    /// levar até a tela certa evita a caça ao ajuste.
    func openFullDiskAccessSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
        if let url {
            NSWorkspace.shared.open(url)
        }
    }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
