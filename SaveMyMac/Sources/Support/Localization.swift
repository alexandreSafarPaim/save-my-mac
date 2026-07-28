import Foundation
import Combine

// MARK: - Idiomas

/// Idiomas da interface. `system` segue o Mac.
enum Language: String, CaseIterable, Identifiable {
    case system
    case en
    case pt
    case es
    case fr

    var id: String { rawValue }

    /// Cada idioma se nomeia **no próprio idioma**.
    ///
    /// Traduzir os nomes para o idioma atual seria pior: alguém que abriu o app
    /// numa língua que não entende precisa reconhecer a sua na lista, e
    /// "Portoghese" não ajuda quem procura "Português".
    var label: String {
        switch self {
        case .system: return L("Same as macOS")
        case .en: return "English"
        case .pt: return "Português"
        case .es: return "Español"
        case .fr: return "Français"
        }
    }

    var flag: String {
        switch self {
        case .system: return "􀆪"
        case .en: return "EN"
        case .pt: return "PT"
        case .es: return "ES"
        case .fr: return "FR"
        }
    }
}

// MARK: - Estado

/// Idioma da interface.
///
/// Sem projeto Xcode não há String Catalog nem pastas `.lproj` compiladas, então
/// a tabela é Swift puro. Isso não é só contorno: `NSLocalizedString` resolve
/// contra o bundle, e trocar de idioma em tempo de execução exigiria substituir
/// o bundle por baixo do sistema. Com tabela própria, trocar é reler um
/// dicionário.
///
/// **Não usa `@Published`** — o setter compara antes de publicar. A regra vale
/// para todo o projeto desde que um `@Published` disparando em atribuição de
/// valor igual fechou um ciclo de atualização que consumia um núcleo inteiro.
/// Ver `Preferences`.
@MainActor
final class Localization: ObservableObject {

    static let shared = Localization()

    private static let key = "interfaceLanguage"

    private var _language: Language

    var language: Language {
        get { _language }
        set {
            guard newValue != _language else { return }
            objectWillChange.send()
            _language = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: Localization.key)
            Localization.active = newValue.resolved
            Trace.mark("idioma da interface: \(newValue.rawValue) → \(newValue.resolved.rawValue)")
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: Localization.key)
        _language = Language(rawValue: saved ?? "") ?? .system
        Localization.active = _language.resolved
        Trace.mark("idioma inicial: \(_language.rawValue) → \(_language.resolved.rawValue)")
    }

    /// Lido pela função `L`, que é global e síncrona.
    ///
    /// Precisa ser `nonisolated(unsafe)`: `L` é chamada de dentro de corpos de
    /// view milhares de vezes por segundo e não pode pagar salto de ator. A
    /// escrita acontece só na troca de idioma, sempre na thread principal, e o
    /// valor é um enum de um byte — não há estado intermediário para alguém ler.
    nonisolated(unsafe) fileprivate static var active: Language = .en
}

extension Language {
    /// Traduz `system` para um idioma concreto usando a preferência do macOS.
    ///
    /// Percorre `preferredLanguages` na ordem em que o usuário as ordenou, em
    /// vez de olhar só a primeira: quem tem "es, pt, en" e não tem espanhol
    /// suportado deve receber português, não inglês.
    var resolved: Language {
        guard self == .system else { return self }

        for tag in Locale.preferredLanguages {
            // "pt-BR" → "pt", "es-419" → "es". O app não distingue variantes
            // regionais; fingir que distingue daria falsa expectativa.
            let base = tag.split(separator: "-").first.map(String.init) ?? tag
            if let match = Language(rawValue: base.lowercased()), match != .system {
                return match
            }
        }
        return .en
    }
}

// MARK: - Busca

/// Texto traduzido.
///
/// A **chave é o texto em inglês**, e não um identificador inventado
/// (`dashboard.title`). Duas razões práticas:
///
/// 1. Idioma sem tradução para aquela frase cai no inglês, que é uma frase de
///    verdade. Com chave simbólica, faltar tradução mostra `dashboard.title` na
///    tela — defeito visível para o usuário em vez de degradação silenciosa.
/// 2. O código continua legível: `Text(L("Analyze my Mac"))` diz o que aparece
///    na tela sem precisar consultar tabela nenhuma.
///
/// O custo é que mudar o texto em inglês invalida as traduções daquela frase.
/// Aceitável: mudar o texto original é justamente quando se quer revisar as
/// traduções.
func L(_ key: String) -> String {
    switch Localization.active {
    case .en, .system: return key
    case .pt: return Strings.pt[key] ?? key
    case .es: return Strings.es[key] ?? key
    case .fr: return Strings.fr[key] ?? key
    }
}

/// Versão com valores interpolados. Use `%@` para texto e `%d` para inteiro.
///
/// Os marcadores existem para a **ordem** poder mudar entre idiomas — em
/// algumas línguas o número vem depois do substantivo. Concatenar com `+`
/// tornaria isso impossível.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key), arguments: arguments)
}

/// Singular ou plural conforme a contagem.
///
/// As quatro línguas daqui se resolvem com duas formas, mas não pela mesma
/// regra: inglês, português e espanhol pluralizam a partir de 2; **o francês
/// usa o singular também para zero** ("0 semaine", não "0 semaines"). Tratar
/// tudo como `count == 1` produziria erro de gramática em francês.
func Lp(_ singular: String, _ plural: String, _ count: Int) -> String {
    let useSingular: Bool
    switch Localization.active {
    case .fr: useSingular = count <= 1
    default: useSingular = count == 1
    }
    return L(useSingular ? singular : plural, count)
}
