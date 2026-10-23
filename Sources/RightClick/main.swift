import AppKit

if CommandLine.arguments.contains("--self-test") {
    SelfTest.run()
    exit(0)
}

// 命令行开关开机自启：--login-item on / off
if let index = CommandLine.arguments.firstIndex(of: "--login-item"),
   CommandLine.arguments.count > index + 1 {
    let value = CommandLine.arguments[index + 1]
    do {
        switch value {
        case "on":
            try LoginItem.enable()
            print("开机自启：已开启（\(LoginItem.mechanismDescription)）")
        case "off":
            try LoginItem.disable()
            print("开机自启：已关闭")
        case "status":
            print("开机自启：\(LoginItem.isEnabled ? "已开启" : "已关闭")（\(LoginItem.mechanismDescription)）")
        default:
            print("用法: --login-item on|off|status")
            exit(1)
        }
    } catch {
        print("设置失败：\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
        exit(1)
    }
    exit(0)
}

// 调试用：不依赖右键，直接在鼠标位置弹出菜单
if CommandLine.arguments.contains("--test-menu") {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    MenuController.debugDumpMenu = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        guard let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.screens.first else {
            return
        }
        let location = NSEvent.mouseLocation
        FileHandle.standardError.write("present at \(location)\n".data(using: .utf8)!)
        MenuController.shared.present(at: CGPoint(x: location.x, y: primary.frame.maxY - location.y))
    }
    app.run()
    exit(0)
}

// 单实例：开机自启与手动打开同时发生时，避免两个进程各挂一个事件监听
if let bundleID = Bundle.main.bundleIdentifier {
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    if !others.isEmpty {
        exit(0)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)

// 调试开关：RC_DEBUG_MENU=1 时把菜单结构打到 stderr
if ProcessInfo.processInfo.environment["RC_DEBUG_MENU"] == "1" {
    MenuController.debugDumpMenu = true
}

app.run()
