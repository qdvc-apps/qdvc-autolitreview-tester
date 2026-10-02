import AppKit
import UniformTypeIdentifiers

/// Thin wrappers over AppKit services.
enum Platform {
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    static func revealInFinder(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// Opens a file in its default app (Preview, a browser, a BibTeX editor…),
    /// or a folder in Finder. Returns false when nothing could open it.
    @discardableResult
    static func openExternally(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }

    /// The content types for a list of file extensions, for open panels.
    static func contentTypes(forExtensions extensions: [String]) -> [UTType] {
        extensions.compactMap { UTType(filenameExtension: $0) }
    }

    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    /// Puts keyboard focus in the window's toolbar search field (the one
    /// `.searchable` adds). Returns false when the window has none.
    @MainActor
    @discardableResult
    static func focusSearchField(in window: NSWindow?) -> Bool {
        guard let window else { return false }
        if let item = window.toolbar?.items.compactMap({ $0 as? NSSearchToolbarItem }).first {
            item.beginSearchInteraction()
            return true
        }
        guard let field = searchField(in: window.contentView?.superview ?? window.contentView) else {
            return false
        }
        window.makeFirstResponder(field)
        return true
    }

    @MainActor
    private static func searchField(in view: NSView?) -> NSSearchField? {
        guard let view else { return nil }
        if let field = view as? NSSearchField, !field.isHidden { return field }
        for subview in view.subviews {
            if let found = searchField(in: subview) { return found }
        }
        return nil
    }
}
