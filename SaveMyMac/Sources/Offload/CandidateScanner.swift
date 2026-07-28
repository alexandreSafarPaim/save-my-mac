import Foundation

/// Sugere pastas que valem ser movidas para outro disco — e, com a mesma
/// clareza, avisa quais **não** valem.
///
/// A distinção importa: não é "grande ou pequeno". É se a pasta é grande, fria
/// e sem alternativa nativa. Cache de npm é grande e regenerável, então apagar
/// é melhor que mover. DerivedData do Xcode em SSD externo até piora o tempo de
/// build, e o Xcode tem ajuste próprio de localização.
final class CandidateScanner: @unchecked Sendable {

    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser

    /// Catálogo de lugares conhecidos, com o veredito de cada um.
    private struct Known {
        var relative: String
        var name: String
        var reason: String
        var recommendation: OffloadRecommendation
        var hint: String?
    }

    private let catalog: [Known] = [
        // --- Boas candidatas: grandes, frias, sem ajuste nativo ---
        .init(relative: "Library/Developer/Xcode/iOS DeviceSupport",
              name: "Xcode — iOS DeviceSupport",
              reason: "Símbolos de versões antigas de iOS. Enorme e consultado raramente.",
              recommendation: .move, hint: nil),
        .init(relative: "Library/Developer/CoreSimulator/Devices",
              name: "Simuladores de iOS",
              reason: "Cada simulador criado fica em disco. Acesso morno, volume alto.",
              recommendation: .move, hint: nil),
        .init(relative: "Library/Application Support/MobileSync/Backup",
              name: "Backups de iPhone/iPad",
              reason: "Costuma ser o maior arquivo escondido do Mac e você quase nunca abre.",
              recommendation: .move, hint: nil),
        .init(relative: "Library/Android/sdk",
              name: "Android SDK",
              reason: "Imagens de sistema e ferramentas pesadas, lidas só ao compilar.",
              recommendation: .move, hint: nil),
        .init(relative: ".android/avd",
              name: "Emuladores Android (AVD)",
              reason: "Discos virtuais grandes, usados sob demanda.",
              recommendation: .move, hint: nil),
        .init(relative: "Library/Application Support/Steam",
              name: "Biblioteca da Steam",
              reason: "Jogos ocupam dezenas de GB e você joga um por vez.",
              recommendation: .useNativeSetting,
              hint: "A Steam tem \"Pastas da biblioteca\" nas preferências — mais robusto que um link."),
        .init(relative: "Movies",
              name: "Filmes e vídeos",
              reason: "Mídia bruta é o maior consumidor típico e raramente é reaberta.",
              recommendation: .move, hint: nil),
        .init(relative: "Parallels",
              name: "Máquinas virtuais Parallels",
              reason: "Discos virtuais de dezenas de GB.",
              recommendation: .move, hint: nil),
        .init(relative: "Library/Containers/com.utmapp.UTM/Data/Documents",
              name: "Máquinas virtuais UTM",
              reason: "Imagens de VM pesadas.",
              recommendation: .move, hint: nil),
        .init(relative: ".ollama/models",
              name: "Modelos do Ollama",
              reason: "Pesos de modelos ocupam muitos GB e são só leitura.",
              recommendation: .move, hint: nil),
        .init(relative: ".cache/huggingface",
              name: "Cache do Hugging Face",
              reason: "Pesos de modelos baixados, raramente todos em uso.",
              recommendation: .move, hint: nil),

        // --- Melhor apagar do que mover ---
        .init(relative: "Library/Developer/Xcode/DerivedData",
              name: "Xcode — DerivedData",
              reason: "Build intermediário. Em disco externo o build fica mais lento, não mais rápido.",
              recommendation: .deleteInstead,
              hint: "Apague pela aba Limpeza; o Xcode reconstrói."),
        .init(relative: ".npm/_cacache",
              name: "Cache do npm",
              reason: "Regenerável e barato — mover dá trabalho sem ganho.",
              recommendation: .deleteInstead, hint: nil),
        .init(relative: "Library/Caches/Homebrew",
              name: "Cache do Homebrew",
              reason: "Downloads já instalados. Apagar é imediato.",
              recommendation: .deleteInstead, hint: nil),
        .init(relative: "Library/Caches/pip",
              name: "Cache do pip",
              reason: "Rodas Python baixadas, refeitas sob demanda.",
              recommendation: .deleteInstead, hint: nil),

        // --- Tem ajuste nativo, melhor que link ---
        .init(relative: "Library/Containers/com.docker.docker/Data/vms",
              name: "Disco virtual do Docker",
              reason: "Cresce sem parar, mas o Docker gerencia esse arquivo ativamente.",
              recommendation: .useNativeSetting,
              hint: "Docker Desktop → Settings → Resources → Disk image location."),
        .init(relative: "Library/Application Support/Adobe",
              name: "Cache do Adobe",
              reason: "Pesado, porém os apps Adobe têm ajuste de cache de mídia.",
              recommendation: .useNativeSetting,
              hint: "Preferências → Media Cache → mudar a pasta."),

        // --- Nunca linkar ---
        .init(relative: "Library/Mobile Documents",
              name: "iCloud Drive",
              reason: "O daemon do iCloud gerencia esta pasta e briga com links.",
              recommendation: .never, hint: nil),
        .init(relative: "Pictures/Photos Library.photoslibrary",
              name: "Biblioteca do Fotos",
              reason: "A Apple não suporta link aqui e há risco real de corrupção.",
              recommendation: .never,
              hint: "Mova a biblioteca e abra o Fotos com Option pressionado para apontar para ela.")
    ]

