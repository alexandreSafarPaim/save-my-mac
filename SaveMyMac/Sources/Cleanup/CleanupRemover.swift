import Foundation
import AppKit

enum CleanupRemover {

    /// Remove os itens selecionados. Nada é apagado sem passar por aqui.
    static func remove(
        items: [CleanupItem],
        mode: CleanupMode,
        progress: (String, Double) -> Void
    ) -> CleanupResult {

        struct Target {
            var path: String
            var size: Int64
            var label: String
        }

        var result = CleanupResult()
        var targets: [Target] = []

        for item in items {
            let paths = item.allPaths
            guard !paths.isEmpty else { continue }
            // Divide o tamanho entre os caminhos apenas para a barra de progresso.
            let share = item.size / Int64(paths.count)
            for path in paths {
                targets.append(Target(path: path, size: share, label: item.displayName))
            }
        }

        let total = max(1, targets.count)

        for (index, entry) in targets.enumerated() {
            progress(entry.label, Double(index) / Double(total))

            let url = URL(fileURLWithPath: entry.path)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }

            // Trava de segurança: nunca sair da home, nem tocar em caminhos do
            // sistema, nem apagar através de um link para outro volume.
            if let reason = rejectionReason(for: url) {
                result.failures.append((entry.path, reason))
                continue
            }

            do {
                switch mode {
                case .trash:
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                case .permanent:
                    try FileManager.default.removeItem(at: url)
                }
                result.removedCount += 1
                result.freedBytes += entry.size
            } catch {
                result.failures.append((entry.path, error.localizedDescription))
            }
        }

        progress("Concluído", 1.0)
        return result
    }

    /// Retorna o motivo da recusa, ou `nil` se o caminho pode ser removido.
    ///
    /// Só permite apagar dentro da pasta pessoal do usuário, nunca as pastas de
    /// primeiro nível (Documents, Desktop, Library…), e nunca conteúdo que viva
    /// em outro volume — este último caso protege quem descarregou pastas para
    /// um disco externo via link simbólico: apagar ali não devolveria espaço ao
    /// Mac e destruiria dados no disco errado.
    static func rejectionReason(for url: URL) -> String? {
        if VolumeResolver.isSymbolicLink(url) {
            return "É um link simbólico — remover não libera espaço no Mac"
        }

        if !VolumeResolver.isOnHomeVolume(url) {
            let volume = VolumeResolver.volumeName(of: url) ?? "outro volume"
            return "O conteúdo real está em \(volume), não no disco do Mac"
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
            .standardizedFileURL.path
        let path = url.standardizedFileURL.path

        guard path.hasPrefix(home + "/") else {
            return "Fora da sua pasta pessoal"
        }

        let relative = String(path.dropFirst(home.count + 1))
        let components = relative.split(separator: "/")

        guard !components.isEmpty else {
            return "Caminho inválido"
        }

        // Bloqueia as pastas de topo inteiras
        let protectedTopLevel: Set<String> = [
            "Documents", "Desktop", "Downloads", "Library", "Pictures",
            "Movies", "Music", "Public", "Applications", ".Trash", "Developer"
        ]
        if components.count == 1 && protectedTopLevel.contains(String(components[0])) {
            return "Pasta de sistema do usuário protegida"
        }

        // Bloqueia caminhos sensíveis dentro da Library
        let blockedPrefixes = [
            "Library/Keychains",
            "Library/Application Support/AddressBook",
            "Library/Application Support/com.apple.sharedfilelist",
            "Library/Mail",
            "Library/Messages/chat.db",
            "Library/Preferences/com.apple",
            "Library/CloudStorage",
            "Library/Mobile Documents",
            "Library/Group Containers"
        ]
        for prefix in blockedPrefixes where relative.hasPrefix(prefix) {
            return "Caminho sensível protegido"
        }

        return nil
    }

    static func isSafeToDelete(_ url: URL) -> Bool {
        rejectionReason(for: url) == nil
    }

    static func revealInFinder(_ path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }
}
