import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        wireEventTap()
        LoginItem.refreshIfEnabled()

        if PermissionCenter.isAccessibilityTrusted {
            _ = EventTapService.shared.start()
        } else {
            // 先触发系统授权弹窗，再给出可操作的引导
            PermissionCenter.requestAccessibility()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.showOnboarding()
            }
        }

        // 用户去系统设置勾选后自动生效，不需要重启 App
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkPermission()
        }
        RunLoop.main.add(permissionTimer!, forMode: .common)

        refreshStatusItem()

        // 调试开关：RC_DEBUG_LOG=1 时把启动状态写到 stderr 与 /tmp/rightclick_startup.log
        if ProcessInfo.processInfo.environment["RC_DEBUG_LOG"] == "1" {
            let trusted = PermissionCenter.isAccessibilityTrusted ? "1" : "0"
            let running = EventTapService.shared.isRunning ? "1" : "0"
            let line = "trusted=\(trusted) tapRunning=\(running)\n"
            FileHandle.standardError.write(line.data(using: .utf8)!)
            try? line.write(toFile: "/tmp/rightclick_startup.log", atomically: true, encoding: .utf8)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        EventTapService.shared.stop()
    }

    // MARK: - 事件监听

    private func wireEventTap() {
        EventTapService.shared.onTrigger = { point in
            MenuController.shared.present(at: point)
        }
        EventTapService.shared.onStateChanged = { [weak self] in
            self?.refreshStatusItem()
        }
    }

    private func checkPermission() {
        guard PermissionCenter.isAccessibilityTrusted else {
            if EventTapService.shared.isRunning {
                EventTapService.shared.stop()
                refreshStatusItem()
            }
            return
        }
        if !EventTapService.shared.isRunning {
            if EventTapService.shared.start() {
                refreshStatusItem()
            }
        }
    }

    // MARK: - 菜单栏

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "RightClick")
        item.button?.image?.isTemplate = true
        item.menu = buildStatusMenu()
        statusItem = item
    }

    private func refreshStatusItem() {
        statusItem?.menu = buildStatusMenu()
        let trusted = PermissionCenter.isAccessibilityTrusted
        let symbol = trusted ? "terminal" : "exclamationmark.triangle"
        statusItem?.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "RightClick")
        statusItem?.button?.image?.isTemplate = true
    }

    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let trusted = PermissionCenter.isAccessibilityTrusted
        let state = NSMenuItem(
            title: "辅助功能权限：\(trusted ? "已授权" : "未授权")",
            action: nil,
            keyEquivalent: ""
        )
        state.isEnabled = false
        menu.addItem(state)

        let running = NSMenuItem(
            title: "监听状态：\(EventTapService.shared.isRunning ? "运行中" : "未运行")",
            action: nil,
            keyEquivalent: ""
        )
        running.isEnabled = false
        menu.addItem(running)

        menu.addItem(.separator())

        let test = NSMenuItem(title: "测试菜单（在鼠标位置弹出）", action: #selector(showTestMenu), keyEquivalent: "")
        test.target = self
        menu.addItem(test)

        let enable = NSMenuItem(title: "启用菜单（\(Settings.shared.trigger.title)）", action: #selector(toggleEnabled), keyEquivalent: "")
        enable.target = self
        enable.state = Settings.shared.enabled ? .on : .off
        menu.addItem(enable)

        let triggerMenu = NSMenu()
        for trigger in TriggerModifier.allCases {
            let item = NSMenuItem(title: trigger.title, action: #selector(selectTrigger(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = trigger.rawValue
            item.state = Settings.shared.trigger == trigger ? .on : .off
            triggerMenu.addItem(item)
        }
        let triggerRoot = NSMenuItem(title: "触发键", action: nil, keyEquivalent: "")
        triggerRoot.submenu = triggerMenu
        menu.addItem(triggerRoot)

        menu.addItem(.separator())

        let grant = NSMenuItem(title: "打开辅助功能设置", action: #selector(openAccessibility), keyEquivalent: "")
        grant.target = self
        menu.addItem(grant)

        let rerun = NSMenuItem(title: "重新检测权限", action: #selector(recheck), keyEquivalent: "")
        rerun.target = self
        menu.addItem(rerun)

        let loginItem = NSMenuItem(title: "开机自启", action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    // MARK: - 菜单动作

    @objc private func showTestMenu() {
        guard let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.screens.first else {
            return
        }
        let location = NSEvent.mouseLocation
        let cgPoint = CGPoint(x: location.x, y: primary.frame.maxY - location.y)
        MenuController.shared.present(at: cgPoint)
    }

    @objc private func toggleEnabled() {
        Settings.shared.enabled.toggle()
        refreshStatusItem()
    }

    @objc private func selectTrigger(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let trigger = TriggerModifier(rawValue: raw) else { return }
        Settings.shared.trigger = trigger
        refreshStatusItem()
    }

    @objc private func openAccessibility() {
        PermissionCenter.openAccessibilitySettings()
    }

    @objc private func recheck() {
        if PermissionCenter.isAccessibilityTrusted {
            if !EventTapService.shared.isRunning {
                _ = EventTapService.shared.start()
            }
        } else {
            PermissionCenter.requestAccessibility()
        }
        refreshStatusItem()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func toggleLoginItem() {
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
        refreshStatusItem()
    }

    // MARK: - 首次引导

    private func showOnboarding() {
        guard !PermissionCenter.isAccessibilityTrusted else { return }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "需要「辅助功能」权限"
        alert.informativeText = """
        RightClick 要监听 Option + 右键，并读取 Finder 的选中项，因此需要辅助功能权限。

        步骤：
        1. 点击「打开系统设置」
        2. 在「隐私与安全性 → 辅助功能」中勾选本 App
        3. 回到这里即可生效，无需重启
        """
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            PermissionCenter.requestAccessibility()
            PermissionCenter.openAccessibilitySettings()
        }
    }
}
