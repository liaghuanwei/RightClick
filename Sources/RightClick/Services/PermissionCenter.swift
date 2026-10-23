import AppKit
import ApplicationServices

enum PermissionCenter {
    /// 辅助功能权限：事件监听与读取选中文本都依赖它
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// 触发系统授权弹窗（只弹一次，之后需用户去系统设置勾选）
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
