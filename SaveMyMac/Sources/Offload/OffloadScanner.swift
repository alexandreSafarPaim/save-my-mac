import Foundation

/// Inventaria os links simbólicos da pasta pessoal que apontam para fora do
/// disco do Mac — o padrão de "descarregar pasta pesada para um SSD externo".
///
/// Totalmente somente leitura: nada é criado, movido ou apagado aqui.
final class OffloadScanner: @unchecked Sendable {

    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser

    /// Profundidade máxima a partir da home. Cobre os casos reais
    /// (`~/.gradle`, `~/Library/Android/sdk`, `~/Library/Application Support/X/y`)
    /// sem varrer a árvore inteira.
    private let maxDepth = 4

    /// Limite de diretórios visitados, para a varredura terminar sempre rápido.
    private let maxDirectories = 40_000

    /// Nunca descer aqui: são grandes, ruidosos e não guardam links de offload.
    ///
    /// `Containers` e `Group Containers` são essenciais nesta lista: todo app
    /// sandboxado tem, dentro de `Data/`, links relativos para Desktop,
    /// Documents, Downloads, Movies, Music e Pictures da home real. Sem o corte,
    /// o inventário viria com centenas de links irrelevantes e o único que o
    /// usuário criou de verdade ficaria enterrado no meio.
    private let skipDescend: Set<String> = [
        "node_modules", ".git", ".svn", ".Trash", "DerivedData",
        "Mobile Documents", "CloudStorage", "Pods", ".build", ".next",
        "build", "dist", "target", "vendor",
        "Containers", "Group Containers"
    ]

    private let skipExtensions: Set<String> = [
        "photoslibrary", "app", "framework", "bundle", "musiclibrary",
        "tvlibrary", "aplibrary", "sparsebundle", "xcodeproj", "xcworkspace"
    ]

    // MARK: - Entrada principal

    func scan(
        progress: @escaping (String, Double) -> Void,
        isCancelled: @escaping () -> Bool
    ) -> OffloadInventory {

        var inventory = OffloadInventory()
        var visitedDirectories = 0
        var linkURLs: [URL] = []

        progress("Procurando links simbólicos…", 0.05)
        walk(
            directory: home,
            depth: 0,
            visited: &visitedDirectories,
            found: &linkURLs,
            isCancelled: isCancelled,
            progress: { count in
                progress("Procurando links simbólicos… (\(count) pastas)",
                         0.05 + min(0.35, Double(count) / 30_000.0 * 0.35))
            }
        )

        inventory.scannedDirectories = visitedDirectories
        inventory.reachedLimit = visitedDirectories >= maxDirectories

        guard !isCancelled() else { return inventory }

        // Resolve cada link e calcula o tamanho real do alvo.
        var entries: [SymlinkEntry] = []
        var acceptedTargets: [String] = []
        let totalLinks = max(1, linkURLs.count)

        for (index, linkURL) in linkURLs.enumerated() {
            if isCancelled() { break }
            let fraction = 0.40 + (Double(index) / Double(totalLinks)) * 0.45
            progress("Medindo \(linkURL.lastPathComponent)…", fraction)

            guard let entry = describe(link: linkURL, isCancelled: isCancelled) else { continue }

            // Dois links aninhados no mesmo alvo (ex.: `~/.gradle` e
            // `~/.gradle/caches`) contariam o mesmo conteúdo duas vezes e
            // inflariam o total L("off the Mac's disk"). Mantém só o de fora.
            if entry.statusRaw == 0 {
                let isNested = acceptedTargets.contains { entry.targetPath.hasPrefix($0 + "/") }
                if isNested { continue }
                acceptedTargets.append(entry.targetPath)
            }

            entries.append(entry)
        }

        // Interessa mostrar tudo, mas com os que economizam espaço primeiro.
        inventory.links = entries.sorted { lhs, rhs in
            if lhs.savesSpace != rhs.savesSpace { return lhs.savesSpace }
            return lhs.size > rhs.size
        }

        inventory.groups = buildGroups(from: inventory.links)

        if !isCancelled() {
            progress("Procurando dados órfãos no destino…", 0.88)
            inventory.orphans = findOrphans(for: inventory.links, isCancelled: isCancelled)
        }

        progress(L("Done"), 1.0)
        return inventory
    }

    // MARK: - Varredura

