import AppKit

enum LaunchError: LocalizedError {
    case appNotFound(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .appNotFound(let name): return "找不到 \(name)，请确认它已安装。"
        case .commandFailed(let detail): return detail
        }
    }
}

protocol TerminalLauncher {
    var id: String { get }
    var displayName: String { get }
    /// 是否支持打开后自动执行命令；不支持时降级为「复制命令 + 打开目录」
    var supportsCommand: Bool { get }
    func isInstalled() -> Bool
    func open(directory: String, command: String?) throws
}

enum TerminalRegistry {
    static let all: [TerminalLauncher] = [
        AppleTerminalLauncher(),
        ITermLauncher(),
        WarpLauncher(),
        WezTermLauncher(),
        KittyLauncher(),
        AlacrittyLauncher()
    ]

    static var installed: [TerminalLauncher] {
        all.filter { $0.isInstalled() }
    }

    static func launcher(id: String) -> TerminalLauncher? {
        all.first { $0.id == id }
    }

    /// 上次使用的终端；不可用时退回系统 Terminal
    static func preferred() -> TerminalLauncher? {
        if let id = Settings.shared.preferredTerminalID,
           let launcher = launcher(id: id),
           launcher.isInstalled() {
            return launcher
        }
        return installed.first ?? all.first
    }
}

// MARK: - 进程与 AppleScript 工具

enum ProcessRunner {
    /// 启动即返回，不等待（终端类进程会长期驻留）
    static func spawn(_ executable: String, _ arguments: [String]) throws {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw LaunchError.appNotFound((executable as NSString).lastPathComponent)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    /// 等待结束并检查退出码，用于 open / osascript 这类短命命令
    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let detail = err.trimmingCharacters(in: .whitespacesAndNewlines)
            throw LaunchError.commandFailed(detail.isEmpty ? "命令执行失败（退出码 \(process.terminationStatus)）" : detail)
        }
        return out
    }
}

enum OSA {
    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// 把 shell 命令包装成可安全放进 AppleScript 双引号字面量的形式
    static func run(shellLine: String, scriptBuilder: (String) -> String) throws {
        let script = scriptBuilder(escape(shellLine))
        try ProcessRunner.run("/usr/bin/osascript", ["-e", script])
    }
}

// MARK: - 系统 Terminal

struct AppleTerminalLauncher: TerminalLauncher {
    let id = "terminal"
    let displayName = "系统 Terminal"
    let supportsCommand = true

    func isInstalled() -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") != nil
    }

    func open(directory: String, command: String?) throws {
        let line = ShellCommand.line(directory: directory, command: command)
        let script = { (escaped: String) in
            """
            tell application "Terminal"
                activate
                do script "\(escaped)"
            end tell
            """
        }
        do {
            try OSA.run(shellLine: line, scriptBuilder: script)
        } catch {
            // 自动化权限被拒时降级：只能打开目录，不能 cd
            try ProcessRunner.run("/usr/bin/open", ["-a", "Terminal", directory])
        }
    }
}

// MARK: - iTerm2

struct ITermLauncher: TerminalLauncher {
    let id = "iterm"
    let displayName = "iTerm2"
    let supportsCommand = true

    func isInstalled() -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.googlecode.iterm2") != nil
    }

    func open(directory: String, command: String?) throws {
        guard isInstalled() else { throw LaunchError.appNotFound("iTerm2") }
        let line = ShellCommand.line(directory: directory, command: command)
        let script = { (escaped: String) in
            """
            tell application "iTerm"
                activate
                set newWindow to (create window with default profile)
                tell current session of newWindow
                    write text "\(escaped)"
                end tell
            end tell
            """
        }
        try OSA.run(shellLine: line, scriptBuilder: script)
    }
}

// MARK: - Warp

struct WarpLauncher: TerminalLauncher {
    let id = "warp"
    let displayName = "Warp"
    let supportsCommand = false

    func isInstalled() -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "dev.warp.Warp-Stable") != nil
            || FileManager.default.fileExists(atPath: "/Applications/Warp.app")
    }

    func open(directory: String, command: String?) throws {
        // Warp 官方方案是 URL scheme；不同版本行为有差异，失败则退回 open -a 打开目录
        // TODO: 装好 Warp 后实测 scheme 参数，必要时调整
        if let encoded = directory.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "warp://action/new_tab?path=\(encoded)"),
           NSWorkspace.shared.open(url) {
            return
        }
        try ProcessRunner.run("/usr/bin/open", ["-a", "Warp", directory])
    }
}

// MARK: - WezTerm / Kitty / Alacritty（CLI 启动，注意 GUI 进程拿不到 brew 的 PATH）

struct WezTermLauncher: TerminalLauncher {
    let id = "wezterm"
    let displayName = "WezTerm"
    let supportsCommand = true

    private var binary: String? {
        ["/opt/homebrew/bin/wezterm",
         "/usr/local/bin/wezterm",
         "/Applications/WezTerm.app/Contents/MacOS/wezterm"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func isInstalled() -> Bool { binary != nil }

    func open(directory: String, command: String?) throws {
        guard let binary else { throw LaunchError.appNotFound("WezTerm") }
        var args = ["start", "--cwd", directory]
        if let command {
            args += ["--", "/bin/zsh", "-lc", command + "; exec /bin/zsh -l"]
        }
        try ProcessRunner.spawn(binary, args)
    }
}

struct KittyLauncher: TerminalLauncher {
    let id = "kitty"
    let displayName = "Kitty"
    let supportsCommand = true

    private var binary: String? {
        ["/Applications/kitty.app/Contents/MacOS/kitty",
         "/opt/homebrew/bin/kitty",
         "/usr/local/bin/kitty"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func isInstalled() -> Bool { binary != nil }

    func open(directory: String, command: String?) throws {
        guard let binary else { throw LaunchError.appNotFound("Kitty") }
        var args = ["--directory", directory]
        if let command {
            args += ["/bin/zsh", "-lc", command + "; exec /bin/zsh -l"]
        }
        try ProcessRunner.spawn(binary, args)
    }
}

struct AlacrittyLauncher: TerminalLauncher {
    let id = "alacritty"
    let displayName = "Alacritty"
    let supportsCommand = true

    private var binary: String? {
        ["/Applications/Alacritty.app/Contents/MacOS/alacritty",
         "/opt/homebrew/bin/alacritty",
         "/usr/local/bin/alacritty"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func isInstalled() -> Bool { binary != nil }

    func open(directory: String, command: String?) throws {
        guard let binary else { throw LaunchError.appNotFound("Alacritty") }
        var args = ["--working-directory", directory]
        if let command {
            args += ["-e", "/bin/zsh", "-lc", command + "; exec /bin/zsh -l"]
        }
        try ProcessRunner.spawn(binary, args)
    }
}
