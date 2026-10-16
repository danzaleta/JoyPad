import SwiftUI
import JoyPadProtocol

#if canImport(UIKit)
import UIKit

/// Native UIKit multitouch surface supporting 1, 2, 3, and 4-finger Magic Trackpad gestures at 120Hz.
public struct NativeMultitouchTrackpadView: UIViewRepresentable {
    public let sensitivity: Double
    public let onMotion: (TrackpadMotionPayload) -> Void
    public let onGesture: (TrackpadGesturePayload) -> Void
    public let onHaptic: (Bool) -> Void

    public init(
        sensitivity: Double,
        onMotion: @escaping (TrackpadMotionPayload) -> Void,
        onGesture: @escaping (TrackpadGesturePayload) -> Void,
        onHaptic: @escaping (Bool) -> Void
    ) {
        self.sensitivity = sensitivity
        self.onMotion = onMotion
        self.onGesture = onGesture
        self.onHaptic = onHaptic
    }

    public func makeUIView(context: Context) -> MultitouchSurfaceUIView {
        let view = MultitouchSurfaceUIView()
        view.sensitivity = sensitivity
        view.onMotion = onMotion
        view.onGesture = onGesture
        view.onHaptic = onHaptic
        return view
    }

    public func updateUIView(_ uiView: MultitouchSurfaceUIView, context: Context) {
        uiView.sensitivity = sensitivity
        uiView.onMotion = onMotion
        uiView.onGesture = onGesture
        uiView.onHaptic = onHaptic
    }
}

public final class MultitouchSurfaceUIView: UIView {
    public var sensitivity: Double = 1.6
    public var onMotion: ((TrackpadMotionPayload) -> Void)?
    public var onGesture: ((TrackpadGesturePayload) -> Void)?
    public var onHaptic: ((Bool) -> Void)?

    private var activeTouches: Set<UITouch> = []
    private var maxFingersInCurrentGesture: Int = 0
    private var touchStartTime: TimeInterval = 0
    private var totalTranslation: CGPoint = .zero
    private var lastCentroid: CGPoint = .zero
    private var lastPinchSpan: CGFloat = 0
    private var pinchAccumulator: CGFloat = 0
    private var didTriggerMultiFingerAction: Bool = false
    private var isScrollActive: Bool = false

    // Double-tap-to-drag state
    private var lastSingleTapReleaseTime: TimeInterval = 0
    private var isDraggingLockedByDoubleTap: Bool = false

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isExclusiveTouch = true
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let wasEmpty = activeTouches.isEmpty
        activeTouches.formUnion(touches)

        let count = activeTouches.count
        if wasEmpty {
            maxFingersInCurrentGesture = count
            touchStartTime = ProcessInfo.processInfo.systemUptime
            totalTranslation = .zero
            didTriggerMultiFingerAction = false
            pinchAccumulator = 0

            // Check if this is a quick second tap -> engage drag-on-move
            if count == 1 && (touchStartTime - lastSingleTapReleaseTime) < 0.28 {
                isDraggingLockedByDoubleTap = true
                onHaptic?(false)
                onGesture?(TrackpadGesturePayload(buttonMask: [.left, .dragLock], action: .press))
            }
        } else {
            if count > maxFingersInCurrentGesture {
                maxFingersInCurrentGesture = count
            }
            // Cancel single-finger drag lock if a second finger lands
            if isDraggingLockedByDoubleTap && count > 1 {
                isDraggingLockedByDoubleTap = false
                onGesture?(TrackpadGesturePayload(buttonMask: .left, action: .release))
            }
        }

        lastCentroid = computeCentroid()
        lastPinchSpan = computeSpan(around: lastCentroid)
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !activeTouches.isEmpty else { return }
        let count = activeTouches.count
        let newCentroid = computeCentroid()
        let dx = newCentroid.x - lastCentroid.x
        let dy = newCentroid.y - lastCentroid.y
        lastCentroid = newCentroid

        totalTranslation.x += dx
        totalTranslation.y += dy

