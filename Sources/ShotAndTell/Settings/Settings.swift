import AppKit
import Observation

/// Everything the user can change, persisted in `UserDefaults`.
///
/// One object rather than scattered `@AppStorage` properties, because several
/// of these have to *do* something when they change — re-registering the hotkey,
/// resolving a security-scoped bookmark — and a property wrapper has nowhere to
/// put that.
@Observable
final class Settings {
    static let shared = Settings()

    enum ExportScale: String, CaseIterable, Codable, Sendable {
        /// The default: crisp text, files small enough to paste around.
        case retinaCapped
        case retinaFull
        case standard

        var title: String {
            switch self {
            case .retinaCapped: "Retina, capped at 2400px"
            case .retinaFull: "Retina, full size"
            case .standard: "Standard (smallest files)"
            }
        }
    }

    enum AppearanceMode: String, CaseIterable, Codable, Sendable {
        case system, light, dark

        var title: String {
            switch self {
            case .system: "Match system"
            case .light: "Light"
            case .dark: "Dark"
            }
        }
    }

    var hotkey: KeyCombo? {
        didSet { applyHotkey() }
    }
    var defaultBackground: BackgroundStyle { didSet { save() } }
    var appearanceMode: AppearanceMode { didSet { save() } }
    var savesToDisk: Bool { didSet { save() } }
    /// Whether the legend text rides along on the clipboard beside the image.
    ///
    /// Off by default, and that default is the point: with both on the
    /// pasteboard, anything that prefers text — a chat box, an editor, a
    /// terminal — pastes the words and silently drops the picture, which is
    /// maddening when you just took a screenshot. ⇧⌘C copies the legend on
    /// purpose when that's what you want.
    var copiesLegendText: Bool { didSet { save() } }
    var exportScale: ExportScale { didSet { save() } }
    /// What clicking the Dock icon starts. Region is the common case, but
    /// someone who mostly grabs whole windows shouldn't have to use the menu.
    var dockClickMode: CaptureMode { didSet { save() } }

    /// A security-scoped bookmark to a folder the user picked. Nil means the
    /// default, `~/Pictures/Shot and Tell`, which the pictures entitlement
    /// covers without any bookmark at all.
    private(set) var saveFolderBookmark: Data?

    @ObservationIgnored var onHotkeyError: ((Error) -> Void)?
    /// The last registration failure, kept so it can be shown even when it
    /// happened at launch — long before the Settings window existed to be told
    /// about it. The menu bar reads this.
    private(set) var hotkeyProblem: String?

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            Key.savesToDisk: true,
            Key.copiesLegendText: false,
            Key.exportScale: ExportScale.retinaCapped.rawValue,
            Key.appearanceMode: AppearanceMode.system.rawValue,
            Key.dockClickMode: CaptureMode.region.rawValue,
        ])

        hotkey = Self.decode(KeyCombo.self, from: defaults.data(forKey: Key.hotkey)) ?? .default
        defaultBackground = Self.decode(BackgroundStyle.self, from: defaults.data(forKey: Key.background)) ?? .neutral
        appearanceMode = AppearanceMode(rawValue: defaults.string(forKey: Key.appearanceMode) ?? "") ?? .system
        savesToDisk = defaults.bool(forKey: Key.savesToDisk)
        copiesLegendText = defaults.bool(forKey: Key.copiesLegendText)
        exportScale = ExportScale(rawValue: defaults.string(forKey: Key.exportScale) ?? "") ?? .retinaCapped
        dockClickMode = CaptureMode(rawValue: defaults.string(forKey: Key.dockClickMode) ?? "") ?? .region
        saveFolderBookmark = defaults.data(forKey: Key.saveFolderBookmark)
    }

    // MARK: - Appearance

    /// Resolved once per capture rather than per render, so a composition can't
    /// change colour underneath the user because the sun went down.
    func resolvedAppearance() -> Composition.Appearance {
        switch appearanceMode {
        case .light: .light
        case .dark: .dark
        case .system: NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
        }
    }

    // MARK: - Hotkey

    func applyHotkey() {
        save()
        GlobalHotkey.shared.unregister()
        hotkeyProblem = nil
        guard let hotkey, hotkey.isUsable else { return }
        do {
            try GlobalHotkey.shared.register(keyCode: hotkey.keyCode, modifiers: hotkey.modifiers)
        } catch {
            Log.app.error("Hotkey registration failed: \(error.localizedDescription, privacy: .public)")
            hotkeyProblem = error.localizedDescription
            onHotkeyError?(error)
        }
    }

    // MARK: - Save folder

    /// The folder to write into, with security-scoped access already started if
    /// it needs it. The caller must call `stopAccessing` on the returned token.
    func resolveSaveFolder() -> (url: URL, stopAccessing: () -> Void)? {
        guard let saveFolderBookmark else { return nil }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: saveFolderBookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        guard url.startAccessingSecurityScopedResource() else { return nil }
        return (url, { url.stopAccessingSecurityScopedResource() })
    }

    func setSaveFolder(_ url: URL?) {
        guard let url else {
            saveFolderBookmark = nil
            defaults.removeObject(forKey: Key.saveFolderBookmark)
            return
        }
        // Without the bookmark the grant lasts only until the app quits, and the
        // next export would fail silently on a folder that worked yesterday.
        saveFolderBookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(saveFolderBookmark, forKey: Key.saveFolderBookmark)
    }

    var saveFolderDisplayName: String {
        guard let resolved = resolveSaveFolder() else { return "Pictures › Shot and Tell" }
        defer { resolved.stopAccessing() }
        return resolved.url.path(percentEncoded: false)
    }

    // MARK: - Persistence

    private func save() {
        defaults.set(Self.encode(hotkey), forKey: Key.hotkey)
        defaults.set(Self.encode(defaultBackground), forKey: Key.background)
        defaults.set(appearanceMode.rawValue, forKey: Key.appearanceMode)
        defaults.set(savesToDisk, forKey: Key.savesToDisk)
        defaults.set(copiesLegendText, forKey: Key.copiesLegendText)
        defaults.set(exportScale.rawValue, forKey: Key.exportScale)
        defaults.set(dockClickMode.rawValue, forKey: Key.dockClickMode)
    }

    private static func encode<T: Encodable>(_ value: T?) -> Data? {
        guard let value else { return nil }
        return try? JSONEncoder().encode(value)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private enum Key {
        static let hotkey = "hotkey"
        static let background = "defaultBackground"
        static let appearanceMode = "appearanceMode"
        static let savesToDisk = "savesToDisk"
        static let copiesLegendText = "copiesLegendText"
        static let exportScale = "exportScale"
        static let dockClickMode = "dockClickMode"
        static let saveFolderBookmark = "saveFolderBookmark"
    }
}
