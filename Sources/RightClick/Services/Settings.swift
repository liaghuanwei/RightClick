import Foundation
import CoreGraphics

/// 触发键：Option + 右键 / Control + 右键
enum TriggerModifier: String, CaseIterable {
    case option
    case control

    var title: String {
        switch self {
        case .option: return "Option + 右键"
        case .control: return "Control + 右键"
        }
    }

    var flag: CGEventFlags {
        switch self {
        case .option: return .maskAlternate
        case .control: return .maskControl
        }
    }
}

/// 全部配置存 UserDefaults，本项目不引入数据库
final class Settings {
    static let shared = Settings()

    private enum Key {
        static let enabled = "enabled"
        static let trigger = "triggerModifier"
        static let preferredTerminal = "preferredTerminalID"
        static let lastFinderPath = "lastFinderPath"
        static let debugLog = "debugLogEnabled"
    }

    private let defaults = UserDefaults.standard

    var enabled: Bool {
        get { defaults.object(forKey: Key.enabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }

    var trigger: TriggerModifier {
        get { TriggerModifier(rawValue: defaults.string(forKey: Key.trigger) ?? "") ?? .option }
        set { defaults.set(newValue.rawValue, forKey: Key.trigger) }
    }

    var preferredTerminalID: String? {
        get { defaults.string(forKey: Key.preferredTerminal) }
        set { defaults.set(newValue, forKey: Key.preferredTerminal) }
    }

    var lastFinderPath: String? {
        get { defaults.string(forKey: Key.lastFinderPath) }
        set { defaults.set(newValue, forKey: Key.lastFinderPath) }
    }

    var debugLog: Bool {
        get { defaults.bool(forKey: Key.debugLog) }
        set { defaults.set(newValue, forKey: Key.debugLog) }
    }
}
