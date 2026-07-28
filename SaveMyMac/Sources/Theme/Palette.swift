import SwiftUI

enum ThemeMode: String, CaseIterable, Codable {
    case dark
    case light

    var label: String {
        switch self {
        case .dark: return "ESCURO"
        case .light: return "CLARO"
        }
    }

    var colorScheme: ColorScheme {
        self == .dark ? .dark : .light
    }

    var toggled: ThemeMode { self == .dark ? .light : .dark }
}

/// Paleta do design, traduzida das variáveis CSS.
struct Palette {

    var bg: Color
    var bg2: Color
    var card: Color
    var card2: Color
    var stroke: Color
    var stroke2: Color
    var t1: Color
    var t2: Color
    var t3: Color
    var accent: Color
    var cyan: Color
    var ok: Color
    var warn: Color
    var danger: Color
    var grid: Color
    var shadow: Color

    /// Gradiente de acento usado em anéis, botões e barras.
    var gradient: LinearGradient {
        LinearGradient(
            colors: [accent, cyan],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var gradientHorizontal: LinearGradient {
        LinearGradient(colors: [accent, cyan], startPoint: .leading, endPoint: .trailing)
    }

    var gradientOk: LinearGradient {
        LinearGradient(colors: [ok, cyan], startPoint: .leading, endPoint: .trailing)
    }

    static let dark = Palette(
        bg: Color(hex: 0x08070F),
        bg2: Color(hex: 0x0D0B18),
        card: Color.white.opacity(0.035),
        card2: Color.white.opacity(0.06),
        stroke: Color.white.opacity(0.09),
        stroke2: Color.white.opacity(0.16),
        t1: Color(hex: 0xF2F0FF),
        t2: Color(hex: 0xF2F0FF).opacity(0.62),
        t3: Color(hex: 0xF2F0FF).opacity(0.34),
        accent: Color(hex: 0x7C5CFF),
        cyan: Color(hex: 0x22E0FF),
        ok: Color(hex: 0x3BE8A0),
        warn: Color(hex: 0xFFB020),
        danger: Color(hex: 0xFF5A6E),
        grid: Color(hex: 0x7C5CFF).opacity(0.07),
        shadow: Color.black.opacity(0.55)
    )

    static let light = Palette(
        bg: Color(hex: 0xEFEDF7),
        bg2: Color(hex: 0xF7F6FC),
        card: Color.white.opacity(0.85),
        card2: Color.white,
        stroke: Color(hex: 0x14102D).opacity(0.09),
        stroke2: Color(hex: 0x14102D).opacity(0.16),
        t1: Color(hex: 0x14102D),
        t2: Color(hex: 0x14102D).opacity(0.62),
        t3: Color(hex: 0x14102D).opacity(0.38),
        accent: Color(hex: 0x6A3FF5),
        cyan: Color(hex: 0x0FA5C9),
        ok: Color(hex: 0x0FA86E),
        warn: Color(hex: 0xC97A00),
        danger: Color(hex: 0xE0344B),
        grid: Color(hex: 0x6A3FF5).opacity(0.07),
        shadow: Color(hex: 0x1E1450).opacity(0.14)
    )

    static func of(_ mode: ThemeMode) -> Palette {
        mode == .dark ? .dark : .light
    }

    // MARK: - Cores por significado

    func usageTint(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.70: return ok
        case ..<0.85: return warn
        default: return danger
        }
    }

    func temperatureTint(_ celsius: Double) -> Color {
        switch celsius {
        case ..<60: return ok
        case ..<80: return warn
        default: return danger
        }
    }

    /// Cor da pílula de risco, seguindo a regra do design:
    /// até 2 verde, até 5 âmbar, acima disso vermelho.
    func riskTint(_ score: Int) -> Color {
        if score <= 2 { return ok }
        if score <= 5 { return warn }
        return danger
    }

    func scoreTint(_ score: Int) -> Color {
        switch score {
        case ..<50: return danger
        case ..<75: return warn
        default: return ok
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: 1
        )
    }
}