    private func walk(
        directory: URL,
        depth: Int,
        visited: inout Int,
        found: inout [URL],
        isCancelled: () -> Bool,
        // `progress` recebe a contagem por parâmetro de propósito: capturar
        // `visitedDirectories` no call site enquanto ele está passado como
        // `inout` seria acesso sobreposto e derrubaria o app em runtime.
        progress: (Int) -> Void
    ) {
        if isCancelled() || depth > maxDepth || visited >= maxDirectories { return }

        visited += 1
        if visited % 500 == 0 { progress(visited) }

        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey],
            options: []   // inclui ocultos: ~/.gradle, ~/.android etc.
        ) else { return }

        for url in contents {
            if isCancelled() || visited >= maxDirectories { return }

            guard let values = try? url.resourceValues(
                forKeys: [.isSymbolicLinkKey, .isDirectoryKey]
            ) else { continue }

            if values.isSymbolicLink == true {
                found.append(url)
                continue   // nunca descer por dentro de um link
            }

            guard values.isDirectory == true else { continue }

            let name = url.lastPathComponent
            if skipDescend.contains(name) { continue }
            if skipExtensions.contains(url.pathExtension.lowercased()) { continue }

            walk(
                directory: url,
                depth: depth + 1,
                visited: &visited,
                found: &found,
                isCancelled: isCancelled,
                progress: progress
            )
        }
    }

    // MARK: - Descrição de um link

    private func describe(link: URL, isCancelled: () -> Bool) -> SymlinkEntry? {
        guard let target = VolumeResolver.symlinkTarget(of: link) else { return nil }

        let targetExists = fm.fileExists(atPath: target.path)
        let mountPoint = targetExists ? VolumeResolver.mountPoint(of: target) : nil
        let volumeName = targetExists ? VolumeResolver.volumeName(of: target) : nil

        // Descobre se o destino pretendido é um volume externo mesmo estando
        // ausente: "/Volumes/Algo/..." é a convenção do macOS.
        let looksLikeExternal = target.path.hasPrefix("/Volumes/")
        let inferredVolumeName: String? = {
            if let volumeName { return volumeName }
            guard looksLikeExternal else { return nil }
            let parts = target.path.split(separator: "/")
            return parts.count >= 2 ? String(parts[1]) : nil
        }()

        let status: Int
        if !targetExists {
            // Link pendurado: distingue "volume desmontado" de "alvo apagado".
            status = looksLikeExternal && !fm.fileExists(atPath: "/Volumes/\(inferredVolumeName ?? "")")
                ? 1   // volumeMissing
                : 2   // broken
        } else if VolumeResolver.isOnHomeVolume(target) {
            status = 3   // sameDisk
        } else {
            status = 0   // offloaded
        }

        let size: Int64 = status == 0
            ? DiskMonitor.directorySize(at: target, isCancelled: isCancelled)
            : 0

        // Para arquivos soltos, directorySize retorna 0 — cai no tamanho direto.
        let finalSize: Int64 = {
            guard status == 0, size == 0 else { return size }
            let values = try? target.resourceValues(
                forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]
            )
            return Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }()

        let created = (try? link.resourceValues(forKeys: [.creationDateKey]))?.creationDate

        return SymlinkEntry(
            linkPath: link.path,
            targetPath: target.path,
            targetVolumeName: inferredVolumeName,
            targetMountPoint: mountPoint,
            size: finalSize,
            created: created,
            statusRaw: status
        )
    }

    // MARK: - Agrupamento por volume

    private func buildGroups(from links: [SymlinkEntry]) -> [OffloadVolumeGroup] {
        var buckets: [String: [SymlinkEntry]] = [:]

        for link in links where link.status != .sameDisk {
            // Chave: ponto de montagem real, ou o inferido de /Volumes/<nome>.
            let key = link.targetMountPoint
                ?? (link.targetVolumeName.map { "/Volumes/\($0)" })
                ?? "desconhecido"
            buckets[key, default: []].append(link)
        }

        return buckets.map { mountPoint, groupLinks in
            let isMounted = fm.fileExists(atPath: mountPoint)
            let capacity = isMounted ? VolumeResolver.capacity(ofMountPoint: mountPoint) : nil
            let name = groupLinks.compactMap(\.targetVolumeName).first
                ?? (mountPoint as NSString).lastPathComponent

            return OffloadVolumeGroup(
                name: name,
                mountPoint: mountPoint,
                isMounted: isMounted,
                capacityTotal: capacity?.total ?? 0,
                capacityAvailable: capacity?.available ?? 0,
                links: groupLinks.sorted { $0.size > $1.size }
            )
        }
        .sorted { $0.offloadedSize > $1.offloadedSize }
    }

    // MARK: - Dados órfãos no destino

    /// Procura, nas pastas-pai dos alvos, itens que não são alvo de nenhum link.
    /// No padrão `/Volumes/X/mac-offload/*`, isso encontra pastas que sobraram
    /// de um link removido e continuam ocupando o disco externo.
    ///
    /// A pasta-pai só é considerada se **a maioria do que está nela já é alvo de
    /// link** — ou seja, se ela é de fato uma área dedicada a offload. Sem essa
    /// checagem, um link apontando para uma pasta qualquer de um disco de
    /// trabalho faria o app acusar como "órfão" todo arquivo que o usuário
    /// guardou ali de propósito.
    private func findOrphans(
        for links: [SymlinkEntry],
        isCancelled: () -> Bool
    ) -> [OrphanEntry] {

        let knownTargets = Set(
            links.map { URL(fileURLWithPath: $0.targetPath).standardizedFileURL.path }
        )

        // Pastas-pai distintas dos alvos que estão realmente montados.
        var parents = Set<String>()
        for link in links where link.status == .offloaded {
            let parent = URL(fileURLWithPath: link.targetPath)
                .deletingLastPathComponent().standardizedFileURL
            // Não sobe até a raiz do volume: só faz sentido numa pasta dedicada.
            guard parent.path != "/", parent.path.split(separator: "/").count >= 3 else { continue }
            parents.insert(parent.path)
        }

        var orphans: [OrphanEntry] = []

        for parentPath in parents.sorted() {
            if isCancelled() { break }
            let parent = URL(fileURLWithPath: parentPath)
            guard let contents = try? fm.contentsOfDirectory(
                at: parent,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            // Confirma que esta pasta é uma área dedicada a offload.
            let known = contents.filter { knownTargets.contains($0.standardizedFileURL.path) }.count
            guard contents.count > 1, known * 2 >= contents.count else { continue }

            for url in contents {
                if isCancelled() { break }
                let path = url.standardizedFileURL.path
                guard !knownTargets.contains(path) else { continue }

                let size = DiskMonitor.directorySize(at: url, isCancelled: isCancelled)
                guard size > 10 * 1024 * 1024 else { continue }

                orphans.append(OrphanEntry(
                    path: path,
                    size: size,
                    modified: (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                        .contentModificationDate,
                    volumeName: VolumeResolver.volumeName(of: url) ?? "—"
                ))
            }
        }

        return orphans.sorted { $0.size > $1.size }
    }
}
