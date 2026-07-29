import Foundation
import SwiftUI
import AppKit
import Combine

@MainActor
final class AppState: ObservableObject {

    init() {
        // `GameStore` is a nested ObservableObject: without forwarding the
        // signal, views reading XP, level and achievements would not refresh.
        game.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Live metrics

    @Published var system = SystemInfoSnapshot()
    @Published var memory = MemorySnapshot()
    @Published var swap = SwapSnapshot()
    @Published var cpu = CPUSnapshot()
    @Published var volumes: [VolumeInfo] = []
    @Published var battery = BatterySnapshot()
    @Published var thermal = ThermalSnapshot()
    @Published var topByCPU: [ProcessInfoRow] = []
    @Published var topByMemory: [ProcessInfoRow] = []
    /// Why the process list is empty, when it is.
    @Published var processFailure: String?
    @Published var memoryHistory = MemoryHistory()
    private var growth = GrowthTracker()
    /// Process awaiting force-quit confirmation.
    @Published var pendingForceQuit: ProcessInfoRow?

    /// Tab requested from outside (by the menu bar panel). The window consumes
    /// it and clears it.
    @Published var requestedSection: AppSection?

    // MARK: - Appearance

    @Published var theme: ThemeMode = .dark {
        didSet { game.setTheme(theme) }
    }

    var palette: Palette { Palette.of(theme) }

    // MARK: - Health and progress

    @Published var health = HealthReport(score: 0, factors: [])
    let game = GameStore()

    // MARK: - Cleanup

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
    // Its own progress: sharing `removeProgress` with cleanup made one card
    // show the other's status.
    @Published var trashProgress: Double = 0
    @Published var trashStatus = ""

    // MARK: - Large files and duplicates

    @Published var files = FileScanResult()
    @Published var isScanningFiles = false
    @Published var filesProgress: Double = 0
    @Published var filesStatus = ""
    @Published var lastFilesScanDate: Date?
    @Published var selectedDuplicateIDs: Set<UUID> = []

    // MARK: - Applications

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

    // MARK: - Dialogs

    @Published var celebration: Celebration?
    @Published var banner: Banner?

    struct Celebration: Identifiable {
        let id = UUID()
        var bytes: Int64
        var xp: Int
        var score: Int
        var title: String
        var unlocked: [Achievement]
        /// When the destination was the Trash, the space only comes back on
        /// emptying it — and the interface has to say that instead of "freed".
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

    // MARK: - Internals

    private let cpuMonitor = CPUMonitor()
    private var timer: Timer?
    private var tick = 0
    // Reentrancy guards for the expensive work — see `refreshMetrics()`.
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

    // MARK: - Derived

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

    /// Suggested destination volume: the largest external volume with space.
    var suggestedDestinationVolume: VolumeInfo? {
        volumes.first { $0.path != "/" && $0.available > 10 * 1_073_741_824 }
    }

    // MARK: - Lifecycle

    func start() {
        guard timer == nil else { return }
        Trace.mark("AppState.start")
        theme = game.state.theme
        destinationRoot = UserDefaults.standard.string(forKey: AppState.destinationKey) ?? ""
        Trace.span("SystemInfo.read") { system = SystemInfo.read() }
        Trace.span("engine.loadJournal") { journal = engine.loadJournal() }
        // One synchronous read at launch only, so the window opens with the
        // disk already filled in. After that, volumes are always read off the
        // main thread.
        Trace.span("DiskMonitor.volumes (launch)") { volumes = DiskMonitor.volumes() }
        refreshMetrics()
        Trace.span("refreshTrash") { refreshTrash() }
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshMetrics() }
        }
        Trace.mark("AppState.start finished")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Wires preferences and the space alert into the metrics cycle.
    /// Done by injection rather than having `AppState` create both, so the
    /// Settings scene and the menu bar scene share exactly the same instances.
    func attach(preferences: Preferences, spaceAlert: SpaceAlert) {
        self.preferences = preferences
        self.spaceAlert = spaceAlert
        // Permission is NOT requested here.
        //
        // `UNUserNotificationCenter.current()` requires a registered, signed
        // bundle; in an ad-hoc app running from an arbitrary path it can throw or
        // block. Doing that on the launch path means hanging before the window
        // exists. It now happens only when the user turns the option on in
        // Settings, which is when they are expecting a permission dialog anyway.
    }

    func toggleTheme() {
        theme = theme.toggled
    }

    // MARK: - Metrics

    /// One metrics tick.
    ///
    /// Not everything in here costs the same, and it all used to run at the same
    /// 2-second cadence. The three fixes:
    ///
    /// 1. **Separate cadences.** Memory and CPU are kernel counter reads and can
    ///    be polled at 2 s. Enumerating volumes, reading sensors and running
    ///    `/bin/ps` are orders of magnitude more expensive and don't change at
    ///    that rate — they moved to every 6 s.
    /// 2. **Volumes come off the main thread.** `mountedVolumeURLs` touches every
    ///    mounted disk. With an external SSD that spins down, that call blocks —
    ///    and blocking there means freezing the window.
    /// 3. **Heavy work can't pile up.** The detached tasks were fired with no
    ///    guard at all: if one took longer than the interval, the next started on
    ///    top of it. Under load that becomes unbounded growth in threads and
    ///    subprocesses. Each now has a lock.
    func refreshMetrics() {
        defer { tick &+= 1 }

        // Cheap, every tick.
        Trace.mark("tick \(tick)")
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

    /// The timer's interval is 2 s; expensive work runs every 3 ticks (6 s).
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

    /// Deliberately separate from the process read. They used to be in the same
    /// task, with the thermal read first: because it goes through a private Apple
    /// API via `dlsym`, any slowness there stopped the process list from running
    /// at all — and the "What's using resources" card stayed permanently empty.
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
                // Growth is tracked from the raw rows (pid + bytes); the AppKit
                // enrichment is only worth it for what goes on screen.
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

    // MARK: - Cleanup scan

    func startScan() {
        guard !isScanning else { return }
        isScanning = true
        cancelFlag.reset()
        scanProgress = 0
        scanStatus = L("Preparing…")
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
                self.scanStatus = flag.isCancelled ? L("Cancelled") : L("Done")
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
        scanStatus = L("Cancelling…")
    }

    // MARK: - File scan

    func startFilesScan() {
        guard !isScanningFiles else { return }
        isScanningFiles = true
        filesCancelFlag.reset()
        filesProgress = 0
        filesStatus = L("Preparing…")
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
                self.filesStatus = flag.isCancelled ? L("Cancelled") : L("Done")
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
        filesStatus = L("Cancelling…")
    }

    // MARK: - App scan

    func startAppsScan() {
        guard !isScanningApps else { return }
        isScanningApps = true
        appsCancelFlag.reset()
        appsProgress = 0
        appsStatus = L("Preparing…")

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
                self.appsStatus = flag.isCancelled ? L("Cancelled") : L("Done")
            }
        }
    }

