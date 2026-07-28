import Foundation

/// Um fator que compõe o score, com o peso e a explicação em texto.
struct HealthFactor: Identifiable {
    var id: String { name }
    var name: String
    var detail: String
    /// 0...1, onde 1 é o ideal.
    var quality: Double
    var weight: Double

    var points: Double { quality * weight }
}

/// Score de saúde 0–100.
///
/// Não existe "score de saúde" no macOS — este é um índice do próprio app.
/// Por isso ele é totalmente explicável: cada fator aparece na interface com o
/// peso e o motivo da nota, para o número nunca parecer mágico.
struct HealthReport {
    var score: Int
    var factors: [HealthFactor]

    var headline: String {
        switch score {
        case ..<50: return "Seu Mac está pedindo socorro."
        case ..<70: return "Dá pra melhorar bastante."
        case ..<85: return "Seu Mac está bem — e dá pra ficar melhor."
        default: return "Seu Mac está em ótima forma."
        }
    }

    /// Pior fator, para sugerir a próxima ação.
    var weakest: HealthFactor? {
        factors.min { $0.quality < $1.quality }
    }
}

enum HealthScore {

    static func evaluate(
        bootVolume: VolumeInfo?,
        memory: MemorySnapshot,
        swap: SwapSnapshot,
        thermal: ThermalSnapshot,
        reclaimable: Int64,
        duplicateBytes: Int64,
        brokenLinks: Int
    ) -> HealthReport {

        var factors: [HealthFactor] = []

        // 1. Espaço livre no disco de inicialização — o fator mais importante.
        //    Abaixo de 10% livres o macOS começa a sofrer de verdade.
        if let volume = bootVolume, volume.total > 0 {
            let freeFraction = Double(volume.available) / Double(volume.total)
            let quality = normalize(freeFraction, poor: 0.05, good: 0.25)
            factors.append(HealthFactor(
                name: "Espaço livre",
                detail: "\(Fmt.bytes(volume.available)) livres de \(Fmt.bytes(volume.total)) (\(Fmt.percent(freeFraction)))",
                quality: quality,
                weight: 34
            ))
        }

        // 2. Pressão de memória. Travada + comprimida é o que realmente indica aperto.
        let pressure = memory.pressureFraction
        factors.append(HealthFactor(
            name: "Pressão de memória",
            detail: "\(memory.pressureLabel) · \(Fmt.bytes(memory.used)) em uso de \(Fmt.bytes(memory.total))",
            quality: normalize(1 - pressure, poor: 0.35, good: 0.7),
            weight: 18
        ))

        // 3. Swap em uso: sinal de que a RAM não está dando conta.
        let swapFraction = memory.total > 0 ? Double(swap.used) / Double(memory.total) : 0
        factors.append(HealthFactor(
            name: "Uso de swap",
            detail: swap.used == 0
                ? "Nenhum swap em uso"
                : "\(Fmt.bytes(swap.used)) em swap",
            quality: normalize(1 - swapFraction * 4, poor: 0.4, good: 0.95),
            weight: 10
        ))

        // 4. Estado térmico — o dado oficial da Apple, sempre disponível.
        let thermalQuality: Double
        switch thermal.thermalState {
        case .nominal: thermalQuality = 1.0
        case .fair: thermalQuality = 0.72
        case .serious: thermalQuality = 0.35
        case .critical: thermalQuality = 0.0
        @unknown default: thermalQuality = 0.8
        }
        factors.append(HealthFactor(
            name: "Temperatura",
            detail: thermal.displayTemperature.map { "\(thermal.thermalStateLabel) · \(Fmt.celsius($0))" }
                ?? thermal.thermalStateLabel,
            quality: thermalQuality,
            weight: 14
        ))

        // 5. Quanto de lixo está acumulado, relativo ao tamanho do disco.
        if let volume = bootVolume, volume.total > 0 {
            let junkFraction = Double(reclaimable) / Double(volume.total)
            factors.append(HealthFactor(
                name: "Lixo acumulado",
                detail: reclaimable == 0
                    ? "Nada identificado ainda — rode uma análise"
                    : "\(Fmt.bytes(reclaimable)) recuperáveis",
                quality: normalize(1 - junkFraction * 6, poor: 0.4, good: 0.95),
                weight: 14
            ))
        }

        // 6. Duplicados.
        factors.append(HealthFactor(
            name: "Duplicados",
            detail: duplicateBytes == 0 ? "Nenhum encontrado" : "\(Fmt.bytes(duplicateBytes)) em cópias idênticas",
            quality: duplicateBytes == 0 ? 1.0 : normalize(1 - Double(duplicateBytes) / (20 * 1_073_741_824), poor: 0.3, good: 0.95),
            weight: 6
        ))

        // 7. Links de offload quebrados: cada um é um app que pode falhar.
        factors.append(HealthFactor(
            name: "Links de offload",
            detail: brokenLinks == 0
                ? "Todos saudáveis"
                : "\(brokenLinks) com problema",
            quality: brokenLinks == 0 ? 1.0 : max(0, 1 - Double(brokenLinks) * 0.34),
            weight: 4
        ))

        let totalWeight = factors.reduce(0) { $0 + $1.weight }
        let earned = factors.reduce(0) { $0 + $1.points }
        let score = totalWeight > 0 ? Int((earned / totalWeight * 100).rounded()) : 0

        return HealthReport(score: max(0, min(100, score)), factors: factors)
    }

    /// Mapeia um valor bruto para 0...1 com corte inferior e superior.
    private static func normalize(_ value: Double, poor: Double, good: Double) -> Double {
        guard good > poor else { return 0.5 }
        return ((value - poor) / (good - poor)).clamped(0, 1)
    }
}
