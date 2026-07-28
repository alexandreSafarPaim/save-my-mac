import Foundation

/// Um item de primeiro nível dentro da Lixeira.
struct TrashItem: Identifiable, Hashable, Sendable {
    let id = UUID()
    var path: String
    var name: String
    var size: Int64
    var discardedAt: Date?
    /// `false` quando `addedToDirectoryDate` não estava disponível e caímos no
    /// mtime original — nesse caso a data não diz quando o item foi descartado.
    var discardedDateIsExact: Bool = true
    var isDirectory: Bool
}

struct TrashInfo: Sendable {
    var items: [TrashItem] = []
    var totalBytes: Int64 = 0
    /// Distingue "Lixeira vazia" de "ainda não medida".
    var isMeasured = false

    var count: Int { items.count }
    var isEmpty: Bool { items.isEmpty }

    /// O item mais antigo, para dar noção de quanto tempo aquilo está parado.
    var oldest: Date? {
        items.compactMap(\.discardedAt).min()
    }

    /// Só devolve texto quando a data é confiável: a frase aparece no diálogo
    /// da única ação irreversível do app e serve de argumento para confirmar.
    var oldestLabel: String? {
        let exact = items.filter(\.discardedDateIsExact).compactMap(\.discardedAt)
        guard let oldest = exact.min() else { return nil }
        return Fmt.relativeDate(oldest)
    }
}

struct TrashEmptyResult: Sendable {
    var removedCount: Int = 0
    var freedBytes: Int64 = 0
    var failures: [(path: String, reason: String)] = []
}

/// Lê e esvazia a Lixeira do usuário.
///
/// Escopo deliberado: **apenas `~/.Trash`**. Cada volume externo tem a sua
/// própria Lixeira em `/Volumes/<nome>/.Trashes/<uid>/`, e mexer nelas é uma
/// decisão diferente — some espaço de um disco que talvez não seja o que você
/// quer limpar. Aqui a conta é só a do Mac.
///
/// Esvaziar é, por definição, permanente: não existe "mover para a Lixeira" o
/// que já está nela. Por isso esta é a única operação do app sem volta, e ela
/// sempre passa por confirmação com total e contagem.
enum TrashManager {

    static var trashURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".Trash", isDirectory: true)
    }

    // MARK: - Leitura

    static func inspect(isCancelled: () -> Bool = { false }) -> TrashInfo {
        var info = TrashInfo()
        let fm = FileManager.default
        let root = trashURL

        guard fm.fileExists(atPath: root.path) else {
            info.isMeasured = true
            return info
        }

        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .addedToDirectoryDateKey,
            .contentModificationDateKey
        ]

        guard let contents = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: keys,
            options: []
        ) else {
            info.isMeasured = true
            return info
        }

        for url in contents {
            if isCancelled() { break }
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isDir = values?.isDirectory ?? false

            let size = isDir
                ? DiskMonitor.directorySize(at: url, isCancelled: isCancelled)
                : Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)

            // `addedToDirectoryDate` é quando o item entrou na Lixeira, que é o
            // que interessa. A Apple avisa que não é suportado em todo volume,
            // daí o fallback — marcado como impreciso.
            let added = values?.addedToDirectoryDate
            info.items.append(TrashItem(
                path: url.path,
                name: url.lastPathComponent,
                size: size,
                discardedAt: added ?? values?.contentModificationDate,
                discardedDateIsExact: added != nil,
                isDirectory: isDir
            ))
            info.totalBytes += size
        }

        info.items.sort { $0.size > $1.size }
        info.isMeasured = true
        return info
    }

    // MARK: - Esvaziar

    /// Esvazia enumerando o diretório **ao vivo**.
    ///
    /// Não recebe a lista da interface de propósito: o snapshot da tela pode ser
    /// de antes da última limpeza — e é justamente a limpeza no modo "Mover para
    /// a Lixeira" que enche isto aqui. Iterando um snapshot velho, o app diria
    /// "Lixeira esvaziada" sem apagar o que acabou de ser movido.
    static func empty(progress: (String, Double) -> Void) -> TrashEmptyResult {
        var result = TrashEmptyResult()
        let fm = FileManager.default
        let root = trashURL
        let rootPath = root.standardizedFileURL.path

        // `standardizedFileURL` resolve `.` e `..` mas NÃO resolve symlink. Se
        // `~/.Trash` for um link, a trava de caminho abaixo passaria e o app
        // apagaria recursivamente o alvo real. Esta é a única operação sem volta
        // do app, então vale a checagem.
        let rootValues = try? root.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard rootValues?.isSymbolicLink != true, rootValues?.isDirectory == true else {
            result.failures.append((root.path, "~/.Trash não é uma pasta real — nada foi removido"))
            return result
        }

        let keys: [URLResourceKey] = [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        guard let contents = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: keys, options: []
        ) else {
            result.failures.append((root.path, "Não foi possível ler a Lixeira"))
            return result
        }

        let total = max(1, contents.count)
        for (index, url) in contents.enumerated() {
            progress(url.lastPathComponent, Double(index) / Double(total))

            guard url.deletingLastPathComponent().standardizedFileURL.path == rootPath else {
                result.failures.append((url.path, "Fora da Lixeira do usuário"))
                continue
            }

            let values = try? url.resourceValues(forKeys: Set(keys))
            let size = (values?.isDirectory ?? false)
                ? DiskMonitor.directorySize(at: url)
                : Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)

            do {
                // `removeItem` não segue symlink: um link dentro da Lixeira
                // apontando para fora tem só o link removido.
                try fm.removeItem(at: url)
                result.removedCount += 1
                result.freedBytes += size
            } catch {
                result.failures.append((url.path, friendlyReason(for: error, url: url)))
            }
        }

        progress("Concluído", 1.0)
        return result
    }

    /// Traduz os erros que de fato aparecem ao esvaziar a Lixeira.
    private static func friendlyReason(for error: Error, url: URL) -> String {
        let ns = error as NSError

        // Arquivo com o flag de imutável (`chflags uchg`) — o Finder pede
        // confirmação nesse caso; aqui só reportamos.
        if let values = try? url.resourceValues(forKeys: [.isUserImmutableKey]),
           values.isUserImmutable == true {
            return "Arquivo travado. Destrave no Finder (Obter Informações) e tente de novo."
        }

        switch ns.code {
        case NSFileWriteNoPermissionError, NSFileReadNoPermissionError:
            return "Sem permissão. Pode pertencer a outro usuário ou estar em uso."
        case NSFileWriteFileExistsError:
            return "Conflito de nome dentro da Lixeira."
        default:
            return ns.localizedDescription
        }
    }
}
