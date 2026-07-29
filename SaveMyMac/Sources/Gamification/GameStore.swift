import Foundation
import Combine

// MARK: - Achievements

struct Achievement: Identifiable, Hashable {
    var id: String
    var symbol: String
    var name: String
    var requirement: String
}

enum Achievements {
    /// A computed `var` rather than `static let`, for the same reason as
    /// `residueLocations`: `L()` inside a static `let` freezes the language of the
    /// first read.
    static var all: [Achievement] {[
        .init(id: "first_clean", symbol: "sparkles", name: L("First cleanup"),
              requirement: L("Run your first cleanup")),
        .init(id: "freed_50", symbol: "bolt.fill", name: L("50 GB freed"),
              requirement: L("Free up 50 GB in total")),
        .init(id: "streak_4", symbol: "flame.fill", name: L("4-week streak"),
              requirement: L("Clean 4 weeks in a row")),
        .init(id: "first_offload", symbol: "link", name: L("First offload"),
              requirement: L("Move a folder to another disk with a link")),
        .init(id: "freed_100", symbol: "mountain.2.fill", name: L("100 GB freed"),
              requirement: L("Free up 100 GB in total")),
        .init(id: "zero_dupes", symbol: "circle.grid.cross.fill", name: L("Zero duplicates"),
              requirement: L("End up with no duplicate files")),
        .init(id: "score_95", symbol: "shield.fill", name: "Score 95+",
              requirement: L("Reach 95 health")),
        .init(id: "level_10", symbol: "crown.fill", name: L("Level 10"),
              requirement: L("Reach level 10")),
        .init(id: "app_purge", symbol: "trash.fill", name: L("App spring cleaning"),
              requirement: L("Uninstall 5 apps completely")),
        .init(id: "cache_master", symbol: "shippingbox.fill", name: L("Zero cache"),
              requirement: L("Clear the cache of 10 apps")),
        .init(id: "streak_12", symbol: "calendar.badge.checkmark", name: L("Clean quarter"),
              requirement: L("Clean 12 weeks in a row")),
        .init(id: "offload_100", symbol: "externaldrive.fill.badge.checkmark", name: L("100 GB offloaded"),
              requirement: L("Keep 100 GB off the Mac's disk"))
    ]}
}

// MARK: - Estado persistido

struct CleanupRecord: Codable, Identifiable {
    var id: UUID = UUID()
    var date: Date
    var bytes: Int64
    var itemCount: Int
    var kind: String        // "limpeza", "lixeira", "cache", L("uninstall"), "offload"
}

struct GameState: Codable {
    var xp: Int = 0
    var totalFreedBytes: Int64 = 0
    var cleanCount: Int = 0
    var appsUninstalled: Int = 0
    var appCachesCleared: Int = 0
    var offloadCount: Int = 0
    var unlocked: Set<String> = []
    var history: [CleanupRecord] = []
    /// Semanas ISO em que houve alguma limpeza, no formato "2026-W31".
    var activeWeeks: Set<String> = []
    var monthlyGoalBytes: Int64 = 60 * 1_073_741_824
    var theme: ThemeMode = .dark

    // MARK: Derivados

    /// 1200 XP per level, as in the design.
    static let xpPerLevel = 1200

    var level: Int { max(1, xp / GameState.xpPerLevel + 1) }
    var xpInLevel: Int { xp % GameState.xpPerLevel }
    var xpProgress: Double { Double(xpInLevel) / Double(GameState.xpPerLevel) }

    /// Consecutive weeks with a cleanup, counted backwards.
    var streak: Int {
        var count = 0
        // If the current week has had no cleanup yet, start from the previous one:
        // the streak only breaks when a whole week goes by empty.
        var cursor = Date()
        if !activeWeeks.contains(GameState.weekKey(cursor)),
           let previous = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: cursor) {
            cursor = previous
        }
        while activeWeeks.contains(GameState.weekKey(cursor)) {
            count += 1
            guard let previous = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = previous
            if count > 520 { break }
        }
        return count
    }

    /// Total freed in the current month, for the goal.
    var freedThisMonth: Int64 {
        let calendar = Calendar.current
        let now = Date()
        return history
            .filter { calendar.isDate($0.date, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + $1.bytes }
    }

    var monthlyGoalProgress: Double {
        monthlyGoalBytes <= 0 ? 0 : Double(freedThisMonth) / Double(monthlyGoalBytes)
    }

    static func weekKey(_ date: Date) -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.firstWeekday = 2
        let week = calendar.component(.weekOfYear, from: date)
        let year = calendar.component(.yearForWeekOfYear, from: date)
        return String(format: "%04ld-W%02ld", year, week)
    }
}

