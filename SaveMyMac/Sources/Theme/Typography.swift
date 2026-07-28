import SwiftUI
import AppKit

/// Tipografia do design: Space Grotesk na interface, JetBrains Mono nos números
/// e rótulos. As duas fontes são variáveis e vêm embutidas em
/// `Contents/Resources/Fonts` (registradas via `ATSApplicationFontsPath`).
///
/// Se por algum motivo o registro falhar, tudo cai para as fontes do sistema
/// sem quebrar o layout.
enum Typo {

    static let uiFamily = "Space Grotesk"
    static let monoFamily = "JetBrains Mono"

    /// Verifica uma vez se as fontes embutidas realmente carregaram.
    private static let hasUI: Bool = isAvailable(uiFamily)
    private static let hasMono: Bool = isAvailable(monoFamily)

    private static func isAvailable(_ family: String) -> Bool {
        NSFontManager.shared.availableFontFamilies.contains(family)
    }

    // MARK: - Interface

    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        hasUI
            ? .custom(uiFamily, size: size).weight(weight)
            : .system(size: size, weight: weight, design: .default)
    }

    // MARK: - Monoespaçada

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        hasMono
            ? .custom(monoFamily, size: size).weight(weight)
            : .system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: - Estilos nomeados do design

    /// Rótulo pequeno em maiúsculas com muito espaçamento (ex.: "PAINEL DO SISTEMA").
    static var eyebrow: Font { mono(11, .regular) }
    static var eyebrowSmall: Font { mono(9.5, .semibold) }

    /// Título grande de tela (32px no Painel, 30px nas outras).
    static var screenTitle: Font { ui(30, .bold) }
    static var screenTitleLarge: Font { ui(32, .bold) }

    static var cardTitle: Font { ui(13.5, .semibold) }
    static var rowTitle: Font { ui(14.5, .semibold) }
    static var body: Font { ui(13, .regular) }
    static var bodySmall: Font { ui(12.5, .regular) }
    static var caption: Font { ui(11.5, .regular) }

    /// Número enorme dos cards de métrica.
    static var metricValue: Font { mono(38, .bold) }
    static var scoreValue: Font { mono(44, .bold) }
    static var statValue: Font { mono(22, .bold) }
    static var sizeValue: Font { mono(16, .bold) }
    static var monoCaption: Font { mono(11) }
    static var monoTiny: Font { mono(10) }
}

/// Espaçamento de letras dos rótulos em maiúsculas.
enum Track {
    static let eyebrow: CGFloat = 2.4
    static let label: CGFloat = 1.9
    static let crumb: CGFloat = 2.2
}
