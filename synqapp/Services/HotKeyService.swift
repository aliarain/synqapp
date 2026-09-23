//  HotKeyService.swift
//  SynqApp — global ⌥Space hotkey for quick capture
//  Registered through Carbon's hotkey API, which needs no Accessibility permission
//  (unlike a CGEventTap, which also sees every keystroke typed in every app).

import AppKit
import Carbon.HIToolbox

final class HotKeyService {

    static let shared = HotKeyService()
    private init() {}

    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    func start() {
        guard hotKeyRef == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let service = Unmanaged<HotKeyService>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated { service.onTrigger?() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )

        let id = EventHotKeyID(signature: OSType(0x53594E51), id: 1) // "SYNQ"
        let status = RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey), id, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            print("[HotKeyService] ⌥Space is already taken by another app (status \(status))")
        }
    }

    func stop() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }
}
