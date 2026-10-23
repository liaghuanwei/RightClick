import AppKit
import ApplicationServices

/// 路径来源，菜单里要如实展示，避免“以为在 A 目录，其实在 B 目录”
enum PathSource {
    case finderSelection
    case finderWindow
    case selectedText
    case clipboard
    case lastFinderPath
    case home

    var label: String {
        switch self {
        case .finderSelection: return "Finder 选中项"
        case .finderWindow: return "Finder 当前目录"
        case .selectedText: return "选中的文本路径"
        case .clipboard: return "剪贴板路径"
        case .lastFinderPath: return "最近使用的 Finder 目录"
        case .home: return "用户主目录"
        }
    }
}

struct Context {
    var workingDirectory: String
    var files: [String]
    var source: PathSource

    /// 兜底来源：需要提醒用户“这可能不是你右键的位置”
    var isFallback: Bool {
        source == .lastFinderPath || source == .home
    }
}

enum ContextResolver {
    /// 250ms 内必须给出结果，否则用兜底上下文，保证菜单一定会弹出来
    static func resolve(frontApp: NSRunningApplication?, completion: @escaping (Context) -> Void) {
        let box = ResolveBox()
        let finish: (Context) -> Void = { context in
            guard box.claim() else { return }
            DispatchQueue.main.async { completion(context) }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            finish(resolveSync(frontApp: frontApp))
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            Log.info("上下文解析超时，使用兜底路径")
            finish(fallbackContext())
        }
    }

    static func resolveSync(frontApp: NSRunningApplication?) -> Context {
        // 1. Finder 选中项 / 当前窗口目录
        if frontApp?.bundleIdentifier == "com.apple.finder" {
            if let context = buildContext(paths: FinderContext.selectedURLs(), source: .finderSelection) {
                Settings.shared.lastFinderPath = context.workingDirectory
                return context
            }
            if let directory = FinderContext.currentDirectory() {
                Settings.shared.lastFinderPath = directory
                return Context(workingDirectory: directory, files: [], source: .finderWindow)
            }
        }

        // 2. 当前选中的文本是路径（IDE 里最常用：先复制路径再右键的替代路径）
        if let path = SelectedText.path(app: frontApp) {
            if let context = buildContext(paths: [path], source: .selectedText) {
                return context
            }
        }

        // 3. 剪贴板里的路径
        if let raw = NSPasteboard.general.string(forType: .string),
           let path = normalizePath(raw),
           let context = buildContext(paths: [path], source: .clipboard) {
            return context
        }

        // 4. 最近一次 Finder 目录
        if let path = Settings.shared.lastFinderPath,
           FileManager.default.fileExists(atPath: path) {
            return Context(workingDirectory: path, files: [], source: .lastFinderPath)
        }

        // 5. 主目录
        return Context(workingDirectory: NSHomeDirectory(), files: [], source: .home)
    }

    static func fallbackContext() -> Context {
        if let path = Settings.shared.lastFinderPath,
           FileManager.default.fileExists(atPath: path) {
            return Context(workingDirectory: path, files: [], source: .lastFinderPath)
        }
        return Context(workingDirectory: NSHomeDirectory(), files: [], source: .home)
    }

    /// 把一堆路径归一成「工作目录 + 文件列表」
    static func buildContext(paths: [String], source: PathSource) -> Context? {
        let fm = FileManager.default
        let valid = paths.filter { fm.fileExists(atPath: $0) }
        guard let first = valid.first else { return nil }

        var isDirectory: ObjCBool = false
        fm.fileExists(atPath: first, isDirectory: &isDirectory)

        if valid.count == 1 {
            if isDirectory.boolValue {
                return Context(workingDirectory: first, files: [], source: source)
            }
            return Context(workingDirectory: (first as NSString).deletingLastPathComponent,
                           files: valid,
                           source: source)
        }

        // 多选：同目录下的多个文件 → 工作目录取父目录
        let parents = Set(valid.map { ($0 as NSString).deletingLastPathComponent })
        if parents.count == 1, let parent = parents.first {
            return Context(workingDirectory: parent, files: valid, source: source)
        }
        if isDirectory.boolValue {
            return Context(workingDirectory: first, files: [], source: source)
        }
        return Context(workingDirectory: (first as NSString).deletingLastPathComponent,
                       files: valid,
                       source: source)
    }

    /// 把剪贴板/选中文本里的内容识别成绝对路径
    static func normalizePath(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("\n") else { return nil }

        if value.hasPrefix("file://") {
            guard let url = URL(string: value) else { return nil }
            value = url.path
        }

        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        value = (value as NSString).expandingTildeInPath

        guard value.hasPrefix("/") else { return nil }
        return value
    }
}

/// 保证超时兜底与真实解析只有一个生效
private final class ResolveBox {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

// MARK: - Finder 上下文（优先走 AX，避免额外申请「自动化」权限）
//
// 实测 macOS 15：Finder 窗口的 AXDocument 返回 NoValue，因此当前目录改为
// 从文件列表首个条目的 AXURL 反推；仍失败时才用 AppleScript 兜底（会触发自动化授权）。

enum FinderContext {
    static func selectedURLs() -> [String] {
        guard let window = focusedWindow() else { return [] }

        if let list = fileListContainer(in: window) {
            let rows = (axValue(list, kAXSelectedRowsAttribute as String) as? [AXUIElement])
                ?? (axValue(list, kAXSelectedChildrenAttribute as String) as? [AXUIElement])
                ?? []
            let paths = rows.compactMap { firstURLPath(under: $0, depth: 0) }
            if !paths.isEmpty { return paths }
        }

        // 兜底：图标视图等其他布局，在整棵树里找选区
        return searchSelection(in: window, depth: 0)
    }