        switch count {
        case 1:
            // Only move cursor if this gesture didn't start as a 2/3/4-finger gesture
            guard maxFingersInCurrentGesture == 1 else { return }
            let scaledDX = Double(dx) * sensitivity
            let scaledDY = Double(dy) * sensitivity
            if abs(scaledDX) > 0.005 || abs(scaledDY) > 0.005 {
                onMotion?(TrackpadMotionPayload(deltaX: scaledDX, deltaY: scaledDY))
            }

        case 2:
            let newSpan = computeSpan(around: newCentroid)
            let spanDelta = newSpan - lastPinchSpan
            lastPinchSpan = newSpan
            pinchAccumulator += spanDelta

            // Detect intentional 2-finger pinch / spread vs 2-finger scroll
            if abs(pinchAccumulator) > 26.0 && abs(spanDelta) > hypot(dx, dy) * 0.75 {
                let pinchStep: Int8 = pinchAccumulator > 0 ? 10 : -10
                pinchAccumulator = 0
                didTriggerMultiFingerAction = true
                onHaptic?(false)
                onMotion?(TrackpadMotionPayload(pinchScaleDelta: pinchStep))
            } else {
                if !isScrollActive && hypot(totalTranslation.x, totalTranslation.y) > 4.0 {
                    isScrollActive = true
                    didTriggerMultiFingerAction = true
                    onMotion?(TrackpadMotionPayload(scrollPhase: .began))
                }
                if isScrollActive {
                    let scrollX = Int16(clamping: Int((dx * 2.4).rounded()))
                    let scrollY = Int16(clamping: Int((dy * 2.4).rounded()))
                    if scrollX != 0 || scrollY != 0 {
                        onMotion?(
                            TrackpadMotionPayload(
                                scrollDeltaX: scrollX,
                                scrollDeltaY: scrollY,
                                scrollPhase: .changed
                            )
                        )
                    }
                }
            }

        case 3:
            guard !didTriggerMultiFingerAction else { return }
            let threshold: CGFloat = 42.0
            if abs(totalTranslation.x) > threshold || abs(totalTranslation.y) > threshold {
                didTriggerMultiFingerAction = true
                onHaptic?(false)
                if abs(totalTranslation.y) > abs(totalTranslation.x) {
                    let gesture: SystemGesture = (totalTranslation.y < 0) ? .missionControl : .appExpose
                    onGesture?(TrackpadGesturePayload(systemGesture: gesture))
                } else {
                    // Natural swipe: swipe left moves to right space, swipe right moves to left space
                    let gesture: SystemGesture = (totalTranslation.x < 0) ? .spaceRight : .spaceLeft
                    onGesture?(TrackpadGesturePayload(systemGesture: gesture))
                }
            }

        case 4...:
            guard !didTriggerMultiFingerAction else { return }
            let newSpan = computeSpan(around: newCentroid)
            let spanDelta = newSpan - lastPinchSpan
            lastPinchSpan = newSpan
            pinchAccumulator += spanDelta

            if abs(pinchAccumulator) > 32.0 || hypot(totalTranslation.x, totalTranslation.y) > 45.0 {
                didTriggerMultiFingerAction = true
                onHaptic?(false)
                onGesture?(TrackpadGesturePayload(systemGesture: .showDesktop))
            }

        default:
            break
        }
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        activeTouches.subtract(touches)
        if activeTouches.isEmpty {
            finishGestureSequence()
        } else {
            lastCentroid = computeCentroid()
            lastPinchSpan = computeSpan(around: lastCentroid)
        }
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        activeTouches.subtract(touches)
        if activeTouches.isEmpty {
            finishGestureSequence()
        }
    }

    private func finishGestureSequence() {
        let elapsed = ProcessInfo.processInfo.systemUptime - touchStartTime
        let totalMove = hypot(totalTranslation.x, totalTranslation.y)

        if isScrollActive {
            isScrollActive = false
            onMotion?(TrackpadMotionPayload(scrollPhase: .ended))
        }

        if isDraggingLockedByDoubleTap {
            isDraggingLockedByDoubleTap = false
            onHaptic?(true)
            onGesture?(TrackpadGesturePayload(buttonMask: .left, action: .release))
            return
        }

        // Quick tap detection (1-finger = Left Click, 2-finger = Right Click)
        if !didTriggerMultiFingerAction && elapsed < 0.28 && totalMove < 10.0 {
            if maxFingersInCurrentGesture == 1 {
                onHaptic?(false)
                onGesture?(TrackpadGesturePayload(buttonMask: .left, action: .tapClick))
                lastSingleTapReleaseTime = ProcessInfo.processInfo.systemUptime
            } else if maxFingersInCurrentGesture == 2 {
                onHaptic?(false)
                onGesture?(TrackpadGesturePayload(buttonMask: .right, action: .tapClick))
            }
        }

        maxFingersInCurrentGesture = 0
        totalTranslation = .zero
        didTriggerMultiFingerAction = false
    }

    private func computeCentroid() -> CGPoint {
        guard !activeTouches.isEmpty else { return .zero }
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        for touch in activeTouches {
            let pt = touch.location(in: self)
            sumX += pt.x
            sumY += pt.y
        }
        let count = CGFloat(activeTouches.count)
        return CGPoint(x: sumX / count, y: sumY / count)
    }

    private func computeSpan(around centroid: CGPoint) -> CGFloat {
        guard activeTouches.count >= 2 else { return 0 }
        var totalDist: CGFloat = 0
        for touch in activeTouches {
            let pt = touch.location(in: self)
            totalDist += hypot(pt.x - centroid.x, pt.y - centroid.y)
        }
        return totalDist / CGFloat(activeTouches.count)
    }
}
#endif
