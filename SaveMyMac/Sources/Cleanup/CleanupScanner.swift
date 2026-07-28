import Foundation

/// Varre o disco procurando o que pode ser removido, agrupado por categoria e risco.
/// Nada é apagado aqui — a varredura é somente leitura.
final class CleanupScanner: @unchecked Sendable {

    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser

    // Arquivos grandes e duplicados agora moram em `FileScanner`, cada um com
    // sua própria tela. Aqui ficam só as categorias regeneráveis.

    // MARK: - Entrada principal

    func scan(
        progress: @escaping (String, Double) -> Void,
        isCancelled: @escaping () -> Bool
    ) -> [CleanupCategory] {

        var categories: [CleanupCategory] = []

        let steps: [(String, () -> CleanupCategory?)] = [
            ("Caches de aplicativos", { self.userCaches(isCancelled) }),
            ("Logs", { self.logs(isCancelled) }),
            ("Ferramentas de desenvolvedor", { self.developerJunk(isCancelled) }),
            ("Caches de gerenciadores de pacotes", { self.packageManagerCaches(isCancelled) }),
            ("Pastas node_modules antigas", { self.staleNodeModules(isCancelled) }),
            ("Backups de iPhone/iPad", { self.deviceBackups(isCancelled) }),
            ("Downloads antigos", { self.oldDownloads(isCancelled) }),
            ("Instaladores", { self.installers(isCancelled) }),
            ("Sobras de apps removidos", { self.appLeftovers(isCancelled) }),
            ("Arquivos .DS_Store", { self.dsStoreFiles(isCancelled) })
        ]

        let stepWeight = 1.0 / Double(steps.count)

        for (index, step) in steps.enumerated() {
            if isCancelled() { return categories }
            progress(step.0, Double(index) * stepWeight)
            if let category = step.1(), !category.isEmpty {
                categories.append(category)
            }
        }

        progress("Concluído", 1.0)
        return categories.sorted { $0.totalSize > $1.totalSize }
    }

    // MARK: - 1. Caches de usuário

    private func userCaches(_ isCancelled: () -> Bool) -> CleanupCategory? {
        let root = home.appendingPathComponent("Library/Caches")
        // Estes têm efeitos colaterais chatos se apagados enquanto o app roda.
        let skip: Set<String> = [
            "com.apple.containermanagerd",
            "CloudKit",
            "com.apple.aned",
            "com.apple.iCloudHelper"
        ]

        var items = childItems(of: root, isCancelled: isCancelled) { name in
            !skip.contains(name)
        }

        // Caches dentro de containers de apps sandboxados
        let containers = home.appendingPathComponent("Library/Containers")
        if let apps = try? fm.contentsOfDirectory(at: containers, includingPropertiesForKeys: nil) {
            for app in apps.prefix(400) {
                if isCancelled() { break }
                let cache = app.appendingPathComponent("Data/Library/Caches")
                guard fm.fileExists(atPath: cache.path) else { continue }
                guard freesSpace(cache) else { continue }
                let size = DiskMonitor.directorySize(at: cache, isCancelled: isCancelled)
                guard size > 5 * 1024 * 1024 else { continue }
                items.append(CleanupItem(
                    path: cache.path,
                    displayName: "\(app.lastPathComponent) (cache do container)",
                    size: size,
                    modified: modificationDate(cache),
                    isDirectory: true,
                    note: "Cache interno de app sandboxado"
                ))
            }
        }

        guard !items.isEmpty else { return nil }
        return CleanupCategory(
            name: "Caches de aplicativos",
            subtitle: "Dados temporários que os apps recriam sozinhos",
            symbol: "shippingbox",
            risk: .safe,
            riskScore: 1,
            items: items.sorted { $0.size > $1.size }
        )
    }

    // MARK: - 2. Logs

