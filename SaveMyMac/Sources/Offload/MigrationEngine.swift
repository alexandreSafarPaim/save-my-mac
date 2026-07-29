import Foundation

/// Move uma pasta para outro volume e deixa um link simbólico no lugar.
///
/// A sequência é deliberadamente conservadora e cada etapa é registrada num
/// journal em disco antes de acontecer:
///
///   1. checagens (volume aceita link? cabe? caminho é permitido?)
///   2. copia para uma área de staging no destino, com `ditto`
///   3. confere contagem de arquivos e bytes
///   4. move o original para a quarentena — rename no mesmo volume, instantâneo
///   5. publica o staging como alvo definitivo
///   6. cria o link simbólico
///   7. testa leitura e escrita através do link
///
/// O original nunca é apagado: ele fica na quarentena até você mandar liberar.
/// Qualquer falha dispara rollback automático.
final class MigrationEngine: @unchecked Sendable {

    static let journalFile = "migrations.json"

    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser

    private var quarantineRoot: URL {
        home.appendingPathComponent(".savemymac-quarantine", isDirectory: true)
    }

    private func stagingRoot(in destination: URL) -> URL {
        destination.appendingPathComponent(".savemymac-staging", isDirectory: true)
    }

    // MARK: - Journal

    func loadJournal() -> MigrationJournal {
        Store.load(MigrationJournal.self, from: MigrationEngine.journalFile) ?? MigrationJournal()
    }

    private func write(_ entry: MigrationJournalEntry) {
        var journal = loadJournal()
        if let index = journal.entries.firstIndex(where: { $0.id == entry.id }) {
            journal.entries[index] = entry
        } else {
            journal.entries.insert(entry, at: 0)
        }
        Store.save(journal, to: MigrationEngine.journalFile)
    }

    // MARK: - Checagens

    /// Motivo pelo qual o destino não serve, ou `nil` se estiver tudo bem.
    static func destinationProblem(_ destination: URL, needing bytes: Int64) -> String? {
        let fm = FileManager.default

        guard fm.fileExists(atPath: destination.path) else {
            return L("The destination folder does not exist, or the volume is not mounted.")
        }

        let keys: Set<URLResourceKey> = [
            .volumeSupportsSymbolicLinksKey,
            .volumeIsReadOnlyKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeNameKey
        ]
        guard let values = try? destination.resourceValues(forKeys: keys) else {
            return L("Could not read the destination volume's characteristics.")
        }

        // O portão eliminatório: exFAT e FAT não têm link simbólico.
        if values.volumeSupportsSymbolicLinks == false {
            let name = values.volumeName ?? "Este volume"
            return L("%@ does not support symlinks. Format it as APFS or HFS+ to use offload.", name)
        }
        if values.volumeIsReadOnly == true {
            return L("The destination volume is read-only.")
        }
        if !fm.isWritableFile(atPath: destination.path) {
            return L("No write permission on the destination folder.")
        }

        // Margem de 3% para metadados.
        let needed = Int64(Double(bytes) * 1.03)
        if let available = values.volumeAvailableCapacityForImportantUsage, available < needed {
            return L("%@ short at the destination (needs %@).", Fmt.bytes(needed - available), Fmt.bytes(needed))
        }

        return nil
    }

    /// Motivo pelo qual a origem não pode ser descarregada.
    static func sourceProblem(_ source: URL) -> String? {
        let fm = FileManager.default
        let path = source.standardizedFileURL.path

        guard fm.fileExists(atPath: path) else { return L("The source folder does not exist.") }

        if VolumeResolver.isSymbolicLink(source) {
            return L("This folder is already a symlink.")
        }
        if !VolumeResolver.isOnHomeVolume(source) {
            return L("The content is already off the Mac's disk.")
        }

        let home = fm.homeDirectoryForCurrentUser.standardizedFileURL.path
        guard path.hasPrefix(home + "/") else {
            return L("Only folders inside your home folder can be offloaded.")
        }

        let relative = String(path.dropFirst(home.count + 1))
        let components = relative.split(separator: "/")

        let protectedTop: Set<String> = [
            "Documents", "Desktop", "Downloads", "Library", "Pictures",
            "Movies", "Music", "Public", "Applications", ".Trash"
        ]
        if components.count == 1 && protectedTop.contains(String(components[0])) {
            return L("Don't offload a whole top-level folder — pick something inside it.")
        }

        // Pastas administradas por daemons do sistema: link simbólico aqui dá problema.
        let never: [(String, String)] = [
            ("Library/Mobile Documents", "iCloud Drive"),
            ("Library/CloudStorage", "provedores de nuvem"),
            ("Library/Keychains", L("the system keychain")),
            ("Library/Mail", "o Mail"),
            ("Library/Messages", "o Mensagens"),
            ("Library/Group Containers", "containers de grupo"),
            ("Library/Containers", "containers de apps sandboxados"),
            ("Library/Preferences", L("its preferences"))
        ]
        for (prefix, who) in never where relative.hasPrefix(prefix) {
            return L("%@ does not handle symlinks well. This folder is out.", who)
        }
        if source.pathExtension.lowercased() == "photoslibrary" {
            return L("Apple does not support a link on the Photos library. Move the library and open Photos holding Option.")
        }

        return nil
    }

