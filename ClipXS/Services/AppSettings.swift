import Carbon.HIToolbox
import Combine
import Foundation

enum SettingsKeys {
    static let hotkeyKeyCode = "hotkeyKeyCode"
    static let hotkeyModifiers = "hotkeyModifiers"
    static let maxEntries = "maxEntries"
    static let excludedBundleIds = "excludedBundleIds"
    static let plainPasteBundleIds = "plainPasteBundleIds"
    static let retentionSeconds = "retentionSeconds"
    static let ocrEnabled = "ocrEnabled"
}

/// How long unpinned history entries are kept. `unlimited` disables expiry.
enum RetentionPeriod: Int, CaseIterable, Identifiable {
    case unlimited = 0
    case day = 86_400
    case week = 604_800
    case month = 2_592_000

    var id: Int { rawValue }

    var titleKey: String {
        switch self {
        case .unlimited: return "retention_unlimited"
        case .day: return "retention_day"
        case .week: return "retention_week"
        case .month: return "retention_month"
        }
    }
}

/// Thread-safe reads for services running off the main actor
/// (ClipboardStore's serial queue, ClipboardMonitor, HotkeyManager).
/// UserDefaults itself is thread-safe.
enum SettingsAccess {
    static let defaultHotkeyKeyCode: UInt32 = UInt32(kVK_ANSI_V)
    static let defaultHotkeyModifiers: UInt32 = UInt32(cmdKey | optionKey)
    static let defaultMaxEntries = 100
    static let maxEntriesRange = 10...1000

    static var maxEntries: Int {
        guard UserDefaults.standard.object(forKey: SettingsKeys.maxEntries) != nil else {
            return defaultMaxEntries
        }
        let stored = UserDefaults.standard.integer(forKey: SettingsKeys.maxEntries)
        return stored.clamped(to: maxEntriesRange)
    }

    static var excludedBundleIds: [String] {
        UserDefaults.standard.stringArray(forKey: SettingsKeys.excludedBundleIds) ?? []
    }

    static var plainPasteBundleIds: [String] {
        UserDefaults.standard.stringArray(forKey: SettingsKeys.plainPasteBundleIds) ?? []
    }

    /// 0 means unlimited (no time-based expiry).
    static var retentionSeconds: Int {
        UserDefaults.standard.integer(forKey: SettingsKeys.retentionSeconds)
    }

    static var ocrEnabled: Bool {
        guard UserDefaults.standard.object(forKey: SettingsKeys.ocrEnabled) != nil else {
            return true
        }
        return UserDefaults.standard.bool(forKey: SettingsKeys.ocrEnabled)
    }

    static var hotkeyKeyCode: UInt32 {
        guard UserDefaults.standard.object(forKey: SettingsKeys.hotkeyKeyCode) != nil else {
            return defaultHotkeyKeyCode
        }
        return UInt32(UserDefaults.standard.integer(forKey: SettingsKeys.hotkeyKeyCode))
    }

    static var hotkeyModifiers: UInt32 {
        guard UserDefaults.standard.object(forKey: SettingsKeys.hotkeyModifiers) != nil else {
            return defaultHotkeyModifiers
        }
        return UInt32(UserDefaults.standard.integer(forKey: SettingsKeys.hotkeyModifiers))
    }

    /// The paste-queue hotkey is always the panel hotkey plus Shift.
    static var queueHotkeyModifiers: UInt32 {
        hotkeyModifiers | UInt32(shiftKey)
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var hotkeyKeyCode: UInt32 {
        didSet { defaults.set(Int(hotkeyKeyCode), forKey: SettingsKeys.hotkeyKeyCode) }
    }

    @Published var hotkeyModifiers: UInt32 {
        didSet { defaults.set(Int(hotkeyModifiers), forKey: SettingsKeys.hotkeyModifiers) }
    }

    @Published var maxEntries: Int {
        didSet {
            let clamped = maxEntries.clamped(to: SettingsAccess.maxEntriesRange)
            if clamped != maxEntries {
                maxEntries = clamped
                return
            }
            defaults.set(maxEntries, forKey: SettingsKeys.maxEntries)
        }
    }

    @Published var excludedBundleIds: [String] {
        didSet { defaults.set(excludedBundleIds, forKey: SettingsKeys.excludedBundleIds) }
    }

    @Published var plainPasteBundleIds: [String] {
        didSet { defaults.set(plainPasteBundleIds, forKey: SettingsKeys.plainPasteBundleIds) }
    }

    @Published var retentionSeconds: Int {
        didSet { defaults.set(retentionSeconds, forKey: SettingsKeys.retentionSeconds) }
    }

    @Published var ocrEnabled: Bool {
        didSet { defaults.set(ocrEnabled, forKey: SettingsKeys.ocrEnabled) }
    }

    private let defaults = UserDefaults.standard

    private init() {
        hotkeyKeyCode = SettingsAccess.hotkeyKeyCode
        hotkeyModifiers = SettingsAccess.hotkeyModifiers
        maxEntries = SettingsAccess.maxEntries
        excludedBundleIds = SettingsAccess.excludedBundleIds
        plainPasteBundleIds = SettingsAccess.plainPasteBundleIds
        retentionSeconds = SettingsAccess.retentionSeconds
        ocrEnabled = SettingsAccess.ocrEnabled
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
