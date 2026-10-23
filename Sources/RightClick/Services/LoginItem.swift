import AppKit
import ServiceManagement

/// 开机自启：优先用官方 SMAppService（系统「登录项」里可见、可管理）；
/// 注册失败时退回写入 ~/Library/LaunchAgents 的 LaunchAgent。
enum LoginItem {
    private static let label = "com.luca.rightclick"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            if SMAppService.mainApp.status == .enabled { return true }
        }
        return FileManager.default.fileExists(atPath: plistURL.path)
    }

    static var mechanismDescription: String {
        if #available(macOS 13.0, *), SMAppService.mainApp.status == .enabled {
            return "系统登录项"
        }
        return FileManager.default.fileExists(atPath: plistURL.path) ? "LaunchAgent" : "未开启"
    }

    static func enable() throws {
        var collectedError: Error?

        if #available(macOS 13.0, *) {
            do {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .enabled { return }
            } catch {
                collectedError = error
            }
        }

        do {
            try writeLaunchAgent()
        } catch {
            throw collectedError ?? error
        }
    }

    static func disable() throws {
        if #available(macOS 13.0, *) {
            if SMAppService.mainApp.status == .enabled {
                try? SMAppService.mainApp.unregister()
            }
        }
        try? ProcessRunner.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try FileManager.default.removeItem(at: plistURL)
        }
    }

    /// App 被移动后重新指向新路径
    static func refreshIfEnabled() {
        guard FileManager.default.fileExists(atPath: plistURL.path) else { return }
        try? writeLaunchAgent()
    }

    private static func writeLaunchAgent() throws {
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension == "app" else {
            throw LaunchError.commandFailed("请先运行打包后的「RightClick.app」，再开启开机自启。")
        }

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/usr/bin/open</string>
                <string>-a</string>
                <string>\(escape(bundleURL.path))</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>LimitLoadToSessionType</key>
            <string>Aqua</string>
        </dict>
        </plist>
        """

        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try plist.write(to: plistURL, atomically: true, encoding: .utf8)
        try? ProcessRunner.run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", plistURL.path])
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