    /// Impede que o destino fique dentro da origem, ou vice-versa.
    static func nestingProblem(source: URL, target: URL) -> String? {
        let s = source.standardizedFileURL.path
        let t = target.standardizedFileURL.path
        if t.hasPrefix(s + "/") { return "O destino não pode estar dentro da própria origem." }
        if s.hasPrefix(t + "/") { return "A origem não pode estar dentro do destino." }
        if s == t { return L("Source and destination are the same path.") }
        return nil
    }

    // MARK: - Migração

    func migrate(
        source: URL,
        destinationRoot: URL,
        progress: @escaping (MigrationPhase, String, Double) -> Void,
        isCancelled: @escaping () -> Bool
    ) -> MigrationOutcome {

        progress(.preflight, "Verificando origem e destino…", 0.01)

        let name = source.lastPathComponent
        let target = destinationRoot.appendingPathComponent(name)
        let uuid = UUID()
        let staging = stagingRoot(in: destinationRoot).appendingPathComponent(uuid.uuidString)
        let stagingItem = staging.appendingPathComponent(name)
        let quarantine = quarantineRoot.appendingPathComponent(uuid.uuidString)
        let quarantineItem = quarantine.appendingPathComponent(name)

        var entry = MigrationJournalEntry(
            id: uuid,
            sourcePath: source.path,
            stagingPath: stagingItem.path,
            targetPath: target.path,
            quarantinePath: quarantineItem.path,
            phase: .preflight,
            startedAt: Date(),
            bytes: 0,
            fileCount: 0
        )

        func fail(_ message: String) -> MigrationOutcome {
            entry.phase = .failed
            entry.errorMessage = message
            entry.finishedAt = Date()
            write(entry)
            return MigrationOutcome(entry: entry, succeeded: false, message: message)
        }

        // --- 1. Checagens ---
        if let problem = MigrationEngine.sourceProblem(source) { return fail(problem) }
        if let problem = MigrationEngine.nestingProblem(source: source, target: target) { return fail(problem) }
        if fm.fileExists(atPath: target.path) {
            return fail(L("\"%@\" already exists at the destination. Rename it or pick another folder.", name))
        }

        let measured = measure(source, isCancelled: isCancelled)
        entry.bytes = measured.bytes
        entry.fileCount = measured.files

        if let problem = MigrationEngine.destinationProblem(destinationRoot, needing: measured.bytes) {
            return fail(problem)
        }

        // --- 2. Cópia ---
        entry.phase = .copying
        write(entry)
        progress(.copying, "Copiando \(Fmt.bytes(measured.bytes))…", 0.05)

        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        } catch {
            return fail(L("Could not create the staging area: %@", error.localizedDescription))
        }

        // `ditto` é da Apple e preserva metadados, xattrs, ACLs e resource forks.
        // Evitamos `rsync` porque a implementação mudou no macOS 14.
        // `shell` devolve "" quando o comando falha, então o status de saída é
        // a única forma confiável de detectar erro do ditto.
        let copy = ProcessMonitor.run("/usr/bin/ditto", ["--noqtn", source.path, stagingItem.path])
        guard copy.status == 0 else {
            cleanup(staging)
            let detail = copy.error.trimmingCharacters(in: .whitespacesAndNewlines)
            return fail(L("ditto failed (code %d)%@.", copy.status, detail.isEmpty ? "" : ": \(detail)"))
        }
        if isCancelled() {
            cleanup(staging)
            return fail(L("Cancelled during the copy."))
        }

        // --- 3. Verificação ---
        entry.phase = .verifying
        write(entry)
        progress(.verifying, "Conferindo \(measured.files) arquivos…", 0.62)