// MARK: - Store

/// Stores progress in `~/Library/Application Support/SaveMyMac/game.json`.
///
/// This is app state, not system state: XP, level, streak and achievements are
/// SaveMyMac's invention. What is real is the history — every record corresponds
/// to bytes that genuinely left the disk.
@MainActor
final class GameStore: ObservableObject {

    private static let fileName = "game.json"

    @Published private(set) var state: GameState
    @Published var lastUnlocked: [Achievement] = []

    init() {
        state = Store.load(GameState.self, from: GameStore.fileName) ?? GameState()
    }

    private func persist() {
        Store.save(state, to: GameStore.fileName)
    }

    // MARK: Actions

    /// XP proportional to the space freed, with a floor of 20 — as in the design.
    static func xpReward(forBytes bytes: Int64) -> Int {
        let gb = Double(bytes) / 1_073_741_824
        return max(20, Int((gb * 12).rounded()))
    }

    /// Records an event that freed space and returns the XP earned.
    @discardableResult
    func record(bytes: Int64, itemCount: Int, kind: String, currentScore: Int) -> Int {
        let reward = GameStore.xpReward(forBytes: bytes)

        state.xp += reward
        state.totalFreedBytes += max(0, bytes)
        state.history.insert(
            CleanupRecord(date: Date(), bytes: max(0, bytes), itemCount: itemCount, kind: kind),
            at: 0
        )
        if state.history.count > 500 { state.history.removeLast(state.history.count - 500) }
        state.activeWeeks.insert(GameState.weekKey(Date()))

        switch kind {
        case "limpeza", "lixeira": state.cleanCount += 1
        case L("uninstall"): state.appsUninstalled += 1
        case "cache": state.appCachesCleared += 1
        case "offload": state.offloadCount += 1
        default: break
        }

        evaluateAchievements(score: currentScore, duplicateBytes: nil, offloadedBytes: nil)
        persist()
        return reward
    }

    func setTheme(_ mode: ThemeMode) {
        state.theme = mode
        persist()
    }

    func setMonthlyGoal(_ bytes: Int64) {
        state.monthlyGoalBytes = max(1_073_741_824, bytes)
        persist()
    }

    func isUnlocked(_ id: String) -> Bool {
        state.unlocked.contains(id)
    }

    func clearRecentUnlocks() {
        lastUnlocked = []
    }

    /// Re-evaluates the achievements. Safe to call at any time — it only unlocks
    /// what wasn't unlocked already.
    func evaluateAchievements(score: Int, duplicateBytes: Int64?, offloadedBytes: Int64?) {
        let gb: (Int64) -> Double = { Double($0) / 1_073_741_824 }
        var newly: [Achievement] = []

        func unlock(_ id: String, _ condition: Bool) {
            guard condition, !state.unlocked.contains(id) else { return }
            state.unlocked.insert(id)
            if let achievement = Achievements.all.first(where: { $0.id == id }) {
                newly.append(achievement)
            }
        }

        unlock("first_clean", state.cleanCount >= 1)
        unlock("freed_50", gb(state.totalFreedBytes) >= 50)
        unlock("freed_100", gb(state.totalFreedBytes) >= 100)
        unlock("streak_4", state.streak >= 4)
        unlock("streak_12", state.streak >= 12)
        unlock("first_offload", state.offloadCount >= 1)
        unlock("score_95", score >= 95)
        unlock("level_10", state.level >= 10)
        unlock("app_purge", state.appsUninstalled >= 5)
        unlock("cache_master", state.appCachesCleared >= 10)
        if let duplicateBytes {
            unlock("zero_dupes", duplicateBytes == 0 && state.cleanCount >= 1)
        }
        if let offloadedBytes {
            unlock("offload_100", gb(offloadedBytes) >= 100)
        }

        if !newly.isEmpty {
            lastUnlocked = newly
            persist()
        }
    }
}
