import Foundation
import Combine

// MARK: - Languages

/// Interface languages. `system` follows the Mac.
enum Language: String, CaseIterable, Identifiable {
    case system
    case en
    case pt
    case es
    case fr

    var id: String { rawValue }

    /// Each language names itself **in its own language**.
    ///
    /// Translating the names into the current language would be worse: someone
    /// who opened the app in a language they don't read needs to recognise
    /// theirs in the list, and "Portoghese" doesn't help anyone looking for
    /// "Português".
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

// MARK: - State

/// The interface language.
///
/// Without an Xcode project there is no String Catalog and no compiled `.lproj`
/// folders, so the table is plain Swift. That isn't only a workaround:
/// `NSLocalizedString` resolves against the bundle, and switching language at
/// runtime would mean swapping the bundle out from under the system. With our
/// own table, switching is re-reading a dictionary.
///
/// **Does not use `@Published`** — the setter compares before publishing. That
/// rule holds across the whole project ever since a `@Published` firing on an
/// equal-value assignment closed an update cycle that burned an entire core.
/// See `Preferences`.
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
            Trace.mark("interface language: \(newValue.rawValue) → \(newValue.resolved.rawValue)")
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: Localization.key)
        _language = Language(rawValue: saved ?? "") ?? .system
        Localization.active = _language.resolved
        Trace.mark("initial language: \(_language.rawValue) → \(_language.resolved.rawValue)")
    }

    /// Read by the `L` function, which is global and synchronous.
    ///
    /// It has to be `nonisolated(unsafe)`: `L` is called from inside view bodies
    /// thousands of times per second and can't afford an actor hop. The write
    /// happens only on a language switch, always on the main thread, and the
    /// value is a one-byte enum — there is no intermediate state for anyone to
    /// read.
    nonisolated(unsafe) fileprivate static var active: Language = .en

    /// The resolved language, for callers that need to configure something by
    /// language — formatter caches, mainly — without gaining write access to
    /// `active`. Same thread-safety argument as `L()` itself.
    nonisolated static var appLanguage: Language { active }

    /// A `Locale` matching the app language, for date and number formatters.
    ///
    /// Deliberately NOT `Locale.current` for concrete languages: the app
    /// language can differ from the system region, and a French interface with
    /// Brazilian date order is the bug this exists to prevent. `pt` maps to
    /// `pt_BR` because that is the Portuguese this app ships.
    nonisolated static var appLocale: Locale {
        switch active {
        case .system: return Locale.current
        case .en: return Locale(identifier: "en_US")
        case .pt: return Locale(identifier: "pt_BR")
        case .es: return Locale(identifier: "es_ES")
        case .fr: return Locale(identifier: "fr_FR")
        }
    }
}

extension Language {
    /// Resolves `system` into a concrete language using the macOS preference.
    ///
    /// Walks `preferredLanguages` in the order the user arranged them, instead
    /// of looking only at the first: someone with "es, pt, en" whose Spanish
    /// isn't supported should get Portuguese, not English.
    var resolved: Language {
        guard self == .system else { return self }

        for tag in Locale.preferredLanguages {
            // "pt-BR" → "pt", "es-419" → "es". The app doesn't distinguish
            // regional variants; pretending it does would set a false
            // expectation.
            let base = tag.split(separator: "-").first.map(String.init) ?? tag
            if let match = Language(rawValue: base.lowercased()), match != .system {
                return match
            }
        }
        return .en
    }
}

// MARK: - Lookup

/// Translated text.
///
/// The **key is the English text**, not an invented identifier
/// (`dashboard.title`). Two practical reasons:
///
/// 1. A language with no translation for that phrase falls back to English,
///    which is a real sentence. With a symbolic key, a missing translation puts
///    `dashboard.title` on screen — a defect visible to the user instead of
///    graceful degradation.
/// 2. The code stays readable: `Text(L("Analyze my Mac"))` says what appears on
///    screen without consulting any table.
///
/// The cost is that changing the English text invalidates the translations for
/// that phrase. Acceptable: changing the original is exactly when you want the
/// translations reviewed.
func L(_ key: String) -> String {
    switch Localization.active {
    case .en, .system: return key
    case .pt: return Strings.pt[key] ?? key
    case .es: return Strings.es[key] ?? key
    case .fr: return Strings.fr[key] ?? key
    }
}

/// Version with interpolated values. Use `%@` for text and `%d` for integers.
///
/// The placeholders exist so the **order** can change between languages — in
/// some languages the number comes after the noun. Concatenating with `+` would
/// make that impossible.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key), arguments: arguments)
}

/// Singular or plural according to the count.
///
/// The four languages here resolve with two forms, but not by the same rule:
/// English, Portuguese and Spanish pluralise from 2 up; **French uses the
/// singular for zero as well** ("0 semaine", not "0 semaines"). Treating
/// everything as `count == 1` would produce a grammar error in French.
///
/// `count` is labelled because it has **two distinct jobs**, and the first
/// version of this function conflated them: it picks the grammatical form, and
/// sometimes it is also one of the interpolated values. When the phrase has only
/// the number ("%d-week streak"), `count` is enough. When it has more ("We found
/// %@ in %d categories"), the values come afterwards, in the order they appear
/// in the phrase — and then `count` appears twice in the call, once to decide
/// the form and once as an argument. It's repetitive and it's explicit, which is
/// worth more here than saving a parameter.
func Lp(
    _ singular: String,
    _ plural: String,
    count: Int,
    _ arguments: CVarArg...
) -> String {
    let useSingular: Bool
    switch Localization.active {
    case .fr: useSingular = count <= 1
    default: useSingular = count == 1
    }
    let format = L(useSingular ? singular : plural)
    return arguments.isEmpty
        ? String(format: format, count)
        : String(format: format, arguments: arguments)
}
