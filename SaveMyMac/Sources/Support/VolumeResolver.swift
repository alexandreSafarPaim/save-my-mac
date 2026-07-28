import Foundation

/// Descobre em qual volume um caminho realmente vive.
///
/// Isso existe por um motivo concreto: se `~/.gradle` é um link simbólico para
/// um SSD externo, apagar aquele conteúdo **não libera nenhum byte no Mac**.
/// Pior: apagaria dados no disco externo enquanto o app reporta espaço
/// recuperado no interno. Todo caminho passa por aqui antes de entrar na
/// lista de limpeza.
enum VolumeResolver {

    /// Identidade do volume onde a pasta pessoal do usuário está.
    /// É esse — e não literalmente "/" — o volume cujo espaço interessa,
    /// porque no macOS moderno a home fica no volume de Dados, ligado à raiz
    /// por firmlink (que não é symlink e não aparece na resolução de caminho).
    private static let homeVolumeIdentifier: NSObject? = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let values = try? home.resourceValues(forKeys: [.volumeIdentifierKey])
        return values?.volumeIdentifier as? NSObject
    }()

    // MARK: - Identidade de volume

    static func volumeIdentifier(of url: URL) -> NSObject? {
        let resolved = url.resolvingSymlinksInPath()
        let values = try? resolved.resourceValues(forKeys: [.volumeIdentifierKey])
        return values?.volumeIdentifier as? NSObject
    }

    /// `true` se o conteúdo real está no mesmo volume da home.
    ///
    /// Caminhos que não existem retornam `true` de propósito: um link quebrado
    /// não deve ser tratado como "conteúdo externo".
    static func isOnHomeVolume(_ url: URL) -> Bool {
        guard let home = homeVolumeIdentifier else { return true }
        guard let target = volumeIdentifier(of: url) else { return true }
        return home.isEqual(target)
    }

    /// Um caminho só rende espaço no Mac se não for link e estiver no volume da home.
    static func freesSpaceOnMac(_ url: URL) -> Bool {
        if isSymbolicLink(url) { return false }
        return isOnHomeVolume(url)
    }

    // MARK: - Informações do volume

    static func volumeName(of url: URL) -> String? {
        let resolved = url.resolvingSymlinksInPath()
        let values = try? resolved.resourceValues(forKeys: [.volumeNameKey])
        return values?.volumeName
    }

    static func mountPoint(of url: URL) -> String? {
        let resolved = url.resolvingSymlinksInPath()
        let values = try? resolved.resourceValues(forKeys: [.volumeURLKey])
        return values?.volume?.path
    }

    struct VolumeCapacity {
        var total: Int64
        var available: Int64
    }

    static func capacity(ofMountPoint path: String) -> VolumeCapacity? {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]) else { return nil }

        let total = Int64(values.volumeTotalCapacity ?? 0)
        guard total > 0 else { return nil }
        let available = values.volumeAvailableCapacityForImportantUsage
            ?? Int64(values.volumeAvailableCapacity ?? 0)
        return VolumeCapacity(total: total, available: max(0, available))
    }

    // MARK: - Links simbólicos

    static func isSymbolicLink(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
        return values?.isSymbolicLink ?? false
    }

    /// Alvo absoluto de um link simbólico, resolvendo alvos relativos.
    static func symlinkTarget(of url: URL) -> URL? {
        guard let raw = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) else {
            return nil
        }
        if raw.hasPrefix("/") {
            return URL(fileURLWithPath: raw).standardizedFileURL
        }
        return url.deletingLastPathComponent()
            .appendingPathComponent(raw)
            .standardizedFileURL
    }
}
