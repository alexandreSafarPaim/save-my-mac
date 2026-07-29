import Foundation
import UserNotifications

/// Avisa quando o disco de inicialização fica com pouco espaço.
///
/// Duas regras que definem se isso é útil ou irritante:
///
/// 1. **Histerese.** O aviso dispara ao cruzar o limiar para baixo e só rearma
///    depois de subir 3 pontos percentuais acima dele. Sem isso, um disco
///    oscilando em torno de 10 % notificaria a cada checagem.
/// 2. **Intervalo mínimo.** Mesmo continuando abaixo do limiar, no máximo um
///    aviso a cada 6 horas.
@MainActor
final class SpaceAlert: ObservableObject {

    private enum Key {
        static let lastAlert = "lowSpaceLastAlertAt"
        static let armed = "lowSpaceArmed"
    }

    /// Quanto o espaço livre precisa subir acima do limiar para rearmar o aviso.
    private let rearmMargin = 3.0
    private let minimumInterval: TimeInterval = 6 * 3600

    @Published private(set) var permissionDenied = false
    @Published private(set) var unavailableReason: String?

    private var didRequestPermission = false

    // MARK: - Permissão

    /// Pedida só quando o usuário liga a opção, não na inicialização — pedir
    /// permissão de notificação antes de o usuário querer notificação é a
    /// maneira mais rápida de ela ser negada para sempre.
    func requestPermissionIfNeeded() {
        guard !didRequestPermission else { return }
        didRequestPermission = true

        // Sem bundle identifier o UNUserNotificationCenter lança exceção em vez
        // de devolver erro — acontece ao rodar o binário fora de um .app.
        guard Bundle.main.bundleIdentifier != nil else {
            permissionDenied = true
            unavailableReason = L("Notifications require the app to run as a bundle (.app).")
            return
        }

        // Fora da thread principal e sem bloquear: se o serviço de notificação
        // estiver ruim, o app continua funcionando.
        Task.detached(priority: .utility) {
            let center = UNUserNotificationCenter.current()
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                await MainActor.run { [weak self] in
                    self?.permissionDenied = !granted
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.permissionDenied = true
                    self?.unavailableReason = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Avaliação

    /// Chamado a cada atualização de métricas. Devolve `true` se notificou.
    @discardableResult
    func evaluate(volume: VolumeInfo?, thresholdPercent: Double, enabled: Bool) -> Bool {
        guard enabled, let volume, volume.total > 0 else { return false }

        let freePercent = Double(volume.available) / Double(volume.total) * 100
        let defaults = UserDefaults.standard
        let armed = defaults.object(forKey: Key.armed) as? Bool ?? true

        // Subiu o suficiente: rearma e não avisa.
        if freePercent >= thresholdPercent + rearmMargin {
            if !armed { defaults.set(true, forKey: Key.armed) }
            return false
        }

        guard freePercent < thresholdPercent, armed else { return false }

        if let last = defaults.object(forKey: Key.lastAlert) as? Date,
           Date().timeIntervalSince(last) < minimumInterval {
            return false
        }

        notify(volume: volume, freePercent: freePercent)
        defaults.set(false, forKey: Key.armed)
        defaults.set(Date(), forKey: Key.lastAlert)
        return true
    }

    private func notify(volume: VolumeInfo, freePercent: Double) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = L("Low space on %@", volume.name)
        content.body = "Restam \(Fmt.bytes(volume.available)) "
            + "(\(String(format: "%.0f", freePercent)) %). "
            + "Abra o SaveMyMac para ver o que pode sair."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "lowSpace-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Para a interface poder mostrar o estado sem esperar a próxima avaliação.
    func isLow(volume: VolumeInfo?, thresholdPercent: Double) -> Bool {
        guard let volume, volume.total > 0 else { return false }
        return Double(volume.available) / Double(volume.total) * 100 < thresholdPercent
    }
}
