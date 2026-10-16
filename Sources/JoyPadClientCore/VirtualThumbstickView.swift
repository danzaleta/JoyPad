import SwiftUI

/// Observable state for a virtual analog thumbstick without using @State macro plugins.
@MainActor
public final class ThumbstickState: ObservableObject {
    @Published public var knobOffset: CGSize = .zero
    @Published public var isDragging: Bool = false
    public init() {}
}

/// Interactive virtual analog thumbstick outputting normalized (-32768...32767) X/Y axes.
public struct VirtualThumbstickView: View {
    public let label: String
    public let radius: CGFloat
    public let onValueChanged: (Int16, Int16) -> Void

    @StateObject private var state = ThumbstickState()

    public init(
        label: String,
        radius: CGFloat = 56,
        onValueChanged: @escaping (Int16, Int16) -> Void
    ) {
        self.label = label
        self.radius = radius
        self.onValueChanged = onValueChanged
    }

    public var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: radius * 2, height: radius * 2)
                    .overlay(
                        Circle()
                            .stroke(state.isDragging ? Color.blue : Color.white.opacity(0.25), lineWidth: 2)
                    )

                Circle()
                    .fill(state.isDragging ? Color.blue : Color.white.opacity(0.75))
                    .frame(width: radius * 0.85, height: radius * 0.85)
                    .offset(state.knobOffset)
                    .shadow(radius: 4)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        state.isDragging = true
                        let dx = value.location.x - radius
                        let dy = value.location.y - radius
                        let dist = hypot(dx, dy)
                        let clampedDist = min(dist, radius)
                        let angle = atan2(dy, dx)

                        let clampedX = cos(angle) * clampedDist
                        let clampedY = sin(angle) * clampedDist
                        state.knobOffset = CGSize(width: clampedX, height: clampedY)

                        let normX = Int16(clamping: Int((clampedX / radius) * 32767.0))
                        let normY = Int16(clamping: Int((clampedY / radius) * 32767.0))
                        onValueChanged(normX, normY)
                    }
                    .onEnded { _ in
                        state.isDragging = false
                        state.knobOffset = .zero
                        onValueChanged(0, 0)
                    }
            )

            Text(label)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
        }
    }
}
