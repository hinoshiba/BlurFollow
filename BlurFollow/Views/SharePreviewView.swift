import SwiftUI

struct SharePreviewView: View {
    @EnvironmentObject private var picker: ContentPickerService
    @EnvironmentObject private var sharePreview: SharePreviewSession
    @State private var pickerRequestID = UUID()
    @State private var activePickerRequest: ContentPickerRequestToken?
    @State private var isPreparingPicker = false
    @State private var pickerMessage: String?
    @State private var reviewedRevision: UInt64?

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                BlurFollowTheme.carbon
                if sharePreview.hasFrame, sharePreview.isRunning {
                    SharePreviewFrameSurface(presenter: sharePreview.framePresenter)
                        .accessibilityLabel("Window mask preview")
                    if sharePreview.frameIsCovered {
                        coveredOverlay
                    }
                } else {
                    stoppedState
                }
            }
            footer
        }
        .background(BlurFollowTheme.carbon)
        .navigationTitle("BlurFollow Share Preview")
        .onDisappear {
            // Closing the share window is an explicit end to capture. Never leave an invisible
            // global session consuming frames after its only preview/control surface is gone.
            pickerRequestID = UUID()
            isPreparingPicker = false
            if let activePickerRequest {
                picker.cancelRequest(activePickerRequest)
                self.activePickerRequest = nil
            }
            Task { await sharePreview.stop() }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: previewWasChecked ? "eye.circle.fill" : (sharePreview.hasRenderablePreview ? "viewfinder.circle" : "pause.circle"))
                .foregroundStyle(sharePreview.hasRenderablePreview ? BlurFollowTheme.cyan : BlurFollowTheme.amber)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 1) {
                Text(previewTitle)
                    .font(.headline)
                Text(sharePreview.sourceName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if sharePreview.isRunning && sharePreview.appliedMaskCount == 0 {
                Label("Preview covered · Add a Window Pin", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BlurFollowTheme.amber)
            } else if sharePreview.hasRenderablePreview {
                Label(
                    appliedMaskCountText,
                    systemImage: "rectangle.dashed"
                )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BlurFollowTheme.cyan)
            }
            Text(previewInstruction)
                .font(.caption2.weight(.heavy))
                .tracking(1.2)
                .foregroundStyle(BlurFollowTheme.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(sharePreview.hasRenderablePreview ? BlurFollowTheme.cyan : BlurFollowTheme.amber, in: Capsule())
        }
        .padding(.horizontal, 18)
        .frame(height: 62)
        .background(.bar)
        .animation(.easeInOut(duration: 0.16), value: previewChromeState)
    }

    private var coveredOverlay: some View {
        VStack(spacing: 10) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 38))
            Text(
                sharePreview.appliedMaskCount == 0
                    ? String(localized: "Add a Window Pin to this source")
                    : String(localized: "Preview covered — check the source and masks")
            )
                .font(.headline)
        }
        .foregroundStyle(.white)
        .padding(24)
        .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 18))
    }

    private var stoppedState: some View {
        VStack(spacing: 14) {
            Image(systemName: previewIsUpdating ? "arrow.triangle.2.circlepath" : "eye.slash.fill")
                .font(.system(size: 48))
                .foregroundStyle(BlurFollowTheme.cyan)
                .contentTransition(.symbolEffect(.replace))
            Text(stoppedMessage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text("The last captured frame is cleared whenever capture stops.")
                .foregroundStyle(.white.opacity(0.65))
        }
        .animation(.easeInOut(duration: 0.16), value: previewIsUpdating)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Label("On this Mac · No audio · No saved frames", systemImage: "desktopcomputer")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(
                previewWasChecked
                    ? String(localized: "Positions checked")
                    : String(localized: "I checked every mask position")
            ) {
                reviewedRevision = sharePreview.reviewRevision
            }
            .contentTransition(.opacity)
            .animation(.easeInOut(duration: 0.16), value: previewWasChecked)
            .disabled(!sharePreview.hasRenderablePreview)
            Button("Choose Another Window") {
                guard !picker.isPicking, !isPreparingPicker else { return }
                let requestID = UUID()
                pickerRequestID = requestID
                pickerMessage = nil
                isPreparingPicker = true
                Task {
                    if sharePreview.isRunning { await sharePreview.stop() }
                    // A reopened preview may already own a newer preparation. Do not clear its
                    // disabled state when this obsolete task resumes after the stop await.
                    guard pickerRequestID == requestID else { return }

                    let pickerRequest = ContentPickerRequestToken()
                    activePickerRequest = pickerRequest
                    let acceptedRequest = picker.pickWindow(requestToken: pickerRequest) { result in
                        guard pickerRequestID == requestID else { return }
                        if activePickerRequest == pickerRequest { activePickerRequest = nil }
                        switch result {
                        case .success(let selection):
                            Task {
                                // The share window may close after the picker callback but before
                                // this task runs. Re-check the view lifetime before capture starts.
                                guard pickerRequestID == requestID else { return }
                                await sharePreview.start(selection)
                                if pickerRequestID == requestID { isPreparingPicker = false }
                            }
                        case .failure(let error):
                            isPreparingPicker = false
                            if case .cancelled = error { return }
                            pickerMessage = userFacingPickerMessage(for: error)
                        }
                    }
                    if acceptedRequest == nil, activePickerRequest == pickerRequest {
                        activePickerRequest = nil
                        isPreparingPicker = false
                    }
                }
            }
            .disabled(picker.isPicking || isPreparingPicker)
            Button("Stop", role: .destructive) {
                Task { await sharePreview.stop() }
            }
            .disabled(!sharePreview.isRunning)
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
        .background(.bar)
    }

    private var stoppedMessage: String {
        if previewIsUpdating {
            return String(localized: "Updating preview — check it before sharing.")
        }
        if let pickerMessage { return pickerMessage }
        if sharePreview.errorMessage != nil {
            return String(localized: "The preview stopped. Choose the window again.")
        }
        return String(localized: "No source is being shared")
    }

    private var appliedMaskCountText: String {
        let count = sharePreview.appliedMaskCount
        let format = count == 1
            ? String(localized: "%lld mask")
            : String(localized: "%lld masks")
        return String.localizedStringWithFormat(format, Int64(count))
    }

    private var previewWasChecked: Bool {
        sharePreview.hasRenderablePreview && reviewedRevision == sharePreview.reviewRevision
    }

    private var previewTitle: String {
        if previewWasChecked { return String(localized: "Mask positions checked") }
        if sharePreview.hasRenderablePreview { return String(localized: "Preview active — check every mask") }
        if previewIsUpdating { return String(localized: "Updating preview") }
        return sharePreview.isRunning
            ? String(localized: "Preview covered")
            : String(localized: "Share Preview stopped")
    }

    private var previewInstruction: String {
        if previewWasChecked { return String(localized: "CHECK MEETING PREVIEW") }
        if sharePreview.hasRenderablePreview { return String(localized: "CHECK MASK POSITIONS") }
        if previewIsUpdating { return String(localized: "UPDATING PREVIEW") }
        return String(localized: "PREVIEW PAUSED")
    }

    private var previewIsUpdating: Bool {
        isPreparingPicker
            || sharePreview.isPreparing
            || (sharePreview.isRunning && !sharePreview.hasFrame)
    }

    private var previewChromeState: PreviewChromeState {
        if previewWasChecked { return .checked }
        if sharePreview.hasRenderablePreview { return .active }
        if previewIsUpdating { return .updating }
        return .paused
    }

    private func userFacingPickerMessage(for error: ContentPickerError) -> String {
        switch error {
        case .cancelled:
            return String(localized: "Window selection was cancelled.")
        case .busy:
            return String(localized: "Another window selection is already in progress.")
        case .noWindow:
            return String(localized: "The selected window could not be identified.")
        case .ambiguousWindow:
            return String(localized: "More than one window matched the selection. Bring the target window forward and try again.")
        case .legacyPermissionRequired:
            return String(localized: "macOS 14 through 15.1 requires Screen Recording access to identify the selected window. Allow it in System Settings, then reopen BlurFollow.")
        case .system:
            return String(localized: "The preview could not start. Choose the window again.")
        }
    }
}

private enum PreviewChromeState: Equatable {
    case paused
    case updating
    case active
    case checked
}

/// The high-frequency pixel stream is pushed directly into this layer-backed AppKit view. SwiftUI
/// only creates and lays out the surface; individual capture frames do not trigger view diffing.
private struct SharePreviewFrameSurface: NSViewRepresentable {
    let presenter: SharePreviewFramePresenter

    func makeNSView(context: Context) -> SharePreviewPixelView {
        let view = SharePreviewPixelView(frame: .zero)
        presenter.attach(view)
        return view
    }

    func updateNSView(_ nsView: SharePreviewPixelView, context: Context) {
        // SwiftUI can recreate this representable when semantic preview state changes. Reattaching
        // synchronizes the replacement surface with the most recently delivered pixel immediately.
        presenter.attach(nsView)
    }
}