    static func currentDirectory() -> String? {
        guard let window = focusedWindow() else { return nil }

        // 1. 老系统上 AXDocument 可用
        if let value = axValue(window, kAXDocumentAttribute as String),
           let url = value as? URL {
            return url.path
        }

        // 2. 用文件列表第一个条目反推父目录（实测约 10ms）
        if let list = fileListContainer(in: window) {
            let rows = (axValue(list, kAXRowsAttribute as String) as? [AXUIElement])
                ?? (axValue(list, kAXChildrenAttribute as String) as? [AXUIElement])
                ?? []
            for row in rows {
                if let path = firstURLPath(under: row, depth: 0) {
                    return (path as NSString).deletingLastPathComponent
                }
            }
        }

        // 3. AppleScript 兜底（约 250ms，只在上面都失败时触发）
        return appleScriptDirectory()
    }

    private static func focusedWindow() -> AXUIElement? {
        guard PermissionCenter.isAccessibilityTrusted,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else {
            return nil
        }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let value = axValue(axApp, kAXFocusedWindowAttribute as String),
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    /// 窗口里的「文件列表」容器（排除边栏，边栏的选中项是当前位置而不是选中文件）
    private static func fileListContainer(in window: AXUIElement) -> AXUIElement? {
        guard let sections = axValue(window, "AXSections") as? [NSDictionary] else { return nil }

        var candidates: [AXUIElement] = []
        for section in sections {
            guard let object = section["SectionObject"],
                  CFGetTypeID(object as CFTypeRef) == AXUIElementGetTypeID() else { continue }
            let element = object as! AXUIElement
            let role = axValue(element, kAXRoleAttribute as String) as? String ?? ""
            guard role == "AXOutline" || role == "AXBrowser" || role == "AXList" else { continue }
            let description = axValue(element, kAXDescriptionAttribute as String) as? String ?? ""
            guard description != "边栏" else { continue }
            candidates.append(element)
        }

        let listView = candidates.first {
            (axValue($0, kAXIdentifierAttribute as String) as? String) == "ListView"
        }
        return listView ?? candidates.first
    }

    /// 列表视图用 AXSelectedRows，图标视图用 AXSelectedChildren
    private static func searchSelection(in element: AXUIElement, depth: Int) -> [String] {
        guard depth <= 12 else { return [] }

        for attribute in [kAXSelectedRowsAttribute as String, kAXSelectedChildrenAttribute as String] {
            guard let value = axValue(element, attribute),
                  let children = value as? [AXUIElement],
                  !children.isEmpty else { continue }
            let paths = children.compactMap { firstURLPath(under: $0, depth: 0) }
            if !paths.isEmpty { return paths }
        }

        for child in (axValue(element, kAXChildrenAttribute as String) as? [AXUIElement]) ?? [] {
            let result = searchSelection(in: child, depth: depth + 1)
            if !result.isEmpty { return result }
        }
        return []
    }

    /// 真实路径挂在行内的文本元素上（行 → 单元格 → 文本），需要往下挖几层
    private static func firstURLPath(under element: AXUIElement, depth: Int) -> String? {
        guard depth <= 4 else { return nil }
        if let value = axValue(element, kAXURLAttribute as String), let url = value as? URL {
            return url.path
        }
        for child in (axValue(element, kAXChildrenAttribute as String) as? [AXUIElement]) ?? [] {
            if let path = firstURLPath(under: child, depth: depth + 1) {
                return path
            }
        }
        return nil
    }

    private static func appleScriptDirectory() -> String? {
        let script = """
        tell application "Finder"
            try
                return POSIX path of (target of front window as alias)
            on error
                return ""
            end try
        end tell
        """
        guard let output = try? ProcessRunner.run("/usr/bin/osascript", ["-e", script]) else { return nil }
        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.hasPrefix("/") ? path : nil
    }

    private static func axValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }
}

// MARK: - 光标下的目标 App

/// 右键事件被我们吞掉，目标窗口不会因此激活，所以不能只看 frontmostApplication
enum TargetApp {
    static func at(cgPoint: CGPoint) -> NSRunningApplication? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for window in windows {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: boundsDictionary),
                  rect.contains(cgPoint) else { continue }
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  pid != ProcessInfo.processInfo.processIdentifier,
                  let app = NSRunningApplication(processIdentifier: pid) else { continue }
            return app
        }
        return nil
    }
}

// MARK: - 当前选中文本

enum SelectedText {
    static func path(app: NSRunningApplication?) -> String? {
        guard PermissionCenter.isAccessibilityTrusted,
              let app else {
            return nil
        }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused,
              CFGetTypeID(element) == AXUIElementGetTypeID() else {
            return nil
        }

        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element as! AXUIElement,
                                            kAXSelectedTextAttribute as CFString,
                                            &selected) == .success,
              let text = selected as? String else {
            return nil
        }
        return ContextResolver.normalizePath(text)
    }
}
