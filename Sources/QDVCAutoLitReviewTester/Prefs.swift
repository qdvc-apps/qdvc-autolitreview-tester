import Foundation

/// App preferences and remembered state, in the standard macOS defaults
/// domain (`defaults read org.qdvc.autolitreviewtester`). The workspace
/// itself holds only the test folders; nothing about the app is written there.
enum Prefs {
    enum Key {
        static let reopenLast = "reopenLastWorkspace"
        static let refreshOnActivate = "refreshWhenActivated"
        static let recentWorkspaces = "recentWorkspaces"
        static let lastWorkspace = "lastWorkspace"
    }

    private static var defaults: UserDefaults { .standard }

    /// Reopen the last workspace at launch (on by default).
    static var reopenLast: Bool {
        get { (defaults.object(forKey: Key.reopenLast) as? Bool) ?? true }
        set { defaults.set(newValue, forKey: Key.reopenLast) }
    }

    /// Rescan the workspace whenever the app comes to the front, so files
    /// added in Finder or by the tool under test show up (on by default).
    static var refreshOnActivate: Bool {
        get { (defaults.object(forKey: Key.refreshOnActivate) as? Bool) ?? true }
        set { defaults.set(newValue, forKey: Key.refreshOnActivate) }
    }

    static var recentWorkspaces: [String] {
        get { defaults.stringArray(forKey: Key.recentWorkspaces) ?? [] }
        set { defaults.set(Array(newValue.prefix(10)), forKey: Key.recentWorkspaces) }
    }

    static var lastWorkspace: String? {
        get { defaults.string(forKey: Key.lastWorkspace) }
        set { defaults.set(newValue, forKey: Key.lastWorkspace) }
    }
}