    private func logs(_ isCancelled: () -> Bool) -> CleanupCategory? {
        var items = childItems(
            of: home.appendingPathComponent("Library/Logs"),
            isCancelled: isCancelled,
            minimumSize: 1024 * 1024
        )

        // Relatórios de travamento
        let crashDirs = [
            "Library/Logs/DiagnosticReports",
            "Library/Application Support/CrashReporter"
        ]
        for relative in crashDirs {
            let url = home.appendingPathComponent(relative)
            guard fm.fileExists(atPath: url.path) else { continue }
            guard freesSpace(url) else { continue }
            let size = DiskMonitor.directorySize(at: url, isCancelled: isCancelled)
            guard size > 512 * 1024 else { continue }
            items.append(CleanupItem(
                path: url.path,
                displayName: url.lastPathComponent,
                size: size,
                modified: modificationDate(url),
                isDirectory: true,
                note: "Relatórios de travamento antigos"
            ))
        }

        guard !items.isEmpty else { return nil }
        return CleanupCategory(
            name: "Logs e relatórios de erro",
            subtitle: "Registros de diagnóstico que não são mais consultados",
            symbol: "doc.text.magnifyingglass",
            risk: .safe,
            riskScore: 1,
            items: items.sorted { $0.size > $1.size }
        )
    }

    // MARK: - 3. Ferramentas de desenvolvedor

    private func developerJunk(_ isCancelled: () -> Bool) -> CleanupCategory? {
        let candidates: [(String, String, String)] = [
            ("Library/Developer/Xcode/DerivedData", "Xcode — DerivedData",
             "Builds intermediários; o Xcode reconstrói na próxima compilação"),
            ("Library/Developer/Xcode/Archives", "Xcode — Archives",
             "Arquivos de distribuição antigos"),
            ("Library/Developer/Xcode/iOS DeviceSupport", "Xcode — iOS DeviceSupport",
             "Símbolos de versões de iOS que você provavelmente não depura mais"),
            ("Library/Developer/Xcode/watchOS DeviceSupport", "Xcode — watchOS DeviceSupport",
             "Símbolos de watchOS antigos"),
            ("Library/Developer/Xcode/UserData/IB Support", "Xcode — IB Support",
             "Cache do Interface Builder"),
            ("Library/Developer/CoreSimulator/Caches", "Simuladores — Caches",
             "Cache de runtimes de simulador"),
            ("Library/Developer/CoreSimulator/Devices", "Simuladores — Dispositivos",
             "Cada simulador criado ocupa espaço; recriáveis pelo Xcode"),
            ("Library/Caches/com.apple.dt.Xcode", "Xcode — Cache geral",
             "Cache de índice e download do Xcode"),
            ("Library/Developer/CoreSimulator/Temp", "Simuladores — Temp",
             "Temporários de simulador"),
            ("Library/Application Support/Code/Cache", "VS Code — Cache", "Cache do editor"),
            ("Library/Application Support/Code/CachedData", "VS Code — CachedData", "Cache do editor"),
            ("Library/Caches/JetBrains", "JetBrains — Cache", "Índices das IDEs JetBrains"),
            ("Library/Android/sdk/system-images", "Android SDK — System Images",
             "Imagens de emulador Android (pesadas)"),
            (".android/avd", "Android — Emuladores (AVD)", "Máquinas virtuais Android"),
            ("Library/Containers/com.docker.docker/Data/vms", "Docker — VMs",
             "Disco virtual do Docker Desktop")
        ]

        var items: [CleanupItem] = []
        for (relative, name, note) in candidates {
            if isCancelled() { break }
            let url = home.appendingPathComponent(relative)
            guard fm.fileExists(atPath: url.path) else { continue }
            guard freesSpace(url) else { continue }
            let size = DiskMonitor.directorySize(at: url, isCancelled: isCancelled)
            guard size > 1024 * 1024 else { continue }
            items.append(CleanupItem(
                path: url.path,
                displayName: name,
                size: size,
                modified: modificationDate(url),
                isDirectory: true,
                note: note
            ))
        }

        guard !items.isEmpty else { return nil }
        return CleanupCategory(
            name: "Ferramentas de desenvolvedor",
            subtitle: "Builds, símbolos e simuladores — normalmente o maior ganho num Mac de dev",
            symbol: "hammer",
            risk: .caution,
            riskScore: 5,
            items: items.sorted { $0.size > $1.size }
        )
    }

    // MARK: - 4. Caches de gerenciadores de pacotes