    func cancelAppsScan() {
        appsCancelFlag.cancel()
        appsStatus = L("Cancelling…")
    }

    // MARK: - Offload scan

    func startOffloadScan() {
        guard !isScanningOffload else { return }
        isScanningOffload = true
        offloadCancelFlag.reset()
        offloadProgress = 0
        offloadStatus = L("Preparing…")

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
                self.offloadStatus = flag.isCancelled ? L("Cancelled") : L("Done")
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
        offloadStatus = L("Cancelling…")
    }

    // MARK: - Cleanup selection

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

    // MARK: - Cleanup removal

    func removeSelected() {
        let items = selectedItems
        guard !items.isEmpty, !isRemoving else { return }

        isRemoving = true
        removeProgress = 0
        removeStatus = L("Starting…")
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

    /// A polite request. The app may ask about unsaved work — it decides, and
    /// that is how it should be.
    func requestQuit(_ row: ProcessInfoRow) {
        let outcome = ProcessController.requestQuit(row)
        banner = Banner(text: outcome.message, isError: outcome.isError)
        // Gives the process time to exit before re-reading the list.
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

    /// Measuring the Trash walks folders, so it goes off the main thread.
    func refreshTrash() {
        queue.async { [weak self] in
            let info = TrashManager.inspect()
            Task { @MainActor [weak self] in
                self?.trash = info
            }
        }
    }

    /// Emptying is permanent by definition — the confirmation lives in the UI.
    func emptyTrash() {
        guard !isEmptyingTrash, !isRemoving, !trash.isEmpty else { return }

        isEmptyingTrash = true
        trashProgress = 0
        trashStatus = L("Emptying the Trash…")

        queue.async { [weak self] in
            let result = TrashManager.empty { name, fraction in
                Task { @MainActor [weak self] in
                    self?.trashStatus = L("Removing %@…", name)
                    self?.trashProgress = fraction
                }
            }

            let info = TrashManager.inspect()

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isEmptyingTrash = false
                self.trash = info
                self.refreshMetrics()

                // Without this, an already-empty Trash or locked items would
                // still award the 20 XP floor, mark the week in the streak, and
                // report "Trash emptied" with nothing having left.
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
                // Here the space genuinely comes back: this is not "moved to the Trash".
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

    // MARK: - Duplicates

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
            // The scan's hash is sample-based. Before deleting, every copy is
            // compared in full against the original — deleting by mistake here
            // would be silent data loss.
            var verified: [CleanupItem] = []
            var expected: Int64 = 0
            var mismatched = 0

            for group in groups {
                guard let original = group.copies.first(where: \.isOriginal) else { continue }
                let originalURL = URL(fileURLWithPath: original.path)
                for copy in group.removable {
                    Task { @MainActor [weak self] in
                        self?.removeStatus = L("Checking %@…", (copy.path as NSString).lastPathComponent)
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

    // MARK: - App actions

    func clearCache(of app: InstalledApp) {
        guard !isRemoving else { return }
        isRemoving = true
        removeStatus = L("Clearing %@ cache…", app.name)
        removeProgress = 0

        queue.async { [weak self] in
            let result = AppUninstaller.clearCache(of: app) { label, fraction in
                Task { @MainActor [weak self] in
                    self?.removeStatus = L("Clearing %@…", label)
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
        removeStatus = L("Uninstalling %@…", app.name)
        removeProgress = 0

        queue.async { [weak self] in
            let result = AppUninstaller.uninstall(app: app) { label, fraction in
                Task { @MainActor [weak self] in
                    self?.removeStatus = L("Removing %@…", label)
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

    // MARK: - Offload: destination and migration

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
        migrationStatus = L("Preparing…")

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
        migrationStatus = L("Rolling back %@…", entry.name)

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
        migrationStatus = Lp("Releasing %d quarantine…", "Releasing %d quarantines…", count: entries.count)

        let engine = self.engine
        queue.async { [weak self] in
            var freed: Int64 = 0
            var failures = 0

            for entry in entries {
                Task { @MainActor [weak self] in
                    self?.migrationStatus = L("Releasing %@…", entry.name)
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

    // MARK: - Celebration

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

    /// `selectFile` would reveal the hidden folder inside Home; for the Trash the
    /// right thing is to open it.
    func openTrashInFinder() {
        NSWorkspace.shared.open(TrashManager.trashURL)
    }

    /// Opens the Full Disk Access pane directly. Granting the permission cannot
    /// be automated — it is the user's decision, by macOS design — but taking
    /// them to the right screen saves hunting for the setting.
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
