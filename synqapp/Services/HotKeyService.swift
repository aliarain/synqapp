
//  HotKeyService.swift
//  SynqApp — global hotkey (⌥Space) to show quick capture window
//  Uses CGEventTap — requires Accessibility permission

import AppKit
import Carbon

final class HotKeyService {

    static let shared = HotKeyService()
    private init() {}

    var onTrigger: (() -> Void)?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // MARK: - Start / stop

    func start() {
        guard eventTap == nil else { return }

        // Check accessibility permission
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        let trusted = AXIsProcessTrustedWithOptions(options)
        guard trusted else {
            print("[HotKeyService] Accessibility permission not granted — global hotkey disabled")
            return
        }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passRetained(event) }
                let service = Unmanaged<HotKeyService>.fromOpaque(refcon).takeUnretainedValue()
                return service.handle(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap else { return }
        eventTap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil
    }

    // MARK: - Event handler

    private func handle(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        guard type == .keyDown else { return Unmanaged.passRetained(event) }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // ⌥Space — keyCode 49 = Space
        let isOptionSpace = keyCode == 49 && flags.contains(.maskAlternate)
            && !flags.contains(.maskCommand)
            && !flags.contains(.maskShift)
            && !flags.contains(.maskControl)

        if isOptionSpace {
            DispatchQueue.main.async { [weak self] in
                self?.onTrigger?()
            }
            return nil // consume the event
        }

        return Unmanaged.passRetained(event)
    }
}