    private func packageManagerCaches(_ isCancelled: () -> Bool) -> CleanupCategory? {
        let candidates: [(String, String)] = [
            (".npm/_cacache", "npm"),
            (".yarn/cache", "Yarn"),
            ("Library/Caches/Yarn", "Yarn (legado)"),
            (".pnpm-store", "pnpm"),
            ("Library/pnpm/store", "pnpm (store)"),
            (".bun/install/cache", "Bun"),
            ("Library/Caches/deno", "Deno"),
            ("Library/Caches/pip", "pip"),
            ("Library/Caches/pypoetry", "Poetry"),
            (".cache/uv", "uv"),
            ("Library/Caches/Homebrew", "Homebrew"),
            (".cargo/registry/cache", "Cargo (Rust)"),
            (".gradle/caches", "Gradle"),
            (".m2/repository", "Maven"),
            ("Library/Caches/go-build", "Go (build)"),
            ("go/pkg/mod/cache/download", "Go (módulos)"),
            ("Library/Caches/CocoaPods", "CocoaPods"),
            ("Library/Caches/composer", "Composer (PHP)"),
            (".nuget/packages", "NuGet"),
            (".rustup/toolchains", "rustup (toolchains)"),
            ("Library/Caches/ms-playwright", "Playwright (navegadores)"),
            (".cache/puppeteer", "Puppeteer (navegadores)")
        ]

        var items: [CleanupItem] = []
        for (relative, name) in candidates {
            if isCancelled() { break }
            let url = home.appendingPathComponent(relative)
            guard fm.fileExists(atPath: url.path) else { continue }
            guard freesSpace(url) else { continue }
            let size = DiskMonitor.directorySize(at: url, isCancelled: isCancelled)
            guard size > 1024 * 1024 else { continue }
            items.append(CleanupItem(
                path: url.path,
                displayName: name,
                size: size,
                modified: modificationDate(url),
                isDirectory: true,
                note: "Será baixado de novo quando necessário"
            ))
        }

        guard !items.isEmpty else { return nil }
        return CleanupCategory(
            name: "Caches de gerenciadores de pacotes",
            subtitle: "npm, pip, Homebrew, Gradle e afins",
            symbol: "arrow.down.circle",
            risk: .caution,
            riskScore: 4,
            items: items.sorted { $0.size > $1.size }
        )
    }

    // MARK: - 5. node_modules abandonados

    private func staleNodeModules(_ isCancelled: () -> Bool) -> CleanupCategory? {
        let cutoff = Date().addingTimeInterval(-90 * 86_400)
        var items: [CleanupItem] = []

        let roots = ["Developer", "Projects", "projetos", "Documents", "Sites", "code", "Code", "dev", "src", "work"]
            .map { home.appendingPathComponent($0) }
            .filter { fm.fileExists(atPath: $0.path) && freesSpace($0) }

        for root in roots {
            if isCancelled() { break }
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let url as URL in enumerator {
                if isCancelled() { break }
                guard url.lastPathComponent == "node_modules" else { continue }
                enumerator.skipDescendants()
                guard freesSpace(url) else { continue }

                let modified = modificationDate(url)
                guard let modified, modified < cutoff else { continue }

                let size = DiskMonitor.directorySize(at: url, isCancelled: isCancelled)
                guard size > 20 * 1024 * 1024 else { continue }

                items.append(CleanupItem(
                    path: url.path,
                    displayName: url.deletingLastPathComponent().lastPathComponent + "/node_modules",
                    size: size,
                    modified: modified,
                    isDirectory: true,
                    note: "Sem alterações desde \(Fmt.shortDate(modified)) — recuperável com npm install"
                ))
                if items.count >= 100 { break }
            }
        }

        guard !items.isEmpty else { return nil }
        return CleanupCategory(
            name: "node_modules abandonados",
            subtitle: "Projetos sem atividade há mais de 90 dias",
            symbol: "folder.badge.minus",
            risk: .caution,
            riskScore: 4,
            items: items.sorted { $0.size > $1.size }
        )
    }

    // MARK: - 6. Backups de dispositivos

    private func deviceBackups(_ isCancelled: () -> Bool) -> CleanupCategory? {
        let root = home.appendingPathComponent("Library/Application Support/MobileSync/Backup")
        let items = childItems(of: root, isCancelled: isCancelled, minimumSize: 1024 * 1024)
            .map { item -> CleanupItem in
                var copy = item
                copy.note = "Backup local de iPhone/iPad — confirme que você tem backup no iCloud antes de remover"
                return copy
            }

        guard !items.isEmpty else { return nil }
        return CleanupCategory(
            name: "Backups locais de iPhone/iPad",
            subtitle: "Costumam ser os maiores arquivos ocultos do Mac",
            symbol: "iphone.gen3",
            risk: .review,
            riskScore: 8,
            items: items
        )
    }

