import Foundation

/// Uma amostra do estado da memória num instante.
struct MemorySample: Identifiable {
    let id = UUID()
    var at: Date
    /// 0...1 — travada + comprimida sobre o total. É esta a curva que importa.
    var pressure: Double
    /// 0...1 — memória em uso sobre o total.
    var used: Double
    var swapBytes: Int64
}

/// Guarda os últimos minutos de pressão de memória.
///
/// Existe porque um número instantâneo não responde à pergunta que o usuário
/// realmente tem. "Pressão: moderada" agora não diz nada; "verde na última meia
/// hora" diz que mais RAM não resolveria nada hoje, e "vermelho há dez minutos"
/// diz que alguma coisa está fora de controle.
struct MemoryHistory {

    /// 2 s por amostra × 450 = 15 minutos.
    static let capacity = 450

    private(set) var samples: [MemorySample] = []

    mutating func record(memory: MemorySnapshot, swap: SwapSnapshot) {
        samples.append(MemorySample(
            at: Date(),
            pressure: memory.pressureFraction,
            used: memory.usedFraction,
            swapBytes: Int64(clamping: swap.used)
        ))
        if samples.count > MemoryHistory.capacity {
            samples.removeFirst(samples.count - MemoryHistory.capacity)
        }
    }

    var pressureCurve: [Double] { samples.map(\.pressure) }

    var span: TimeInterval {
        guard let first = samples.first?.at, let last = samples.last?.at else { return 0 }
        return last.timeIntervalSince(first)
    }

    var peakPressure: Double { samples.map(\.pressure).max() ?? 0 }

    /// Resumo em texto do período observado.
    var verdict: String? {
        guard samples.count >= 10 else { return nil }
        let minutes = Int(span / 60)
        let window = minutes >= 1 ? "\(minutes) min" : "\(Int(span)) s"

        if peakPressure < 0.35 {
            return "Pressão baixa nos últimos \(window) — mais RAM não mudaria nada hoje."
        }
        if peakPressure < 0.60 {
            return "Pressão chegou a \(Fmt.percent(peakPressure)) nos últimos \(window)."
        }
        return "Pressão alta (pico de \(Fmt.percent(peakPressure))) nos últimos \(window) — algo está apertando a RAM."
    }
}

// MARK: - Crescimento por processo

/// Rastreia o consumo de cada processo ao longo da sessão para apontar quem
/// cresce sem parar — o sintoma de vazamento que um número instantâneo esconde.
struct GrowthTracker {

    private struct Record {
        var firstSeen: Date
        var firstBytes: Int64
        var lastBytes: Int64
    }

    private var records: [Int32: Record] = [:]

    /// Precisa de tempo mínimo de observação para não acusar um app que acabou
    /// de abrir e naturalmente cresceu enquanto carregava.
    private let minimumObservation: TimeInterval = 150
    private let minimumGrowth: Int64 = 250 * 1024 * 1024
    private let minimumRatio: Double = 1.5

    mutating func update(with rows: [ProcessInfoRow]) {
        let now = Date()
        var seen = Set<Int32>()

        for row in rows {
            seen.insert(row.pid)
            if var record = records[row.pid] {
                record.lastBytes = row.memoryBytes
                records[row.pid] = record
            } else {
                records[row.pid] = Record(
                    firstSeen: now,
                    firstBytes: row.memoryBytes,
                    lastBytes: row.memoryBytes
                )
            }
        }

        // Processo que morreu sai do mapa, senão o dicionário cresce para sempre
        // e um pid reciclado herdaria o histórico de outro.
        records = records.filter { seen.contains($0.key) }
    }

    /// Quanto o processo cresceu desde que foi visto pela primeira vez, se é
    /// crescimento relevante.
    func growth(for pid: Int32) -> Int64? {
        guard let record = records[pid] else { return nil }
        guard Date().timeIntervalSince(record.firstSeen) >= minimumObservation else { return nil }

        let delta = record.lastBytes - record.firstBytes
        guard delta >= minimumGrowth else { return nil }
        guard record.firstBytes > 0,
              Double(record.lastBytes) / Double(record.firstBytes) >= minimumRatio else { return nil }

        return delta
    }

    func isGrowing(_ pid: Int32) -> Bool {
        growth(for: pid) != nil
    }
}
