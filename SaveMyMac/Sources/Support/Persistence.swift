import Foundation

/// Simple JSON storage inside
/// `~/Library/Application Support/SaveMyMac/`.
///
/// Used by the gamification, the cleanup history and the migration journal.
/// Atomic writes: it writes to a temporary file and swaps, so a power cut halfway
/// through doesn't leave corrupted JSON.
///
/// One of its clients is not like the others. The migration journal is the only
/// record of where a quarantined original went — lose it and an interrupted
/// migration becomes unrecoverable by the app. The original version of this file
/// treated all clients the same and swallowed every failure: `save` returned
/// `Void` with the write wrapped in `try?`, and `load` returned the same `nil`
/// for "no file yet" and "the JSON is corrupt". A corrupted journal therefore
/// presented as *no migrations exist* while quarantined data sat on disk.
enum Store {

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("SaveMyMac", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func url(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(type, from: data)
        } catch {
            // Corrupt is not the same as absent, and pretending it is would
            // silently discard the user's history — or worse, the migration
            // journal. The unreadable file is set aside, not deleted: the data
            // survives for manual recovery, and the caller starting fresh no
            // longer overwrites the evidence.
            let quarantined = url(name + ".corrupt")
            try? FileManager.default.removeItem(at: quarantined)
            try? FileManager.default.moveItem(at: url(name), to: quarantined)
            Trace.mark("Store.load: \(name) is corrupt, set aside as \(name).corrupt — \(error.localizedDescription)")
            return nil
        }
    }

    /// Persists `value`. Returns whether the data actually reached the disk,
    /// because for one caller — the migration journal — a silent write failure
    /// means an in-flight migration loses its only map back.
    @discardableResult
    static func save<T: Encodable>(_ value: T, to name: String) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else {
            Trace.mark("Store.save: could not encode \(name)")
            return false
        }

        let target = url(name)
        let temp = target.appendingPathExtension("tmp")
        do {
            try data.write(to: temp, options: .atomic)
            if FileManager.default.fileExists(atPath: target.path) {
                _ = try FileManager.default.replaceItemAt(target, withItemAt: temp)
            } else {
                try FileManager.default.moveItem(at: temp, to: target)
            }
            return true
        } catch {
            // The atomic path failed (exotic but real: the temp file and the
            // target can land on different volumes). One direct attempt before
            // giving up — and if that also fails, say so instead of shrugging.
            try? FileManager.default.removeItem(at: temp)
            do {
                try data.write(to: target, options: .atomic)
                return true
            } catch {
                Trace.mark("Store.save: writing \(name) FAILED — \(error.localizedDescription)")
                return false
            }
        }
    }
}