    // A Lixeira saiu daqui de propósito.
    //
    // Ela virou um card próprio na aba Limpeza, com `TrashManager`. O motivo é
    // um bug real: no modo padrão ("Mover para a Lixeira") o removedor chamava
    // `trashItem` em algo que já estava na Lixeira — o Cocoa devolve erro ou,
    // pior, renomeia dentro dela e o app reportava sucesso sem liberar byte.
    // Esvaziar é sempre permanente, então não pode compartilhar o caminho das
    // outras categorias.

    // MARK: - 8. Downloads antigos

    private func oldDownloads(_ isCancelled: () -> Bool) -> CleanupCategory? {
        let root = home.appendingPathComponent("Downloads")
        let cutoff = Date().addingTimeInterval(-90 * 86_400)

        let items = childItems(of: root, isCancelled: isCancelled, minimumSize: 1024 * 1024)
            .filter { item in
                guard let modified = item.modified else { return false }
                return modified < cutoff
            }
            .map { item -> CleanupItem in
                var copy = item
                copy.note = "Baixado \(Fmt.relativeDate(item.modified))"
                return copy
            }

        guard !items.isEmpty else { return nil }
        return CleanupCategory(
            name: "Downloads antigos",
            subtitle: "Sem uso há mais de 90 dias",
            symbol: "arrow.down.doc",
            risk: .review,
            riskScore: 6,
            items: items
        )
    }

    // MARK: - 9. Instaladores

    private func installers(_ isCancelled: () -> Bool) -> CleanupCategory? {
        let extensions: Set<String> = ["dmg", "pkg", "mpkg", "iso"]
        let roots = ["Downloads", "Desktop", "Documents"].map { home.appendingPathComponent($0) }
        var items: [CleanupItem] = []

        for root in roots {
            if isCancelled() { break }
            guard let contents = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in contents {
                guard extensions.contains(url.pathExtension.lowercased()) else { continue }
                guard freesSpace(url) else { continue }
                let size = fileSize(url)
                guard size > 5 * 1024 * 1024 else { continue }
                items.append(CleanupItem(
                    path: url.path,
                    displayName: url.lastPathComponent,
                    size: size,
                    modified: modificationDate(url),
                    isDirectory: false,
                    note: "Instalador em \(root.lastPathComponent) — o app já instalado não precisa dele"
                ))
            }
        }

        guard !items.isEmpty else { return nil }
        return CleanupCategory(
            name: "Instaladores (.dmg, .pkg, .iso)",
            subtitle: "Imagens de instalação que já cumpriram seu papel",
            symbol: "externaldrive.badge.xmark",
            risk: .caution,
            riskScore: 3,
            items: items.sorted { $0.size > $1.size }
        )
    }

    // MARK: - 10. Sobras de apps removidos

    private func appLeftovers(_ isCancelled: () -> Bool) -> CleanupCategory? {
        let installed = installedBundleIdentifiers()
        guard !installed.isEmpty else { return nil }

        let searchDirs = [
            "Library/Application Support",
            "Library/Containers",
            "Library/Saved Application State",
            "Library/HTTPStorages"
        ]

        var items: [CleanupItem] = []

        for relative in searchDirs {
            if isCancelled() { break }
            let root = home.appendingPathComponent(relative)
            guard let contents = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in contents.prefix(600) {
                if isCancelled() { break }
                var name = url.lastPathComponent
                if name.hasSuffix(".savedState") { name = String(name.dropLast(11)) }

                // Apenas pastas com nome de bundle id (com pontos) e não da Apple
                guard name.contains("."), !name.hasPrefix("com.apple.") else { continue }
                // Match por prefixo: `com.foo.App.Helper` e
                // `com.foo.App.binarycookies` pertencem a `com.foo.app` e não
                // podem ser tratados como sobra de app desinstalado.
                let lowerName = name.lowercased()
                guard !installed.contains(where: { lowerName == $0 || lowerName.hasPrefix($0 + ".") })
                else { continue }
                guard freesSpace(url) else { continue }
                // Ignora prefixos conhecidos do sistema
                guard !name.hasPrefix("com.microsoft.autoupdate"),
                      !name.hasPrefix("CrashReporter") else { continue }

                let size = DiskMonitor.directorySize(at: url, isCancelled: isCancelled)
                guard size > 5 * 1024 * 1024 else { continue }

                items.append(CleanupItem(
                    path: url.path,
                    displayName: name,
                    size: size,
                    modified: modificationDate(url),
                    isDirectory: true,
                    note: "Nenhum app instalado corresponde a este identificador (\(relative.tildeShortened))"
                ))
            }
        }

        guard !items.isEmpty else { return nil }
        return CleanupCategory(
            name: "Sobras de apps desinstalados",
            subtitle: "Dados de suporte sem aplicativo correspondente",
            symbol: "app.badge.checkmark",
            risk: .review,
            riskScore: 7,
            items: items.sorted { $0.size > $1.size }
        )
    }

