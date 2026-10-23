import AppKit
import os

/// 只记录动作与来源，不记录完整路径（路径可能含隐私信息）
enum Log {
    private static let logger = Logger(subsystem: "com.luca.rightclick", category: "app")

    static func info(_ message: String) {
        guard Settings.shared.debugLog else { return }
        logger.info("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}

enum Alert {
    static func error(_ title: String, _ message: String) {
        show(title: title, message: message, style: .warning)
    }

    static func info(_ title: String, _ message: String) {
        show(title: title, message: message, style: .informational)
    }

    private static func show(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

/// 动作统一在后台线程执行，异常一律回主线程提示，避免拖住事件监听线程
enum ActionRunner {
    static func perform(_ work: @escaping () throws -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try work()
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                Log.error("动作执行失败: \(message)")
                DispatchQueue.main.async {
                    Alert.error("操作失败", message)
                }
            }
        }
    }
}
