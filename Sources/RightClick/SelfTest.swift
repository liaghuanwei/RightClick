import AppKit

/// 无 UI 自检：不依赖辅助功能权限，用于验证路径解析、终端探测与命令拼装
enum SelfTest {
    static func run() {
        print("== 环境 ==")
        print("辅助功能权限: \(PermissionCenter.isAccessibilityTrusted ? "已授权" : "未授权")")
        print("前台 App: \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown")")

        print("\n== 上下文解析 ==")
        let context = ContextResolver.resolveSync(frontApp: NSWorkspace.shared.frontmostApplication)
        print("来源: \(context.source.label)\(context.isFallback ? "（兜底）" : "")")
        print("工作目录: \(context.workingDirectory)")
        print("选中文件: \(context.files.isEmpty ? "无" : context.files.joined(separator: ", "))")

        print("\n== Finder 上下文（AX 直读） ==")
        print("当前窗口目录: \(FinderContext.currentDirectory() ?? "读取失败")")
        let selection = FinderContext.selectedURLs()
        print("选中项: \(selection.isEmpty ? "无" : selection.joined(separator: ", "))")

        print("\n== 终端探测 ==")
        for launcher in TerminalRegistry.all {
            let mark = launcher.isInstalled() ? "已安装" : "未安装"
            print("\(launcher.id)\t\(launcher.displayName)\t\(mark)\t\(launcher.supportsCommand ? "支持执行命令" : "仅打开目录")")
        }

        print("\n== 编辑器探测 ==")
        let editors = EditorRegistry.installed
        if editors.isEmpty {
            print("无")
        } else {
            for entry in editors {
                print("\(entry.app.name)\t\(entry.url.path)")
            }
        }

        print("\n== 命令拼装（含特殊字符） ==")
        print(ShellCommand.line(directory: "/tmp/a b/中文", command: nil))
        print(ShellCommand.line(directory: "/tmp/it's", command: "git status"))
        print(ShellCommand.line(directory: "/tmp/$(whoami);rm -rf", command: "echo `date`"))

        print("\n== 复制格式 ==")
        let sample = Context(workingDirectory: "/tmp/a b", files: ["/tmp/a b/x.txt"], source: .finderSelection)
        for format in [PathFormat.absolute, .quoted, .cdCommand] {
            print("\(format.title): \(format.render(context: sample))")
        }
    }
}