        let copied = measure(stagingItem, isCancelled: isCancelled)
        // Tolerância de 0,5% em bytes: `ditto` pode diferir por blocos e clones.
        let byteDelta = abs(copied.bytes - measured.bytes)
        let tolerance = Int64(Double(measured.bytes) * 0.005) + 4096
        guard copied.files == measured.files, byteDelta <= tolerance else {
            cleanup(staging)
            return fail(L("The copy does not match: %d of %d files, %@ of %@. Nothing was moved.", copied.files, measured.files, Fmt.bytes(copied.bytes), Fmt.bytes(measured.bytes)))
        }

        // --- 4. Quarentena do original ---
        entry.phase = .quarantining
        write(entry)
        progress(.quarantining, L("Moving the original into quarantine…"), 0.72)

        do {
            try fm.createDirectory(at: quarantine, withIntermediateDirectories: true)
            try fm.moveItem(at: source, to: quarantineItem)
        } catch {
            cleanup(staging)
            return fail(L("Could not move the original: %@", error.localizedDescription))
        }

        // --- 5. Publicação no destino ---
        entry.phase = .publishing
        write(entry)
        progress(.publishing, "Publicando no destino…", 0.80)

        do {
            try fm.moveItem(at: stagingItem, to: target)
        } catch {
            // Rollback: devolve o original ao lugar.
            try? fm.moveItem(at: quarantineItem, to: source)
            cleanup(quarantine)
            cleanup(staging)
            entry.phase = .rolledBack
            write(entry)
            return fail(L("Failed to publish to the destination, original restored: %@", error.localizedDescription))
        }
        cleanup(staging)

        // --- 6. Link simbólico ---
        entry.phase = .linking
        write(entry)
        progress(.linking, L("Creating the symlink…"), 0.88)

        do {
            try fm.createSymbolicLink(at: source, withDestinationURL: target)
        } catch {
            // O original está intacto na quarentena: devolvê-lo é um rename
            // local e instantâneo. Trazer a cópia do volume externo de volta
            // seria uma cópia física lenta, que poderia falhar por espaço e
            // deixaria a quarentena órfã ocupando o disco para sempre.
            try? fm.moveItem(at: quarantineItem, to: source)
            try? fm.removeItem(at: target)
            cleanup(quarantine)
            entry.phase = .rolledBack
            write(entry)
            return fail(L("Failed to create the link, the original was restored: %@", error.localizedDescription))
        }

        // --- 7. Validação através do link ---
        entry.phase = .validating
        write(entry)
        progress(.validating, "Testando leitura e escrita pelo link…", 0.94)

        if let problem = validate(link: source, expectedFiles: measured.files, isCancelled: isCancelled) {
            try? fm.removeItem(at: source)              // remove só o link
            try? fm.moveItem(at: quarantineItem, to: source)
            try? fm.removeItem(at: target)
            cleanup(quarantine)
            entry.phase = .rolledBack
            write(entry)
            return fail(L("The link failed the test, everything was rolled back: %@", problem))
        }

        entry.phase = .done
        entry.finishedAt = Date()
        write(entry)
        progress(.done, L("Done"), 1.0)

