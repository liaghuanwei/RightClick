import AppKit

enum MenuPresenter {
    /// 在 CGEvent 全局坐标处弹出原生 NSMenu
    static func show(menu: NSMenu, atCGPoint point: CGPoint) {
        guard let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.screens.first else {
            return
        }

        // CG 坐标原点在左上，AppKit 在左下，需要按主屏高度翻转
        let appKitPoint = NSPoint(x: point.x, y: primary.frame.maxY - point.y)

        let window = NSWindow(
            contentRect: NSRect(origin: appKitPoint, size: NSSize(width: 1, height: 1)),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .transient]
        window.isReleasedWhenClosed = false

        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()

        menu.popUp(positioning: nil, at: .zero, in: window.contentView)

        window.orderOut(nil)
    }
}
