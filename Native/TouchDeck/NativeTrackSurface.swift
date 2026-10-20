import SwiftUI
import UIKit

struct NativeTrackSurface: UIViewRepresentable {
    let connection: MacConnection
    var onStatus: (String) -> Void

    func makeUIView(context: Context) -> TrackTouchView {
        let view = TrackTouchView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.onStatus = onStatus
        view.onMove = { [weak connection] in connection?.move(dx: $0, dy: $1) }
        view.onScroll = { [weak connection] in connection?.scroll(dx: $0, dy: $1) }
        view.onScrollState = { [weak connection] in connection?.scrollState($0) }
        view.onTap = { [weak connection] in connection?.click(right: $0) }
        view.onDrag = { [weak connection] in connection?.mouseButton(down: $0) }
        view.onShortcut = { [weak connection] key, modifiers in
            connection?.key(key, down: true, modifiers: modifiers)
            connection?.key(key, down: false, modifiers: modifiers)
        }
        return view
    }

    func updateUIView(_ view: TrackTouchView, context: Context) { view.onStatus = onStatus }
    static func dismantleUIView(_ view: TrackTouchView, coordinator: ()) { view.cancelGesture() }
}

final class TrackTouchView: UIView {
    override var canBecomeFirstResponder: Bool { true }
    override var editingInteractionConfiguration: UIEditingInteractionConfiguration { .none }
    var onStatus: ((String) -> Void)?
    private var lastStatus = ""
    var onMove: ((CGFloat, CGFloat) -> Void)?
    var onScroll: ((CGFloat, CGFloat) -> Void)?
    var onScrollState: ((String) -> Void)?
    private var scrolling = false
    var onTap: ((Bool) -> Void)?
    var onDrag: ((Bool) -> Void)?
    var onShortcut: ((String, [String]) -> Void)?
    private var active = Set<UITouch>()
    private var previous = CGPoint.zero
    private var origin = CGPoint.zero
    private var beganAt = 0.0
    private var maxFingers = 0
    private var travel: CGFloat = 0
    private var startSpan: CGFloat = 0
    private var zoomSpan: CGFloat = 0
    private var twoFingerMode = "pending"
    private var fired = false
    private var dragging = false
    private var hold: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // The trackpad, rather than a previously focused text field, owns editing
        // interaction policy while touches are being used for remote control.
        becomeFirstResponder()
        onScrollState?("cancel")
        scrolling = false
        if active.isEmpty {
            beganAt = ProcessInfo.processInfo.systemUptime
            travel = 0; maxFingers = 0; fired = false; twoFingerMode = "pending"
        }
        active.formUnion(touches)
        maxFingers = max(maxFingers, active.count)
        report("\(active.count) finger\(active.count == 1 ? "" : "s") detected")
        previous = center(); origin = previous
        startSpan = span(); zoomSpan = startSpan
        hold?.invalidate()
        if active.count > 1 && dragging { endDrag() }
        if maxFingers == 1 {
            hold = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
                guard let self, self.active.count == 1, self.travel < 5 else { return }
                self.dragging = true
                self.onDrag?(true)
                self.report("1 finger · Dragging")
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !active.isEmpty else { return }
        let point = center(), dx = point.x - previous.x, dy = point.y - previous.y
        previous = point
        travel += hypot(dx, dy)
        if travel > 5 { hold?.invalidate() }
        // Lifting one finger from a multi-touch gesture must not move the cursor.
        guard active.count == maxFingers else { return }
        if maxFingers == 1 {
            onMove?(dx, dy)
            if !dragging { report("1 finger · Pointer") }
        } else if maxFingers == 2 {
            let currentSpan = span()
            let spread = abs(currentSpan - startSpan)
            let translation = hypot(point.x-origin.x, point.y-origin.y)
            // Fingers do not land/move at precisely the same instant. Allow a
            // tentative scroll to become a pinch when separation dominates.
            if twoFingerMode != "pinch" && spread > max(16, translation * 1.4) {
                if scrolling { onScrollState?("cancel"); scrolling = false }
                twoFingerMode = "pinch"
            } else if twoFingerMode == "pending" && translation > 6 {
                twoFingerMode = "scroll"
            }
            if twoFingerMode == "pinch", zoomSpan > 0, currentSpan > 0 {
                report("2 fingers · Pinch zoom")
                let ratio = currentSpan / zoomSpan
                if ratio > 1.13 || ratio < 0.87 {
                    onShortcut?(ratio > 1 ? "=" : "-", ["command"])
                    zoomSpan = currentSpan
                    travel = max(travel, 20)
                }
            } else if twoFingerMode == "scroll" {
                if !scrolling { onScrollState?("begin"); scrolling = true }
                report("2 fingers · Scrolling")
                onScroll?(dx * 1.8, dy * 1.8)
            }
        } else if maxFingers == 3 {
            // Wait for intentional movement so a fourth finger can land
            // without generating a mouse-down as part of a desktop swipe.
            if !dragging {
                let x = point.x-origin.x, y = point.y-origin.y
                guard hypot(x, y) > 6 else { return }
                dragging = true
                onDrag?(true)
                report("3 fingers · Dragging")
                onMove?(x, y)
            } else {
                onMove?(dx, dy)
            }
        } else if maxFingers == 4 && !fired {
            let x = point.x-origin.x, y = point.y-origin.y
            if max(abs(x), abs(y)) > 65 {
                fired = true
                let key = abs(x) > abs(y) ? (x < 0 ? "right" : "left") : (y < 0 ? "up" : "down")
                report("4 fingers · \(abs(x) > abs(y) ? "Switch desktop" : (y < 0 ? "Mission Control" : "App Exposé"))")
                onShortcut?(key, ["control"])
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        hold?.invalidate()
        active.subtract(touches)
        if scrolling && active.count < 2 {
            onScrollState?("end")
            scrolling = false
        }
        if maxFingers == 3 && active.count < 3 && dragging {
            endDrag()
            report("3 fingers · Dropped")
        }
        if active.isEmpty {
            let wasDragging = dragging
            endDrag()
            if !wasDragging && maxFingers <= 2 && travel < 8 && twoFingerMode == "pending"
                && ProcessInfo.processInfo.systemUptime-beganAt < 0.4 {
                onTap?(maxFingers == 2)
            }
        } else { previous = center() }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        report("Touch cancelled · Try away from screen edges")
        cancelGesture()
    }
    override func didMoveToWindow() {
        if window == nil { cancelGesture() }
        else { becomeFirstResponder() }
    }
    private func report(_ message: String) {
        guard lastStatus != message else { return }
        lastStatus = message
        onStatus?(message)
    }
    func cancelGesture() {
        onScrollState?("cancel")
        scrolling = false
        hold?.invalidate(); hold = nil
        endDrag(); active.removeAll(); maxFingers = 0
    }
    private func endDrag() {
        if dragging { onDrag?(false) }
        dragging = false
    }
    private func center() -> CGPoint {
        guard !active.isEmpty else { return .zero }
        let sum = active.map { $0.location(in: self) }.reduce(CGPoint.zero) {
            CGPoint(x: $0.x+$1.x, y: $0.y+$1.y)
        }
        return CGPoint(x: sum.x/CGFloat(active.count), y: sum.y/CGFloat(active.count))
    }
    private func span() -> CGFloat {
        guard active.count == 2 else { return 0 }
        let points = active.map { $0.location(in: self) }
        return hypot(points[0].x-points[1].x, points[0].y-points[1].y)
    }
}