        return MigrationOutcome(
            entry: entry,
            succeeded: true,
            message: L("%@ moved. The original stays in quarantine until you release it.", Fmt.bytes(measured.bytes))
        )
    }

    // MARK: - Reverter

    /// Desfaz uma migração: apaga o link, devolve o original da quarentena e
    /// remove a cópia do destino.
    func restore(_ entry: MigrationJournalEntry) -> MigrationOutcome {
        var updated = entry
        let source = URL(fileURLWithPath: entry.sourcePath)
        let target = URL(fileURLWithPath: entry.targetPath)
        let quarantine = URL(fileURLWithPath: entry.quarantinePath)

        guard fm.fileExists(atPath: quarantine.path) else {
            return MigrationOutcome(entry: entry, succeeded: false,
                                    message: L("The original is no longer in quarantine — there is no way to undo."))
        }

        // Remove o link (nunca o alvo: removeItem num symlink apaga só o link).
        if VolumeResolver.isSymbolicLink(source) {
            try? fm.removeItem(at: source)
        } else if fm.fileExists(atPath: source.path) {
            return MigrationOutcome(entry: entry, succeeded: false,
                                    message: L("Something real already exists at %@. Resolve it manually before undoing.", entry.sourcePath.tildeShortened))
        }

        do {
            try fm.moveItem(at: quarantine, to: source)
        } catch {
            return MigrationOutcome(entry: entry, succeeded: false,
                                    message: L("Failed to restore the original: %@", error.localizedDescription))
        }

        // A cópia no destino vira lixo — para a Lixeira, não apagada.
        if fm.fileExists(atPath: target.path) {
            try? fm.trashItem(at: target, resultingItemURL: nil)
        }
        cleanup(quarantine.deletingLastPathComponent())

        updated.phase = .rolledBack
        updated.finishedAt = Date()
        write(updated)

        return MigrationOutcome(entry: updated, succeeded: true,
                                message: L("%@ is back in its original place.", updated.name))
    }

    /// Libera a quarentena de uma migração concluída — é aqui que o espaço
    /// realmente volta para o disco do Mac.
    func releaseQuarantine(_ entry: MigrationJournalEntry) -> MigrationOutcome {
        var updated = entry
        let quarantine = URL(fileURLWithPath: entry.quarantinePath)

        guard fm.fileExists(atPath: quarantine.path) else {
            return MigrationOutcome(entry: entry, succeeded: true, message: L("Quarantine was already empty."))
        }
        // Confere que o link e o alvo estão de pé antes de soltar o original.
        guard VolumeResolver.isSymbolicLink(URL(fileURLWithPath: entry.sourcePath)),
              fm.fileExists(atPath: entry.targetPath) else {
            return MigrationOutcome(entry: entry, succeeded: false,
                                    message: L("The link or the target is not intact. Quarantine stays where it is."))
        }

        do {
            try fm.trashItem(at: quarantine, resultingItemURL: nil)
        } catch {
            return MigrationOutcome(entry: entry, succeeded: false,
                                    message: L("Failed to release the quarantine: %@", error.localizedDescription))
        }

        updated.quarantinePath = ""
        write(updated)
        return MigrationOutcome(entry: updated, succeeded: true,
                                message: L("%@ freed on the Mac's disk.", Fmt.bytes(entry.bytes)))
    }

    // MARK: - Auxiliares

    private struct Measurement {
        var bytes: Int64
        var files: Int
    }

    /// Conta arquivos e bytes. Serve para dimensionar e depois para conferir.
    private func measure(_ url: URL, isCancelled: () -> Bool) -> Measurement {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]

        var isDirectory = false
        if let values = try? url.resourceValues(forKeys: [.isDirectoryKey]) {
            isDirectory = values.isDirectory ?? false
        }

        if !isDirectory {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let size = Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
            return Measurement(bytes: size, files: 1)
        }

        var bytes: Int64 = 0
        var files = 0

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else { return Measurement(bytes: 0, files: 0) }

        for case let item as URL in enumerator {
            if isCancelled() { break }
            guard let values = try? item.resourceValues(forKeys: Set(keys)) else { continue }
            guard values.isRegularFile == true else { continue }
            files += 1
            bytes += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }

        return Measurement(bytes: bytes, files: files)
    }

    /// Confere que o link resolve, que a contagem bate e que dá para escrever
    /// através dele — este último teste é o que pega volume montado só-leitura.
    private func validate(link: URL, expectedFiles: Int, isCancelled: () -> Bool) -> String? {
        guard VolumeResolver.isSymbolicLink(link) else {
            return L("the link was not created")
        }
        guard let target = VolumeResolver.symlinkTarget(of: link),
              fm.fileExists(atPath: target.path) else {
            return L("the link does not resolve to an existing path")
        }

        let through = measure(link, isCancelled: isCancelled)
        guard through.files == expectedFiles else {
            return L("reading through the link gives %d files instead of %d", through.files, expectedFiles)
        }

        // Escreve e apaga um arquivo de teste dentro do alvo.
        var isDirectory = false
        if let values = try? target.resourceValues(forKeys: [.isDirectoryKey]) {
            isDirectory = values.isDirectory ?? false
        }
        if isDirectory {
            let probe = link.appendingPathComponent(".savemymac-probe")
            do {
                try Data("ok".utf8).write(to: probe)
                try fm.removeItem(at: probe)
            } catch {
                return L("could not write through the link (%@)", error.localizedDescription)
            }
        }

        return nil
    }

    private func cleanup(_ url: URL) {
        guard fm.fileExists(atPath: url.path) else { return }
        try? fm.removeItem(at: url)
    }
}
