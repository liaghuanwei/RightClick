import AppKit

final class MenuController: NSObject {
    static let shared = MenuController()

    private var context: Context?
    private var isPresenting = false
    private var actionPerformed = false
    static var debugDumpMenu = false

    /// 入口：Option + 右键
    func present(at point: CGPoint) {
        guard !isPresenting else { return }
        isPresenting = true
        actionPerformed = false

        let frontApp = TargetApp.at(cgPoint: point) ?? NSWorkspace.shared.frontmostApplication
        Log.info("触发菜单，目标 App: \(frontApp?.bundleIdentifier ?? "unknown")")

        ContextResolver.resolve(frontApp: frontApp) { [weak self] context in
            guard let self else { return }
            self.context = context
            Log.info("上下文来源: \(context.source.label)，文件数: \(context.files.count)")

            let menu = self.buildMenu(context: context)
            MenuPresenter.show(menu: menu, atCGPoint: point)

            // 没有执行动作时把焦点还给原来的 App，避免复制路径后焦点留在后台
            if !self.actionPerformed {
                frontApp?.activate(options: [])
            }
            self.isPresenting = false
        }
    }

    // MARK: - 菜单构建

    private func buildMenu(context: Context) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let header = NSMenuItem(title: "目标：" + Self.displayPath(context.workingDirectory).text, action: nil, keyEquivalent: "")
        if Self.displayPath(context.workingDirectory).truncated {
            header.toolTip = context.workingDirectory
        }
        header.isEnabled = false
        menu.addItem(header)

        let sourceTitle = context.isFallback
            ? "来源：\(context.source.label)（可能不是你右键的位置）"
            : "来源：\(context.source.label)"
        let sourceItem = NSMenuItem(title: sourceTitle, action: nil, keyEquivalent: "")
        sourceItem.isEnabled = false
        menu.addItem(sourceItem)

        menu.addItem(.separator())
        menu.addItem(terminalItem())
        menu.addItem(commandItem())
        menu.addItem(copyPathItem())
        menu.addItem(editorItem())
        menu.addItem(.separator())
        menu.addItem(settingsItem())

        if Self.debugDumpMenu {
            Self.dump(menu: menu)
        }

