import AppKit

struct EditorApp {
    let name: String
    let bundleID: String
}

enum EditorRegistry {
    static let all: [EditorApp] = [
        EditorApp(name: "VS Code", bundleID: "com.microsoft.VSCode"),
        EditorApp(name: "Cursor", bundleID: "com.todesktop.230313mzl4w4u92")
    ]

    static var installed: [(app: EditorApp, url: URL)] {
        all.compactMap { app in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) else {
                return nil
            }
            return (app, url)
        }
    }

    static func open(appPath: String, targets: [String]) throws {
        var args = ["-a", appPath]
        args += targets
        try ProcessRunner.run("/usr/bin/open", args)
    }
}

enum Clipboard {
    static func copy(_ text: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
    }
}

/// 复制路径的三种格式
enum PathFormat: String {
    case absolute
    case quoted
    case cdCommand

    var title: String {
        switch self {
        case .absolute: return "绝对路径"
        case .quoted: return "带引号的路径"
        case .cdCommand: return "cd 命令"
        }
    }

    func render(context: Context) -> String {
        let items = context.files.isEmpty ? [context.workingDirectory] : context.files
        switch self {
        case .absolute:
            return items.joined(separator: "\n")
        case .quoted:
            return items.map(ShellCommand.quote).joined(separator: "\n")
        case .cdCommand:
            return "cd " + ShellCommand.quote(context.workingDirectory)
        }
    }
}