    private func installedBundleIdentifiers() -> Set<String> {
        var ids = Set<String>()
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Library/CoreServices"),
            home.appendingPathComponent("Applications")
        ]

        for root in roots {
            guard let contents = try? fm.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }
            for app in contents where app.pathExtension == "app" {
                let plist = app.appendingPathComponent("Contents/Info.plist")
                guard let data = try? Data(contentsOf: plist),
                      let dict = try? PropertyListSerialization.propertyList(
                        from: data, options: [], format: nil
                      ) as? [String: Any],
                      let bundleID = dict["CFBundleIdentifier"] as? String
                else { continue }
                ids.insert(bundleID.lowercased())
            }
        }
        return ids
    }

    // MARK: - 11. .DS_Store

    private func dsStoreFiles(_ isCancelled: () -> Bool) -> CleanupCategory? {
        var totalSize: Int64 = 0
        var count = 0
        var paths: [String] = []

        let roots = ["Desktop", "Documents", "Downloads"].map { home.appendingPathComponent($0) }
        for root in roots {
            if isCancelled() { break }
            guard freesSpace(root) else { continue }
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let url as URL in enumerator {
                if isCancelled() { break }
                guard url.lastPathComponent == ".DS_Store" else { continue }
                totalSize += fileSize(url)
                count += 1
                if paths.count < 5000 { paths.append(url.path) }
            }
        }

        guard count > 0, let first = paths.first else { return nil }
        // Agrupado num único item para não poluir a lista com milhares de linhas.
        let item = CleanupItem(
            path: first,
            displayName: "\(count) arquivos .DS_Store",
            size: totalSize,
            modified: nil,
            isDirectory: false,
            note: "Metadados de visualização do Finder — recriados automaticamente",
            extraPaths: Array(paths.dropFirst())
        )
        return CleanupCategory(
            name: "Arquivos .DS_Store",
            subtitle: "Poluição do Finder espalhada pelas pastas",
            symbol: "eye.slash",
            risk: .safe,
            riskScore: 1,
            items: [item]
        )
    }

    // MARK: - Utilitários

    /// Lista os filhos diretos de um diretório como itens de limpeza.
    private func childItems(
        of root: URL,
        isCancelled: () -> Bool,
        minimumSize: Int64 = 1024 * 1024,
        filter: (String) -> Bool = { _ in true }
    ) -> [CleanupItem] {

        guard fm.fileExists(atPath: root.path) else { return [] }
        guard let contents = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: []
        ) else { return [] }

        var items: [CleanupItem] = []
        for url in contents {
            if isCancelled() { break }
            guard filter(url.lastPathComponent) else { continue }
            guard freesSpace(url) else { continue }

            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let size = isDir
                ? DiskMonitor.directorySize(at: url, isCancelled: isCancelled)
                : fileSize(url)

            guard size >= minimumSize else { continue }

            items.append(CleanupItem(
                path: url.path,
                displayName: url.lastPathComponent,
                size: size,
                modified: modificationDate(url),
                isDirectory: isDir,
                note: nil
            ))
        }
        return items.sorted { $0.size > $1.size }
    }

    /// Só entra na lista de limpeza o que realmente libera espaço no Mac.
    ///
    /// Links simbólicos são descartados (apagar o link não devolve bytes) e
    /// conteúdo que vive em outro volume também — é o caso de pastas já
    /// descarregadas para um SSD externo, como `~/.gradle` apontando para
    /// `/Volumes/CachePart`. Sem esse filtro o app contaria espaço do disco
    /// externo como recuperável no interno e apagaria dados do lado errado.
    private func freesSpace(_ url: URL) -> Bool {
        VolumeResolver.freesSpaceOnMac(url)
    }

    private func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
        return Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
    }

    private func modificationDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
