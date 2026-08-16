import SwiftUI

enum BlurFollowTheme {
    static let carbon = Color(red: 0.063, green: 0.067, blue: 0.086)
    static let ink = Color(red: 0.043, green: 0.063, blue: 0.125)
    static let iris = Color(red: 0.486, green: 0.424, blue: 1.0)
    static let cyan = Color(red: 0.259, green: 0.851, blue: 0.784)
    static let mint = Color(red: 0.325, green: 0.839, blue: 0.631)
    static let amber = Color(red: 1.0, green: 0.706, blue: 0.298)
    static let coral = Color(red: 1.0, green: 0.369, blue: 0.424)

    static var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.965, green: 0.972, blue: 0.995),
                Color(red: 0.925, green: 0.942, blue: 0.985)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

struct GlassCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.65), lineWidth: 1)
            }
            .shadow(color: BlurFollowTheme.ink.opacity(0.07), radius: 18, y: 8)
    }
}

struct StatusPill: View {
    let title: String
    let state: TrackingState

    var color: Color {
        switch state {
        case .positionKnown: return BlurFollowTheme.cyan
        case .reconnecting: return BlurFollowTheme.amber
        case .unavailable: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: statusIcon)
            Text(title)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(color.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var statusIcon: String {
        switch state {
        case .positionKnown: return "scope"
        case .reconnecting: return "arrow.triangle.2.circlepath"
        case .unavailable: return "questionmark.circle"
        }
    }
}