        return menu
    }

    private static func dump(menu: NSMenu, indent: Int = 0) {
        let pad = String(repeating: "  ", count: indent)
        for item in menu.items {
            let state = item.isEnabled ? "" : " [disabled]"
            let line = item.isSeparatorItem ? "\(pad)---" : "\(pad)\(item.title)\(state)"
            FileHandle.standardError.write((line + "\n").data(using: .utf8)!)
            if let submenu = item.submenu {
                dump(menu: submenu, indent: indent + 1)
            }
        }
    }

    private func terminalItem() -> NSMenuItem {
        let root = NSMenuItem(title: "在此处打开终端", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        let terminals = TerminalRegistry.installed
        for launcher in terminals {
            var title = launcher.displayName
            if launcher.id == Settings.shared.preferredTerminalID {
                title += "（上次）"
            }
            let item = NSMenuItem(title: title, action: #selector(openTerminal(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = launcher.id
            submenu.addItem(item)
        }

        if terminals.isEmpty {
            let empty = NSMenuItem(title: "未检测到可用终端", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        }

        root.submenu = submenu
        root.isEnabled = !terminals.isEmpty
        return root
    }

    private func commandItem() -> NSMenuItem {
        let root = NSMenuItem(title: "执行预设命令", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        for command in PredefinedCommands.all {
            let item = NSMenuItem(title: command.title, action: #selector(runPresetCommand(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = command
            submenu.addItem(item)
        }

        root.submenu = submenu
        return root
    }

    private func copyPathItem() -> NSMenuItem {
        let root = NSMenuItem(title: "复制路径", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        for format in [PathFormat.absolute, .quoted, .cdCommand] {
            let item = NSMenuItem(title: format.title, action: #selector(copyPath(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = format.rawValue
            submenu.addItem(item)
        }

        root.submenu = submenu
        return root
    }

    private func editorItem() -> NSMenuItem {
        let root = NSMenuItem(title: "在编辑器中打开", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        let editors = EditorRegistry.installed
        for entry in editors {
            let item = NSMenuItem(title: entry.app.name, action: #selector(openEditor(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.url.path
            submenu.addItem(item)
        }

        if editors.isEmpty {
            let empty = NSMenuItem(title: "未检测到已安装的编辑器", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        }

        root.submenu = submenu
        root.isEnabled = !editors.isEmpty
        return root
    }

    private func settingsItem() -> NSMenuItem {
        let root = NSMenuItem(title: "设置…", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        for trigger in TriggerModifier.allCases {
            let item = NSMenuItem(title: trigger.title, action: #selector(selectTrigger(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = trigger.rawValue
            item.state = Settings.shared.trigger == trigger ? .on : .off
            submenu.addItem(item)
        }

        submenu.addItem(.separator())

        let enable = NSMenuItem(title: "启用菜单", action: #selector(toggleEnabled(_:)), keyEquivalent: "")
        enable.target = self
        enable.state = Settings.shared.enabled ? .on : .off
        submenu.addItem(enable)

        let loginItem = NSMenuItem(title: "开机自启", action: #selector(toggleLoginItem(_:)), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = LoginItem.isEnabled ? .on : .off
        submenu.addItem(loginItem)

        let permission = NSMenuItem(title: "打开辅助功能设置", action: #selector(openAccessibilitySettings(_:)), keyEquivalent: "")
        permission.target = self
        submenu.addItem(permission)

        root.submenu = submenu
        return root
    }

    // MARK: - 动作

    @objc private func openTerminal(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let context,
              let launcher = TerminalRegistry.launcher(id: id) else { return }

        actionPerformed = true
        Settings.shared.preferredTerminalID = id
        launch(launcher, context: context, command: nil)
    }

    @objc private func runPresetCommand(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? PredefinedCommand,
              let context,
              let launcher = TerminalRegistry.preferred() else { return }

        actionPerformed = true
        Settings.shared.preferredTerminalID = launcher.id
        launch(launcher, context: context, command: command.command)
    }

    @objc private func copyPath(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let format = PathFormat(rawValue: raw),
              let context else { return }

        actionPerformed = true
        Clipboard.copy(format.render(context: context))
        Log.info("已复制路径，格式: \(raw)")
    }

    @objc private func openEditor(_ sender: NSMenuItem) {
        guard let appPath = sender.representedObject as? String,
              let context else { return }

        actionPerformed = true
        let targets = context.files.isEmpty ? [context.workingDirectory] : context.files
        ActionRunner.perform {
            try EditorRegistry.open(appPath: appPath, targets: targets)
        }
    }

    @objc private func selectTrigger(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let trigger = TriggerModifier(rawValue: raw) else { return }
        Settings.shared.trigger = trigger
    }

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        Settings.shared.enabled.toggle()
        EventTapService.shared.notifyStateChanged()
    }

    @objc private func openAccessibilitySettings(_ sender: NSMenuItem) {
        PermissionCenter.openAccessibilitySettings()
    }

    @objc private func toggleLoginItem(_ sender: NSMenuItem) {
        do {
            if LoginItem.isEnabled {
                try LoginItem.disable()
            } else {
                try LoginItem.enable()
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            Alert.error("设置开机自启失败", message)
        }
    }

    // MARK: - 启动终端

    private func launch(_ launcher: TerminalLauncher, context: Context, command: String?) {
        let directory = context.workingDirectory
        ActionRunner.perform {
            // 不支持自动执行命令的终端：打开目录 + 复制命令，让用户粘贴
            if command != nil, !launcher.supportsCommand {
                try launcher.open(directory: directory, command: nil)
                Clipboard.copy(ShellCommand.line(directory: directory, command: command))
                DispatchQueue.main.async {
                    Alert.info("命令已复制到剪贴板",
                               "\(launcher.displayName) 不支持自动执行命令，请在新窗口里直接粘贴。")
                }
                return
            }
            try launcher.open(directory: directory, command: command)
        }
    }

    // MARK: - 展示用路径

    private static func displayPath(_ path: String) -> (text: String, truncated: Bool) {
        let home = NSHomeDirectory()
        var display = path
        if display == home {
            display = "~"
        } else if display.hasPrefix(home + "/") {
            display = "~" + display.dropFirst(home.count)
        }
        guard display.count > 48 else { return (display, false) }
        return ("\(display.prefix(20))…\(display.suffix(24))", true)
    }
}