    // MARK: - Varredura

    func scan(
        progress: @escaping (String, Double) -> Void,
        isCancelled: @escaping () -> Bool
    ) -> [OffloadCandidate] {

        var candidates: [OffloadCandidate] = []
        let total = max(1, catalog.count)

        for (index, known) in catalog.enumerated() {
            if isCancelled() { break }
            progress("Avaliando \(known.name)…", Double(index) / Double(total) * 0.7)

            let url = home.appendingPathComponent(known.relative)
            guard fm.fileExists(atPath: url.path) else { continue }
            // Se já está descarregado, não é candidato.
            guard VolumeResolver.freesSpaceOnMac(url) else { continue }

            let size = DiskMonitor.directorySize(at: url, isCancelled: isCancelled)
            guard size > 200 * 1024 * 1024 else { continue }

            candidates.append(OffloadCandidate(
                path: url.path,
                displayName: known.name,
                size: size,
                reason: known.reason,
                recommendation: known.recommendation,
                nativeSettingHint: known.hint
            ))
        }

        // Descobertas: pastas grandes de primeiro nível que não estão no catálogo.
        if !isCancelled() {
            progress("Procurando outras pastas grandes…", 0.75)
            candidates += discoverUnknown(
                existing: Set(candidates.map(\.path)),
                isCancelled: isCancelled
            )
        }

        progress(L("Done"), 1.0)

        // Boas candidatas primeiro, depois por tamanho.
        return candidates.sorted { lhs, rhs in
            let order: [OffloadRecommendation: Int] = [
                .move: 0, .useNativeSetting: 1, .deleteInstead: 2, .never: 3
            ]
            let l = order[lhs.recommendation] ?? 9
            let r = order[rhs.recommendation] ?? 9
            if l != r { return l < r }
            return lhs.size > rhs.size
        }
    }

    /// Pastas grandes que o catálogo não conhece — sugeridas com cautela.
    private func discoverUnknown(
        existing: Set<String>,
        isCancelled: () -> Bool
    ) -> [OffloadCandidate] {

        let roots = ["Developer", "Projects", "projetos", "Documents", "Movies", "Music", "Pictures", "work", "code"]
        var found: [OffloadCandidate] = []

        for rootName in roots {
            if isCancelled() { break }
            let root = home.appendingPathComponent(rootName)
            guard fm.fileExists(atPath: root.path), VolumeResolver.freesSpaceOnMac(root) else { continue }
            guard let contents = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in contents {
                if isCancelled() { break }
                guard existing.contains(url.path) == false else { continue }
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
                guard VolumeResolver.freesSpaceOnMac(url) else { continue }

                let size = DiskMonitor.directorySize(at: url, isCancelled: isCancelled)
                guard size > 5 * 1024 * 1024 * 1024 else { continue }   // acima de 5 GB

                found.append(OffloadCandidate(
                    path: url.path,
                    displayName: "\(rootName)/\(url.lastPathComponent)",
                    size: size,
                    reason: "Pasta de \(Fmt.bytes(size)) que o catálogo não conhece. Confira se é conteúdo de acesso raro antes de mover.",
                    recommendation: .move,
                    nativeSettingHint: nil
                ))
                if found.count >= 20 { return found }
            }
        }

        return found
    }
}
