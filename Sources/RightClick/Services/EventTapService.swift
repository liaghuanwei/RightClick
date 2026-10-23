import AppKit
import CoreGraphics

/// 全局右键监听。三条硬规则：
/// 1. 回调内不做任何 IO；2. 任何失败都放行事件（fail-open）；3. tap 被系统禁用后自动重启
final class EventTapService {
    static let shared = EventTapService()

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var lastTriggerTime: CFAbsoluteTime = 0
    private var enableFailures = 0

    var onTrigger: ((CGPoint) -> Void)?
    var onStateChanged: (() -> Void)?

    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        stop()

        // 只订阅右键；tapDisabledBy* 无论是否在 mask 里都会被投递
        let mask = CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.error("事件监听创建失败（大概率是缺少辅助功能权限）")
            return false
        }

        tap = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        Log.info("事件监听已启动")
        return true
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        runLoopSource = nil
        tap = nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // tap 被系统禁用（回调超时 / 用户输入打断）→ 立刻重启
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            reenable()
            return Unmanaged.passUnretained(event)
        }

        guard type == .rightMouseDown, Settings.shared.enabled else {
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        guard flags.contains(Settings.shared.trigger.flag) else {
            // 普通右键：原样放行，不做任何干预
            return Unmanaged.passUnretained(event)
        }

        // 防抖，避免一次手势触发多次
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastTriggerTime > 0.25 else { return nil }
        lastTriggerTime = now

        let point = event.location
        DispatchQueue.main.async { [weak self] in
            self?.onTrigger?(point)
        }
        return nil
    }

    private func reenable() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        if CGEvent.tapIsEnabled(tap: tap) {
            enableFailures = 0
            Log.info("事件监听已自动恢复")
        } else {
            enableFailures += 1
            Log.error("事件监听恢复失败，第 \(enableFailures) 次")
            if enableFailures >= 3 {
                stop()
                onStateChanged?()
            }
        }
    }

    /// 权限被撤销或 tap 意外退出时，给出可观测的状态变化
    func notifyStateChanged() {
        onStateChanged?()
    }
}

private let eventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let service = Unmanaged<EventTapService>.fromOpaque(refcon).takeUnretainedValue()
    return service.handle(type: type, event: event)
}
