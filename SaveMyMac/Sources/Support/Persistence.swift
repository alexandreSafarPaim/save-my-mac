import Foundation

/// Armazenamento simples em JSON dentro de
/// `~/Library/Application Support/SaveMyMac/`.
///
/// Usado pela gamificação, pelo histórico de limpezas e pelo journal de
/// migração. Escrita atômica: grava num arquivo temporário e troca, para que
/// uma queda de energia no meio não deixe JSON corrompido.
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
        return try? decoder.decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, to name: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }

        let target = url(name)
        let temp = target.appendingPathExtension("tmp")
        do {
            try data.write(to: temp, options: .atomic)
            if FileManager.default.fileExists(atPath: target.path) {
                _ = try FileManager.default.replaceItemAt(target, withItemAt: temp)
            } else {
                try FileManager.default.moveItem(at: temp, to: target)
            }
        } catch {
            try? data.write(to: target, options: .atomic)
            try? FileManager.default.removeItem(at: temp)
        }
    }
}
