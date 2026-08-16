import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var store: MaskStore
    @State private var step = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [BlurFollowTheme.ink, Color(red: 0.12, green: 0.10, blue: 0.28)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 44, height: 44)
                    Text("BlurFollow")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(String.localizedStringWithFormat(
                        String(localized: "%lld / %lld"),
                        Int64(step + 1),
                        Int64(3)
                    ))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(26)

                Group {
                    switch step {
                    case 0: promisePage
                    case 1: modesPage
                    default: sharingPage
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity.combined(with: .move(edge: .trailing)))

                HStack {
                    if step > 0 {
                        Button("Back") { withAnimation(.easeInOut(duration: 0.2)) { step -= 1 } }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Spacer()
                    Button(
                        step == 2
                            ? String(localized: "Start Blurring")
                            : String(localized: "Continue")
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if step < 2 { step += 1 }
                            else { store.hasCompletedOnboarding = true }
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.headline)
                    .foregroundStyle(BlurFollowTheme.ink)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
                    .background(BlurFollowTheme.cyan.gradient, in: Capsule())
                    .shadow(color: BlurFollowTheme.cyan.opacity(0.28), radius: 12, y: 4)
                }
                .padding(26)
            }
        }
        .frame(width: 720, height: 520)
    }

    private var promisePage: some View {
        VStack(spacing: 24) {
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .stroke(BlurFollowTheme.cyan.opacity(0.38), lineWidth: 2)
                    .frame(width: 300, height: 176)
                    .offset(x: -28, y: -10)
                RoundedRectangle(cornerRadius: 18)
                    .fill(.ultraThinMaterial)
                    .frame(width: 145, height: 74)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(BlurFollowTheme.iris, lineWidth: 2))
                    .offset(x: 58, y: 24)
                Image(systemName: "arrow.right")
                    .font(.title2)
                    .foregroundStyle(BlurFollowTheme.cyan)
                    .offset(x: 126, y: -18)
            }
            Text("Blur that follows your window.")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("Place a blur once, then let it keep the same relative position as the selected window moves and resizes.")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
        }
        .padding(.horizontal, 50)
    }

    private var modesPage: some View {
        VStack(spacing: 24) {
            Text("Choose how each blur moves")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            HStack(spacing: 18) {
                OnboardingModeCard(
                    icon: "display",
                    title: String(localized: "Display Pin"),
                    detail: String(localized: "Fixed to one display. Works without screen recording permission."),
                    color: BlurFollowTheme.iris
                )
                OnboardingModeCard(
                    icon: "macwindow.badge.plus",
                    title: String(localized: "Window Pin"),
                    detail: String(localized: "Keeps a relative position when the selected window moves or resizes."),
                    color: BlurFollowTheme.cyan
                )
            }
        }
        .padding(.horizontal, 48)
    }

    private var sharingPage: some View {
        VStack(spacing: 22) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 56))
                .foregroundStyle(BlurFollowTheme.cyan)
            Text("Check what your audience will see")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 14) {
                Label("Entire display: confirm overlays in the meeting preview", systemImage: "display")
                Label("Single window or app: open Share Preview", systemImage: "play.rectangle.on.rectangle")
                Label("Browser tab: select the browser window in Share Preview", systemImage: "rectangle.on.rectangle.slash")
            }
            .font(.title3.weight(.medium))
            .foregroundStyle(.white.opacity(0.82))
            Text("BlurFollow is a visual aid, not a security control. Check every mask and the meeting app’s own preview before presenting.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 540)
        }
        .padding(.horizontal, 48)
    }
}

private struct OnboardingModeCard: View {
    let icon: String
    let title: String
    let detail: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 52, height: 52)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.66))
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .leading)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.10)))
    }
}
