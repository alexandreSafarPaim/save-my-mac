import Foundation
import Combine
import AppKit

/// Preferências do app, persistidas em `UserDefaults`.
///
/// Separado do `GameStore` de propósito: aquilo é progresso, isto é
/// configuração — e configuração precisa estar disponível antes de qualquer
/// varredura, inclusive na inicialização em segundo plano.
///
/// ─────────────────────────────────────────────────────────────────────────
/// POR QUE NENHUMA PROPRIEDADE AQUI USA `@Published`
/// ─────────────────────────────────────────────────────────────────────────
///
/// `@Published` dispara `objectWillChange` em **toda atribuição**, inclusive
/// quando o valor novo é igual ao antigo. Isso parece detalhe e não é.
///
/// O `MenuBarExtra(isInserted:)` escreve no binding a cada passagem de
/// atualização, para refletir o estado real de inserção do item. Com
/// `@Published` por trás, a sequência virava:
///
///     escreve false → publica → corpo do App invalidado → cena da barra de
///     menus reconstruída → escreve false → publica → …
///
/// Um ciclo que se realimenta na velocidade do processador. Medido: **6.600
/// reconstruções em 9,6 segundos, 100 % de CPU, +86 MB em 13 s**. O spindump
/// mostrava a atualização do menu chamando `invalidateProperties` em si mesma.
///
/// Nenhuma das minhas correções anteriores pegou isso porque todas terminavam
/// escrevendo no mesmo `@Published`: primeiro via `Binding(get:set:)`, depois
/// via `$prefs.showMenuBar`. O caminho mudava; o gatilho não.
///
/// Agora cada setter compara antes de publicar. Escrever o mesmo valor é um
/// no-op, e o ciclo não fecha. Vale para todas as propriedades, não só a que
/// deu problema: publicar mudança que não houve nunca está certo.
@MainActor
final class Preferences: ObservableObject {

    private enum Key {
        static let showMenuBar = "showMenuBarExtra"
        static let hideDockIcon = "hideDockIcon"
        static let lowSpaceAlerts = "lowSpaceAlerts"
        static let lowSpaceThreshold = "lowSpaceThresholdPercent"
        static let menuBarMetric = "menuBarMetric"
    }

    /// O que aparece ao lado do relógio quando o espaço é curto.
    enum MenuBarMetric: String, CaseIterable, Identifiable {
        case disk
        case memory
        case cpu
        case temperature
        case none

        var id: String { rawValue }

        var label: String {
            switch self {
            case .disk: return "Espaço livre"
            case .memory: return "Pressão de memória"
            case .cpu: return "Uso de CPU"
            case .temperature: return "Temperatura"
            case .none: return "Só o ícone"
            }
        }
    }

    // MARK: - Armazenamento

    private var _showMenuBar: Bool
    private var _hideDockIcon: Bool
    private var _lowSpaceAlerts: Bool
    private var _lowSpaceThreshold: Double
    private var _menuBarMetric: MenuBarMetric

    // MARK: - Propriedades

    /// Escrito pelo `MenuBarExtra` a cada atualização — é exatamente aqui que a
    /// comparação impede o ciclo. O contador registra a frequência, para a
    /// próxima suspeita ter número em vez de palpite.
    var showMenuBar: Bool {
        get { _showMenuBar }
        set {
            Trace.count("Preferences.showMenuBar escrito", every: 500)
            guard newValue != _showMenuBar else { return }
            Trace.mark("showMenuBar mudou de fato: \(_showMenuBar) → \(newValue)")
            objectWillChange.send()
            _showMenuBar = newValue
            UserDefaults.standard.set(newValue, forKey: Key.showMenuBar)
        }
    }

    /// Esconder do Dock transforma o app num utilitário de barra de menus.
    var hideDockIcon: Bool {
        get { _hideDockIcon }
        set {
            guard newValue != _hideDockIcon else { return }
            objectWillChange.send()
            _hideDockIcon = newValue
            UserDefaults.standard.set(newValue, forKey: Key.hideDockIcon)
            applyActivationPolicy()
        }
    }

    var lowSpaceAlerts: Bool {
        get { _lowSpaceAlerts }
        set {
            guard newValue != _lowSpaceAlerts else { return }
            objectWillChange.send()
            _lowSpaceAlerts = newValue
            UserDefaults.standard.set(newValue, forKey: Key.lowSpaceAlerts)
        }
    }

    /// Percentual de espaço livre abaixo do qual o app avisa.
    var lowSpaceThreshold: Double {
        get { _lowSpaceThreshold }
        set {
            guard newValue != _lowSpaceThreshold else { return }
            objectWillChange.send()
            _lowSpaceThreshold = newValue
            UserDefaults.standard.set(newValue, forKey: Key.lowSpaceThreshold)
        }
    }

    var menuBarMetric: MenuBarMetric {
        get { _menuBarMetric }
        set {
            guard newValue != _menuBarMetric else { return }
            objectWillChange.send()
            _menuBarMetric = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: Key.menuBarMetric)
        }
    }

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Key.showMenuBar: true,
            Key.hideDockIcon: false,
            Key.lowSpaceAlerts: true,
            Key.lowSpaceThreshold: 10.0
        ])

        // Reparo pontual de um valor escrito por defeito, não pelo usuário.
        //
        // Durante o ciclo de atualização infinito, o `MenuBarExtra` escrevia
        // `false` no binding milhares de vezes, e o `didSet` de então persistia
        // cada uma em `UserDefaults`. Resultado: a preferência ficou gravada
        // como falsa sem que ninguém tivesse desligado nada — e `register`
        // não sobrepõe valor explicitamente gravado. O ícone então nunca
        // aparecia, mesmo com o recurso ligado e o bug corrigido.
        //
        // Isto roda uma única vez, marcado por chave própria. Não é o app
        // ignorando a escolha do usuário: é o app desfazendo a escolha que ele
        // nunca fez. Depois desta vez, a preferência é respeitada sempre.
        let repairKey = "menuBarPreferenceRepaired.v1"
        if !defaults.bool(forKey: repairKey) {
            defaults.set(true, forKey: repairKey)
            if MenuBarFeature.isEnabled {
                defaults.set(true, forKey: Key.showMenuBar)
                NSLog("[SaveMyMac] Preferência da barra de menus restaurada para ligada.")
            }
        }

        // A trava do recurso é aplicada aqui, uma vez. A cena recebe o binding
        // projetado direto; envolvê-lo para aplicar a trava criaria um objeto
        // novo a cada avaliação, que é outro jeito de nunca convergir.
        _showMenuBar = MenuBarFeature.isEnabled && defaults.bool(forKey: Key.showMenuBar)
        _hideDockIcon = defaults.bool(forKey: Key.hideDockIcon)
        _lowSpaceAlerts = defaults.bool(forKey: Key.lowSpaceAlerts)
        _lowSpaceThreshold = defaults.double(forKey: Key.lowSpaceThreshold)
        _menuBarMetric = MenuBarMetric(
            rawValue: defaults.string(forKey: Key.menuBarMetric) ?? MenuBarMetric.disk.rawValue
        ) ?? .disk
    }

    /// Aplica a política de ativação sem precisar reiniciar o app — é o que
    /// permite esconder e mostrar o ícone do Dock na hora.
    func applyActivationPolicy() {
        NSApp.setActivationPolicy(hideDockIcon ? .accessory : .regular)
        if !hideDockIcon {
            NSApp.activate(ignoringOtherApps: false)
        }
    }
}
