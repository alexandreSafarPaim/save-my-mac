import Foundation

/// The app's navigation sections.
///
/// This lived in `SaveMyMacApp.swift` — the `@main` file — and that placement
/// created the only dependency cycle in the codebase: `AppState` holds a
/// `requestedSection: AppSection?`, so the view-model depended on the app entry
/// point. The cost was concrete, not theoretical: `tools/e2e.sh` had to exclude
/// `AppState` from the test target entirely, with a comment naming this exact
/// enum as the reason. The app's central object was untestable by construction,
/// and the fix was moving one type.
///
/// It sits in Support rather than Views because both layers legitimately need
/// it: views render it, `AppState` routes with it (the menu bar panel requests
/// a section, the window consumes the request).
enum AppSection: String, CaseIterable, Identifiable {
    case dashboard
    case cleanup
    case apps
    case files
    case duplicates
    case offload

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return L("Dashboard")
        case .cleanup: return L("Cleanup")
        case .apps: return L("Apps")
        case .files: return L("Large files")
        case .duplicates: return L("Duplicates")
        case .offload: return L("Offload")
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: return "circle.circle"
        case .cleanup: return "sparkles"
        case .apps: return "square.grid.2x2"
        case .files: return "square.stack.3d.up"
        case .duplicates: return "square.on.square"
        case .offload: return "link"
        }
    }
}
