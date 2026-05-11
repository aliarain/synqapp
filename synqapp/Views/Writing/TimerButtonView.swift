
//  TimerButtonView.swift
//  Spill — focus timer with scroll-to-adjust and double-click reset

import SwiftUI

struct TimerButtonView: View {

    @Binding var isRunning: Bool
    @Binding var seconds: Int          // current countdown value
    @Binding var totalSeconds: Int     // configured duration

    private let defaultDuration = 900  // 15:00
    private let maxDuration = 2700     // 45:00

    @State private var isHovering = false
    @State private var scale: CGFloat = 1.0
    @State private var lastClickTime: Date? = nil

    private var label: String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    var body: some View {
        Text(label)
            .font(.system(size: 13))
            .foregroundColor(isRunning ? .primary : .secondary)
            .scaleEffect(scale)
            .onHover { hovering in
                isHovering = hovering
                withAnimation(.easeInOut(duration: 0.2)) {
                    scale = hovering ? 1.1 : 1.0
                }
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onTapGesture {
                let now = Date()
                if let last = lastClickTime, now.timeIntervalSince(last) < 0.3 {
                    // Double-click: reset
                    isRunning = false
                    seconds = defaultDuration
                    totalSeconds = defaultDuration
                    lastClickTime = nil
                } else {
                    lastClickTime = now
                    isRunning.toggle()
                }
            }
            .gesture(
                MagnificationGesture()  // placeholder; scroll handled via NSEvent below
                    .onChanged { _ in }
            )
            .background(
                ScrollWheelView { delta in
                    guard isHovering else { return }
                    let change = Int(delta * 0.25) * 60
                    totalSeconds = max(0, min(maxDuration, totalSeconds + change))
                    if !isRunning { seconds = totalSeconds }
                    withAnimation(.easeInOut(duration: 0.1)) { scale = 1.2 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.easeInOut(duration: 0.1)) { scale = isHovering ? 1.1 : 1.0 }
                    }
                }
            )
    }
}

// NSScrollView bridge to capture scroll wheel events
struct ScrollWheelView: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ScrollCapture()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    class ScrollCapture: NSView {
        var onScroll: ((CGFloat) -> Void)?
        override func scrollWheel(with event: NSEvent) {
            onScroll?(event.deltaY)
        }
    }
}
